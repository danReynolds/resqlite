// ignore_for_file: avoid_print

// Focused public-API A/B harness for exp 271's bounded writer-completion
// mailbox catch.
//
// Run this file unchanged in baseline and candidate checkouts:
//
//   dart run benchmark/experiments/writer_completion_catch.dart \
//     --label=baseline
//
// The first three lanes isolate sequential writer completions without active
// streams. The remaining lanes are guardrails for paths that should either
// bypass a bounded fast catch or preserve their existing semantics: active
// streams, concurrent submissions, transactions, deliberately slow writes,
// and SQLite errors. The 16 ms heartbeat lane deliberately performs no
// explicit yield between sequential writes. Its timer exposes event-loop
// starvation if immediately completed write futures monopolize the isolate.
//
// Every timed sample is emitted as JSON after its stopwatch has stopped. The
// final `RESULT` line contains the complete machine-readable result.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';

const _defaultSamples = 7;
const _defaultWarmupOps = 1200;
const _defaultJitterRuns = 3;
const _defaultJitterMs = 1500;

const _noopOpsPerSample = 1200;
const _pointOpsPerSample = 1000;
const _insertOpsPerSample = 600;
const _activeStreamOpsPerSample = 160;
const _burstsPerSample = 16;
const _burstSize = 32;
const _transactionsPerSample = 60;
const _writesPerTransaction = 3;
const _slowRows = 20000;
const _slowWritesPerSample = 4;
const _constraintErrorsPerSample = 96;

const _heartbeatPeriod = Duration(milliseconds: 16);
const _heartbeatPeriodUs = 16000;
const _pointUpdateSql = 'UPDATE items SET value = value + 1 WHERE id = ?';
const _pointUpdateParameters = <Object?>[1];

Future<void> main(List<String> args) async {
  late final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('Argument error: ${error.message}');
    stderr.writeln('Use --help for usage.');
    exitCode = 64;
    return;
  }

  if (options.help) {
    print(_usage);
    return;
  }

  final config = <String, Object?>{
    'experiment': 'writer_completion_catch',
    'label': options.label,
    'samples': options.samples,
    'warmup_ops': options.warmupOps,
    'workload_divisor': options.workloadDivisor,
    'jitter_runs': options.jitterRuns,
    'jitter_duration_ms': options.jitterDuration.inMilliseconds,
    'heartbeat_period_us': _heartbeatPeriodUs,
    'pid': pid,
  };
  print('Writer completion catch benchmark (exp 271)');
  print('CONFIG ${jsonEncode(config)}');

  final lanes = <String, _TimingSeries>{};
  lanes['sequential_no_stream_noop_update'] = await _runNoopUpdate(options);
  lanes['sequential_no_stream_point_update'] = await _runPointUpdate(options);
  lanes['sequential_no_stream_small_insert'] = await _runSmallInsert(options);
  final activeStream = await _runActiveStreamGuard(options);
  lanes[activeStream.timing.lane] = activeStream.timing;
  lanes['concurrent_burst_guard'] = await _runConcurrentBurstGuard(options);
  lanes['transaction_guard'] = await _runTransactionGuard(options);
  lanes['slow_write_miss_path'] = await _runSlowWriteGuard(options);
  final constraint = await _runConstraintErrorGuard(options);
  lanes[constraint.timing.lane] = constraint.timing;
  final jitter = await _runJitterGuard(options);

  _printTimingTable(lanes.values);
  print(
    'GUARD ${jsonEncode({'guard': 'active_stream', ...activeStream.guard})}',
  );
  print(
    'GUARD ${jsonEncode({'guard': 'constraint_error', ...constraint.guard})}',
  );
  print('JITTER ${jsonEncode(jitter.summary)}');

  final result = <String, Object?>{
    ...config,
    'lanes': {
      for (final entry in lanes.entries) entry.key: entry.value.toJson(),
    },
    'guards': {
      'active_stream': activeStream.guard,
      'constraint_error': constraint.guard,
    },
    'heartbeat_16ms': jitter.summary,
    'jitter_runs_detail': [for (final run in jitter.runs) run.toJson()],
  };
  print('RESULT ${jsonEncode(result)}');
}

