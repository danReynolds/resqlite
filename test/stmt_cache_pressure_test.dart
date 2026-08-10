// Correctness of the SQL-keyed caches once a workload overruns them
// ([EXP-267](../experiments/267-stmt-cache-capacity.md)).
//
// Three caches on the read path are keyed by SQL text and bounded: the C
// per-connection prepared-statement cache (`STMT_CACHE_MAX`), the per-worker
// Dart `schemaCache`, and the pool's row-size memory. Exp 267 raised all three
// and changed how the C cache reclaims a slot — it now disposes the
// least-recently-used entry and builds the new one in place, instead of
// compacting the array so the newest entry lands at the tail.
//
// A cache that returns the *wrong* entry is silent: the caller gets a
// well-formed result belonging to a different statement. Every test here
// therefore makes each statement's identity checkable from its result — the
// row it selects, or the columns it projects — so a mismatched entry fails
// rather than passing with plausible data.
//
// `_overrun` is deliberately far above any of the caps rather than read from
// them: the C capacity is a compile-time constant with no FFI getter, and a
// test that tracked the constant would stop overrunning the day it was raised.
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Distinct statements to push through the caches. Comfortably past the
/// 128-entry caps, so every cache evicts many times over.
const _overrun = 400;

void main() {
  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('resqlite_stmt_cap_');
    db = await Database.open('${tempDir.path}/test.db');
    await db.execute('''
      CREATE TABLE items(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        value REAL NOT NULL
      )
    ''');
    await db.executeBatch('INSERT INTO items(id, name, value) VALUES (?, ?, ?)', [
      for (var i = 0; i < _overrun; i++) [i, 'name_$i', i * 1.5],
    ]);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('every statement in an over-capacity cycle returns its own row', () async {
    // Each statement selects a different row by literal, so an entry served
    // from the wrong slot yields the wrong id rather than an error. Three
    // cycles: the first fills and overruns the caches, the next two run
    // entirely in the evicting steady state.
    for (var cycle = 0; cycle < 3; cycle++) {
      for (var i = 0; i < _overrun; i++) {
        final rows = await db.select('SELECT id, name FROM items WHERE id = $i');
        expect(rows, hasLength(1), reason: 'statement $i, cycle $cycle');
        expect(rows.single['id'], i, reason: 'statement $i, cycle $cycle');
        expect(rows.single['name'], 'name_$i');
      }
    }
  });

  test('projections stay attached to their own statement under eviction', () async {
    // Column count and names come from the Dart schema cache, keyed by the
    // same SQL text; rotating two shapes means a stale schema shows up as the
    // wrong columns on a result that is otherwise well-formed.
    for (var cycle = 0; cycle < 2; cycle++) {
      for (var i = 0; i < _overrun; i++) {
        if (i.isEven) {
          final rows = await db.select('SELECT id FROM items WHERE id = $i');
          expect(rows.single.keys, ['id'], reason: 'narrow $i, cycle $cycle');
        } else {
          final rows = await db.select(
            'SELECT id, name, value FROM items WHERE id = $i',
          );
          expect(
            rows.single.keys,
            ['id', 'name', 'value'],
            reason: 'wide $i, cycle $cycle',
          );
          expect(rows.single['value'], i * 1.5);
        }
      }
    }
  });

  test('parameters still bind to the right statement under eviction', () async {
    // The cached entry carries `param_count`. A wrong entry with a different
    // arity would either throw or bind into the wrong statement, so rotating
    // one- and two-parameter shapes past capacity gates that field too.
    for (var i = 0; i < _overrun; i++) {
      final one = await db.select(
        'SELECT id FROM items WHERE id = ? -- p$i',
        [i],
      );
      expect(one.single['id'], i);

      final two = await db.select(
        'SELECT id FROM items WHERE id >= ? AND id < ? -- p$i',
        [i, i + 1],
      );
      expect(two.single['id'], i);
    }
  });

  test('a stream still sees writes after the cache has churned', () async {
    // Read-table dependencies are captured during prepare and copied into the
    // cache entry; `resqlite_get_read_tables` serves them from the entry the
    // last acquire tagged. If eviction left that tag pointing at a recycled
    // slot, a stream would be registered against the wrong tables and would
    // silently stop updating.
    for (var i = 0; i < _overrun; i++) {
      await db.select('SELECT id FROM items WHERE id = $i');
    }

    final stream = db.stream('SELECT COUNT(*) AS n FROM items');
    final seen = <int>[];
    final sub = stream.listen((rows) => seen.add(rows.single['n'] as int));

    await _settle();
    expect(seen, isNotEmpty, reason: 'no initial emission');
    final before = seen.last;

    await db.execute('INSERT INTO items(id, name, value) VALUES (?, ?, ?)', [
      _overrun + 1,
      'fresh',
      1.0,
    ]);
    await _settle();

    expect(seen.last, before + 1, reason: 'stream missed the write');
    await sub.cancel();
  });

  test('the writer cache survives its own overrun', () async {
    // `stmt_cache_insert` is shared with the writer connection, which has its
    // own cache of the same capacity.
    for (var i = 0; i < _overrun; i++) {
      await db.execute('UPDATE items SET name = ? WHERE id = $i', ['w_$i']);
    }
    final rows = await db.select(
      'SELECT id, name FROM items WHERE id IN (0, ${_overrun ~/ 2}, ${_overrun - 1}) '
      'ORDER BY id',
    );
    expect(rows.map((r) => r['name']), [
      'w_0',
      'w_${_overrun ~/ 2}',
      'w_${_overrun - 1}',
    ]);
  });
}

/// Let stream invalidation and re-query microtasks drain.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
