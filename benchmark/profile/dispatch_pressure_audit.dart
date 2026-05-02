// ignore_for_file: avoid_print
//
// Post-FIFO dispatch-pressure audit — exp 119.
//
// Runs resqlite-only profile workloads after exp 118's FIFO dispatch
// waiters to answer one question before trying another dispatch
// optimization:
//
//   Do real app-shaped workloads still produce ReaderPool dispatch
//   parking or wake retries?
//
// The direct-read control intentionally overloads the reader pool so
// the counters prove they are live. The stream workloads mirror the
// current A11c and keyed-PK pressure shapes, where upstream stream
// admission and result hashing may dominate before ReaderPool._dispatch
// ever parks.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/dispatch_pressure_audit.dart --markdown

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

const int _readerControlRows = 1000;
const int _readerControlConcurrency = 32;
const int _readerControlWarmupBursts = 2;
const int _readerControlBursts = 5;

const int _a11cRowCount = 5000;
const int _a11cStreamCount = 50;
const int _a11cWriteCount = 500;

const int _keyedRowCount = 10000;
const int _keyedStreamCount = 50;
const int _keyedWriteCount = 200;
const int _keyedPrngSeed = 0xBEEF;

final class _AuditRow {
  _AuditRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.parked,
    required this.retries,
    required this.maxParked,
    required this.invalidateUs,
    required this.invalidateCount,
    required this.intersectionUs,
    required this.intersectionEntries,
    required this.emissions,
    required this.observedHits,
  });

  final String workload;
  final String shape;
  final int wallUs;
  final int parked;
  final int retries;
  final int maxParked;
  final int invalidateUs;
  final int invalidateCount;
  final int intersectionUs;
  final int intersectionEntries;
  final int emissions;
  final int observedHits;

  double get wallMs => wallUs / 1000.0;
  double get invalidateMs => invalidateUs / 1000.0;
  double get intersectionMs => intersectionUs / 1000.0;
  double get invalidatePctOfWall =>
      wallUs == 0 ? 0.0 : (invalidateUs * 100.0) / wallUs;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; dispatch counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');
  String? explicitOut;
  for (final arg in args) {
    if (arg.startsWith('--out=')) {
      explicitOut = arg.substring('--out='.length);
    }
  }

  final rows = <_AuditRow>[];
  rows.add(await _runReaderControl());
  rows.addAll(await _runA11cAudit());
  rows.add(await _runKeyedPkAudit());

  final markdown = _renderMarkdown(rows);
  print(markdown);

  if (writeMarkdown || explicitOut != null) {
    final outPath =
        explicitOut ??
        'benchmark/profile/results/exp-119-dispatch-pressure-audit.md';
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<_AuditRow> _runReaderControl() async {
  final tempDir = await Directory.systemTemp.createTemp('dispatch_audit_read_');
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY, v INTEGER)');
    await db.executeBatch(
      'INSERT INTO items(v) VALUES (?)',
      List.generate(_readerControlRows, (i) => [i]),
    );

    for (var i = 0; i < _readerControlWarmupBursts; i++) {
      await _readerBurst(db, _readerControlConcurrency);
    }

    final wallUs = <int>[];
    final parked = <int>[];
    final retries = <int>[];
    final maxParked = <int>[];
    for (var i = 0; i < _readerControlBursts; i++) {
      final row = await _readerBurst(db, _readerControlConcurrency);
      wallUs.add(row.wallUs);
      parked.add(row.parked);
      retries.add(row.retries);
      maxParked.add(row.maxParked);
    }

    return _AuditRow(
      workload: 'direct reads control',
      shape: '$_readerControlConcurrency concurrent selects, median burst',
      wallUs: _median(wallUs),
      parked: _median(parked),
      retries: _median(retries),
      maxParked: _median(maxParked),
      invalidateUs: 0,
      invalidateCount: 0,
      intersectionUs: 0,
      intersectionEntries: 0,
      emissions: 0,
      observedHits: 0,
    );
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<_AuditRow> _readerBurst(Database db, int concurrency) async {
  ProfileCounters.reset();
  final sw = Stopwatch()..start();
  await Future.wait([
    for (var i = 0; i < concurrency; i++)
      db.select('SELECT v FROM items WHERE v >= ? AND v < ?', [0, 1000]),
  ]);
  sw.stop();
  return _rowFromCounters(
    workload: 'direct reads control',
    shape: '$concurrency concurrent selects',
    wallUs: sw.elapsedMicroseconds,
  );
}

Future<List<_AuditRow>> _runA11cAudit() async {
  final tempDir = await Directory.systemTemp.createTemp('dispatch_audit_a11c_');
  final db = await Database.open('${tempDir.path}/test.db');
  final colNames = [
    for (var i = 0; i < 20; i++) String.fromCharCode('a'.codeUnitAt(0) + i),
  ];
  final createSql =
      'CREATE TABLE wide(id INTEGER PRIMARY KEY, ' +
      colNames.map((c) => '$c TEXT NOT NULL').join(', ') +
      ')';
  final insertSql =
      'INSERT INTO wide(id, ${colNames.join(', ')}) '
      'VALUES (?, ${List.filled(colNames.length, '?').join(', ')})';

  try {
    await db.execute(createSql);
    await db.executeBatch(insertSql, [
      for (var i = 0; i < _a11cRowCount; i++)
        [i, for (final _ in colNames) 'v$i'],
    ]);

    return [
      await _runA11cScenario(
        db,
        name: 'A11c baseline',
        streamCount: 0,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'b$writeIndex',
      ),
      await _runA11cScenario(
        db,
        name: 'A11c disjoint',
        streamCount: _a11cStreamCount,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'd$writeIndex',
      ),
      await _runA11cScenario(
        db,
        name: 'A11c overlap',
        streamCount: _a11cStreamCount,
        updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
        valueFor: (writeIndex) => 'o$writeIndex',
      ),
    ];
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<_AuditRow> _runA11cScenario(
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
    final partWidth = _a11cRowCount ~/ streamCount;
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
    for (var w = 0; w < _a11cWriteCount; w++) {
      await db.execute(updateSql, [valueFor(w), w % _a11cRowCount]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sw.stop();

    final emissions = emitCounts.fold<int>(0, (a, b) => a + b);
    return _rowFromCounters(
      workload: name,
      shape: '$streamCount streams x $_a11cWriteCount writes',
      wallUs: sw.elapsedMicroseconds,
      emissions: emissions,
    );
  } finally {
    for (final sub in subscriptions) {
      await sub.cancel();
    }
  }
}

Future<_AuditRow> _runKeyedPkAudit() async {
  final tempDir = await Directory.systemTemp.createTemp('dispatch_audit_pk_');
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
      for (var i = 1; i <= _keyedRowCount; i++) ['seed_body_$i', 0],
    ]);

    final watchedIds = _pickWatchedIds();
    final watchedSet = watchedIds.toSet();
    final initials = <Completer<void>>[];
    final subscriptions = <StreamSubscription<List<Map<String, Object?>>>>[];
    final emitCounts = List<int>.filled(_keyedStreamCount, 0);
    for (var i = 0; i < _keyedStreamCount; i++) {
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
      final prng = math.Random(_keyedPrngSeed);

      ProfileCounters.reset();
      final sw = Stopwatch()..start();
      for (var w = 0; w < _keyedWriteCount; w++) {
        final pk = prng.nextInt(_keyedRowCount) + 1;
        if (watchedSet.contains(pk)) observedHits++;
        await db.execute(
          'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
          ['body_$w', w, pk],
        );
      }

      var lastEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
      const quietWindow = Duration(milliseconds: 200);
      final quietDeadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(quietDeadline)) {
        await Future<void>.delayed(quietWindow);
        final nowEmissions = emitCounts.fold<int>(0, (a, b) => a + b);
        if (nowEmissions == lastEmissions) break;
        lastEmissions = nowEmissions;
      }
      sw.stop();

      return _rowFromCounters(
        workload: 'keyed PK subscriptions',
        shape: '$_keyedStreamCount streams x $_keyedWriteCount random writes',
        wallUs: sw.elapsedMicroseconds,
        emissions: lastEmissions,
        observedHits: observedHits,
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

List<int> _pickWatchedIds() {
  final step = _keyedRowCount ~/ _keyedStreamCount;
  return [for (var i = 0; i < _keyedStreamCount; i++) (i * step) + 1];
}

_AuditRow _rowFromCounters({
  required String workload,
  required String shape,
  required int wallUs,
  int emissions = 0,
  int observedHits = 0,
}) {
  final counters = ProfileCounters.snapshot();
  return _AuditRow(
    workload: workload,
    shape: shape,
    wallUs: wallUs,
    parked: counters['dispatcher_parked_total']!,
    retries: counters['dispatcher_wake_retry_total']!,
    maxParked: counters['dispatcher_max_parked_concurrent']!,
    invalidateUs: counters['invalidate_us']!,
    invalidateCount: counters['invalidate_count']!,
    intersectionUs: counters['intersection_us']!,
    intersectionEntries: counters['intersection_entries']!,
    emissions: emissions,
    observedHits: observedHits,
  );
}

String _renderMarkdown(List<_AuditRow> rows) {
  final readerCount = _readerPoolSize();
  final buf = StringBuffer();
  buf.writeln('# Dispatch Pressure Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: `benchmark/profile/dispatch_pressure_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/dispatch_pressure_audit.dart --markdown',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Dispatch counters');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | parked_total | wake_retry_total | '
    'max_parked | emissions | observed_hits |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | '
      '${row.wallMs.toStringAsFixed(2)} | ${row.parked} | '
      '${row.retries} | ${row.maxParked} | ${row.emissions} | '
      '${row.observedHits} |',
    );
  }
  buf.writeln();
  buf.writeln('## Invalidation traversal cost');
  buf.writeln();
  buf.writeln(
    '`invalidate_us` is cumulative wall-clock microseconds spent inside '
    'the synchronous body of `StreamEngine.onDependencyChanges` across '
    'every write in the workload. `intersection_us` is the subset spent '
    'inside per-watcher column-set intersection probes. '
    '`invalidate_pct_wall` is `invalidate_us / wall_us` — the fraction of '
    'workload wall time consumed by writer-side invalidation, including '
    'time blocked by `await Future.delayed` between writes and any quiet '
    'window after the last write (so this is a lower bound on the active '
    'fraction).',
  );
  buf.writeln();
  buf.writeln(
    '| workload | wall_ms | invalidate_ms | intersection_ms | '
    'invalidate_count | intersection_entries | invalidate_pct_wall |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.invalidateMs.toStringAsFixed(2)} | '
      '${row.intersectionMs.toStringAsFixed(2)} | '
      '${row.invalidateCount} | ${row.intersectionEntries} | '
      '${row.invalidatePctOfWall.toStringAsFixed(2)}% |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `direct reads control` intentionally overloads the reader pool. '
    'It should still park, but FIFO dispatch should keep '
    '`wake_retry_total` at zero. No streams are registered, so '
    '`invalidate_*` columns stay at zero.',
  );
  buf.writeln(
    '- A11c rows use the same 50-stream, 20-column shape as the release '
    'many-streams writer-throughput workload. Disjoint writes update `c`; '
    'overlap writes update `a`, which every stream projects.',
  );
  buf.writeln(
    '- `keyed PK subscriptions` mirrors the release keyed-PK miss-path: '
    '50 streams watch fixed primary keys while 200 deterministic writes '
    'target random rows.',
  );
  return buf.toString();
}

int _readerPoolSize() => (Platform.numberOfProcessors - 1).clamp(2, 4);

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}