Future<_TimingSeries> _runNoopUpdate(_Options options) {
  return _withDatabase('noop', (db) async {
    await _createItems(db);
    const sql = 'UPDATE items SET value = value WHERE 0';

    for (var i = 0; i < options.warmupOps; i++) {
      final result = await db.execute(sql);
      if (result.affectedRows != 0) {
        throw StateError('No-op warmup unexpectedly affected rows.');
      }
    }

    final operations = options.scaled(_noopOpsPerSample, minimum: 20);
    var affectedRows = 0;
    return _measure(
      lane: 'sequential_no_stream_noop_update',
      unit: 'write',
      samples: options.samples,
      unitsPerSample: operations,
      body: (_) async {
        affectedRows = 0;
        for (var i = 0; i < operations; i++) {
          affectedRows += (await db.execute(sql)).affectedRows;
        }
      },
      verify: (_) async {
        if (affectedRows != 0) {
          throw StateError(
            'No-op update affected $affectedRows rows; expected 0.',
          );
        }
      },
    );
  });
}

Future<_TimingSeries> _runPointUpdate(_Options options) {
  return _withDatabase('point', (db) async {
    await _createItems(db);
    var expectedValue = 0;
    for (var i = 0; i < options.warmupOps; i++) {
      await db.execute(_pointUpdateSql, _pointUpdateParameters);
      expectedValue++;
    }

    final operations = options.scaled(_pointOpsPerSample, minimum: 20);
    var affectedRows = 0;
    return _measure(
      lane: 'sequential_no_stream_point_update',
      unit: 'write',
      samples: options.samples,
      unitsPerSample: operations,
      body: (_) async {
        affectedRows = 0;
        for (var i = 0; i < operations; i++) {
          affectedRows += (await db.execute(
            _pointUpdateSql,
            _pointUpdateParameters,
          )).affectedRows;
        }
        expectedValue += operations;
      },
      verify: (_) async {
        if (affectedRows != operations) {
          throw StateError(
            'Point updates affected $affectedRows rows; '
            'expected $operations.',
          );
        }
        await _expectItemValue(db, expectedValue);
      },
    );
  });
}

Future<_TimingSeries> _runSmallInsert(_Options options) {
  return _withDatabase('insert', (db) async {
    await db.execute('''
CREATE TABLE inserts(
  id INTEGER PRIMARY KEY,
  payload TEXT NOT NULL,
  ordinal INTEGER NOT NULL
)
''');
    const sql = 'INSERT INTO inserts(payload, ordinal) VALUES (?, ?)';
    final operations = options.scaled(_insertOpsPerSample, minimum: 20);
    final parameters = <List<Object?>>[
      for (var i = 0; i < operations; i++) <Object?>['small-$i', i],
    ];

    for (var i = 0; i < options.warmupOps; i++) {
      await db.execute(sql, <Object?>['warmup-$i', i]);
    }
    await db.execute('DELETE FROM inserts');

    var affectedRows = 0;
    var lastInsertId = 0;
    return _measure(
      lane: 'sequential_no_stream_small_insert',
      unit: 'write',
      samples: options.samples,
      unitsPerSample: operations,
      beforeSample: (_) => db.execute('DELETE FROM inserts'),
      body: (_) async {
        affectedRows = 0;
        for (final values in parameters) {
          final result = await db.execute(sql, values);
          affectedRows += result.affectedRows;
          lastInsertId = result.lastInsertId;
        }
      },
      verify: (_) async {
        if (affectedRows != operations || lastInsertId <= 0) {
          throw StateError(
            'Insert completion mismatch: affected=$affectedRows '
            'lastInsertId=$lastInsertId expected affected=$operations.',
          );
        }
        final rows = await db.select('SELECT COUNT(*) AS count FROM inserts');
        if (rows.single['count'] != operations) {
          throw StateError(
            'Insert count was ${rows.single['count']}; expected $operations.',
          );
        }
      },
    );
  });
}

