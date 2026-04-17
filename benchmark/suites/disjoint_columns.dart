// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

/// Disjoint-column streaming benchmark.
///
/// Two workloads run against a wide (20-column) table with 10 concurrent
/// streams that read `id, a, b`:
///
/// - **Disjoint:** writer updates column `c` (never read) 500 times.
/// - **Overlapping (control):** writer updates column `a` (read by
///   every stream) 500 times.
///
/// **The ratio `disjoint / overlapping` is the primary metric**, NOT the
/// absolute re-emit count. Absolute counts are coalescing-dependent and
/// vary by library:
///
/// - resqlite (with experiment 045) coalesces sequential writes into one
///   invalidation per subscriber per microtask. Expected: disjoint ≈ 0,
///   overlap ≈ 10 (one invalidation × 10 streams). Ratio 0.0 = column
///   tracking is live.
/// - sqlite_async uses table-level tracking. Expected: disjoint ≈
///   overlap ≈ several hundred (coalescing is lighter). Ratio ≈ 1.0 =
///   table-level.
///
/// We add two event-queue yields per write (`Future.delayed(Duration.zero)`
/// schedules via Timer.run, draining both microtasks and the timer queue)
/// to defeat coalescing where we can. Deeper coalescing (writer-worker
/// batching) is library-internal and intentional. The ratio isolates what
/// we care about: does the library *distinguish* columns a subscriber
/// reads from columns it doesn't?
///
/// sqlite3 is excluded (no stream/watch API). sqlite_async uses
/// `throttle: Duration.zero` so throttling doesn't mask the invalidation
/// granularity.
Future<String> runDisjointColumnsBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Streaming (Column Granularity)');
  markdown.writeln('');
  markdown.writeln(
    '10 concurrent streams read `SELECT id, a, b FROM wide ...`. The '
    'writer issues 500 updates — first against a **disjoint** column '
    '(`c`), then against an **overlapping** column (`a`). '
    '**`Re-emit ratio` = `disjoint / overlapping` is the primary metric.** '
    'Absolute counts depend on each library\'s write coalescing and are '
    'not directly comparable across libraries. Column-level dependency '
    'tracking drives the ratio toward 0; table-level tracking toward 1.0.',
  );
  markdown.writeln('');

  final dir = await Directory.systemTemp.createTemp('bench_disjoint_');
  try {
    // Build the wide table schema (20 TEXT columns a..t plus id).
    final colNames = [
      for (var i = 0; i < 20; i++) String.fromCharCode('a'.codeUnitAt(0) + i),
    ];
    final createSql = 'CREATE TABLE wide(id INTEGER PRIMARY KEY, ' +
        colNames.map((c) => '$c TEXT NOT NULL').join(', ') +
        ')';
    final insertSql = 'INSERT INTO wide(id, ${colNames.join(', ')}) '
        'VALUES (?, ${List.filled(colNames.length, '?').join(', ')})';
    const rowCount = 5000;
    const writeCount = 500;
    const streamCount = 10;
    const watchQuery = 'SELECT id, a, b FROM wide WHERE id < 1000 ORDER BY id';

    List<Object?> row(int i) => [
          i,
          for (final _ in colNames) 'v$i',
        ];

    // ---- resqlite ----
    final resqliteDb = await resqlite.Database.open('${dir.path}/resqlite.db');
    await resqliteDb.execute(createSql);
    await resqliteDb.executeBatch(
      insertSql,
      [for (var i = 0; i < rowCount; i++) row(i)],
    );

    final resqliteDisjoint = await _measureResqlite(
      db: resqliteDb,
      watchQuery: watchQuery,
      streamCount: streamCount,
      writeCount: writeCount,
      updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
      newValueFor: (i) => 'd$i',
    );
    final resqliteOverlap = await _measureResqlite(
      db: resqliteDb,
      watchQuery: watchQuery,
      streamCount: streamCount,
      writeCount: writeCount,
      updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
      newValueFor: (i) => 'z$i',
    );
    await resqliteDb.close();

    // ---- sqlite_async ----
    final asyncDb = sqlite_async.SqliteDatabase(path: '${dir.path}/async.db');
    await asyncDb.initialize();
    await asyncDb.execute(createSql);
    await asyncDb.executeBatch(
      insertSql,
      [for (var i = 0; i < rowCount; i++) row(i)],
    );

    final asyncDisjoint = await _measureSqliteAsync(
      db: asyncDb,
      watchQuery: watchQuery,
      streamCount: streamCount,
      writeCount: writeCount,
      updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
      newValueFor: (i) => 'd$i',
    );
    final asyncOverlap = await _measureSqliteAsync(
      db: asyncDb,
      watchQuery: watchQuery,
      streamCount: streamCount,
      writeCount: writeCount,
      updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
      newValueFor: (i) => 'z$i',
    );
    await asyncDb.close();

    // ---- Render ----
    _writeSubsection(markdown, 'Disjoint column writes (SET c = ?)', {
      'resqlite': (resqliteDisjoint, resqliteOverlap),
      'sqlite_async': (asyncDisjoint, asyncOverlap),
    }, disjoint: true);

    _writeSubsection(markdown, 'Overlapping column writes (SET a = ?)', {
      'resqlite': (resqliteDisjoint, resqliteOverlap),
      'sqlite_async': (asyncDisjoint, asyncOverlap),
    }, disjoint: false);

    print('');
    print('=== Disjoint-column streaming ===');
    print(
      'resqlite disjoint re-emits: ${resqliteDisjoint.reemits} '
      '(${resqliteDisjoint.drainMs.toStringAsFixed(1)} ms drain)',
    );
    print(
      'resqlite overlap  re-emits: ${resqliteOverlap.reemits} '
      '(${resqliteOverlap.drainMs.toStringAsFixed(1)} ms drain)',
    );
    print(
      'sqlite_async disjoint re-emits: ${asyncDisjoint.reemits} '
      '(${asyncDisjoint.drainMs.toStringAsFixed(1)} ms drain)',
    );
    print(
      'sqlite_async overlap  re-emits: ${asyncOverlap.reemits} '
      '(${asyncOverlap.drainMs.toStringAsFixed(1)} ms drain)',
    );
  } finally {
    await dir.delete(recursive: true);
  }

  return markdown.toString();
}

