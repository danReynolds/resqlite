// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../drift/writes_db.dart';
import '../shared/config.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';

const int _wideBatchSize = 10000;
const int _wideBatchParamWidth = 20;

// Exp 161: concurrent standalone writes per iteration. The focused
// `benchmark/experiments/writer_pipelining.dart` proved exp 159's
// send-gated writer lock can pipeline -36% to -45% on a 200 x 10 burst;
// this section uses a leaner 100-write burst so it fits inside the
// release iteration budget while still exposing the same `Future.wait`
// shape on the public benchmark path.
const int _concurrentBurstSize = 100;

/// Write performance benchmarks: single writes, batch, transactions.
///
/// Organized in seven sections:
///   1. Single Inserts — [PeerSet]-based, 4 peers
///   2. Concurrent Single Inserts — [PeerSet]-based, 4 peers
///   3. Batch Insert (3 narrow sizes) — [PeerSet]-based, 4 peers
///   4. Wide Batch Insert (10k rows x 20 params) — [PeerSet]-based, 4 peers
///   5. Interactive Transaction — hand-rolled, resqlite + sqlite_async
///   6. Batched Write Inside Transaction — hand-rolled, resqlite
///      variants + sqlite_async. Guards the [`resqlite_run_batch_nested`]
///      C entry point.
///   7. Transaction Read — hand-rolled, resqlite + sqlite_async
///
/// Sections 4–6 aren't on [PeerSet] because they exercise interactive
/// transaction APIs (`tx.execute` / `tx.select` / `tx.executeBatch`
/// nested inside `db.transaction`) which [BenchmarkPeer] doesn't yet
/// expose. Extending the peer interface with a `transaction()`
/// primitive is possible but intentionally out of scope here — would
/// require each peer to thread the transaction handle through a
/// uniform shape, and drift/sqlite_async/resqlite semantics diverge
/// enough that it's its own PR.
Future<String> runWritesBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Write Performance');
  markdown.writeln('');

  final tempDir = await Directory.systemTemp.createTemp('bench_writes_');
  try {
    // -----------------------------------------------------------------
    // Single inserts — 4 peers via PeerSet
    // -----------------------------------------------------------------
    {
      final subdir = await Directory('${tempDir.path}/single').create();
      final peers = await PeerSet.open(
        subdir.path,
        driftFactory: driftFactoryFor((exec) => WritesDriftDb(exec)),
      );
      final timings = <BenchmarkTiming>[];
      try {
        const createSql =
            'CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)';
        const insertSql = 'INSERT INTO t(name, value) VALUES (?, ?)';
        for (final peer in peers.all) {
          await peer.execute(createSql);
        }

        const insertCount = 100;
        for (final peer in peers.all) {
          // Warmup + clear.
          for (var i = 0; i < defaultWarmup; i++) {
            await peer.execute(insertSql, ['warmup', 0.0]);
          }
          await peer.execute('DELETE FROM t');

          final t = BenchmarkTiming('${peer.label} execute()');
          for (var iter = 0; iter < defaultIterations; iter++) {
            final sw = Stopwatch()..start();
            for (var i = 0; i < insertCount; i++) {
              await peer.execute(insertSql, ['item_$i', i * 1.5]);
            }
            sw.stop();
            t.recordWallOnly(sw.elapsedMicroseconds);
            await peer.execute('DELETE FROM t');
          }
          timings.add(t);
        }

        printComparisonTable(
          '=== Single Inserts ($insertCount sequential) ===',
          timings,
        );
        markdown.write(
          markdownTable('Single Inserts ($insertCount sequential)', timings),
        );
      } finally {
        await peers.closeAll();
      }
    }

    // -----------------------------------------------------------------
    // Concurrent single inserts — 4 peers via PeerSet
    //
    // Matches Single Inserts in row count and schema, but issues the
    // writes through `Future.wait` so the writer port FIFO can pipeline
    // them. Exp 159 (writer request pipelining + persistent reply port)
    // showed -36% to -45% on the focused
    // `benchmark/experiments/writer_pipelining.dart` 200 x 10 burst,
    // but that benchmark stayed local and the release suite had no
    // line exercising concurrent standalone writes. This section is
    // the public guard so future writer-scheduling experiments can
    // claim a wall-time win on a release lane, and sequential vs
    // concurrent for the same workload is a side-by-side row.
    // -----------------------------------------------------------------
    {
      final subdir = await Directory('${tempDir.path}/concurrent').create();
      final peers = await PeerSet.open(
        subdir.path,
        driftFactory: driftFactoryFor((exec) => WritesDriftDb(exec)),
      );
      final timings = <BenchmarkTiming>[];
      try {
        const createSql =
            'CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)';
        const insertSql = 'INSERT INTO t(name, value) VALUES (?, ?)';
        for (final peer in peers.all) {
          await peer.execute(createSql);
        }

        for (final peer in peers.all) {
          // Warmup + clear.
          for (var i = 0; i < defaultWarmup; i++) {
            await Future.wait([
              for (var j = 0; j < _concurrentBurstSize; j++)
                peer.execute(insertSql, ['warmup_$j', j.toDouble()]),
            ]);
            await peer.execute('DELETE FROM t');
          }

          final t = BenchmarkTiming('${peer.label} concurrent execute()');
          for (var iter = 0; iter < defaultIterations; iter++) {
            final sw = Stopwatch()..start();
            await Future.wait([
              for (var i = 0; i < _concurrentBurstSize; i++)
                peer.execute(insertSql, ['item_$i', i * 1.5]),
            ]);
            sw.stop();
            t.recordWallOnly(sw.elapsedMicroseconds);
            await peer.execute('DELETE FROM t');
          }
          timings.add(t);
        }

        printComparisonTable(
          '=== Concurrent Single Inserts '
          '($_concurrentBurstSize concurrent) ===',
          timings,
        );
        markdown.write(
          markdownTable(
            'Concurrent Single Inserts ($_concurrentBurstSize concurrent)',
            timings,
          ),
        );
      } finally {
        await peers.closeAll();
      }
    }

    // -----------------------------------------------------------------
    // Batch inserts — 4 peers via PeerSet, 3 batch sizes
    // -----------------------------------------------------------------
    for (final batchSize in [100, 1000, 10000]) {
      final subdir = await Directory(
        '${tempDir.path}/batch_$batchSize',
      ).create();
      final peers = await PeerSet.open(
        subdir.path,
        driftFactory: driftFactoryFor((exec) => WritesDriftDb(exec)),
      );
      final timings = <BenchmarkTiming>[];
      try {
        const createSql =
            'CREATE TABLE IF NOT EXISTS t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)';
        const insertSql = 'INSERT INTO t(name, value) VALUES (?, ?)';
        for (final peer in peers.all) {
          await peer.execute(createSql);
        }
        final paramSets = [
          for (var i = 0; i < batchSize; i++) ['item_$i', i * 1.5],
        ];

        for (final peer in peers.all) {
          // Warmup + clear.
          for (var i = 0; i < defaultWarmup; i++) {
            await peer.executeBatch(insertSql, paramSets);
          }
          await peer.execute('DELETE FROM t');

          final t = BenchmarkTiming('${peer.label} executeBatch()');
          for (var iter = 0; iter < defaultIterations; iter++) {
            final swWall = Stopwatch()..start();
            await peer.executeBatch(insertSql, paramSets);
            swWall.stop();
            // Main-isolate time for batch is near-zero on async peers
            // (dispatch-only); identical to wall on the sync peer. We
            // record wall-only — finer split isn't meaningful here.
            t.recordWallOnly(swWall.elapsedMicroseconds);
            await peer.execute('DELETE FROM t');
          }
          timings.add(t);
        }

        printComparisonTable('=== Batch Insert ($batchSize rows) ===', timings);
        markdown.write(
          markdownTable('Batch Insert ($batchSize rows)', timings),
        );
      } finally {
        await peers.closeAll();
      }
    }

    // -----------------------------------------------------------------
    // Wide batch insert — 4 peers via PeerSet.
    //
    // The narrow 2-parameter shape above is still the common baseline,
    // but exp 113 showed it is not enough to track batch parameter
    // encoding costs. This 20-parameter mixed-type shape is the release
    // suite guard for ORM/generated-statement-style batch writes.
    // -----------------------------------------------------------------
    {
      final subdir = await Directory('${tempDir.path}/wide_batch').create();
      final peers = await PeerSet.open(
        subdir.path,
        driftFactory: driftFactoryFor((exec) => WritesDriftDb(exec)),
      );
      final timings = <BenchmarkTiming>[];
      try {
        final createSql = _wideBatchCreateSql();
        final insertSql = _wideBatchInsertSql();
        final paramSets = [
          for (var i = 0; i < _wideBatchSize; i++) _wideBatchRow(i),
        ];

        for (final peer in peers.all) {
          await peer.execute(createSql);
        }

        for (final peer in peers.all) {
          // Warmup + clear.
          for (var i = 0; i < defaultWarmup; i++) {
            await peer.executeBatch(insertSql, paramSets);
            await peer.execute('DELETE FROM wide_batch');
          }

          final t = BenchmarkTiming('${peer.label} executeBatch()');
          for (var iter = 0; iter < defaultIterations; iter++) {
            final swWall = Stopwatch()..start();
            await peer.executeBatch(insertSql, paramSets);
            swWall.stop();
            t.recordWallOnly(swWall.elapsedMicroseconds);
            await peer.execute('DELETE FROM wide_batch');
          }
          timings.add(t);
        }

        printComparisonTable(
          '=== Wide Batch Insert '
          '($_wideBatchSize rows x $_wideBatchParamWidth params) ===',
          timings,
        );
        markdown.write(
          markdownTable(
            'Wide Batch Insert '
            '($_wideBatchSize rows x $_wideBatchParamWidth params)',
            timings,
          ),
        );
      } finally {
        await peers.closeAll();
      }
    }

    // EXP-273's AOT bundle intentionally packages only Resqlite's native
    // asset. The sections below construct sqlite_async directly instead of
    // going through PeerSet, so stop after the shared release write shapes;
    // transaction coverage is supplied by tx_body_write_coalescing.dart.
    if (Platform.environment['RESQLITE_BENCH_ONLY'] == '1') {
      return markdown.toString();
    }

    // -----------------------------------------------------------------
    // Transaction with mixed read + write
    // -----------------------------------------------------------------
    {
      final resqliteDb = await resqlite.Database.open(
        '${tempDir.path}/resqlite_tx.db',
      );
      final asyncDb = sqlite_async.SqliteDatabase(
        path: '${tempDir.path}/async_tx.db',
      );
      await asyncDb.initialize();

      await resqliteDb.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
      );
      await asyncDb.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
      );

      // Seed some data.
      await resqliteDb.executeBatch('INSERT INTO t(value) VALUES (?)', [
        for (var i = 0; i < 100; i++) [i],
      ]);
      await asyncDb.executeBatch('INSERT INTO t(value) VALUES (?)', [
        for (var i = 0; i < 100; i++) [i],
      ]);

      // Warmup.
      for (var i = 0; i < defaultWarmup; i++) {
        await resqliteDb.transaction((tx) async {
          await tx.execute('INSERT INTO t(value) VALUES (?)', [999]);
          await tx.select('SELECT COUNT(*) FROM t');
          await tx.execute('DELETE FROM t WHERE value = ?', [999]);
        });
        await asyncDb.writeTransaction((tx) async {
          await tx.execute('INSERT INTO t(value) VALUES (?)', [999]);
          await tx.getAll('SELECT COUNT(*) FROM t');
          await tx.execute('DELETE FROM t WHERE value = ?', [999]);
        });
      }

      final tResqlite = BenchmarkTiming('resqlite transaction()');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await resqliteDb.transaction((tx) async {
          await tx.execute('INSERT INTO t(value) VALUES (?)', [999]);
          final rows = await tx.select('SELECT COUNT(*) as cnt FROM t');
          if (rows[0]['cnt'] as int > 50) {
            await tx.execute('DELETE FROM t WHERE value = ?', [999]);
          }
        });
        sw.stop();
        tResqlite.recordWallOnly(sw.elapsedMicroseconds);
      }

      final tAsync = BenchmarkTiming('sqlite_async writeTransaction()');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await asyncDb.writeTransaction((tx) async {
          await tx.execute('INSERT INTO t(value) VALUES (?)', [999]);
          final rows = await tx.getAll('SELECT COUNT(*) as cnt FROM t');
          if (rows.first['cnt'] as int > 50) {
            await tx.execute('DELETE FROM t WHERE value = ?', [999]);
          }
        });
        sw.stop();
        tAsync.recordWallOnly(sw.elapsedMicroseconds);
      }

      printComparisonTable(
        '=== Interactive Transaction (insert + select + conditional delete) ===',
        [tResqlite, tAsync],
      );
      markdown.write(
        markdownTable(
          'Interactive Transaction (insert + select + conditional delete)',
          [tResqlite, tAsync],
        ),
      );

      await resqliteDb.close();
      await asyncDb.close();
    }

    // -----------------------------------------------------------------
    // Batched writes INSIDE an interactive transaction.
    //
    // Regression guard for the "tx.executeBatch is a loop of individual
    // tx.execute calls" pattern. The new path routes through the writer
    // isolate's BatchRequest handler via a dedicated nested C entry
    // point (resqlite_run_batch_nested), collapsing N isolate
    // round-trips to 1 and reusing the prepared statement cache.
    //
    // Compares three strategies inside the same transaction:
    //   - tx.executeBatch (the fast path we care about)
    //   - a hand-written for-loop of tx.execute calls (the old path)
    //   - sqlite_async's equivalent batched insert inside a txn
    // -----------------------------------------------------------------
    for (final batchSize in [100, 1000]) {
      final resqliteDb = await resqlite.Database.open(
        '${tempDir.path}/resqlite_txbatch_$batchSize.db',
      );
      final asyncDb = sqlite_async.SqliteDatabase(
        path: '${tempDir.path}/async_txbatch_$batchSize.db',
      );
      await asyncDb.initialize();

      const createSql =
          'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)';
      const insertSql = 'INSERT INTO t(name, value) VALUES (?, ?)';

      await resqliteDb.execute(createSql);
      await asyncDb.execute(createSql);

      final paramSets = [
        for (var i = 0; i < batchSize; i++) ['item_$i', i * 1.5],
      ];

      // Warmup.
      for (var i = 0; i < defaultWarmup; i++) {
        await resqliteDb.transaction((tx) async {
          await tx.executeBatch(insertSql, paramSets);
        });
        await asyncDb.writeTransaction((tx) async {
          for (final ps in paramSets) {
            await tx.execute(insertSql, ps);
          }
        });
      }
      await resqliteDb.execute('DELETE FROM t');
      await asyncDb.execute('DELETE FROM t');

      final tResqliteBatch = BenchmarkTiming('resqlite tx.executeBatch()');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await resqliteDb.transaction((tx) async {
          await tx.executeBatch(insertSql, paramSets);
        });
        sw.stop();
        tResqliteBatch.recordWallOnly(sw.elapsedMicroseconds);
        await resqliteDb.execute('DELETE FROM t');
      }

      final tResqliteLoop = BenchmarkTiming('resqlite tx.execute() loop');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await resqliteDb.transaction((tx) async {
          for (final ps in paramSets) {
            await tx.execute(insertSql, ps);
          }
        });
        sw.stop();
        tResqliteLoop.recordWallOnly(sw.elapsedMicroseconds);
        await resqliteDb.execute('DELETE FROM t');
      }

      final tAsyncLoop = BenchmarkTiming('sqlite_async tx.execute() loop');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await asyncDb.writeTransaction((tx) async {
          for (final ps in paramSets) {
            await tx.execute(insertSql, ps);
          }
        });
        sw.stop();
        tAsyncLoop.recordWallOnly(sw.elapsedMicroseconds);
        await asyncDb.execute('DELETE FROM t');
      }

      printComparisonTable(
        '=== Batched Write Inside Transaction ($batchSize rows) ===',
        [tResqliteBatch, tResqliteLoop, tAsyncLoop],
      );
      markdown.write(
        markdownTable('Batched Write Inside Transaction ($batchSize rows)', [
          tResqliteBatch,
          tResqliteLoop,
          tAsyncLoop,
        ]),
      );

      await resqliteDb.close();
      await asyncDb.close();
    }

    // -----------------------------------------------------------------
    // Transaction reads (tx.select with larger result sets)
    // -----------------------------------------------------------------
    for (final rowCount in [500, 1000]) {
      final resqliteDb = await resqlite.Database.open(
        '${tempDir.path}/resqlite_txread_$rowCount.db',
      );
      final asyncDb = sqlite_async.SqliteDatabase(
        path: '${tempDir.path}/async_txread_$rowCount.db',
      );
      await asyncDb.initialize();

      const createSql = '''
        CREATE TABLE items(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          value REAL NOT NULL,
          category TEXT NOT NULL
        )
      ''';
      const insertSql =
          'INSERT INTO items(name, value, category) VALUES (?, ?, ?)';

      await resqliteDb.execute(createSql);
      await asyncDb.execute(createSql);
      final paramSets = [
        for (var i = 0; i < rowCount; i++)
          ['item_$i', i * 1.5, 'cat_${i % 10}'],
      ];
      await resqliteDb.executeBatch(insertSql, paramSets);
      await asyncDb.executeBatch(insertSql, paramSets);

      const selectSql = 'SELECT * FROM items ORDER BY id';

      // Warmup.
      for (var i = 0; i < defaultWarmup; i++) {
        await resqliteDb.transaction((tx) async {
          await tx.select(selectSql);
        });
        await asyncDb.writeTransaction((tx) async {
          await tx.getAll(selectSql);
        });
      }

      final tResqlite = BenchmarkTiming('resqlite tx.select()');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await resqliteDb.transaction((tx) async {
          final rows = await tx.select(selectSql);
          // Touch data to prevent dead-code elimination.
          if (rows.length != rowCount) throw StateError('bad');
        });
        sw.stop();
        tResqlite.recordWallOnly(sw.elapsedMicroseconds);
      }

      final tAsync = BenchmarkTiming('sqlite_async tx.getAll()');
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await asyncDb.writeTransaction((tx) async {
          final rows = await tx.getAll(selectSql);
          if (rows.length != rowCount) throw StateError('bad');
        });
        sw.stop();
        tAsync.recordWallOnly(sw.elapsedMicroseconds);
      }

      printComparisonTable('=== Transaction Read ($rowCount rows) ===', [
        tResqlite,
        tAsync,
      ]);
      markdown.write(
        markdownTable('Transaction Read ($rowCount rows)', [tResqlite, tAsync]),
      );

      await resqliteDb.close();
      await asyncDb.close();
    }

    // -----------------------------------------------------------------
    // Nested transactions (savepoints).
    //
    // Stresses the SAVEPOINT / RELEASE / ROLLBACK TO code path that
    // exp 102 (cached savepoint strings) and exp 103 (native nested-tx
    // depth control) targeted but couldn't measure for lack of a
    // workload. Two shapes:
    //
    //   - Shallow fan-out: 50 sequential nested savepoints inside one
    //     outer transaction, each inserting one row and releasing.
    //     Hits SAVEPOINT s1 / RELEASE s1 in a tight loop — the worst
    //     case for the per-call `'SAVEPOINT sN'.toNativeUtf8()` +
    //     `calloc.free` pair, since the same depth fires 50× per
    //     iteration.
    //
    //   - Deep chain: 5 levels of nesting deep with the insert at the
    //     innermost level, then unwind. Hits each of s1..s5 once per
    //     iteration — the worst case for unique-depth savepoint
    //     strings.
    //
    // Resqlite-only (no peer) — sqlite_async's nested transaction
    // semantics don't map cleanly enough for an apples-to-apples
    // single-row picture, and the goal here is a baseline for
    // resqlite-vs-resqlite experiment comparisons in the
    // transaction-control-paths direction (see
    // experiments/signals.json).
    // -----------------------------------------------------------------
    {
      final resqliteDb = await resqlite.Database.open(
        '${tempDir.path}/resqlite_nested_tx.db',
      );
      try {
        const createSql =
            'CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)';
        const insertSql = 'INSERT INTO t(value) VALUES (?)';
        await resqliteDb.execute(createSql);

        // ---- Shallow fan-out: 50 sequential nested savepoints. ----
        const fanout = 50;

        Future<void> runShallowFanout() async {
          await resqliteDb.transaction((tx) async {
            for (var i = 0; i < fanout; i++) {
              await tx.transaction((inner) async {
                await inner.execute(insertSql, [i]);
              });
            }
          });
        }

        for (var i = 0; i < defaultWarmup; i++) {
          await runShallowFanout();
        }
        await resqliteDb.execute('DELETE FROM t');

        final tFanout = BenchmarkTiming(
          'resqlite nested transaction() x$fanout',
        );
        for (var iter = 0; iter < defaultIterations; iter++) {
          final sw = Stopwatch()..start();
          await runShallowFanout();
          sw.stop();
          tFanout.recordWallOnly(sw.elapsedMicroseconds);
          await resqliteDb.execute('DELETE FROM t');
        }

        // ---- Deep chain: 5-level nesting with one insert at depth 5. ----
        const depth = 5;

        Future<void> runDeepNest(resqlite.Transaction tx, int remaining) async {
          if (remaining == 0) {
            await tx.execute(insertSql, [remaining]);
            return;
          }
          await tx.transaction((inner) => runDeepNest(inner, remaining - 1));
        }

        Future<void> runDeepNestOuter() async {
          await resqliteDb.transaction((tx) => runDeepNest(tx, depth));
        }

        for (var i = 0; i < defaultWarmup; i++) {
          await runDeepNestOuter();
        }
        await resqliteDb.execute('DELETE FROM t');

        final tDeep = BenchmarkTiming(
          'resqlite nested transaction() depth=$depth',
        );
        for (var iter = 0; iter < defaultIterations; iter++) {
          final sw = Stopwatch()..start();
          await runDeepNestOuter();
          sw.stop();
          tDeep.recordWallOnly(sw.elapsedMicroseconds);
          await resqliteDb.execute('DELETE FROM t');
        }

        printComparisonTable('=== Nested Transactions (savepoints) ===', [
          tFanout,
          tDeep,
        ]);
        markdown.write(
          markdownTable('Nested Transactions (savepoints)', [tFanout, tDeep]),
        );
      } finally {
        await resqliteDb.close();
      }
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  return markdown.toString();
}