Future<_GuardedTiming> _runActiveStreamGuard(_Options options) {
  return _withDatabase('stream', (db) async {
    await _createItems(db);
    final probe = _ValueStreamProbe(
      db.stream('SELECT value FROM items WHERE id = 1'),
    );
    try {
      await probe.waitForAtLeast(0);
      var expectedValue = 0;
      for (var i = 0; i < options.warmupOps; i++) {
        await db.execute(_pointUpdateSql, _pointUpdateParameters);
        expectedValue++;
      }
      await probe.waitForAtLeast(expectedValue);

      final operations = options.scaled(_activeStreamOpsPerSample, minimum: 10);
      var affectedRows = 0;
      final timing = await _measure(
        lane: 'active_stream_sequential_guard',
        unit: 'write',
        samples: options.samples,
        unitsPerSample: operations,
        body: (_) async {
          affectedRows = 0;
          for (var i = 0; i < operations; i++) {
            affectedRows += (await db.execute(
              _pointUpdateSql,
              _pointUpdateParameters,
            )).affectedRows;
          }
          expectedValue += operations;
        },
        verify: (_) async {
          if (affectedRows != operations) {
            throw StateError(
              'Active-stream updates affected $affectedRows rows; '
              'expected $operations.',
            );
          }
          await probe.waitForAtLeast(expectedValue);
          await _expectItemValue(db, expectedValue);
        },
      );
      return _GuardedTiming(
        timing: timing,
        guard: <String, Object?>{
          'passed': true,
          'emissions': probe.emissions,
          'final_stream_value': probe.latestValue,
          'expected_final_value': expectedValue,
        },
      );
    } finally {
      await probe.cancel();
    }
  });
}

Future<_TimingSeries> _runConcurrentBurstGuard(_Options options) {
  return _withDatabase('burst', (db) async {
    await _createItems(db);
    final bursts = options.scaled(_burstsPerSample);
    final operations = bursts * _burstSize;
    var expectedValue = 0;

    final warmupBursts = math.max(1, options.warmupOps ~/ _burstSize);
    for (var burst = 0; burst < warmupBursts; burst++) {
      await Future.wait([
        for (var i = 0; i < _burstSize; i++)
          db.execute(_pointUpdateSql, _pointUpdateParameters),
      ]);
      expectedValue += _burstSize;
    }

    return _measure(
      lane: 'concurrent_burst_guard',
      unit: 'write',
      samples: options.samples,
      unitsPerSample: operations,
      metadata: <String, Object?>{
        'bursts_per_sample': bursts,
        'writes_per_burst': _burstSize,
      },
      body: (_) async {
        for (var burst = 0; burst < bursts; burst++) {
          final results = await Future.wait([
            for (var i = 0; i < _burstSize; i++)
              db.execute(_pointUpdateSql, _pointUpdateParameters),
          ]);
          if (results.any((result) => result.affectedRows != 1)) {
            throw StateError('Concurrent burst returned a non-unit result.');
          }
        }
        expectedValue += operations;
      },
      verify: (_) => _expectItemValue(db, expectedValue),
    );
  });
}

Future<_TimingSeries> _runTransactionGuard(_Options options) {
  return _withDatabase('transaction', (db) async {
    await _createItems(db);
    final transactions = options.scaled(_transactionsPerSample, minimum: 2);
    var expectedValue = 0;
    final warmupTransactions = math.max(
      1,
      options.warmupOps ~/ _writesPerTransaction,
    );
    for (var i = 0; i < warmupTransactions; i++) {
      await _pointUpdateTransaction(db);
      expectedValue += _writesPerTransaction;
    }

    return _measure(
      lane: 'transaction_guard',
      unit: 'transaction',
      samples: options.samples,
      unitsPerSample: transactions,
      metadata: <String, Object?>{
        'writes_per_transaction': _writesPerTransaction,
        'writes_per_sample': transactions * _writesPerTransaction,
      },
      body: (_) async {
        for (var i = 0; i < transactions; i++) {
          await _pointUpdateTransaction(db);
        }
        expectedValue += transactions * _writesPerTransaction;
      },
      verify: (_) => _expectItemValue(db, expectedValue),
    );
  });
}

