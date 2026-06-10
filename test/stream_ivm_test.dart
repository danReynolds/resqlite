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

void main() {
  group('classifyIvmQuery', () {
    IvmShape? classify(String sql, [List<Object?> params = const []]) =>
        classifyIvmQuery(sql, params, 'items', _itemsTableInfo);

    test('admits range + ORDER BY pk', () {
      final shape = classify(
        'SELECT id, score, name FROM items WHERE id >= ? AND id < ? ORDER BY id',
        [10, 20],
      );
      expect(shape, isNotNull);
      expect(shape!.predicates, hasLength(2));
      expect(shape.pkOutputName, 'id');
      expect(shape.projection.map((p) => p.$1), ['id', 'score', 'name']);
    });

    test('admits pk equality without ORDER BY', () {
      expect(classify('SELECT * FROM items WHERE id = ?', [5]), isNotNull);
    });

    test('admits SELECT * with table-order projection', () {
      final shape = classify('SELECT * FROM items WHERE id = 3');
      expect(shape, isNotNull);
      expect(shape!.projection.map((p) => p.$1), [
        'id',
        'flag',
        'score',
        'name',
      ]);
    });

    test('admits integer equality on non-pk column with ORDER BY pk', () {
      expect(
        classify('SELECT id, name FROM items WHERE flag = 1 ORDER BY id'),
        isNotNull,
      );
    });

    test('rejects everything outside the grammar', () {
      final rejected = <String>[
        // No deterministic order and no pk pin.
        'SELECT id FROM items WHERE flag = 1',
        // Order by non-pk.
        'SELECT id, score FROM items WHERE id > 0 ORDER BY score',
        'SELECT id FROM items ORDER BY id DESC',
        'SELECT id FROM items ORDER BY id LIMIT 10',
        'SELECT id FROM items WHERE id > 0 OR flag = 1 ORDER BY id',
        'SELECT id FROM items WHERE name = ? ORDER BY id', // text param
        'SELECT count(*) FROM items WHERE id = 1',
        'SELECT i.id FROM items i WHERE id = 1',
        'SELECT id FROM items JOIN other ON 1 WHERE id = 1',
        'SELECT DISTINCT id FROM items WHERE id = 1',
        'SELECT id AS x FROM items WHERE id = 1',
        'SELECT id FROM other WHERE id = 1', // table mismatch
        'SELECT flag FROM items WHERE id = 1', // pk not projected
        'SELECT id FROM items WHERE missing = 1 ORDER BY id',
        "SELECT id FROM items WHERE name = 'x' ORDER BY id",
        'SELECT id FROM items WHERE id IN (1, 2) ORDER BY id',
      ];
      for (final sql in rejected) {
        expect(classify(sql), isNull, reason: sql);
      }
    });

    test('rejects text bind parameter values', () {
      expect(
        classify('SELECT id FROM items WHERE id = ? ORDER BY id', ['5']),
        isNull,
      );
    });

    test('rejects tables without an INTEGER pk rowid alias', () {
      final noPk = [
        {'cid': 0, 'name': 'a', 'type': 'INTEGER', 'pk': 0},
      ];
      expect(
        classifyIvmQuery('SELECT a FROM t WHERE a = 1', const [], 't', noPk),
        isNull,
      );
      final textPk = [
        {'cid': 0, 'name': 'k', 'type': 'TEXT', 'pk': 1},
      ];
      expect(
        classifyIvmQuery('SELECT k FROM t WHERE k = 1', const [], 't', textPk),
        isNull,
      );
      final compositePk = [
        {'cid': 0, 'name': 'a', 'type': 'INTEGER', 'pk': 1},
        {'cid': 1, 'name': 'b', 'type': 'INTEGER', 'pk': 2},
      ];
      expect(
        classifyIvmQuery(
          'SELECT a, b FROM t WHERE a = 1',
          const [],
          't',
          compositePk,
        ),
        isNull,
      );
    });
  });

  group('IvmState.apply', () {
    IvmState freshState() {
      final shape = classifyIvmQuery(
        'SELECT id, score, name FROM items WHERE id >= 10 AND id < 20 ORDER BY id',
        const [],
        'items',
        _itemsTableInfo,
      )!;
      final state = IvmState(shape);
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
      final outcome = state.apply([
        update(50, [50, 0, 1, 'x'], [50, 0, 2, 'x']),
      ]);
      expect(outcome, IvmOutcome.unchanged);
      expect(identical(state.rows, before), isTrue);
    });

    test('in-window patch emits a fresh list and preserves order', () {
      final state = freshState();
      final before = state.rows;
      final outcome = state.apply([
        update(15, [15, 0, 7, 'b'], [15, 0, 9, 'b2']),
      ]);
      expect(outcome, IvmOutcome.applied);
      expect(identical(state.rows, before), isFalse);
      expect(state.rows, [
        {'id': 11, 'score': 5, 'name': 'a'},
        {'id': 15, 'score': 9, 'name': 'b2'},
      ]);
      // The pre-patch list (held by earlier subscribers) is unchanged.
      expect(before!.last['score'], 7);
    });

    test('update touching only unprojected columns is unchanged', () {
      final state = freshState();
      final outcome = state.apply([
        update(15, [15, 0, 7, 'b'], [15, 1, 7, 'b']), // flag not projected
      ]);
      expect(outcome, IvmOutcome.unchanged);
    });

    test('insert enters at the sorted position', () {
      final state = freshState();
      final outcome = state.apply([
        RowDelta(
          op: deltaOpInsert,
          table: 'items',
          oldRowid: 13,
          newRowid: 13,
          oldValues: null,
          newValues: [13, 0, 1, 'c'],
        ),
      ]);
      expect(outcome, IvmOutcome.applied);
      expect(state.rows!.map((r) => r['id']), [11, 13, 15]);
    });

    test('delete departs exactly', () {
      final state = freshState();
      final outcome = state.apply([
        RowDelta(
          op: deltaOpDelete,
          table: 'items',
          oldRowid: 11,
          newRowid: 11,
          oldValues: [11, 0, 5, 'a'],
          newValues: null,
        ),
      ]);
      expect(outcome, IvmOutcome.applied);
      expect(state.rows!.map((r) => r['id']), [15]);
    });

    test('rowid change splits into departure + entry', () {
      final state = freshState();
      final outcome = state.apply([
        RowDelta(
          op: deltaOpUpdate,
          table: 'items',
          oldRowid: 15,
          newRowid: 12,
          oldValues: [15, 0, 7, 'b'],
          newValues: [12, 0, 7, 'b'],
        ),
      ]);
      expect(outcome, IvmOutcome.applied);
      expect(state.rows!.map((r) => r['id']), [11, 12]);
    });

    test('NULL predicate cell means the row does not match', () {
      final state = freshState();
      final outcome = state.apply([
        update(50, [null, 0, 1, 'x'], [null, 0, 2, 'x']),
      ]);
      expect(outcome, IvmOutcome.unchanged);
    });

    test('non-int predicate cell bails', () {
      final state = freshState();
      final outcome = state.apply([
        update(50, ['oops', 0, 1, 'x'], ['oops', 0, 2, 'x']),
      ]);
      expect(outcome, IvmOutcome.bail);
      expect(state.rows, isNull);
    });

    test('cache inconsistency bails (entry already present)', () {
      final state = freshState();
      final outcome = state.apply([
        RowDelta(
          op: deltaOpInsert,
          table: 'items',
          oldRowid: 15,
          newRowid: 15,
          oldValues: null,
          newValues: [15, 0, 1, 'dup'],
        ),
      ]);
      expect(outcome, IvmOutcome.bail);
    });

    test('schema drift (column count mismatch) bails', () {
      final state = freshState();
      final outcome = state.apply([
        update(15, [15, 0, 7], [15, 0, 9]),
      ]);
      expect(outcome, IvmOutcome.bail);
    });

    test('rebuild rejects unkeyable or unordered results', () {
      final shape = classifyIvmQuery(
        'SELECT id, score, name FROM items WHERE id >= 0 ORDER BY id',
        const [],
        'items',
        _itemsTableInfo,
      )!;
      expect(
        IvmState(shape).rebuild([
          {'id': 'nope', 'score': 1, 'name': 'a'},
        ]),
        isFalse,
      );
      expect(
        IvmState(shape).rebuild([
          {'id': 5, 'score': 1, 'name': 'a'},
          {'id': 3, 'score': 1, 'name': 'b'},
        ]),
        isFalse,
      );
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
