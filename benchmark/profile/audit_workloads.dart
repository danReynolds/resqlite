// ignore_for_file: avoid_print
//
// Shared profile-mode workload runners for dispatch / invalidation
// audits.
//
// Both `dispatch_pressure_audit.dart` (exp 119) and
// `invalidation_traversal_audit.dart` (exp 121) need the same A11c and
// keyed-PK stream shapes. Extracting them keeps "directly comparable"
// across audits a structural property — workload tweaks land in one
// place.
//
// Each scenario:
//
//   1. resets `ProfileCounters` AFTER stream subscriptions are warm,
//   2. starts a stopwatch, runs the write loop,
//   3. **stops the stopwatch immediately after the last write** — the
//      wall reported is writer-side burst wall, not denominator-padded
//      with a fixed drain sleep,
//   4. lets stream emissions drain to count them, but does NOT include
//      that drain in the reported wall (that would bias fractions
//      downward by an arbitrary constant on fast machines and bias
//      them upward when the drain is too short on slower ones).
//
// Each scenario returns a raw map containing `wall_us`, `emissions`,
// and the relevant `ProfileCounters` snapshot. Writer/invalidation counters
// are complete when the stopwatch stops; stream completion counters are
// captured after the post-wall drain so trailing re-queries are visible
// without inflating `wall_us`. Callers format their own report tables.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';

/// A11c shared shape — same row count and stream count exp 119 / 121
/// agreed on. Keep these in sync with the values used in benchmarks
/// flagged by the `stream-rerun-dispatch` direction.
const int a11cRowCount = 5000;
const int a11cStreamCount = 50;
const int a11cWriteCount = 500;

/// Keyed-PK shared shape — mirrors the release keyed-PK miss-path:
/// 50 streams watch fixed primary keys while 200 deterministic random
/// writes target the table.
const int keyedPkRowCount = 10000;
const int keyedPkStreamCount = 50;
const int keyedPkWriteCount = 200;
const int keyedPkPrngSeed = 0xBEEF;

/// Direct-read overload control — 32 concurrent selects against the
/// clamped reader pool. Used by the dispatch audit (exp 119) to prove
/// the dispatcher counters are live.
const int directReadRowCount = 1000;
const int directReadConcurrency = 32;
const int directReadWarmupBursts = 2;
const int directReadBursts = 5;

/// Result of one scenario run. `wallUs` is writer-side burst wall —
/// it does not include the post-write drain used to count trailing
/// stream emissions. `counters` is the full `ProfileCounters.snapshot`
/// taken right after the burst wall completes; consumers pick the
/// fields they care about.
class AuditScenarioResult {
  AuditScenarioResult({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.emissions,
    required this.observedHits,
    required this.counters,
  });

  final String workload;
  final String shape;
  final int wallUs;
  final int emissions;
  final int observedHits;
  final Map<String, int> counters;
}