String _wideBatchCreateSql() {
  final columns = [
    'id INTEGER PRIMARY KEY',
    for (var i = 0; i < _wideBatchParamWidth; i++)
      'c$i ${_wideBatchSqliteType(i)} NOT NULL',
  ];
  return 'CREATE TABLE IF NOT EXISTS wide_batch(${columns.join(', ')})';
}

String _wideBatchInsertSql() {
  final columns = [for (var i = 0; i < _wideBatchParamWidth; i++) 'c$i'];
  final placeholders = List.filled(_wideBatchParamWidth, '?');
  return 'INSERT INTO wide_batch(${columns.join(', ')}) '
      'VALUES (${placeholders.join(', ')})';
}

List<Object?> _wideBatchRow(int row) => [
  for (var col = 0; col < _wideBatchParamWidth; col++)
    _wideBatchValue(row, col),
];

String _wideBatchSqliteType(int col) => switch (col % 4) {
  0 => 'TEXT',
  1 => 'INTEGER',
  2 => 'REAL',
  _ => 'BLOB',
};

Object _wideBatchValue(int row, int col) => switch (col % 4) {
  0 => 'item_${row}_$col',
  1 => row * 31 + col,
  2 => row * 1.5 + col / 10,
  _ => Uint8List.fromList([row & 0xff, (row >> 8) & 0xff, col & 0xff, 0xA5]),
};

Future<void> main() async {
  await runWritesBenchmark();
}
