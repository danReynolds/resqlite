// Focused benchmark for exp 209: explicit heterogeneous read batching.
//
// Compares the current public way to run many unrelated small reads together
// (parallel `Future.wait([db.select(...), db.select(...), ...])` fan-out over
// the reader pool) against the prototype single-round-trip batch
// `db.selectAll([...ReadStatement...])`.
//
// Three lanes:
//   * point:   20 single-row PK lookups, payloads negligible — the win lane;
//              per-query SQLite work is well below the reader-pool round trip
//              so amortization should dominate.
//   * medium:  20 short-list SELECTs returning ~10 rows each — the middle
//              ground where parallelism matters more.
//   * large:   4 large SELECTs (10k rows each) — the guard lane; the reader
//              pool can spread each large read across its workers, and the
//              batch's one-worker serialization should lose here.

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _rounds = 9;

Future<void> main(List<String> args) async {
  final order = _parseOrder(args);
  final dir = await Directory.systemTemp.createTemp('resqlite_hetero_read_');
  try {
    print('=== Heterogeneous read batch experiment (exp 209) ===');
    print('order: $order');
    print('rounds: $_rounds\n');

    final db = await _openSeededDb('${dir.path}/exp209.db');
    try {
      // JIT warmup — one round of each shape on each side. Not measured.
      await _pointParallel(db);
      await _pointBatch(db);
      await _mediumParallel(db);
      await _mediumBatch(db);
      await _largeParallel(db);
      await _largeBatch(db);

      final results = <String, List<int>>{
        'point_parallel': [],
        'point_batch': [],
        'medium_parallel': [],
        'medium_batch': [],
        'large_parallel': [],
        'large_batch': [],
      };

      for (var round = 0; round < _rounds; round++) {
        if (order == _Order.parallelFirst) {
          results['point_parallel']!.add(await _time(() => _pointParallel(db)));
          results['point_batch']!.add(await _time(() => _pointBatch(db)));
          results['medium_parallel']!
              .add(await _time(() => _mediumParallel(db)));
          results['medium_batch']!.add(await _time(() => _mediumBatch(db)));
          results['large_parallel']!.add(await _time(() => _largeParallel(db)));
          results['large_batch']!.add(await _time(() => _largeBatch(db)));
        } else {
          results['point_batch']!.add(await _time(() => _pointBatch(db)));
          results['point_parallel']!.add(await _time(() => _pointParallel(db)));
          results['medium_batch']!.add(await _time(() => _mediumBatch(db)));
          results['medium_parallel']!
              .add(await _time(() => _mediumParallel(db)));
          results['large_batch']!.add(await _time(() => _largeBatch(db)));
          results['large_parallel']!.add(await _time(() => _largeParallel(db)));
        }
      }

      _report(
        'point / 20 single-row PK lookups (parallel)',
        results['point_parallel']!,
      );
      _report(
        'point / 20 single-row PK lookups (batch)',
        results['point_batch']!,
      );
      _report(
        'medium / 20 ~10-row list SELECTs (parallel)',
        results['medium_parallel']!,
      );
      _report(
        'medium / 20 ~10-row list SELECTs (batch)',
        results['medium_batch']!,
      );
      _report(
        'large / 4 10k-row SELECTs (parallel) [guard]',
        results['large_parallel']!,
      );
      _report(
        'large / 4 10k-row SELECTs (batch) [guard]',
        results['large_batch']!,
      );
    } finally {
      await db.close();
    }
  } finally {
    await dir.delete(recursive: true);
  }
}

enum _Order { parallelFirst, batchFirst }

_Order _parseOrder(List<String> args) {
  for (final arg in args) {
    if (arg == '--order=parallel-first') return _Order.parallelFirst;
    if (arg == '--order=batch-first') return _Order.batchFirst;
  }
  return _Order.parallelFirst;
}

