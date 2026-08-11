/// Where a `select()` runs, and what stops it running there
/// ([EXP-269](../experiments/269-enforced-inline-reads.md)).
///
/// Every assertion here is about *routing*, which is deliberately invisible
/// from the public API — an inline read and a dispatched one return the same
/// result, and that is the whole point. The pool's three counters are the only
/// surface that distinguishes them.
///
/// The important tests are the caps, and what they are protecting against is
/// not a wrong answer. A read that overruns its budget still returns the right
/// rows; it just returns them after holding the isolate that paints frames for
/// as long as the query took. So each cap test asserts on the counter, not only
/// on the data, and [EXP-267]'s rule applies — a test whose subject fails
/// silently has to be checked against a build where the mechanism is absent.
/// These were: with `inlineByteCap`/`inlineVmStepMax` enforcement removed,
/// `large blob`, `unindexed sort` and `filtered count` all fail on the counter
/// while still passing on the data.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/database.dart' show debugReaderPoolOf;
import 'package:resqlite/src/reader/read_worker.dart'
    show inlineRowMax, inlineTurnBudgetUs;
import 'package:resqlite/src/reader/reader_pool.dart';
import 'package:test/test.dart';

/// How a single `select()` was served.
enum _Route { inline, abort, turnYield, dispatch }

extension on ReaderPool {
  /// Run [body] and report which route the single read inside it took.
  Future<(T, _Route)> routeOf<T>(Future<T> Function() body) async {
    final inline = inlineSelectTotal;
    final abort = inlineAbortTotal;
    final yielded = inlineTurnYieldTotal;
    final result = await body();
    return (
      result,
      inlineSelectTotal > inline
          ? _Route.inline
          : inlineAbortTotal > abort
          ? _Route.abort
          : inlineTurnYieldTotal > yielded
          ? _Route.turnYield
          : _Route.dispatch,
    );
  }
}

/// Execute [sql] twice so the pool forms an opinion about it, then report how
/// the third execution was routed.
///
/// Two executions is [RowSizeMemory]'s own arming rule: one observation cannot
/// tell a point read from the small leg of a `LIMIT ?`.
Future<_Route> _routeAfterArming(
  Database db,
  ReaderPool pool,
  String sql, [
  List<Object?> parameters = const [],
]) async {
  await db.select(sql, parameters);
  await db.select(sql, parameters);
  final (_, route) = await pool.routeOf(() => db.select(sql, parameters));
  return route;
}