class _StreamResult {
  _StreamResult({required this.reemits, required this.drainMs});
  final int reemits;
  final double drainMs;
}

void _writeSubsection(
  StringBuffer md,
  String title,
  Map<String, (_StreamResult disjoint, _StreamResult overlap)> byLib, {
  required bool disjoint,
}) {
  md.writeln('### $title');
  md.writeln('');
  md.writeln('| Library | Re-emits (total) | Wall drain (ms) | Re-emit ratio |');
  md.writeln('|---|---|---|---|');
  for (final entry in byLib.entries) {
    final (dis, over) = entry.value;
    final pick = disjoint ? dis : over;
    final ratio = over.reemits == 0 ? 0.0 : dis.reemits / over.reemits;
    md.writeln(
      '| ${entry.key} '
      '| ${pick.reemits} '
      '| ${pick.drainMs.toStringAsFixed(1)} '
      '| ${ratio.toStringAsFixed(3)} |',
    );
  }
  md.writeln('');
}

Future<_StreamResult> _measureResqlite({
  required resqlite.Database db,
  required String watchQuery,
  required int streamCount,
  required int writeCount,
  required String updateSql,
  required String Function(int i) newValueFor,
}) async {
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
  var totalEmits = 0;
  final initials = <Completer<void>>[];

  for (var i = 0; i < streamCount; i++) {
    final initialC = Completer<void>();
    initials.add(initialC);
    subs.add(
      db.stream(watchQuery).listen((_) {
        if (!initialC.isCompleted) {
          initialC.complete();
        } else {
          totalEmits++;
        }
      }),
    );
  }

  await Future.wait(initials.map((c) => c.future));

  final sw = Stopwatch()..start();
  for (var i = 0; i < writeCount; i++) {
    await db.execute(updateSql, [newValueFor(i), i]);
    // Two event-queue yields. `Future.delayed(Duration.zero)` schedules
    // via `Timer.run`, which drains the microtask queue first and then
    // fires on the next event-loop turn — so this defeats resqlite's
    // per-microtask invalidation coalescing (experiment 045). Without
    // this, 500 sequential writes collapse to ~10 emissions and the
    // granularity signal is lost.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
  // Wait for any trailing re-emits in flight.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  sw.stop();

  for (final sub in subs) {
    await sub.cancel();
  }

  return _StreamResult(
    reemits: totalEmits,
    drainMs: sw.elapsedMicroseconds / 1000.0,
  );
}

Future<_StreamResult> _measureSqliteAsync({
  required sqlite_async.SqliteDatabase db,
  required String watchQuery,
  required int streamCount,
  required int writeCount,
  required String updateSql,
  required String Function(int i) newValueFor,
}) async {
  final subs = <StreamSubscription<Object?>>[];
  var totalEmits = 0;
  final initials = <Completer<void>>[];

  for (var i = 0; i < streamCount; i++) {
    final initialC = Completer<void>();
    initials.add(initialC);
    subs.add(
      db
          .watch(watchQuery, throttle: Duration.zero)
          .listen((_) {
        if (!initialC.isCompleted) {
          initialC.complete();
        } else {
          totalEmits++;
        }
      }),
    );
  }

  await Future.wait(initials.map((c) => c.future));

  final sw = Stopwatch()..start();
  for (var i = 0; i < writeCount; i++) {
    await db.execute(updateSql, [newValueFor(i), i]);
    // Same coalescing-defeat yield as the resqlite measurement, so both
    // libraries are measured identically.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(const Duration(milliseconds: 50));
  sw.stop();

  for (final sub in subs) {
    await sub.cancel();
  }

  return _StreamResult(
    reemits: totalEmits,
    drainMs: sw.elapsedMicroseconds / 1000.0,
  );
}

// Allow running standalone.
Future<void> main() async {
  final md = await runDisjointColumnsBenchmark();
  print(md);
}