/// Open a temp database, create the wide A11c table, populate it, and
/// return the database alongside the temp directory the caller is
/// responsible for cleaning up.
Future<({Database db, Directory tempDir})> setupA11cDb({
  required String prefix,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(prefix);
  final db = await Database.open('${tempDir.path}/test.db');
  final colNames = a11cColumnNames();
  final createSql =
      'CREATE TABLE wide(id INTEGER PRIMARY KEY, ' +
      colNames.map((c) => '$c TEXT NOT NULL').join(', ') +
      ')';
  final insertSql =
      'INSERT INTO wide(id, ${colNames.join(', ')}) '
      'VALUES (?, ${List.filled(colNames.length, '?').join(', ')})';
  await db.execute(createSql);
  await db.executeBatch(insertSql, [
    for (var i = 0; i < a11cRowCount; i++) [i, for (final _ in colNames) 'v$i'],
  ]);
  return (db: db, tempDir: tempDir);
}

List<String> a11cColumnNames() => [
  for (var i = 0; i < 20; i++) String.fromCharCode('a'.codeUnitAt(0) + i),
];

/// Run one A11c scenario: install [streamCount] streams projecting
/// `id, a, b`, wait for their initial emissions, run [a11cWriteCount]
/// updates, capture the stopwatch immediately after the last write,
/// then drain emissions for the count without inflating the wall.
Future<AuditScenarioResult> runA11cScenario(
  Database db, {
  required String name,
  required int streamCount,
  required String updateSql,
  required String Function(int writeIndex) valueFor,
}) async {
  final initials = <Completer<void>>[];
  final subscriptions = <StreamSubscription<List<Map<String, Object?>>>>[];
  final emitCounts = List<int>.filled(streamCount, 0);

  for (var i = 0; i < streamCount; i++) {
    final idx = i;
    final initial = Completer<void>();
    initials.add(initial);
    final partWidth = a11cRowCount ~/ streamCount;
    final partStart = idx * partWidth;
    final partEnd = partStart + partWidth;
    subscriptions.add(
      db
          .stream(
            'SELECT id, a, b FROM wide WHERE id >= ? AND id < ? ORDER BY id',
            [partStart, partEnd],
          )
          .listen((_) {
            if (!initial.isCompleted) {
              initial.complete();
            } else {
              emitCounts[idx]++;
            }
          }),
    );
  }

  try {
    if (streamCount > 0) {
      await Future.wait(
        initials.map((c) => c.future),
      ).timeout(const Duration(seconds: 60));
    }

    ProfileCounters.reset();
    final sw = Stopwatch()..start();
    for (var w = 0; w < a11cWriteCount; w++) {
      await db.execute(updateSql, [valueFor(w), w % a11cRowCount]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }
    sw.stop();

    // Drain emissions without inflating wall_us.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final emissions = emitCounts.fold<int>(0, (a, b) => a + b);
    final counters = ProfileCounters.snapshot();

    return AuditScenarioResult(
      workload: name,
      shape: '$streamCount streams x $a11cWriteCount writes',
      wallUs: sw.elapsedMicroseconds,
      emissions: emissions,
      observedHits: 0,
      counters: counters,
    );
  } finally {
    for (final sub in subscriptions) {
      await sub.cancel();
    }
  }
}

/// Run the keyed-PK scenario: 50 streams watch fixed primary keys
/// while 200 deterministic random writes target the table. Wall is
/// the deterministic write loop only — the trailing quiet-window
/// drain runs after the stopwatch stops, so emission count is stable
/// without padding the wall denominator with idle wait.
Future<AuditScenarioResult> runKeyedPkScenario() async {
  final tempDir = await Directory.systemTemp.createTemp('audit_workloads_pk_');
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute(
      'CREATE TABLE items('
      'id INTEGER PRIMARY KEY, '
      'body TEXT NOT NULL, '
      'updated_at INTEGER NOT NULL'
      ')',
    );
    await db.executeBatch('INSERT INTO items(body, updated_at) VALUES (?, ?)', [
      for (var i = 1; i <= keyedPkRowCount; i++) ['seed_body_$i', 0],
    ]);

    final watchedIds = _pickKeyedPkWatchedIds();
    final watchedSet = watchedIds.toSet();
    final initials = <Completer<void>>[];
    final subscriptions = <StreamSubscription<List<Map<String, Object?>>>>[];
    final emitCounts = List<int>.filled(keyedPkStreamCount, 0);
    for (var i = 0; i < keyedPkStreamCount; i++) {
      final idx = i;
      final initial = Completer<void>();
      initials.add(initial);
      subscriptions.add(
        db
            .stream('SELECT id, body, updated_at FROM items WHERE id = ?', [
              watchedIds[i],
            ])
            .listen((_) {
              if (!initial.isCompleted) {
                initial.complete();
              } else {
                emitCounts[idx]++;
              }
            }),
      );
    }

    try {
      await Future.wait(
        initials.map((c) => c.future),
      ).timeout(const Duration(seconds: 60));

      var observedHits = 0;
      final prng = math.Random(keyedPkPrngSeed);

      ProfileCounters.reset();
      final sw = Stopwatch()..start();
      for (var w = 0; w < keyedPkWriteCount; w++) {
        final pk = prng.nextInt(keyedPkRowCount) + 1;
        if (watchedSet.contains(pk)) observedHits++;
        await db.execute(
          'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
          ['body_$w', w, pk],
        );
      }
      sw.stop();

      // Drain trailing emissions on a quiet-window pattern AFTER the
      // stopwatch stops so wall_us is purely write-loop wall.
      var lastEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
      const quietWindow = Duration(milliseconds: 200);
      final quietDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(quietDeadline)) {
        await Future<void>.delayed(quietWindow);
        final nowEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
        if (nowEmissions == lastEmissions) break;
        lastEmissions = nowEmissions;
      }
      final counters = ProfileCounters.snapshot();

      return AuditScenarioResult(
        workload: 'keyed PK subscriptions',
        shape: '$keyedPkStreamCount streams x $keyedPkWriteCount random writes',
        wallUs: sw.elapsedMicroseconds,
        emissions: lastEmissions,
        observedHits: observedHits,
        counters: counters,
      );
    } finally {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
    }
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

List<int> _pickKeyedPkWatchedIds() {
  final step = keyedPkRowCount ~/ keyedPkStreamCount;
  return [for (var i = 0; i < keyedPkStreamCount; i++) (i * step) + 1];
}

/// Run the direct-read overload control used by the dispatch audit.
/// Returns the median of [directReadBursts] timed bursts after
/// [directReadWarmupBursts] discarded warmups.
Future<AuditScenarioResult> runDirectReadControl() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'audit_workloads_read_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, v INTEGER)');
    await db.executeBatch(
      'INSERT INTO items(v) VALUES (?)',
      List.generate(directReadRowCount, (i) => [i]),
    );

    for (var i = 0; i < directReadWarmupBursts; i++) {
      await _readerBurst(db);
    }

    final wallUs = <int>[];
    final parked = <int>[];
    final retries = <int>[];
    final maxParked = <int>[];
    for (var i = 0; i < directReadBursts; i++) {
      final burst = await _readerBurst(db);
      wallUs.add(burst.wallUs);
      parked.add(burst.counters['dispatcher_parked_total']!);
      retries.add(burst.counters['dispatcher_wake_retry_total']!);
      maxParked.add(burst.counters['dispatcher_max_parked_concurrent']!);
    }

    return AuditScenarioResult(
      workload: 'direct reads control',
      shape: '$directReadConcurrency concurrent selects, median burst',
      wallUs: _median(wallUs),
      emissions: 0,
      observedHits: 0,
      counters: {
        'dispatcher_parked_total': _median(parked),
        'dispatcher_wake_retry_total': _median(retries),
        'dispatcher_max_parked_concurrent': _median(maxParked),
        'invalidate_us': 0,
        'invalidate_count': 0,
        'intersection_us': 0,
        'intersection_entries': 0,
        'rows_decoded': 0,
        'cells_decoded': 0,
      },
    );
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<AuditScenarioResult> _readerBurst(Database db) async {
  ProfileCounters.reset();
  final sw = Stopwatch()..start();
  await Future.wait([
    for (var i = 0; i < directReadConcurrency; i++)
      db.select('SELECT v FROM items WHERE v >= ? AND v < ?', [0, 1000]),
  ]);
  sw.stop();
  final counters = ProfileCounters.snapshot();
  return AuditScenarioResult(
    workload: 'direct reads control',
    shape: '$directReadConcurrency concurrent selects',
    wallUs: sw.elapsedMicroseconds,
    emissions: 0,
    observedHits: 0,
    counters: counters,
  );
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Reader pool size as configured in `ReaderPool`. Useful for the
/// audit reports' header text.
int readerPoolSize() => (Platform.numberOfProcessors - 1).clamp(2, 4);