Future<void> _pointUpdateTransaction(Database db) {
  return db.transaction((transaction) async {
    for (var i = 0; i < _writesPerTransaction; i++) {
      final result = await transaction.execute(
        _pointUpdateSql,
        _pointUpdateParameters,
      );
      if (result.affectedRows != 1) {
        throw StateError(
          'Transaction update affected ${result.affectedRows} rows.',
        );
      }
    }
  });
}

Future<_TimingSeries> _runSlowWriteGuard(_Options options) {
  return _withDatabase('slow', (db) async {
    final rowCount = options.scaled(_slowRows, minimum: 1000);
    await db.execute(
      'CREATE TABLE slow_items('
      'id INTEGER PRIMARY KEY, value INTEGER NOT NULL, payload TEXT NOT NULL)',
    );
    await db.executeBatch(
      'INSERT INTO slow_items(id, value, payload) VALUES (?, ?, ?)',
      <List<Object?>>[
        for (var i = 1; i <= rowCount; i++) <Object?>[i, 0, 'payload-$i'],
      ],
    );
    const sql =
        'UPDATE slow_items '
        'SET value = value + 1, payload = substr(payload || ?, 1, 48)';
    const parameters = <Object?>['x'];

    final warmup = await db.execute(sql, parameters);
    if (warmup.affectedRows != rowCount) {
      throw StateError(
        'Slow-write warmup affected ${warmup.affectedRows}; '
        'expected $rowCount.',
      );
    }
    var expectedValue = 1;
    final writes = options.scaled(_slowWritesPerSample);
    var affectedRows = 0;

    return _measure(
      lane: 'slow_write_miss_path',
      unit: 'write',
      samples: options.samples,
      unitsPerSample: writes,
      metadata: <String, Object?>{'rows_per_write': rowCount},
      body: (_) async {
        affectedRows = 0;
        for (var i = 0; i < writes; i++) {
          affectedRows += (await db.execute(sql, parameters)).affectedRows;
        }
        expectedValue += writes;
      },
      verify: (_) async {
        if (affectedRows != rowCount * writes) {
          throw StateError(
            'Slow writes affected $affectedRows rows; '
            'expected ${rowCount * writes}.',
          );
        }
        final rows = await db.select(
          'SELECT MIN(value) AS minimum, MAX(value) AS maximum '
          'FROM slow_items',
        );
        final row = rows.single;
        if (row['minimum'] != expectedValue ||
            row['maximum'] != expectedValue) {
          throw StateError(
            'Slow-write values were ${row['minimum']}..${row['maximum']}; '
            'expected $expectedValue.',
          );
        }
      },
    );
  });
}

