// Focused cross-worktree benchmark for exp 239: transparent select overflow
// batching.
//
// Run this unchanged from an origin/main worktree and the experiment worktree.
// Every lane uses the public `Database.select` API and the same
// `Future.wait` shape on both revisions; only the reader-pool implementation
// differs. `--order=first` uses the lane order below and `--order=second`
// reverses it so paired runs can expose order and cache effects.
//
// The fixture and lane shapes extend exp 209's 10k-row heterogeneous-read
// benchmark. Setup, warmup, result validation, and reader respawn settling are
// deliberately outside the timed region.

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _defaultRounds = 15;
const _readerSettleDelay = Duration(milliseconds: 150);

const _pointIds = <int>[
  1,
  17,
  42,
  63,
  88,
  111,
  137,
  164,
  200,
  251,
  312,
  405,
  511,
  620,
  733,
  848,
  999,
  1234,
  4321,
  9876,
];

const _pointSql = 'SELECT id, category, n FROM items WHERE id = ?';
const _mediumSql =
    'SELECT id, body, n FROM items '
    'WHERE category = ? AND id < 200 ORDER BY id LIMIT 10';
const _largeSql = 'SELECT id, body, n FROM items ORDER BY id';

Future<void> main(List<String> args) async {
  final order = _parseOrder(args);
  final lanes = _parseLanes(args);
  final rounds = _parseRounds(args);
  if (order == null) {
    stderr.writeln(
      'usage: dart run benchmark/experiments/select_overflow_batch.dart '
      '--order=first|second [--lanes=name,name] [--rounds=N]',
    );
    exitCode = 64;
    return;
  }

  final dir = await Directory.systemTemp.createTemp(
    'resqlite-select-overflow-batch-',
  );
  try {
    final db = await _openSeededDb('${dir.path}/exp239.db');
    try {
      stdout.writeln(
        'select overflow batch (exp 239): order=${order.name} '
        'rounds=$rounds lanes=${lanes.map((lane) => lane.wireName).join(',')}',
      );

      await _warmUp(db, lanes);

      final samples = <_Lane, _LaneSamples>{
        for (final lane in lanes) lane: _LaneSamples(),
      };
      final laneOrder = order == _Order.first ? lanes : lanes.reversed;

      for (var round = 0; round < rounds; round++) {
        for (final lane in laneOrder) {
          samples[lane]!.add(await _measure(db, lane));
          if (lane.needsReaderSettle) {
            await Future<void>.delayed(_readerSettleDelay);
          }
        }
      }

      for (final lane in lanes) {
        _report(lane.wireName, samples[lane]!);
      }
      if (samples[_Lane.mixed] case final mixed?) {
        _reportMixedPointCompletion(mixed, 'mixed_point_p95', rounds);
      }
    } finally {
      await db.close();
    }
  } finally {
    await dir.delete(recursive: true);
  }
}

enum _Order { first, second }

_Order? _parseOrder(List<String> args) {
  final matches = args.where((arg) => arg.startsWith('--order='));
  if (matches.length != 1) return null;
  return switch (matches.single) {
    '--order=first' => _Order.first,
    '--order=second' => _Order.second,
    _ => null,
  };
}

List<_Lane> _parseLanes(List<String> args) {
  final matches = args.where((arg) => arg.startsWith('--lanes='));
  if (matches.isEmpty) return _Lane.values;
  if (matches.length != 1) {
    throw FormatException('Expected at most one --lanes argument.');
  }
  final requested = matches.single.substring('--lanes='.length).split(',');
  if (requested.isEmpty) throw FormatException('--lanes cannot be empty.');
  return [
    for (final name in requested)
      _Lane.values.singleWhere(
        (lane) => lane.wireName == name,
        orElse: () => throw FormatException('Unknown lane: $name'),
      ),
  ];
}

int _parseRounds(List<String> args) {
  final matches = args.where((arg) => arg.startsWith('--rounds='));
  if (matches.isEmpty) return _defaultRounds;
  if (matches.length != 1) {
    throw FormatException('Expected at most one --rounds argument.');
  }
  final rounds = int.tryParse(matches.single.substring('--rounds='.length));
  if (rounds == null || rounds < 3) {
    throw FormatException('--rounds must be an integer >= 3.');
  }
  return rounds;
}

enum _Lane {
  sequentialPoint('sequential_point', false),
  point4('point_4way', false),
  point20('point_20way', false),
  medium20('medium_20way', false),
  large20('large_20way', true),
  mixed('mixed_total', true);