Future<Database> _openSeededDb(String path) async {
  final db = await Database.open(path);
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, category INTEGER NOT NULL, '
    'body TEXT NOT NULL, n INTEGER NOT NULL)',
  );
  await db.execute(
    'CREATE INDEX items_category_idx ON items(category)',
  );
  // Seed 10k rows across 20 categories: ample for large-lane 10k reads and
  // medium-lane category-in lookups; each row has a small text body.
  await db.transaction((tx) async {
    for (var i = 0; i < 10000; i++) {
      await tx.execute(
        'INSERT INTO items(id, category, body, n) VALUES (?, ?, ?, ?)',
        [i, i % 20, 'row_$i', i * 3],
      );
    }
  });
  return db;
}

// ---------------------------------------------------------------------------
// Point lane — 20 single-row PK lookups
// ---------------------------------------------------------------------------

const _pointIds = <int>[
  1, 17, 42, 63, 88, 111, 137, 164, 200, 251,
  312, 405, 511, 620, 733, 848, 999, 1234, 4321, 9876,
];

Future<void> _pointParallel(Database db) async {
  final futures = <Future<List<Map<String, Object?>>>>[];
  for (final id in _pointIds) {
    futures.add(db.select('SELECT id, category, n FROM items WHERE id = ?', [id]));
  }
  final results = await Future.wait(futures);
  if (results.length != _pointIds.length) {
    throw StateError('point-parallel result count mismatch');
  }
}

Future<void> _pointBatch(Database db) async {
  final statements = [
    for (final id in _pointIds)
      ReadStatement('SELECT id, category, n FROM items WHERE id = ?', [id]),
  ];
  final results = await db.selectAll(statements);
  if (results.length != statements.length) {
    throw StateError('point-batch result count mismatch');
  }
}

// ---------------------------------------------------------------------------
// Medium lane — 20 short-list SELECTs (~10 rows each)
// ---------------------------------------------------------------------------

Future<void> _mediumParallel(Database db) async {
  final futures = <Future<List<Map<String, Object?>>>>[];
  for (var cat = 0; cat < 20; cat++) {
    futures.add(db.select(
      'SELECT id, body, n FROM items WHERE category = ? AND id < ? LIMIT 10',
      [cat, 200],
    ));
  }
  final results = await Future.wait(futures);
  if (results.length != 20) {
    throw StateError('medium-parallel result count mismatch');
  }
}

Future<void> _mediumBatch(Database db) async {
  final statements = <ReadStatement>[
    for (var cat = 0; cat < 20; cat++)
      ReadStatement(
        'SELECT id, body, n FROM items WHERE category = ? AND id < ? LIMIT 10',
        [cat, 200],
      ),
  ];
  final results = await db.selectAll(statements);
  if (results.length != 20) {
    throw StateError('medium-batch result count mismatch');
  }
}

// ---------------------------------------------------------------------------
// Large lane [guard] — 4 10k-row SELECTs
// ---------------------------------------------------------------------------

Future<void> _largeParallel(Database db) async {
  final futures = <Future<List<Map<String, Object?>>>>[];
  for (var i = 0; i < 4; i++) {
    futures.add(db.select('SELECT id, body, n FROM items'));
  }
  final results = await Future.wait(futures);
  if (results.length != 4) {
    throw StateError('large-parallel result count mismatch');
  }
}

Future<void> _largeBatch(Database db) async {
  final statements = <ReadStatement>[
    for (var i = 0; i < 4; i++)
      const ReadStatement('SELECT id, body, n FROM items'),
  ];
  final results = await db.selectAll(statements);
  if (results.length != 4) {
    throw StateError('large-batch result count mismatch');
  }
}

// ---------------------------------------------------------------------------
// Timing + reporting
// ---------------------------------------------------------------------------

Future<int> _time(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  return sw.elapsedMicroseconds;
}

void _report(String name, List<int> roundsUs) {
  final sorted = [...roundsUs]..sort();
  final median = sorted[sorted.length ~/ 2];
  final ms = (median / 1000).toStringAsFixed(3);
  final all = roundsUs.map((us) => (us / 1000).toStringAsFixed(3)).join(', ');
  print('$name: median ${ms}ms  rounds [${all}]ms');
}