Future<_GuardedTiming> _runConstraintErrorGuard(_Options options) {
  return _withDatabase('constraint', (db) async {
    await db.execute(
      'CREATE TABLE unique_items('
      'id INTEGER PRIMARY KEY, token TEXT NOT NULL UNIQUE)',
    );
    const sql = 'INSERT INTO unique_items(id, token) VALUES (?, ?)';
    const duplicateParameters = <Object?>[2, 'duplicate'];
    await db.execute(sql, const <Object?>[1, 'duplicate']);

    var caught = 0;
    Future<void> expectConstraintError() async {
      try {
        await db.execute(sql, duplicateParameters);
        throw StateError('Duplicate insert unexpectedly succeeded.');
      } on ResqliteQueryException catch (error) {
        if (error.sqliteCode != 19 ||
            error.sql != sql ||
            error.parameters == null ||
            !_listEquals(error.parameters!, duplicateParameters) ||
            !error.message.contains('UNIQUE constraint failed')) {
          throw StateError(
            'Constraint error lost fidelity: code=${error.sqliteCode} '
            'sql=${error.sql} params=${error.parameters} '
            'message=${error.message}',
          );
        }
        caught++;
      }
    }

    final warmupErrors = math.max(1, math.min(options.warmupOps, 16));
    for (var i = 0; i < warmupErrors; i++) {
      await expectConstraintError();
    }
    caught = 0;

    final errors = options.scaled(_constraintErrorsPerSample, minimum: 4);
    final timing = await _measure(
      lane: 'constraint_error_fidelity',
      unit: 'error',
      samples: options.samples,
      unitsPerSample: errors,
      body: (_) async {
        for (var i = 0; i < errors; i++) {
          await expectConstraintError();
        }
      },
    );
    final expectedCaught = errors * options.samples;
    if (caught != expectedCaught) {
      throw StateError(
        'Caught $caught constraint errors; expected $expectedCaught.',
      );
    }

    final recovery = await db.execute(sql, const <Object?>[3, 'recovered']);
    final rows = await db.select('SELECT COUNT(*) AS count FROM unique_items');
    if (recovery.affectedRows != 1 || rows.single['count'] != 2) {
      throw StateError('Writer did not recover after constraint errors.');
    }

    return _GuardedTiming(
      timing: timing,
      guard: <String, Object?>{
        'passed': true,
        'caught_errors': caught,
        'sqlite_code': 19,
        'sql_preserved': true,
        'parameters_preserved': true,
        'writer_recovered': true,
      },
    );
  });
}

Future<_JitterResult> _runJitterGuard(_Options options) {
  return _withDatabase('jitter', (db) async {
    await _createItems(db);
    var expectedValue = 0;
    for (var i = 0; i < options.warmupOps; i++) {
      await db.execute(_pointUpdateSql, _pointUpdateParameters);
      expectedValue++;
    }

    final runs = <_JitterRun>[];
    for (var run = 1; run <= options.jitterRuns; run++) {
      final stopwatch = Stopwatch()..start();
      final callbackTimesUs = <int>[];
      final timer = Timer.periodic(_heartbeatPeriod, (timer) {
        callbackTimesUs.add(stopwatch.elapsedMicroseconds);
      });

      var writes = 0;
      while (stopwatch.elapsed < options.jitterDuration) {
        final result = await db.execute(
          _pointUpdateSql,
          _pointUpdateParameters,
        );
        if (result.affectedRows != 1) {
          timer.cancel();
          throw StateError(
            'Jitter-lane update affected ${result.affectedRows} rows.',
          );
        }
        writes++;
      }
      timer.cancel();
      stopwatch.stop();

      expectedValue += writes;
      await _expectItemValue(db, expectedValue);

      final jitterRun = _JitterRun.fromCallbacks(
        run: run,
        elapsedUs: stopwatch.elapsedMicroseconds,
        writes: writes,
        callbackTimesUs: callbackTimesUs,
      );
      runs.add(jitterRun);
      print('JITTER_RUN ${jsonEncode(jitterRun.toJson())}');
    }

    return _JitterResult(runs);
  });
}

Future<_TimingSeries> _measure({
  required String lane,
  required String unit,
  required int samples,
  required int unitsPerSample,
  required Future<void> Function(int sample) body,
  Future<void> Function(int sample)? beforeSample,
  Future<void> Function(int sample)? verify,
  Map<String, Object?> metadata = const <String, Object?>{},
}) async {
  final elapsedUs = <int>[];
  for (var sample = 1; sample <= samples; sample++) {
    if (beforeSample != null) await beforeSample(sample);
    final stopwatch = Stopwatch()..start();
    await body(sample);
    stopwatch.stop();
    elapsedUs.add(stopwatch.elapsedMicroseconds);
    if (verify != null) await verify(sample);
    print(
      'SAMPLE ${jsonEncode(<String, Object?>{'lane': lane, 'sample': sample, 'elapsed_us': stopwatch.elapsedMicroseconds, 'units': unitsPerSample, 'unit': unit, 'us_per_unit': stopwatch.elapsedMicroseconds / unitsPerSample})}',
    );
  }
  return _TimingSeries(
    lane: lane,
    unit: unit,
    unitsPerSample: unitsPerSample,
    elapsedUs: elapsedUs,
    metadata: metadata,
  );
}