  const _Lane(this.wireName, this.needsReaderSettle);

  final String wireName;
  final bool needsReaderSettle;
}

final class _LaneOutput {
  const _LaneOutput(this.rows, {this.pointCompletionUs = const []});

  final List<List<Map<String, Object?>>> rows;
  final List<int> pointCompletionUs;
}

final class _TimedSample {
  const _TimedSample({
    required this.elapsedUs,
    required this.rssKiB,
    this.pointCompletionP95Us,
  });

  final int elapsedUs;
  final int rssKiB;
  final int? pointCompletionP95Us;
}

final class _LaneSamples {
  final elapsedUs = <int>[];
  final rssKiB = <int>[];
  final pointCompletionP95Us = <int>[];

  void add(_TimedSample sample) {
    elapsedUs.add(sample.elapsedUs);
    rssKiB.add(sample.rssKiB);
    if (sample.pointCompletionP95Us case final pointP95?) {
      pointCompletionP95Us.add(pointP95);
    }
  }
}

Future<Database> _openSeededDb(String path) async {
  final db = await Database.open(path);
  await db.execute(
    'CREATE TABLE items('
    'id INTEGER PRIMARY KEY, '
    'category INTEGER NOT NULL, '
    'body TEXT NOT NULL, '
    'n INTEGER NOT NULL)',
  );
  await db.execute('CREATE INDEX items_category_idx ON items(category)');
  await db.executeBatch(
    'INSERT INTO items(id, category, body, n) VALUES (?, ?, ?, ?)',
    [
      for (var i = 0; i < 10000; i++) <Object?>[i, i % 20, 'row_$i', i * 3],
    ],
  );
  return db;
}

Future<void> _warmUp(Database db, List<_Lane> lanes) async {
  for (var pass = 0; pass < 5; pass++) {
    for (final lane in lanes) {
      final sw = Stopwatch()..start();
      final output = await _invoke(db, lane, sw);
      sw.stop();
      _validate(lane, output);
      if (lane.needsReaderSettle) {
        await Future<void>.delayed(_readerSettleDelay);
      }
    }
  }
}

Future<_TimedSample> _measure(Database db, _Lane lane) async {
  final sw = Stopwatch()..start();
  final output = await _invoke(db, lane, sw);
  sw.stop();

  final elapsedUs = sw.elapsedMicroseconds;
  final rssKiB = ProcessInfo.currentRss ~/ 1024;
  final pointP95 = output.pointCompletionUs.isEmpty
      ? null
      : _percentile95(output.pointCompletionUs);

  // Validation intentionally follows the timing and RSS snapshot while the
  // result graph is still live.
  _validate(lane, output);
  return _TimedSample(
    elapsedUs: elapsedUs,
    rssKiB: rssKiB,
    pointCompletionP95Us: pointP95,
  );
}

Future<_LaneOutput> _invoke(
  Database db,
  _Lane lane,
  Stopwatch stopwatch,
) async {
  switch (lane) {
    case _Lane.sequentialPoint:
      final rows = <List<Map<String, Object?>>>[];
      for (final id in _pointIds) {
        rows.add(await db.select(_pointSql, [id]));
      }
      return _LaneOutput(rows);

    case _Lane.point4:
      return _LaneOutput(
        await Future.wait([
          for (final id in _pointIds.take(4)) db.select(_pointSql, [id]),
        ]),
      );

    case _Lane.point20:
      return _LaneOutput(
        await Future.wait([
          for (final id in _pointIds) db.select(_pointSql, [id]),
        ]),
      );

    case _Lane.medium20:
      return _LaneOutput(
        await Future.wait([
          for (var category = 0; category < 20; category++)
            db.select(_mediumSql, [category]),
        ]),
      );

    case _Lane.large20:
      return _LaneOutput(
        await Future.wait([for (var i = 0; i < 20; i++) db.select(_largeSql)]),
      );

    case _Lane.mixed:
      final futures = <Future<List<Map<String, Object?>>>>[];
      final pointCompletionUs = <int>[];
      for (var i = 0; i < 10; i++) {
        // Keep the submitted queue alternating. A point read behind each large
        // read exposes head-of-line effects without using an internal API.
        futures.add(db.select(_largeSql));
        final id = _pointIds[i];
        futures.add(
          db.select(_pointSql, [id]).then((rows) {
            pointCompletionUs.add(stopwatch.elapsedMicroseconds);
            return rows;
          }),
        );
      }
      return _LaneOutput(
        await Future.wait(futures),
        pointCompletionUs: pointCompletionUs,
      );
  }
}