void main() {
  group('inline read routing', () {
    late Directory tempDir;
    late Database db;
    late ReaderPool pool;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_inline_test_');
      db = await Database.open('${tempDir.path}/test.db');
      pool = await debugReaderPoolOf(db);
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> seedItems(int count) async {
      await db.execute('''
        CREATE TABLE items(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          weight REAL NOT NULL,
          note TEXT
        )
      ''');
      await db.executeBatch(
        'INSERT INTO items(name, weight, note) VALUES (?, ?, ?)',
        [
          for (var i = 0; i < count; i++)
            ['item $i', i * 1.5, i.isEven ? null : 'note $i'],
        ],
      );
    }

    // -----------------------------------------------------------------
    // The happy path exists at all
    // -----------------------------------------------------------------

    test('a small repeated statement ends up running inline', () async {
      await seedItems(500);
      expect(
        await _routeAfterArming(db, pool, 'SELECT * FROM items WHERE id = ?', [
          17,
        ]),
        _Route.inline,
      );
    });

    test('the first two executions of a statement are dispatched', () async {
      await seedItems(500);
      const sql = 'SELECT * FROM items WHERE id = ?';
      for (var i = 0; i < 2; i++) {
        final (_, route) = await pool.routeOf(() => db.select(sql, [17]));
        expect(route, _Route.dispatch, reason: 'execution ${i + 1}');
      }
    });

    test('an inline result is identical to a dispatched one', () async {
      await seedItems(500);
      // Every storage class the decoder has an arm for, plus a NULL.
      const sql = 'SELECT * FROM items WHERE id IN (1, 2)';
      final dispatched = await db.select(sql);
      await db.select(sql);
      final (inline, route) = await pool.routeOf(() => db.select(sql));
      expect(route, _Route.inline);
      expect(
        inline.map(Map<String, Object?>.from),
        dispatched.map(Map<String, Object?>.from),
      );
      expect(inline.first['weight'], isA<double>());
      expect(inline.first['note'], isNull);
      expect(inline.last['note'], 'note 1');
    });

    // -----------------------------------------------------------------
    // The three caps. Each one is a failure mode exp 265 could not see.
    // -----------------------------------------------------------------

    test('row cap: a statement that suddenly returns many rows aborts', () async {
      await seedItems(500);
      // Armed on its small leg, then run on its large one — the mispredict the
      // row cap exists for. The rows still have to be right.
      const sql = 'SELECT * FROM items LIMIT ?';
      await db.select(sql, [1]);
      await db.select(sql, [1]);
      final (rows, route) = await pool.routeOf(
        () => db.select(sql, [inlineRowMax * 4]),
      );
      expect(route, _Route.abort);
      expect(rows, hasLength(inlineRowMax * 4));
      expect(rows.first['id'], 1);
      expect(rows.last['id'], inlineRowMax * 4);
    });

    test('byte cap: a one-row read of a 5 MB blob aborts', () async {
      // The shape that killed exp 265. `SELECT ... WHERE id = ?` over this
      // table returns exactly one row forever, so its row-count high-water mark
      // is permanently 1 and no result-shape signal will ever hold it back.
      await db.execute('CREATE TABLE photos(id INTEGER PRIMARY KEY, img BLOB)');
      final image = Uint8List(5 * 1024 * 1024);
      image[image.length - 1] = 42;
      await db.execute('INSERT INTO photos(img) VALUES (?)', [image]);

      const sql = 'SELECT * FROM photos WHERE id = ?';
      await db.select(sql, [1]);
      await db.select(sql, [1]);
      final (rows, route) = await pool.routeOf(() => db.select(sql, [1]));
      expect(route, _Route.abort);
      // Served by a worker, so the cell went through the transfer wrapping the
      // inline path never reaches.
      expect(rows.single['img'], isA<Uint8List>());
      expect((rows.single['img']! as Uint8List).length, image.length);
      expect((rows.single['img']! as Uint8List).last, 42);
    });

    test('vm-step cap: one row after a full scan aborts', () async {
      await seedItems(20000);
      // A *filtered* count. A bare `count(*)` is one `OP_Count` opcode however
      // large the table, so it is genuinely cheap and correctly runs inline —
      // exp 265 named it as this failure mode and it is the wrong query.
      final route = await _routeAfterArming(
        db,
        pool,
        "SELECT count(*) FROM items WHERE note LIKE '%1234%'",
      );
      expect(route, _Route.abort);
    });

    test('vm-step cap: an unindexed sort aborts', () async {
      await seedItems(20000);
      // Ten rows out, a full sort in.
      final route = await _routeAfterArming(
        db,
        pool,
        'SELECT * FROM items ORDER BY name LIMIT 10',
      );
      expect(route, _Route.abort);
    });

    test('a bare count(*) is cheap enough to run inline', () async {
      await seedItems(20000);
      expect(
        await _routeAfterArming(db, pool, 'SELECT count(*) FROM items'),
        _Route.inline,
      );
    });

    // -----------------------------------------------------------------
    // What happens after a cap fires
    // -----------------------------------------------------------------

    test('an aborted statement is not attempted again', () async {
      await seedItems(20000);
      const sql = "SELECT count(*) FROM items WHERE note LIKE '%1234%'";
      expect(await _routeAfterArming(db, pool, sql), _Route.abort);
      for (var i = 0; i < 3; i++) {
        final (_, route) = await pool.routeOf(() => db.select(sql));
        expect(route, _Route.dispatch, reason: 'retry ${i + 1}');
      }
    });

    test('an abort does not leave the connection on a stale snapshot', () async {
      // A statement abandoned mid-iteration holds its connection's read
      // transaction open. If the reset were missing, every later read on the
      // inline connection would be served from the snapshot taken here.
      await seedItems(500);
      const abortSql = 'SELECT * FROM items LIMIT ?';
      await db.select(abortSql, [1]);
      await db.select(abortSql, [1]);
      final (_, route) = await pool.routeOf(
        () => db.select(abortSql, [inlineRowMax * 4]),
      );
      expect(route, _Route.abort);

      await db.execute(
        'INSERT INTO items(name, weight, note) VALUES (?, ?, ?)',
        ['fresh', 1.0, 'fresh'],
      );

      const pointSql = 'SELECT count(*) AS n FROM items WHERE name = ?';
      await db.select(pointSql, ['fresh']);
      await db.select(pointSql, ['fresh']);
      final (rows, pointRoute) = await pool.routeOf(
        () => db.select(pointSql, ['fresh']),
      );
      expect(pointRoute, _Route.inline);
      expect(rows.single['n'], 1);
    });

    test('a statement that has returned many rows is never attempted', () async {
      await seedItems(500);
      const sql = 'SELECT * FROM items LIMIT 400';
      final before = pool.inlineAbortTotal;
      for (var i = 0; i < 4; i++) {
        final (_, route) = await pool.routeOf(() => db.select(sql));
        expect(route, _Route.dispatch);
      }
      // Never *started*, as distinct from started and abandoned: the row
      // high-water mark keeps the work from being wasted at all.
      expect(pool.inlineAbortTotal, before);
    });

    // -----------------------------------------------------------------
    // The per-turn budget
    // -----------------------------------------------------------------

    test('a long awaited chain gives the event loop back', () async {
      await seedItems(500);
      const sql = 'SELECT * FROM items WHERE id = ?';
      await db.select(sql, [17]);
      await db.select(sql, [17]);

      // A timer cannot fire while a microtask chain is draining, so if inline
      // reads never yielded this would still be false at the end of the loop.
      var ticked = false;
      Timer(const Duration(milliseconds: 1), () => ticked = true);

      final watch = Stopwatch()..start();
      while (watch.elapsedMicroseconds < inlineTurnBudgetUs * 8) {
        await db.select(sql, [17]);
      }
      expect(pool.inlineTurnYieldTotal, greaterThan(0));
      expect(ticked, isTrue);
    });

    test('a short chain stays inline throughout', () async {
      await seedItems(500);
      const sql = 'SELECT * FROM items WHERE id = ?';
      await db.select(sql, [17]);
      await db.select(sql, [17]);
      final before = pool.inlineTurnYieldTotal;
      for (var i = 0; i < 20; i++) {
        await db.select(sql, [17]);
      }
      expect(pool.inlineTurnYieldTotal, before);
    });
  });
}