Future<T> _withDatabase<T>(
  String label,
  Future<T> Function(Database db) body,
) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_exp271_${label}_',
  );
  Database? db;
  try {
    db = await Database.open('${tempDir.path}/benchmark.db');
    return await body(db);
  } finally {
    if (db != null) await db.close();
    await tempDir.delete(recursive: true);
  }
}

Future<void> _createItems(Database db) async {
  await db.execute(
    'CREATE TABLE items('
    'id INTEGER PRIMARY KEY, value INTEGER NOT NULL, payload TEXT NOT NULL)',
  );
  await db.execute(
    'INSERT INTO items(id, value, payload) VALUES (?, ?, ?)',
    const <Object?>[1, 0, 'seed'],
  );
}

Future<void> _expectItemValue(Database db, int expected) async {
  final rows = await db.select('SELECT value FROM items WHERE id = 1');
  final actual = rows.single['value'];
  if (actual != expected) {
    throw StateError('Item value was $actual; expected $expected.');
  }
}

bool _listEquals(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

void _printTimingTable(Iterable<_TimingSeries> lanes) {
  print('');
  print(
    '| lane | unit | samples | units/sample | median us/unit | p90 | max |',
  );
  print('|---|---|---:|---:|---:|---:|---:|');
  for (final lane in lanes) {
    print(
      '| ${lane.lane} | ${lane.unit} | ${lane.elapsedUs.length} '
      '| ${lane.unitsPerSample} | ${lane.medianUsPerUnit.toStringAsFixed(3)} '
      '| ${lane.p90UsPerUnit.toStringAsFixed(3)} '
      '| ${lane.maxUsPerUnit.toStringAsFixed(3)} |',
    );
  }
  print('');
}

double _percentileDouble(List<double> values, double fraction) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * fraction).round();
  return sorted[index];
}

int _percentileInt(List<int> values, double fraction) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * fraction).round();
  return sorted[index];
}

final class _TimingSeries {
  const _TimingSeries({
    required this.lane,
    required this.unit,
    required this.unitsPerSample,
    required this.elapsedUs,
    required this.metadata,
  });

  final String lane;
  final String unit;
  final int unitsPerSample;
  final List<int> elapsedUs;
  final Map<String, Object?> metadata;

  List<double> get usPerUnit => <double>[
    for (final elapsed in elapsedUs) elapsed / unitsPerSample,
  ];

  double get medianUsPerUnit => _percentileDouble(usPerUnit, 0.50);
  double get p90UsPerUnit => _percentileDouble(usPerUnit, 0.90);
  double get maxUsPerUnit => usPerUnit.reduce(math.max);

  Map<String, Object?> toJson() => <String, Object?>{
    'unit': unit,
    'samples': elapsedUs.length,
    'units_per_sample': unitsPerSample,
    ...metadata,
    'samples_elapsed_us': elapsedUs,
    'samples_us_per_unit': usPerUnit,
    'min_us_per_unit': usPerUnit.reduce(math.min),
    'median_us_per_unit': medianUsPerUnit,
    'p90_us_per_unit': p90UsPerUnit,
    'max_us_per_unit': maxUsPerUnit,
  };
}

final class _GuardedTiming {
  const _GuardedTiming({required this.timing, required this.guard});

  final _TimingSeries timing;
  final Map<String, Object?> guard;
}

final class _JitterRun {
  const _JitterRun({
    required this.run,
    required this.elapsedUs,
    required this.writes,
    required this.callbackTimesUs,
    required this.callbackGapsUs,
  });

  factory _JitterRun.fromCallbacks({
    required int run,
    required int elapsedUs,
    required int writes,
    required List<int> callbackTimesUs,
  }) {
    final gaps = <int>[];
    var previousUs = 0;
    for (final callbackUs in callbackTimesUs) {
      gaps.add(callbackUs - previousUs);
      previousUs = callbackUs;
    }
    gaps.add(math.max(0, elapsedUs - previousUs));
    return _JitterRun(
      run: run,
      elapsedUs: elapsedUs,
      writes: writes,
      callbackTimesUs: callbackTimesUs,
      callbackGapsUs: gaps,
    );
  }

