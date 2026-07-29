// Benchmark: native independent-autocommit envelope (exp 257).
//
// Run the same file from baseline and candidate worktrees. The homogeneous
// insert burst is the product-shaped decision gate. Homogeneous no-op updates
// isolate fixed per-member orchestration, while mixed SQL and sequential
// writes are inert controls that must not move materially.

import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _warmupRounds = 3;
const _rounds = 11;
const _burstSize = 256;
const _burstsPerRound = 20;
const _sequentialWrites = 3000;

const _createSql =
    'CREATE TABLE items('
    'id INTEGER PRIMARY KEY, body TEXT NOT NULL, n INTEGER NOT NULL)';
const _insertSql = 'INSERT INTO items(body, n) VALUES (?, ?)';
const _insertSqlAlternate = 'INSERT INTO items(n, body) VALUES (?, ?)';
const _noopUpdateSql = 'UPDATE items SET n = n WHERE id = ?';

Future<void> main(List<String> args) async {
  final requested = args.isEmpty ? 'all' : args.single;
  final shapes = requested == 'all'
      ? const ['insert', 'noop', 'mixed', 'sequential']
      : [requested];
  final runners = <String, Future<int> Function(String, int)>{
    'insert': _homogeneousInsertRound,
    'noop': _homogeneousNoopRound,
    'mixed': _mixedInsertRound,
    'sequential': _sequentialRound,
  };
  if (shapes.any((shape) => !runners.containsKey(shape))) {
    stderr.writeln(
      'Usage: dart run independent_autocommit_envelope.dart '
      '[insert|noop|mixed|sequential|all]',
    );
    exitCode = 64;
    return;
  }

  final dir = await Directory.systemTemp.createTemp('resqlite_exp257_');
  try {
    print('=== Independent autocommit envelope (exp 257) ===');
    for (final shape in shapes) {
      final samples = <int>[];
      for (var round = -_warmupRounds; round < _rounds; round++) {
        final elapsed = await runners[shape]!(dir.path, round);
        if (round >= 0) samples.add(elapsed);
      }
      _report(shape, samples);
    }
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<Database> _freshDb(String dirPath, String label) async {
  final db = await Database.open('$dirPath/$label.db');
  await db.execute(_createSql);
  return db;
}

Future<int> _homogeneousInsertRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'insert_$round');
  final stopwatch = Stopwatch()..start();
  for (var burst = 0; burst < _burstsPerRound; burst++) {
    await Future.wait([
      for (var i = 0; i < _burstSize; i++)
        db.execute(_insertSql, ['row_${burst}_$i', i]),
    ]);
  }
  stopwatch.stop();
  await db.close();
  return stopwatch.elapsedMicroseconds;
}

Future<int> _homogeneousNoopRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'noop_$round');
  final stopwatch = Stopwatch()..start();
  for (var burst = 0; burst < _burstsPerRound; burst++) {
    await Future.wait([
      for (var i = 0; i < _burstSize; i++) db.execute(_noopUpdateSql, [i + 1]),
    ]);
  }
  stopwatch.stop();
  await db.close();
  return stopwatch.elapsedMicroseconds;
}

Future<int> _mixedInsertRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'mixed_$round');
  final stopwatch = Stopwatch()..start();
  for (var burst = 0; burst < _burstsPerRound; burst++) {
    await Future.wait([
      for (var i = 0; i < _burstSize; i++)
        if (i.isEven)
          db.execute(_insertSql, ['row_${burst}_$i', i])
        else
          db.execute(_insertSqlAlternate, [i, 'row_${burst}_$i']),
    ]);
  }
  stopwatch.stop();
  await db.close();
  return stopwatch.elapsedMicroseconds;
}

Future<int> _sequentialRound(String dirPath, int round) async {
  final db = await _freshDb(dirPath, 'sequential_$round');
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < _sequentialWrites; i++) {
    await db.execute(_insertSql, ['row_$i', i]);
  }
  stopwatch.stop();
  await db.close();
  return stopwatch.elapsedMicroseconds;
}

void _report(String shape, List<int> samplesUs) {
  final sorted = [...samplesUs]..sort();
  final median = sorted[sorted.length ~/ 2];
  final samples = samplesUs
      .map((sample) => (sample / 1000).toStringAsFixed(3))
      .join(', ');
  print(
    '$shape: median ${(median / 1000).toStringAsFixed(3)}ms '
    'samples [$samples]ms',
  );
}