void _validate(_Lane lane, _LaneOutput output) {
  switch (lane) {
    case _Lane.sequentialPoint:
      _validatePointResults(output.rows, _pointIds);

    case _Lane.point4:
      _validatePointResults(output.rows, _pointIds.take(4));

    case _Lane.point20:
      _validatePointResults(output.rows, _pointIds);

    case _Lane.medium20:
      if (output.rows.length != 20) {
        throw StateError('medium result-set count: ${output.rows.length}');
      }
      for (var category = 0; category < output.rows.length; category++) {
        final rows = output.rows[category];
        if (rows.length != 10) {
          throw StateError(
            'medium category $category row count: ${rows.length}',
          );
        }
        for (var i = 0; i < rows.length; i++) {
          final expectedId = category + i * 20;
          _validateProjectedRow(rows[i], expectedId);
        }
      }

    case _Lane.large20:
      if (output.rows.length != 20) {
        throw StateError('large result-set count: ${output.rows.length}');
      }
      for (final rows in output.rows) {
        _validateLargeRows(rows);
      }

    case _Lane.mixed:
      if (output.rows.length != 20 || output.pointCompletionUs.length != 10) {
        throw StateError(
          'mixed result counts: rows=${output.rows.length} '
          'pointCompletions=${output.pointCompletionUs.length}',
        );
      }
      for (var i = 0; i < 10; i++) {
        _validateLargeRows(output.rows[i * 2]);
        _validatePointResults([output.rows[i * 2 + 1]], [_pointIds[i]]);
      }
  }
}

void _validatePointResults(
  List<List<Map<String, Object?>>> results,
  Iterable<int> ids,
) {
  final expectedIds = ids.toList(growable: false);
  if (results.length != expectedIds.length) {
    throw StateError(
      'point result-set count: ${results.length}, '
      'expected ${expectedIds.length}',
    );
  }
  for (var i = 0; i < results.length; i++) {
    final rows = results[i];
    final id = expectedIds[i];
    if (rows.length != 1) {
      throw StateError('point id $id row count: ${rows.length}');
    }
    final row = rows.single;
    if (row['id'] != id || row['category'] != id % 20 || row['n'] != id * 3) {
      throw StateError('point id $id payload mismatch: $row');
    }
  }
}

void _validateLargeRows(List<Map<String, Object?>> rows) {
  if (rows.length != 10000) {
    throw StateError('large row count: ${rows.length}');
  }
  _validateProjectedRow(rows.first, 0);
  _validateProjectedRow(rows[5000], 5000);
  _validateProjectedRow(rows.last, 9999);
}

void _validateProjectedRow(Map<String, Object?> row, int expectedId) {
  if (row['id'] != expectedId ||
      row['body'] != 'row_$expectedId' ||
      row['n'] != expectedId * 3) {
    throw StateError('row $expectedId payload mismatch: $row');
  }
}

int _percentile95(List<int> values) {
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * 0.95).ceil();
  return sorted[index];
}

void _report(String lane, _LaneSamples samples) {
  final sorted = [...samples.elapsedUs]..sort();
  final median = sorted[sorted.length ~/ 2];
  final p95 = _percentile95(sorted);
  final peakRssKiB = samples.rssKiB.reduce((a, b) => a > b ? a : b);
  stdout.writeln(
    'RESULT lane=$lane median_us=$median p95_us=$p95 '
    'rss_kib=$peakRssKiB samples_us=${samples.elapsedUs.join(',')}',
  );
}

void _reportMixedPointCompletion(
  _LaneSamples samples,
  String lane,
  int rounds,
) {
  final pointSamples = samples.pointCompletionP95Us;
  if (pointSamples.length != rounds) {
    throw StateError(
      'mixed point completion samples: ${pointSamples.length}, '
      'expected $rounds',
    );
  }
  final sorted = [...pointSamples]..sort();
  final median = sorted[sorted.length ~/ 2];
  final p95 = _percentile95(sorted);
  final peakRssKiB = samples.rssKiB.reduce((a, b) => a > b ? a : b);
  stdout.writeln(
    'RESULT lane=$lane median_us=$median p95_us=$p95 '
    'rss_kib=$peakRssKiB samples_us=${pointSamples.join(',')}',
  );
}