  final int run;
  final int elapsedUs;
  final int writes;
  final List<int> callbackTimesUs;
  final List<int> callbackGapsUs;

  int get callbacks => callbackTimesUs.length;
  // This deliberately reports a conservative lower bound from each observed
  // gap instead of subtracting callback count from elapsed time. Periodic
  // timers may deliver later callbacks less than one period apart, so total
  // callback count can mask an earlier gap spanning multiple periods.
  int get longGapMissedPeriodsLowerBound => callbackGapsUs.fold<int>(
    0,
    (total, gapUs) => total + math.max(0, gapUs ~/ _heartbeatPeriodUs - 1),
  );
  double get writesPerSecond =>
      elapsedUs == 0 ? 0 : writes * 1000000 / elapsedUs;

  Map<String, Object?> toJson() => <String, Object?>{
    'run': run,
    'elapsed_us': elapsedUs,
    'writes': writes,
    'writes_per_second': writesPerSecond,
    'heartbeat_period_us': _heartbeatPeriodUs,
    'timer_callbacks': callbacks,
    'long_gap_missed_periods_lower_bound': longGapMissedPeriodsLowerBound,
    'callback_gaps_us': callbackGapsUs,
    'p50_callback_gap_us': _percentileInt(callbackGapsUs, 0.50),
    'p95_callback_gap_us': _percentileInt(callbackGapsUs, 0.95),
    'p99_callback_gap_us': _percentileInt(callbackGapsUs, 0.99),
    'max_callback_gap_us': callbackGapsUs.reduce(math.max),
  };
}

final class _JitterResult {
  const _JitterResult(this.runs);

  final List<_JitterRun> runs;

  Map<String, Object?> get summary {
    final gaps = <int>[for (final run in runs) ...run.callbackGapsUs];
    final writesPerSecond = <double>[
      for (final run in runs) run.writesPerSecond,
    ];
    final callbacks = runs.fold<int>(0, (total, run) => total + run.callbacks);
    final longGapMissedPeriodsLowerBound = runs.fold<int>(
      0,
      (total, run) => total + run.longGapMissedPeriodsLowerBound,
    );
    return <String, Object?>{
      'completed': true,
      'runs': runs.length,
      'heartbeat_period_us': _heartbeatPeriodUs,
      'median_writes_per_second': _percentileDouble(writesPerSecond, 0.50),
      'timer_callbacks': callbacks,
      'long_gap_missed_periods_lower_bound': longGapMissedPeriodsLowerBound,
      'p50_callback_gap_us': _percentileInt(gaps, 0.50),
      'p95_callback_gap_us': _percentileInt(gaps, 0.95),
      'p99_callback_gap_us': _percentileInt(gaps, 0.99),
      'max_callback_gap_us': gaps.reduce(math.max),
    };
  }
}

final class _ValueStreamProbe {
  _ValueStreamProbe(Stream<List<Map<String, Object?>>> stream) {
    _subscription = stream.listen(
      (rows) {
        final value = rows.single['value'];
        if (value is! int) {
          _completeError(StateError('Stream value was not an int: $value'));
          return;
        }
        latestValue = value;
        emissions++;
        final waiter = _waiter;
        if (waiter != null && value >= _targetValue) {
          _waiter = null;
          waiter.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _completeError(error, stackTrace);
      },
      onDone: () {
        _completeError(StateError('Stream closed before its target arrived.'));
      },
    );
  }

  late final StreamSubscription<List<Map<String, Object?>>> _subscription;
  Completer<void>? _waiter;
  int _targetValue = 0;
  int? latestValue;
  int emissions = 0;
  Object? _error;
  StackTrace? _errorStackTrace;

  Future<void> waitForAtLeast(int target) {
    final error = _error;
    if (error != null) {
      return Future<void>.error(error, _errorStackTrace);
    }
    final latest = latestValue;
    if (latest != null && latest >= target) return Future<void>.value();
    if (_waiter != null) {
      throw StateError('Only one active stream wait is supported.');
    }
    _targetValue = target;
    final waiter = Completer<void>();
    _waiter = waiter;
    return waiter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (identical(_waiter, waiter)) _waiter = null;
        throw TimeoutException(
          'Timed out waiting for stream value >= $target; latest=$latestValue.',
        );
      },
    );
  }

  void _completeError(Object error, [StackTrace? stackTrace]) {
    _error = error;
    _errorStackTrace = stackTrace;
    final waiter = _waiter;
    if (waiter == null || waiter.isCompleted) return;
    _waiter = null;
    waiter.completeError(error, stackTrace);
  }

  Future<void> cancel() => _subscription.cancel();
}

