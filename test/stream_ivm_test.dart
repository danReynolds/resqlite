import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/row_deltas.dart';
import 'package:resqlite/src/stream_ivm.dart';
import 'package:test/test.dart';

final _itemsTableInfo = <Map<String, Object?>>[
  {'cid': 0, 'name': 'id', 'type': 'INTEGER', 'pk': 1},
  {'cid': 1, 'name': 'flag', 'type': 'INTEGER', 'pk': 0},
  {'cid': 2, 'name': 'score', 'type': 'INTEGER', 'pk': 0},
  {'cid': 3, 'name': 'name', 'type': 'TEXT', 'pk': 0},
];

const _itemsCreateSql =
    'CREATE TABLE items(id INTEGER PRIMARY KEY, flag INTEGER NOT NULL, '
    'score INTEGER NOT NULL, name TEXT NOT NULL)';

void main() {
  group('classifyIvmQuery (modes)', () {
    IvmAdmission? classify(
      String sql, [
      List<Object?> params = const [],
      String? createSql = _itemsCreateSql,
    ]) =>
        classifyIvmQuery(
          sql,
          params,
          'items',
          _itemsTableInfo,
          createSql: createSql,
        );

    test('full: range + ORDER BY pk', () {
      final shape = classify(
        'SELECT id, score, name FROM items WHERE id >= ? AND id < ? ORDER BY id',
        [10, 20],
      );
      expect(shape, isA<IvmFullShape>());
      final full = shape! as IvmFullShape;
      expect(full.predicates, hasLength(2));
      expect(full.pkOutputName, 'id');
      expect(full.limit, isNull);
      expect(full.projection.map((c) => c.$1), ['id', 'score', 'name']);
    });

    test('full: pk equality without ORDER BY, * projection', () {
      expect(
        classify('SELECT * FROM items WHERE id = ?', [5]),
        isA<IvmFullShape>(),
      );
    });

    test('full: DESC on pk alone is deterministic', () {
      final shape = classify('SELECT id, score FROM items ORDER BY id DESC');
      expect(shape, isA<IvmFullShape>());
      expect((shape! as IvmFullShape).orderDesc, isTrue);
    });

    test('full windowed: composite ORDER BY with pk tiebreak + LIMIT', () {
      final shape = classify(
        'SELECT id, score FROM items WHERE flag = 1 '
        'ORDER BY score DESC, id DESC LIMIT 20',
      );
      expect(shape, isA<IvmFullShape>());
      final full = shape! as IvmFullShape;
      expect(full.limit, 20);
      expect(full.orderDesc, isTrue);
      expect(full.pkDesc, isTrue);
      expect(full.orderOutputName, 'score');
    });

    test('full windowed: LIMIT as a bind parameter', () {
      final shape = classify(
        'SELECT id, score FROM items ORDER BY score, id LIMIT ?',
        [30],
      );
      expect(shape, isA<IvmFullShape>());
      expect((shape! as IvmFullShape).limit, 30);
    });

    test('full: aliased pk keeps keying through the alias', () {
      final shape = classify('SELECT id AS x FROM items WHERE id = 1');
      expect(shape, isA<IvmFullShape>());
      expect((shape! as IvmFullShape).pkOutputName, 'x');
    });

    test('skip: evaluable predicate with unmaintainable result', () {
      final cases = <String>[
        // No deterministic order, no pk pin.
        'SELECT id FROM items WHERE flag = 1',
        // Order by non-pk without tiebreak.
        'SELECT id, score FROM items WHERE id > 0 ORDER BY score',
        // DESC window without pk tiebreak.
        'SELECT id, score FROM items WHERE flag = 1 ORDER BY score DESC LIMIT 20',
        // OFFSET demotes.
        'SELECT id FROM items WHERE flag = 1 ORDER BY id LIMIT 10 OFFSET 5',
        // DISTINCT demotes.
        'SELECT DISTINCT id FROM items WHERE id = 1',
        // pk not projected.
        'SELECT flag FROM items WHERE id = 1',
        // Order column not projected.
        'SELECT id FROM items WHERE flag = 1 ORDER BY score, id LIMIT 5',
      ];
      for (final sql in cases) {
        expect(classify(sql), isA<IvmSkipShape>(), reason: sql);
      }
    });

    test('skip: TEXT equality admitted only without COLLATE', () {
      const sql = "SELECT id FROM items WHERE name = 'x'";
      expect(classify(sql), isA<IvmSkipShape>());
      expect(
        classify(sql, const [], null),
        isNull,
        reason: 'unknown CREATE sql must reject text predicates',
      );
      expect(
        classify(
          sql,
          const [],
          'CREATE TABLE items(id INTEGER PRIMARY KEY, '
          'name TEXT COLLATE NOCASE)',
        ),
        isNull,
        reason: 'COLLATE anywhere in the table rejects text predicates',
      );
    });

    test('full: TEXT equality predicate with ORDER BY pk', () {
      final shape = classify(
        'SELECT id, name FROM items WHERE name = ? ORDER BY id',
        ['row_7'],
      );
      expect(shape, isA<IvmFullShape>());
    });

    test('skip: TEXT inequality never admitted', () {
      expect(
        classify("SELECT id FROM items WHERE name > 'x' ORDER BY id"),
        isNull,
      );
    });

    test('aggregate: aliased aggregates over evaluable predicate', () {
      final shape = classify(
        'SELECT COUNT(*) AS n, SUM(score) AS total, MIN(score) AS lo, '
        'MAX(score) AS hi, AVG(score) AS mean '
        'FROM items WHERE flag = ?',
        [1],
      );
      expect(shape, isA<IvmAggregateShape>());
      final agg = shape! as IvmAggregateShape;
      expect(agg.aggregates, hasLength(5));
      expect(agg.aggregateColumns, [2]);
    });

    test('aggregate: COUNT(*) without WHERE', () {
      expect(
        classify('SELECT COUNT(*) AS n FROM items'),
        isA<IvmAggregateShape>(),
      );
    });

    test('aggregate: missing AS alias rejects', () {
      expect(classify('SELECT COUNT(*) FROM items WHERE flag = 1'), isNull);
    });

    test('aggregate: non-INTEGER column for SUM rejects to skip', () {
      expect(
        classify('SELECT SUM(name) AS s FROM items WHERE flag = 1'),
        isNull,
      );
    });

    test('rejected outright', () {
      final cases = <String>[
        'SELECT id FROM items WHERE id > 0 OR flag = 1 ORDER BY id',
        'SELECT i.id FROM items i WHERE id = 1',
        'SELECT id FROM items JOIN other ON 1 WHERE id = 1',
        'SELECT id FROM other WHERE id = 1',
        'SELECT id FROM items WHERE missing = 1 ORDER BY id',
        'SELECT id FROM items WHERE id IN (1, 2) ORDER BY id',
        'SELECT id FROM items ORDER BY id LIMIT 10', // window without preds is full though
      ];
      for (final sql in cases.sublist(0, cases.length - 1)) {
        expect(classify(sql), isNull, reason: sql);
      }
      // Windowed full without predicates is admissible.
      expect(classify(cases.last), isA<IvmFullShape>());
    });

    test('rejects text bind parameter for int column ops', () {
      expect(
        classify('SELECT id FROM items WHERE id < ? ORDER BY id', ['5']),
        isNull,
      );
    });
  });

  group('IvmFullState (unwindowed)', () {
    IvmFullState freshState() {
      final shape = classifyIvmQuery(
        'SELECT id, score, name FROM items '
        'WHERE id >= 10 AND id < 20 ORDER BY id',
        const [],
        'items',
        _itemsTableInfo,
        createSql: _itemsCreateSql,
      )! as IvmFullShape;
      final state = IvmFullState(shape);
      expect(
        state.rebuild([
          {'id': 11, 'score': 5, 'name': 'a'},
          {'id': 15, 'score': 7, 'name': 'b'},
        ]),
        isTrue,
      );
      return state;
    }

    RowDelta update(int rowid, List<Object?> oldV, List<Object?> newV) =>
        RowDelta(
          op: deltaOpUpdate,
          table: 'items',
          oldRowid: rowid,
          newRowid: rowid,
          oldValues: oldV,
          newValues: newV,
        );

    test('proven miss leaves the cache untouched', () {
      final state = freshState();
      final before = state.rows;
      expect(
        state.apply([
          update(50, [50, 0, 1, 'x'], [50, 0, 2, 'x']),
        ]),
        IvmOutcome.unchanged,
      );
      expect(identical(state.rows, before), isTrue);
    });

    test('patch clones and preserves order', () {
      final state = freshState();
      final before = state.rows;
      expect(
        state.apply([
          update(15, [15, 0, 7, 'b'], [15, 0, 9, 'b2']),
        ]),
        IvmOutcome.applied,
      );
      expect(identical(state.rows, before), isFalse);
      expect(state.rows, [
        {'id': 11, 'score': 5, 'name': 'a'},
        {'id': 15, 'score': 9, 'name': 'b2'},
      ]);
      expect(before!.last['score'], 7);
    });

    test('insert, delete, rowid change', () {
      final state = freshState();
      expect(
        state.apply([
          RowDelta(
            op: deltaOpInsert,
            table: 'items',
            oldRowid: 13,
            newRowid: 13,
            oldValues: null,
            newValues: [13, 0, 1, 'c'],
          ),
        ]),
        IvmOutcome.applied,
      );
      expect(state.rows!.map((r) => r['id']), [11, 13, 15]);

      expect(
        state.apply([
          RowDelta(
            op: deltaOpDelete,
            table: 'items',
            oldRowid: 11,
            newRowid: 11,
            oldValues: [11, 0, 5, 'a'],
            newValues: null,
          ),
        ]),
        IvmOutcome.applied,
      );
      expect(state.rows!.map((r) => r['id']), [13, 15]);

      expect(
        state.apply([
          RowDelta(
            op: deltaOpUpdate,
            table: 'items',
            oldRowid: 15,
            newRowid: 12,
            oldValues: [15, 0, 7, 'b'],
            newValues: [12, 0, 7, 'b'],
          ),
        ]),
        IvmOutcome.applied,
      );
      expect(state.rows!.map((r) => r['id']), [12, 13]);
    });

    test('unprovable cell and cache inconsistency bail', () {
      final state = freshState();
      expect(
        state.apply([
          update(50, ['oops', 0, 1, 'x'], ['oops', 0, 2, 'x']),
        ]),
        IvmOutcome.bail,
      );
      expect(state.rows, isNull);

      final state2 = freshState();
      expect(
        state2.apply([
          RowDelta(
            op: deltaOpInsert,
            table: 'items',
            oldRowid: 15,
            newRowid: 15,
            oldValues: null,
            newValues: [15, 0, 1, 'dup'],
          ),
        ]),
        IvmOutcome.bail,
      );
    });
  });

  group('IvmFullState (windowed)', () {
    // Window: top 3 by (score DESC, id DESC) of flag = 1 rows.
    IvmFullShape windowShape() =>
        classifyIvmQuery(
              'SELECT id, score FROM items WHERE flag = 1 '
              'ORDER BY score DESC, id DESC LIMIT 3',
              const [],
              'items',
              _itemsTableInfo,
              createSql: _itemsCreateSql,
            )!
            as IvmFullShape;

    List<Object?> row(int id, int flag, int score) => [id, flag, score, 'r$id'];

    RowDelta insert(int id, int flag, int score) => RowDelta(
      op: deltaOpInsert,
      table: 'items',
      oldRowid: id,
      newRowid: id,
      oldValues: null,
      newValues: row(id, flag, score),
    );

    RowDelta delete(int id, int flag, int score) => RowDelta(
      op: deltaOpDelete,
      table: 'items',
      oldRowid: id,
      newRowid: id,
      oldValues: row(id, flag, score),
      newValues: null,
    );

    test('full window: entries inside/below, departures fall back', () {
      final state = IvmFullState(windowShape());
      expect(
        state.rebuild([
          {'id': 9, 'score': 90},
          {'id': 7, 'score': 70},
          {'id': 5, 'score': 50},
        ]),
        isTrue,
      );
      expect(state.complete, isFalse); // len == K, more may exist

      // Below-window entry is invisible and ignored.
      expect(state.apply([insert(2, 1, 10)]), IvmOutcome.unchanged);

      // In-window entry displaces the tail.
      expect(state.apply([insert(8, 1, 80)]), IvmOutcome.applied);
      expect(state.visibleRows().map((r) => r['id']), [9, 8, 7]);

      // Miss: flag = 0 rows never matter.
      expect(state.apply([insert(99, 0, 999)]), IvmOutcome.unchanged);

      // Departure from a full, incomplete window cannot be patched.
      expect(state.apply([delete(9, 1, 90)]), IvmOutcome.bail);
      expect(state.rows, isNull);
    });

    test('complete window absorbs departures', () {
      final state = IvmFullState(windowShape());
      expect(
        state.rebuild([
          {'id': 9, 'score': 90},
          {'id': 7, 'score': 70},
        ]),
        isTrue,
      );
      expect(state.complete, isTrue); // fewer rows than K exist

      expect(state.apply([delete(9, 1, 90)]), IvmOutcome.applied);
      expect(state.visibleRows().map((r) => r['id']), [7]);

      expect(state.apply([insert(8, 1, 80)]), IvmOutcome.applied);
      expect(state.apply([insert(6, 1, 60)]), IvmOutcome.applied);
      expect(state.apply([insert(4, 1, 40)]), IvmOutcome.applied);
      // Window shows top 3; the 4th row is retained (complete set).
      expect(state.visibleRows().map((r) => r['id']), [8, 7, 6]);
      expect(state.rows!.length, 4);

      // Now a departure from the window promotes the retained row.
      expect(state.apply([delete(7, 1, 70)]), IvmOutcome.applied);
      expect(state.visibleRows().map((r) => r['id']), [8, 6, 4]);
    });

    test('tie order follows the explicit pk tiebreak', () {
      final state = IvmFullState(windowShape());
      expect(
        state.rebuild([
          {'id': 9, 'score': 50},
          {'id': 4, 'score': 50},
        ]),
        isTrue,
      );
      expect(state.apply([insert(6, 1, 50)]), IvmOutcome.applied);
      expect(state.visibleRows().map((r) => r['id']), [9, 6, 4]);
    });
  });

  group('IvmSkipState', () {
    IvmSkipState skipState() =>
        IvmSkipState(
          classifyIvmQuery(
                'SELECT id, score FROM items WHERE flag = 1 '
                'ORDER BY score DESC LIMIT 20',
                const [],
                'items',
                _itemsTableInfo,
                createSql: _itemsCreateSql,
              )!
              as IvmSkipShape,
        );

    RowDelta update(int rowid, List<Object?> oldV, List<Object?> newV) =>
        RowDelta(
          op: deltaOpUpdate,
          table: 'items',
          oldRowid: rowid,
          newRowid: rowid,
          oldValues: oldV,
          newValues: newV,
        );

    test('all-miss batches are proven unchanged', () {
      final state = skipState();
      expect(
        state.apply([
          update(1, [1, 0, 5, 'a'], [1, 0, 9, 'a']),
          update(2, [2, 0, 5, 'b'], [2, 0, 9, 'b']),
        ]),
        IvmOutcome.unchanged,
      );
    });

    test('any hit falls back', () {
      final state = skipState();
      expect(
        state.apply([
          update(1, [1, 0, 5, 'a'], [1, 1, 5, 'a']), // enters flag = 1
        ]),
        IvmOutcome.bail,
      );
    });

    test('unprovable cells fall back', () {
      final state = skipState();
      expect(
        state.apply([
          update(1, [1, 'x', 5, 'a'], [1, 'x', 9, 'a']),
        ]),
        IvmOutcome.bail,
      );
    });
  });

  group('IvmAggregateState', () {
    IvmAggregateShape aggShape() =>
        classifyIvmQuery(
              'SELECT COUNT(*) AS n, SUM(score) AS total, MIN(score) AS lo, '
              'MAX(score) AS hi, AVG(score) AS mean '
              'FROM items WHERE flag = 1',
              const [],
              'items',
              _itemsTableInfo,
              createSql: _itemsCreateSql,
            )!
            as IvmAggregateShape;

    IvmAggregateState seeded() {
      final state = IvmAggregateState(aggShape());
      expect(
        state.seedFromSnapshot({
          '__rows': 2,
          '__n2': 2,
          '__s2': 30,
          '__lo2': 10,
          '__hi2': 20,
        }),
        isTrue,
      );
      return state;
    }

    List<Object?> row(int id, int flag, int? score) => [id, flag, score, 'r'];

    test('entries, departures, and patches maintain exact values', () {
      final state = seeded();

      // Entry of (score 5): count 3, sum 35, min 5, max 20.
      expect(
        state.apply([
          RowDelta(
            op: deltaOpInsert,
            table: 'items',
            oldRowid: 7,
            newRowid: 7,
            oldValues: null,
            newValues: row(7, 1, 5),
          ),
        ]),
        IvmOutcome.applied,
      );
      expect(state.visibleRow(), {
        'n': 3,
        'total': 35,
        'lo': 5,
        'hi': 20,
        'mean': closeTo(35 / 3, 1e-9),
      });

      // NULL cells count for COUNT(*) but not the column aggregates.
      expect(
        state.apply([
          RowDelta(
            op: deltaOpInsert,
            table: 'items',
            oldRowid: 8,
            newRowid: 8,
            oldValues: null,
            newValues: row(8, 1, null),
          ),
        ]),
        IvmOutcome.applied,
      );
      expect(state.visibleRow()['n'], 4);
      expect(state.visibleRow()['total'], 35);

      // Patch a non-extremum row: score 10 -> 12 (extremum departures
      // are covered below and legitimately bail).
      expect(
        state.apply([
          RowDelta(
            op: deltaOpUpdate,
            table: 'items',
            oldRowid: 1,
            newRowid: 1,
            oldValues: row(1, 1, 10),
            newValues: row(1, 1, 12),
          ),
        ]),
        IvmOutcome.applied,
      );
      expect(state.visibleRow()['total'], 37);
      expect(state.visibleRow()['lo'], 5);

      // Misses never touch state.
      expect(
        state.apply([
          RowDelta(
            op: deltaOpUpdate,
            table: 'items',
            oldRowid: 50,
            newRowid: 50,
            oldValues: row(50, 0, 1),
            newValues: row(50, 0, 2),
          ),
        ]),
        IvmOutcome.unchanged,
      );
    });

    test('departing extremum bails and unseeds', () {
      final state = seeded();
      expect(
        state.apply([
          RowDelta(
            op: deltaOpDelete,
            table: 'items',
            oldRowid: 3,
            newRowid: 3,
            oldValues: row(3, 1, 20), // current max departs
            newValues: null,
          ),
        ]),
        IvmOutcome.bail,
      );
      expect(state.seeded, isFalse);
    });

    test('empty set reports SQL aggregate semantics', () {
      final state = IvmAggregateState(aggShape());
      expect(
        state.seedFromSnapshot({
          '__rows': 0,
          '__n2': 0,
          '__s2': null,
          '__lo2': null,
          '__hi2': null,
        }),
        isTrue,
      );
      expect(state.visibleRow(), {
        'n': 0,
        'total': null,
        'lo': null,
        'hi': null,
        'mean': null,
      });
    });

    test('snapshot SQL is well-formed', () {
      final sql = buildAggregateSnapshotSql(aggShape(), _itemsTableInfo);
      expect(sql, contains('COUNT(*) AS __rows'));
      expect(sql, contains('SUM("score") AS __s2'));
      expect(sql, contains('FROM "items" WHERE "flag" = 1'));
    });
  });

  group('end-to-end incremental streams', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_ivm_test_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE items(id INTEGER PRIMARY KEY, flag INTEGER NOT NULL, '
        'score INTEGER NOT NULL, name TEXT NOT NULL, weight REAL, '
        'blob_col BLOB)',
      );
      await db.executeBatch(
        'INSERT INTO items(id, flag, score, name) VALUES (?, ?, ?, ?)',
        [
          for (var i = 0; i < 50; i++) [i, i % 2, i * 10, 'row_$i'],
        ],
      );
    });

    tearDown(() async {
      await db.close();
      try {
        await tempDir.delete(recursive: true);
      } on PathNotFoundException {
        // ignore
      }
    });

    /// Wait until [emissions] has stopped changing across consecutive
    /// quiet windows, so in-flight admissions/re-queries drain before a
    /// "no emission happened" assertion.
    Future<void> settleQuiet(List<Object?> emissions) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var last = emissions.length;
      var quietWindows = 0;
      while (quietWindows < 2) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (emissions.length == last) {
          quietWindows++;
        } else {
          quietWindows = 0;
          last = emissions.length;
        }
      }
    }
    /// Wait until [emissions] reaches at least [count], then let any
    /// trailing work drain. Use before positive emission-count
    /// assertions — fixed delays flake under full-suite load where a
    /// re-query (or the initial query) can take longer than any chosen
    /// constant.
    Future<void> settleTo(List<Object?> emissions, int count) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (emissions.length < count) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'expected $count emissions within 15s, saw ${emissions.length}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await settleQuiet(emissions);
    }


    /// Assert the latest emission matches a fresh query of the same SQL.
    Future<void> expectMatchesSelect(
      List<List<Map<String, Object?>>> emissions,
      String sql,
      List<Object?> params,
    ) async {
      final fresh = await db.select(sql, params);
      expect(emissions, isNotEmpty);
      expect(emissions.last, fresh);
    }

    test('range stream tracks misses, patches, entries, departures', () async {
      const sql =
          'SELECT id, score, name FROM items '
          'WHERE id >= ? AND id < ? ORDER BY id';
      final params = [10, 20];
      final emissions = <List<Map<String, Object?>>>[];
      final sub = db.stream(sql, params).listen(emissions.add);
      addTearDown(sub.cancel);
      await settleTo(emissions, 1);
      expect(emissions, hasLength(1));

      // Miss: out-of-range write must not emit.
      await db.execute('UPDATE items SET score = 999 WHERE id = 40');
      await settleQuiet(emissions);
      expect(emissions, hasLength(1));

      // Patch: in-range projected column.
      await db.execute('UPDATE items SET score = 111 WHERE id = 15');
      await settleTo(emissions, 2);
      expect(emissions, hasLength(2));
      await expectMatchesSelect(emissions, sql, params);
      expect(
        emissions.last.firstWhere((r) => r['id'] == 15)['score'],
        111,
      );

      // Entry: insert into the range.
      await db.execute(
        "INSERT INTO items(id, flag, score, name) VALUES (1000, 0, 5, 'x')",
      );
      await settleQuiet(emissions);
      expect(emissions, hasLength(2)); // out of range — no emission
      await db.execute('DELETE FROM items WHERE id = 1000');
      await settleQuiet(emissions);
      expect(emissions, hasLength(2));

      await db.execute('DELETE FROM items WHERE id = 12');
      await settleTo(emissions, 3);
      expect(emissions, hasLength(3));
      await expectMatchesSelect(emissions, sql, params);
      expect(emissions.last.map((r) => r['id']), isNot(contains(12)));

      // Rowid change: moves a row out of the range.
      await db.execute('UPDATE items SET id = 500 WHERE id = 15');
      await settleTo(emissions, 4);
      await expectMatchesSelect(emissions, sql, params);
      expect(emissions.last.map((r) => r['id']), isNot(contains(15)));

      // Rowid change: moves a row into the range.
      await db.execute('UPDATE items SET id = 12 WHERE id = 500');
      await settleTo(emissions, 5);
      await expectMatchesSelect(emissions, sql, params);
      expect(emissions.last.map((r) => r['id']), contains(12));
    });

    test('keyed stream only wakes for its row', () async {
      const sql = 'SELECT * FROM items WHERE id = ?';
      final emissions = <List<Map<String, Object?>>>[];
      final sub = db.stream(sql, [15]).listen(emissions.add);
      addTearDown(sub.cancel);
      await settleTo(emissions, 1);
      expect(emissions, hasLength(1));

      for (var i = 0; i < 10; i++) {
        await db.execute('UPDATE items SET score = ? WHERE id = ?', [
          i,
          20 + i,
        ]);
      }
      await settleQuiet(emissions);
      expect(emissions, hasLength(1)); // all misses

      await db.execute('UPDATE items SET name = ? WHERE id = ?', ['hit', 15]);
      await settleTo(emissions, 2);
      expect(emissions, hasLength(2));
      await expectMatchesSelect(emissions, sql, [15]);
    });

    test('REAL, NULL, and BLOB projected values survive patching', () async {
      const sql =
          'SELECT id, weight, blob_col FROM items '
          'WHERE id >= 0 AND id < 5 ORDER BY id';
      final emissions = <List<Map<String, Object?>>>[];
      final sub = db.stream(sql, const []).listen(emissions.add);
      addTearDown(sub.cancel);
      await settleTo(emissions, 1);

      await db.execute(
        'UPDATE items SET weight = 2.5, blob_col = ? WHERE id = 3',
        [
          Uint8List.fromList([1, 2, 3]),
        ],
      );
      await settleTo(emissions, 2);
      await expectMatchesSelect(emissions, sql, const []);
      final patched = emissions.last.firstWhere((r) => r['id'] == 3);
      expect(patched['weight'], 2.5);
      expect(patched['blob_col'], [1, 2, 3]);
    });

    test('transaction deltas apply once on commit', () async {
      const sql =
          'SELECT id, score, name FROM items '
          'WHERE id >= 10 AND id < 20 ORDER BY id';
      final emissions = <List<Map<String, Object?>>>[];
      final sub = db.stream(sql, const []).listen(emissions.add);
      addTearDown(sub.cancel);
      await settleTo(emissions, 1);
      expect(emissions, hasLength(1));

      await db.transaction((tx) async {
        await tx.execute('UPDATE items SET score = 1 WHERE id = 11');
        await tx.execute('UPDATE items SET score = 2 WHERE id = 13');
        await tx.execute('DELETE FROM items WHERE id = 17');
      });
      await settleTo(emissions, 2);
      expect(emissions, hasLength(2));
      await expectMatchesSelect(emissions, sql, const []);
    });

    test('rolled-back savepoint never leaks deltas', () async {
      const sql =
          'SELECT id, score, name FROM items '
          'WHERE id >= 10 AND id < 20 ORDER BY id';
      final emissions = <List<Map<String, Object?>>>[];
      final sub = db.stream(sql, const []).listen(emissions.add);
      addTearDown(sub.cancel);
      await settleTo(emissions, 1);

      await db.transaction((tx) async {
        await tx.execute('UPDATE items SET score = 1 WHERE id = 11');
        try {
          await tx.transaction((tx2) async {
            await tx2.execute('UPDATE items SET score = 666 WHERE id = 13');
            throw StateError('undo savepoint');
          });
        } on StateError {
          // expected
        }
        await tx.execute('UPDATE items SET score = 2 WHERE id = 14');
      });
      await settleTo(emissions, 2);
      await expectMatchesSelect(emissions, sql, const []);
      final byId = {for (final r in emissions.last) r['id']: r};
      expect(byId[11]!['score'], 1);
      expect(byId[13]!['score'], 130); // savepoint rollback restored it
      expect(byId[14]!['score'], 2);
    });

    test('delta overflow falls back to re-query and stays correct', () async {
      const sql =
          'SELECT id, score, name FROM items '
          'WHERE id >= 0 AND id < 5000 ORDER BY id';
      final emissions = <List<Map<String, Object?>>>[];
      final sub = db.stream(sql, const []).listen(emissions.add);
      addTearDown(sub.cancel);
      await settleTo(emissions, 1);

      // 400 rows > RESQLITE_MAX_DELTA_ROWS (256) — capture goes unreliable.
      await db.executeBatch(
        'INSERT INTO items(id, flag, score, name) VALUES (?, ?, ?, ?)',
        [
          for (var i = 100; i < 500; i++) [i, 0, 1, 'bulk_$i'],
        ],
      );
      await settleTo(emissions, 2);
      await expectMatchesSelect(emissions, sql, const []);
      expect(emissions.last, hasLength(450));
    });

    test('unadmitted text-predicate stream still works via re-query', () async {
      const sql = "SELECT id, name FROM items WHERE name = 'row_7'";
      final emissions = <List<Map<String, Object?>>>[];
      final sub = db.stream(sql, const []).listen(emissions.add);
      addTearDown(sub.cancel);
      await settleTo(emissions, 1);
      expect(emissions, hasLength(1));

      await db.execute("UPDATE items SET name = 'row_7' WHERE id = 8");
      await settleTo(emissions, 2);
      await expectMatchesSelect(emissions, sql, const []);
      expect(emissions.last, hasLength(2));
    });

    test('two partitioned streams wake independently', () async {
      const sqlA =
          'SELECT id, score FROM items WHERE id >= 0 AND id < 10 ORDER BY id';
      const sqlB =
          'SELECT id, score FROM items WHERE id >= 10 AND id < 20 ORDER BY id';
      final emissionsA = <List<Map<String, Object?>>>[];
      final emissionsB = <List<Map<String, Object?>>>[];
      final subA = db.stream(sqlA, const []).listen(emissionsA.add);
      final subB = db.stream(sqlB, const []).listen(emissionsB.add);
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);
      await settleTo(emissionsA, 1);
      await settleTo(emissionsB, 1);
      expect(emissionsA, hasLength(1));
      expect(emissionsB, hasLength(1));

      await db.execute('UPDATE items SET score = 1 WHERE id = 5');
      await settleTo(emissionsA, 2);
      await settleQuiet(emissionsB);
      expect(emissionsA, hasLength(2));
      expect(emissionsB, hasLength(1));
      await expectMatchesSelect(emissionsA, sqlA, const []);
    });
  });
}
