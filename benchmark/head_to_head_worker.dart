// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';

const _todoSchemaSql = '''
CREATE TABLE IF NOT EXISTS todos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  done INTEGER NOT NULL DEFAULT 0 CHECK(done IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

const _todoSelectSql = '''
SELECT id, title, done, created_at, updated_at
FROM todos
ORDER BY id
''';

const _todoByIdSql = '''
SELECT id, title, done, created_at, updated_at
FROM todos
WHERE id = ?
''';

const _coldOpenIterations = 10;
const _singleCrudIterations = 300;
const _batchWriteCount = 1000;
const _readUnderWriteRowCount = 500;
const _readUnderWriteTargetOpsPerSecond = 1000;
const _readUnderWriteDuration = Duration(seconds: 2);
const _streamLatencyIterations = 20;
const _burstWriteCount = 200;
const _reactiveFanoutWatcherCount = 25;
const _largeReadRowCount = 5000;
const _largeReadIterations = 12;
const _largeReadLargeRowCount = 20000;
const _largeReadLargeIterations = 10;
const _repeatedPointQuerySeedCount = 500;
const _repeatedPointQueryIterations = 1000;
final String _titlePad = List<String>.filled(96, 'x').join();

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);

  final caseRunners = <String, Future<Map<String, Object?>> Function()>{
    'open_only': _runOpenOnlyCase,
    'cold_open': _runColdOpenCase,
    'single_row_crud': _runSingleRowCrudCase,
    'batch_write_transaction': _runBatchWriteTransactionCase,
    'read_under_write': _runReadUnderWriteCase,
    'stream_invalidation_latency': _runStreamInvalidationLatencyCase,
    'burst_coalescing': _runBurstCoalescingCase,
    'reactive_fanout_shared_query': _runReactiveFanoutSharedCase,
    'reactive_fanout_unique_queries': _runReactiveFanoutUniqueCase,
    'large_result_read': () => _runLargeResultReadCase(
      rowCount: _largeReadRowCount,
      iterations: _largeReadIterations,
    ),
    'large_result_read_large': () => _runLargeResultReadCase(
      rowCount: _largeReadLargeRowCount,
      iterations: _largeReadLargeIterations,
    ),
    'repeated_point_query': _runRepeatedPointQueryCase,
  };

  // Run all cases N times, collect per-case results.
  final allRuns = <String, List<Map<String, Object?>>>{};
  for (var i = 0; i < options.repeat; i++) {
    if (options.repeat > 1) print('--- Run ${i + 1}/${options.repeat} ---');
    for (final entry in caseRunners.entries) {
      final result = await _captureCase(entry.value);
      (allRuns[entry.key] ??= []).add(result);
    }
  }

  // Pick median run for each case (by the headline metric).
  final cases = <String, Object?>{};
  for (final entry in allRuns.entries) {
    cases[entry.key] = _medianResult(entry.value);
  }

  final results = <String, Object?>{
    'library': 'resqlite',
    'generatedAt': DateTime.now().toIso8601String(),
    'repeats': options.repeat,
    'cases': cases,
  };

  await File(
    options.outPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  print('Wrote ${options.outPath}');
  exit(0);
}

/// Pick the median result from multiple runs, using the first numeric metric
/// as the sort key.
Map<String, Object?> _medianResult(List<Map<String, Object?>> runs) {
  if (runs.length == 1) return runs.first;
  // Find the first numeric metric to sort by.
  String? sortKey;
  for (final key in runs.first.keys) {
    if (key != 'supported' && key != 'note' && runs.first[key] is num) {
      sortKey = key;
      break;
    }
  }
  if (sortKey == null) return runs.last; // no numeric metric, use last run
  final sorted = List<Map<String, Object?>>.from(runs)
    ..sort((a, b) => ((a[sortKey] as num?) ?? 0)
        .compareTo((b[sortKey] as num?) ?? 0));
  return sorted[sorted.length ~/ 2];
}

Future<Map<String, Object?>> _captureCase(
  Future<Map<String, Object?>> Function() action,
) async {
  try {
    final result = await action();
    return <String, Object?>{'supported': true, ...result};
  } catch (error) {
    return <String, Object?>{'supported': false, 'note': '$error'};
  }
}

class _Options {
  _Options({required this.outPath, required this.repeat});
  final String outPath;
  final int repeat;
}

_Options _parseArgs(List<String> args) {
  String? outPath;
  var repeat = 1;
  for (final arg in args) {
    if (arg.startsWith('--out=')) {
      outPath = arg.substring('--out='.length);
    } else if (arg.startsWith('--repeat=')) {
      repeat = int.parse(arg.substring('--repeat='.length));
    }
  }
  if (outPath == null) {
    throw ArgumentError(
      'Usage: dart run benchmark/head_to_head_worker.dart --out=path.json [--repeat=3]',
    );
  }
  return _Options(outPath: outPath, repeat: repeat);
}

Future<Map<String, Object?>> _runOpenOnlyCase() async {
  final latencies = <double>[];

  Future<void> runIteration({
    required bool measure,
    required int iteration,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_open_only_$iteration',
    );
    try {
      final sw = Stopwatch()..start();
      final db = await Database.open('${tempDir.path}/bench.db');
      sw.stop();
      if (measure) {
        latencies.add(sw.elapsedMicroseconds / 1000.0);
      }
      await db.close();
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  await runIteration(measure: false, iteration: -1);
  for (var i = 0; i < _coldOpenIterations; i++) {
    await runIteration(measure: true, iteration: i);
  }
  return _latencyMetrics(latencies);
}

Future<Map<String, Object?>> _runColdOpenCase() async {
  final latencies = <double>[];

  Future<void> runIteration({
    required bool measure,
    required int iteration,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'resqlite_cold_open_$iteration',
    );
    try {
      final sw = Stopwatch()..start();
      final db = await Database.open('${tempDir.path}/bench.db');
      await db.execute(_todoSchemaSql);
      await db.select('SELECT COUNT(*) AS count FROM todos');
      sw.stop();
      if (measure) {
        latencies.add(sw.elapsedMicroseconds / 1000.0);
      }
      await db.close();
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  await runIteration(measure: false, iteration: -1);
  for (var i = 0; i < _coldOpenIterations; i++) {
    await runIteration(measure: true, iteration: i);
  }
  return _latencyMetrics(latencies);
}

Future<Map<String, Object?>> _runSingleRowCrudCase() async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_single_crud_');
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');

    for (var i = 0; i < 25; i++) {
      final id = await _insertTodo(db, 'warmup_$i', i.isEven);
      await _updateTodoTitle(db, id, 'warmup_updated_$i');
      await _toggleTodo(db, id);
      await _deleteTodo(db, id);
    }

    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < _singleCrudIterations; i++) {
      final id = await _insertTodo(db, 'crud_$i', i.isEven);
      await _updateTodoTitle(db, id, 'crud_updated_$i');
      await _toggleTodo(db, id);
      await _deleteTodo(db, id);
    }
    stopwatch.stop();

    final totalMs = stopwatch.elapsedMicroseconds / 1000.0;
    final opCount = _singleCrudIterations * 4;
    return <String, Object?>{
      'total_ms': totalMs,
      'ops_per_sec': opCount / (totalMs / 1000.0),
    };
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _runBatchWriteTransactionCase() async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_batch_tx_');
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');
    await _insertTodosBatch(db, 100, titlePrefix: 'warmup');
    await db.execute('DELETE FROM todos');

    final sw = Stopwatch()..start();
    await _insertTodosBatch(db, _batchWriteCount, titlePrefix: 'batch');
    sw.stop();
    final totalMs = sw.elapsedMicroseconds / 1000.0;
    return <String, Object?>{
      'total_ms': totalMs,
      'rows_per_sec': _batchWriteCount / (totalMs / 1000.0),
      'rows_committed': (await _countTodos(db)).toDouble(),
    };
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _runReadUnderWriteCase() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_read_under_write_',
  );
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');
    await _insertTodosBatch(db, _readUnderWriteRowCount, titlePrefix: 'seed');

    var stopWriter = false;
    var writeCount = 0;
    final targetWriteIntervalUs =
        Duration.microsecondsPerSecond / _readUnderWriteTargetOpsPerSecond;
    final writerStopwatch = Stopwatch();
    final writer = Future<void>(() async {
      writerStopwatch.start();
      var i = 0;
      while (!stopWriter) {
        final rowId = (i % _readUnderWriteRowCount) + 1;
        await _toggleTodo(db, rowId);
        writeCount += 1;
        i += 1;
        final targetElapsedUs = (writeCount * targetWriteIntervalUs).round();
        final remainingUs =
            targetElapsedUs - writerStopwatch.elapsedMicroseconds;
        if (remainingUs > 0) {
          await Future<void>.delayed(Duration(microseconds: remainingUs));
        }
      }
      writerStopwatch.stop();
    });

    final latencies = <double>[];
    final deadline = DateTime.now().add(_readUnderWriteDuration);
    while (DateTime.now().isBefore(deadline)) {
      final sw = Stopwatch()..start();
      await db.select(_todoSelectSql);
      sw.stop();
      latencies.add(sw.elapsedMicroseconds / 1000.0);
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    stopWriter = true;
    await writer;
    final writerDurationSeconds =
        writerStopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
    final achievedWriterOpsPerSecond = writerDurationSeconds == 0
        ? 0.0
        : writeCount / writerDurationSeconds;

    return <String, Object?>{
      ..._latencyMetrics(latencies),
      'read_samples': latencies.length.toDouble(),
      'writer_ops': writeCount.toDouble(),
      'writer_ops_per_sec': achievedWriterOpsPerSecond,
      'target_writer_ops_per_sec': _readUnderWriteTargetOpsPerSecond.toDouble(),
      'rows': _readUnderWriteRowCount.toDouble(),
    };
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _runStreamInvalidationLatencyCase() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_stream_latency_',
  );
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');
    await _insertTodo(db, 'seed', false);

    final pendingByTitle = <String, Completer<void>>{};
    final sub = db.stream(_todoSelectSql).listen((rows) {
      for (final entry in pendingByTitle.entries.toList(growable: false)) {
        if (_findRowByTitle(rows, entry.key) != null &&
            !entry.value.isCompleted) {
          entry.value.complete();
          pendingByTitle.remove(entry.key);
        }
      }
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      for (var i = 0; i < 3; i++) {
        final title = 'stream_latency_warmup_$i';
        final pending = Completer<void>();
        pendingByTitle[title] = pending;
        await _insertTodo(db, title, false);
        await pending.future.timeout(const Duration(seconds: 2));
      }

      final latencies = <double>[];
      for (var i = 0; i < _streamLatencyIterations; i++) {
        final title =
            'stream_latency_${DateTime.now().microsecondsSinceEpoch}_$i';
        final pending = Completer<void>();
        pendingByTitle[title] = pending;
        final sw = Stopwatch()..start();
        await _insertTodo(db, title, false);
        await pending.future.timeout(const Duration(seconds: 2));
        sw.stop();
        latencies.add(sw.elapsedMicroseconds / 1000.0);
      }
      return _latencyMetrics(latencies);
    } finally {
      await sub.cancel();
    }
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _runBurstCoalescingCase() async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_burst_');
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');
    await _insertTodo(db, 'seed', false);

    var emissions = 0;
    var latestRowCount = 0;
    DateTime? lastEmissionAt;
    final sub = db.stream(_todoSelectSql).listen((rows) {
      emissions += 1;
      latestRowCount = rows.length;
      lastEmissionAt = DateTime.now();
    });

    try {
      await _waitForCondition(
        condition: () => emissions > 0,
        timeout: const Duration(seconds: 2),
      );

      final beforeBurst = emissions;
      final settleStopwatch = Stopwatch()..start();
      await _insertTodosBatch(db, _burstWriteCount, titlePrefix: 'batch');
      final expectedRows = 1 + _burstWriteCount;

      await _waitForCondition(
        condition: () => latestRowCount >= expectedRows,
        timeout: const Duration(seconds: 2),
      );
      await _waitForCondition(
        condition: () {
          final last = lastEmissionAt;
          if (last == null) {
            return false;
          }
          return DateTime.now().difference(last) >=
              const Duration(milliseconds: 200);
        },
        timeout: const Duration(seconds: 2),
      );
      settleStopwatch.stop();

      final afterBurst = math.max(0, emissions - beforeBurst);
      return <String, Object?>{
        'emissions_after_burst': afterBurst.toDouble(),
        'burst_writes': _burstWriteCount.toDouble(),
        'emissions_per_100_writes': (afterBurst / _burstWriteCount) * 100,
        'time_to_quiet_ms': settleStopwatch.elapsedMicroseconds / 1000.0,
      };
    } finally {
      await sub.cancel();
    }
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _runReactiveFanoutSharedCase() {
  return _runReactiveFanoutCase(
    serializeWatcherAttach: true,
    streamForWatcher: (Database db, int index) => db.stream(_todoSelectSql),
    trigger: (Database db, int watcherCount) =>
        _insertTodo(db, 'fanout_probe', false),
    matchForWatcher: (rows, index) => _findRowByTitle(rows, 'fanout_probe'),
  );
}

Future<Map<String, Object?>> _runReactiveFanoutUniqueCase() {
  return _runReactiveFanoutCase(
    serializeWatcherAttach: false,
    streamForWatcher: (Database db, int index) =>
        db.stream(_todoByIdSql, <Object?>[index + 1]),
    trigger: (Database db, int watcherCount) =>
        _insertTodosBatch(db, watcherCount, titlePrefix: 'batch'),
    matchForWatcher: (rows, index) => rows.isEmpty ? null : rows.first,
  );
}

Future<Map<String, Object?>> _runReactiveFanoutCase({
  required bool serializeWatcherAttach,
  required Stream<List<Map<String, Object?>>> Function(Database db, int index)
      streamForWatcher,
  required Future<void> Function(Database db, int watcherCount) trigger,
  required Map<String, Object?>? Function(
    List<Map<String, Object?>> rows,
    int index,
  )
      matchForWatcher,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_fanout_');
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');

    final ready = <Completer<void>>[];
    final postWrite = <Completer<void>>[];
    final subscriptions = <StreamSubscription<List<Map<String, Object?>>>>[];

    void attachWatcher(int index) {
      final readyCompleter = Completer<void>();
      final postWriteCompleter = Completer<void>();
      ready.add(readyCompleter);
      postWrite.add(postWriteCompleter);

      final sub = streamForWatcher(db, index).listen((rows) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
        if (!postWriteCompleter.isCompleted &&
            matchForWatcher(rows, index) != null) {
          postWriteCompleter.complete();
        }
      });
      subscriptions.add(sub);
    }

    if (serializeWatcherAttach) {
      attachWatcher(0);
      await Future.wait(
        ready.map(
          (completer) => completer.future.timeout(const Duration(seconds: 2)),
        ),
      );
      for (var index = 1; index < _reactiveFanoutWatcherCount; index++) {
        attachWatcher(index);
      }
    } else {
      for (var index = 0; index < _reactiveFanoutWatcherCount; index++) {
        attachWatcher(index);
      }
    }

    try {
      await Future.wait(
        ready.map(
          (completer) => completer.future.timeout(const Duration(seconds: 2)),
        ),
      );
      final sw = Stopwatch()..start();
      await trigger(db, _reactiveFanoutWatcherCount);
      await Future.wait(
        postWrite.map(
          (completer) => completer.future.timeout(const Duration(seconds: 2)),
        ),
      );
      sw.stop();
      final totalMs = sw.elapsedMicroseconds / 1000.0;
      return <String, Object?>{
        'fanout_ms': totalMs,
        'per_watcher_ms': totalMs / _reactiveFanoutWatcherCount,
        'watchers': _reactiveFanoutWatcherCount.toDouble(),
      };
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

Future<Map<String, Object?>> _runLargeResultReadCase({
  required int rowCount,
  required int iterations,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_large_read_');
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');
    await _insertTodosBatch(db, rowCount, titlePrefix: 'batch');

    final latencies = <double>[];
    for (var i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      await db.select(_todoSelectSql);
      sw.stop();
      if (i > 0) {
        latencies.add(sw.elapsedMicroseconds / 1000.0);
      }
    }

    return <String, Object?>{
      'mean_ms': _mean(latencies),
      'p95_ms': _percentile(latencies, 0.95),
      'rows': rowCount.toDouble(),
    };
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _runRepeatedPointQueryCase() async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_point_query_');
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(_todoSchemaSql);
    await db.execute('DELETE FROM todos');
    await _insertTodosBatch(
      db,
      _repeatedPointQuerySeedCount,
      titlePrefix: 'batch',
    );

    final rng = math.Random(42);
    final warmupCount = (_repeatedPointQueryIterations * 0.1).ceil();
    for (var i = 0; i < warmupCount; i++) {
      final id = rng.nextInt(_repeatedPointQuerySeedCount) + 1;
      await db.select(_todoByIdSql, <Object?>[id]);
    }

    final latencies = <double>[];
    for (var i = 0; i < _repeatedPointQueryIterations; i++) {
      final id = rng.nextInt(_repeatedPointQuerySeedCount) + 1;
      final sw = Stopwatch()..start();
      await db.select(_todoByIdSql, <Object?>[id]);
      sw.stop();
      latencies.add(sw.elapsedMicroseconds / 1000.0);
    }

    final totalMs = latencies.fold<double>(0.0, (a, b) => a + b);
    return <String, Object?>{
      ..._latencyMetrics(latencies),
      'qps': _repeatedPointQueryIterations / (totalMs / 1000.0),
    };
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<int> _insertTodo(Database db, String title, bool done) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final result = await db.execute(
    'INSERT INTO todos(title, done, created_at, updated_at) VALUES (?, ?, ?, ?)',
    <Object?>[title, done ? 1 : 0, now, now],
  );
  return result.lastInsertId;
}

Future<void> _insertTodosBatch(
  Database db,
  int count, {
  required String titlePrefix,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final parameterSets = List<List<Object?>>.generate(
    count,
    (index) => <Object?>[
      '$titlePrefix-$index $_titlePad',
      index.isEven ? 1 : 0,
      now,
      now,
    ],
    growable: false,
  );
  await db.executeBatch(
    'INSERT INTO todos(title, done, created_at, updated_at) VALUES (?, ?, ?, ?)',
    parameterSets,
  );
}

Future<void> _updateTodoTitle(Database db, int id, String title) {
  return db.execute(
    'UPDATE todos SET title = ?, updated_at = ? WHERE id = ?',
    <Object?>[title, DateTime.now().toUtc().toIso8601String(), id],
  );
}

Future<void> _toggleTodo(Database db, int id) {
  return db.execute(
    '''
    UPDATE todos
    SET done = CASE done WHEN 0 THEN 1 ELSE 0 END,
        updated_at = ?
    WHERE id = ?
    ''',
    <Object?>[DateTime.now().toUtc().toIso8601String(), id],
  );
}

Future<void> _deleteTodo(Database db, int id) {
  return db.execute('DELETE FROM todos WHERE id = ?', <Object?>[id]);
}

Future<int> _countTodos(Database db) async {
  final rows = await db.select('SELECT COUNT(*) AS count FROM todos');
  return (rows.first['count']! as num).toInt();
}

Map<String, Object?>? _findRowByTitle(
  List<Map<String, Object?>> rows,
  String title,
) {
  for (final row in rows) {
    if (row['title'] == title) {
      return row;
    }
  }
  return null;
}

Future<void> _waitForCondition({
  required bool Function() condition,
  required Duration timeout,
}) async {
  final start = DateTime.now();
  while (!condition()) {
    if (DateTime.now().difference(start) > timeout) {
      throw TimeoutException('Timed out waiting for condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Map<String, Object?> _latencyMetrics(List<double> latencies) {
  return <String, Object?>{
    'mean_ms': _mean(latencies),
    'p50_ms': _percentile(latencies, 0.50),
    'p95_ms': _percentile(latencies, 0.95),
    'p99_ms': _percentile(latencies, 0.99),
  };
}

double _mean(List<double> values) {
  return values.reduce((a, b) => a + b) / values.length;
}

double _percentile(List<double> values, double percentile) {
  final sorted = List<double>.from(values)..sort();
  final clamped = percentile.clamp(0.0, 1.0);
  final rank = (sorted.length - 1) * clamped;
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  final weight = rank - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}