final class _Options {
  const _Options({
    required this.label,
    required this.samples,
    required this.warmupOps,
    required this.workloadDivisor,
    required this.jitterRuns,
    required this.jitterDuration,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    var label = 'unlabeled';
    var samples = _defaultSamples;
    var warmupOps = _defaultWarmupOps;
    var workloadDivisor = 1;
    var jitterRuns = _defaultJitterRuns;
    var jitterMs = _defaultJitterMs;
    var help = false;

    for (final argument in args) {
      if (argument == '--help' || argument == '-h') {
        help = true;
      } else if (argument == '--quick') {
        samples = 2;
        warmupOps = 8;
        workloadDivisor = 20;
        jitterRuns = 1;
        jitterMs = 250;
      } else if (argument.startsWith('--label=')) {
        label = argument.substring('--label='.length);
      } else if (argument.startsWith('--samples=')) {
        samples = _positiveInt(argument, '--samples=');
      } else if (argument.startsWith('--warmup-ops=')) {
        warmupOps = _nonNegativeInt(argument, '--warmup-ops=');
      } else if (argument.startsWith('--workload-divisor=')) {
        workloadDivisor = _positiveInt(argument, '--workload-divisor=');
      } else if (argument.startsWith('--jitter-runs=')) {
        jitterRuns = _positiveInt(argument, '--jitter-runs=');
      } else if (argument.startsWith('--jitter-ms=')) {
        jitterMs = _positiveInt(argument, '--jitter-ms=');
      } else {
        throw FormatException('Unknown argument: $argument');
      }
    }

    if (label.isEmpty) throw const FormatException('Label must not be empty.');
    return _Options(
      label: label,
      samples: samples,
      warmupOps: warmupOps,
      workloadDivisor: workloadDivisor,
      jitterRuns: jitterRuns,
      jitterDuration: Duration(milliseconds: jitterMs),
      help: help,
    );
  }

  final String label;
  final int samples;
  final int warmupOps;
  final int workloadDivisor;
  final int jitterRuns;
  final Duration jitterDuration;
  final bool help;

  int scaled(int value, {int minimum = 1}) {
    return math.max(minimum, (value / workloadDivisor).ceil());
  }
}

int _positiveInt(String argument, String prefix) {
  final value = int.tryParse(argument.substring(prefix.length));
  if (value == null || value <= 0) {
    throw FormatException('$prefix expects a positive integer.');
  }
  return value;
}

int _nonNegativeInt(String argument, String prefix) {
  final value = int.tryParse(argument.substring(prefix.length));
  if (value == null || value < 0) {
    throw FormatException('$prefix expects a non-negative integer.');
  }
  return value;
}

const _usage = '''
Writer completion catch benchmark (exp 271)

Usage:
  dart run benchmark/experiments/writer_completion_catch.dart [options]

Options:
  --label=NAME              Label stored in the final JSON result.
  --samples=N               Timed samples per latency lane (default 7).
  --warmup-ops=N            Fast writes used to warm each lane (default 1200).
  --workload-divisor=N      Divide default lane sizes by N.
  --jitter-runs=N           16 ms heartbeat write-chain runs (default 3).
  --jitter-ms=N             Duration of each jitter run (default 1500).
  --quick                    Small smoke configuration, overridable afterward.
  --help                     Show this message.
''';
