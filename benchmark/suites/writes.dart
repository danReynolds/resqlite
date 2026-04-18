// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../drift/writes_db.dart';
import '../shared/config.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';

/// Write performance benchmarks: single writes, batch, transactions.
///
/// Organized in five sections:
///   1. Single Inserts — [PeerSet]-based, 4 peers
///   2. Batch Insert (3 sizes) — [PeerSet]-based, 4 peers
///   3. Interactive Transaction — hand-rolled, resqlite + sqlite_async
///   4. Batched Write Inside Transaction — hand-rolled, resqlite
///      variants + sqlite_async. Guards the [`resqlite_run_batch_nested`]
///      C entry point.
///   5. Transaction Read — hand-rolled, resqlite + sqlite_async
///
/// Sections 3–5 aren't on [PeerSet] because they exercise interactive
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
        markdown.write(markdownTable(
          'Single Inserts ($insertCount sequential)',
          timings,
        ));
      } finally {
        await peers.closeAll();
      }
    }

    // -----------------------------------------------------------------
    // Batch inserts — 4 peers via PeerSet, 3 batch sizes
    // -----------------------------------------------------------------
    for (final batchSize in [100, 1000, 10000]) {
      final subdir =
          await Directory('${tempDir.path}/batch_$batchSize').create();
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

        printComparisonTable(
          '=== Batch Insert ($batchSize rows) ===',
          timings,
        );
        markdown.write(markdownTable(
          'Batch Insert ($batchSize rows)',
          timings,
        ));
      } finally {
        await peers.closeAll();
      }
    }

    // -----------------------------------------------------------------
    // Transaction with mixed read + write
    // -----------------------------------------------------------------
    {
      final resqliteDb = await resqlite.Database.open('${tempDir.path}/resqlite_tx.db');
      final asyncDb = sqlite_async.SqliteDatabase(path: '${tempDir.path}/async_tx.db');
      await asyncDb.initialize();

      await resqliteDb.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)');
      await asyncDb.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)');

      // Seed some data.
      await resqliteDb.executeBatch(
        'INSERT INTO t(value) VALUES (?)',
        [for (var i = 0; i < 100; i++) [i]],
      );
      await asyncDb.executeBatch(
        'INSERT INTO t(value) VALUES (?)',
        [for (var i = 0; i < 100; i++) [i]],
      );

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
      markdown.write(markdownTable(
        'Interactive Transaction (insert + select + conditional delete)',
        [tResqlite, tAsync],
      ));

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

      final tResqliteBatch = BenchmarkTiming(
        'resqlite tx.executeBatch()',
      );
      for (var iter = 0; iter < defaultIterations; iter++) {
        final sw = Stopwatch()..start();
        await resqliteDb.transaction((tx) async {
          await tx.executeBatch(insertSql, paramSets);
        });
        sw.stop();
        tResqliteBatch.recordWallOnly(sw.elapsedMicroseconds);
        await resqliteDb.execute('DELETE FROM t');
      }

      final tResqliteLoop = BenchmarkTiming(
        'resqlite tx.execute() loop',
      );
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

      final tAsyncLoop = BenchmarkTiming(
        'sqlite_async tx.execute() loop',
      );
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
      markdown.write(markdownTable(
        'Batched Write Inside Transaction ($batchSize rows)',
        [tResqliteBatch, tResqliteLoop, tAsyncLoop],
      ));

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

      printComparisonTable(
        '=== Transaction Read ($rowCount rows) ===',
        [tResqlite, tAsync],
      );
      markdown.write(markdownTable(
        'Transaction Read ($rowCount rows)',
        [tResqlite, tAsync],
      ));

      await resqliteDb.close();
      await asyncDb.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  return markdown.toString();
}

Future<void> main() async {
  await runWritesBenchmark();
}
