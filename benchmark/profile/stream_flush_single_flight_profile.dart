// ignore_for_file: avoid_print
//
// Stream flush admission profile — exp 120.
//
// Measures whether stream re-query admission is dispatching beyond reader
// availability after exp 118 eliminated wake retries. Run once on baseline,
// then again on the candidate branch:
//
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/stream_flush_single_flight_profile.dart --label=baseline

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

const int _a11cRowCount = 5000;
const int _a11cStreamCount = 50;
const int _a11cWriteCount = 500;

const int _keyedRowCount = 10000;
const int _keyedStreamCount = 50;
const int _keyedWriteCount = 200;
const int _keyedPrngSeed = 0xBEEF;

final class _ProfileRow {
  _ProfileRow({
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.parked,
    required this.retries,
    required this.maxParked,
    required this.invalidateCount,
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
  final int invalidateCount;
  final int intersectionEntries;
  final int emissions;
  final int observedHits;

  double get wallMs => wallUs / 1000.0;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; dispatch counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final label = _option(args, '--label') ?? 'candidate';

  final rows = <_ProfileRow>[
    ...await _runA11cProfile(),
    await _runKeyedPkProfile(),
  ];

  final markdown = _renderMarkdown(rows, label);
  print(markdown);
}

Future<List<_ProfileRow>> _runA11cProfile() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'stream_flush_profile_a11c_',
  );
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

Future<_ProfileRow> _runA11cScenario(
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

Future<_ProfileRow> _runKeyedPkProfile() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'stream_flush_profile_pk_',
  );
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

_ProfileRow _rowFromCounters({
  required String workload,
  required String shape,
  required int wallUs,
  int emissions = 0,
  int observedHits = 0,
}) {
  final counters = ProfileCounters.snapshot();
  return _ProfileRow(
    workload: workload,
    shape: shape,
    wallUs: wallUs,
    parked: counters['dispatcher_parked_total']!,
    retries: counters['dispatcher_wake_retry_total']!,
    maxParked: counters['dispatcher_max_parked_concurrent']!,
    invalidateCount: counters['invalidate_count']!,
    intersectionEntries: counters['intersection_entries']!,
    emissions: emissions,
    observedHits: observedHits,
  );
}

String _renderMarkdown(List<_ProfileRow> rows, String label) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 120 - Stream Flush Single-Flight Profile');
  buf.writeln();
  buf.writeln('Run label: `$label`');
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/stream_flush_single_flight_profile.dart '
    '--label=$label',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln(
    '| workload | shape | wall_ms | parked_total | wake_retry_total | '
    'max_parked | invalidate_count | intersection_entries | emissions | observed_hits |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.workload} | ${row.shape} | '
      '${row.wallMs.toStringAsFixed(2)} | ${row.parked} | '
      '${row.retries} | ${row.maxParked} | ${row.invalidateCount} | '
      '${row.intersectionEntries} | ${row.emissions} | '
      '${row.observedHits} |',
    );
  }
  return buf.toString();
}

String? _option(List<String> args, String name) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  return null;
}
