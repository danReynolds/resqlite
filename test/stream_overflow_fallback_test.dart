// Black-box correctness tests for the column / read / dirty set
// overflow fallbacks introduced in the exp-106 polish.
//
// These prove end-to-end correctness under the failure modes the
// reliability flags target. A stream that overflows the C-side caps
// must still re-emit when its data changes — the polish trades a perf
// optimization (column elision) for guaranteed correctness when the
// optimization can't be applied.
//
// Caps under test (must match `RESQLITE_MAX_DEP_COLUMNS`,
// `RESQLITE_MAX_READ_TABLES`, `RESQLITE_MAX_DIRTY_TABLES` in C):
//   * RESQLITE_MAX_DEP_COLUMNS    = 64
//   * RESQLITE_MAX_READ_TABLES    = 64
//   * RESQLITE_MAX_DIRTY_TABLES   = 64
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

const int _capReadTables = 64;
const int _capDirtyTables = 64;

final class _EventWaiter<T> {
  _EventWaiter(this.count, this.completer);

  final int count;
  final Completer<T> completer;
}

final class _StreamProbe<T> {
  _StreamProbe(Stream<T> stream) {
    _subscription = stream.listen((event) {
      _events.add(event);
      final ready = _waiters.where((w) => w.count <= _events.length);
      for (final w in ready.toList()) {
        _waiters.remove(w);
        if (!w.completer.isCompleted) {
          w.completer.complete(_events[w.count - 1]);
        }
      }
    });
  }

  final _events = <T>[];
  final _waiters = <_EventWaiter<T>>[];
  late final StreamSubscription<T> _subscription;

  Future<T> event(int count, {Duration timeout = const Duration(seconds: 4)}) {
    if (_events.length >= count) {
      return Future.value(_events[count - 1]);
    }
    final completer = Completer<T>();
    final waiter = _EventWaiter<T>(count, completer);
    _waiters.add(waiter);
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(waiter);
        throw TimeoutException('Timed out waiting for event $count');
      },
    );
  }

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  group('Reliability fallback under overflow', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'resqlite_stream_overflow_',
      );
      db = await Database.open('${tempDir.path}/test.db');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } on PathNotFoundException {
          // ignore
        }
      }
    });

    test(
      'wide-table SELECT * with > RESQLITE_MAX_DEP_COLUMNS columns re-emits on write to any column',
      () async {
        // 70 columns — strictly more than the 64-column read-column cap.
        const colCount = 70;
        final cols = List.generate(colCount, (i) => 'c$i').join(', ');
        final colDefs = List.generate(
          colCount,
          (i) => 'c$i INTEGER',
        ).join(', ');
        await db.execute('CREATE TABLE wide(id INTEGER PRIMARY KEY, $colDefs)');
        final placeholders = List.generate(colCount, (_) => '?').join(', ');
        final initialValues = [1, ...List.generate(colCount, (i) => i)];
        await db.execute(
          'INSERT INTO wide(id, $cols) VALUES (?, $placeholders)',
          initialValues,
        );

        final probe = _StreamProbe(
          db.stream('SELECT * FROM wide WHERE id = 1'),
        );
        final initial = await probe.event(1);
        expect(initial, hasLength(1));
        // SELECT * captures every column → overflows the 64-cap.
        // Writer's UPDATE on a column past the cap must still re-emit.
        await db.execute('UPDATE wide SET c69 = ? WHERE id = ?', [9999, 1]);
        final after = await probe.event(2);
        expect(after[0]['c69'], 9999);

        await probe.cancel();
      },
    );

    test(
      'single UPDATE statement writing > RESQLITE_MAX_DEP_COLUMNS columns invalidates downstream stream',
      () async {
        // Writer-side overflow: a stmt that SETs more than 64 columns
        // makes its `dep_columns` set unreliable. The preupdate hook
        // then propagates `dep_columns_reliable = 0` into
        // `dirty_columns.reliable = 0`, so no column detail is attached —
        // every stream that watches the table re-emits via
        // table-only fallback.
        //
        // The stream watches a column past the writer's 64-column cap
        // so without the polish the column-intersection check would
        // see an empty intersection (reader column past cap, writer's
        // dirty list truncated to first 64) and silently elide
        // dispatch — that's the bug being fixed.
        const colCount = 70;
        const watchedColumn = 'c69';
        final cols = List.generate(colCount, (i) => 'c$i').join(', ');
        final colDefs = List.generate(
          colCount,
          (i) => 'c$i INTEGER',
        ).join(', ');
        await db.execute('CREATE TABLE wide(id INTEGER PRIMARY KEY, $colDefs)');
        final placeholders = List.generate(colCount, (_) => '?').join(', ');
        await db.execute(
          'INSERT INTO wide(id, $cols) VALUES (?, $placeholders)',
          [1, ...List.generate(colCount, (i) => 0)],
        );

        final probe = _StreamProbe(
          db.stream('SELECT id, $watchedColumn FROM wide WHERE id = 1'),
        );
        await probe.event(1);

        // Build an UPDATE that writes 70 columns — overflows the 64-cap
        // for the writer's dep_columns scratch.
        final setClause = List.generate(colCount, (i) => 'c$i = ?').join(', ');
        await db.execute(
          'UPDATE wide SET $setClause WHERE id = 1',
          List.generate(colCount, (i) => 1),
        );
        final after = await probe.event(2);
        expect(after[0][watchedColumn], 1);

        await probe.cancel();
      },
    );

    test(
      'stream watching > RESQLITE_MAX_READ_TABLES tables re-emits on a write to any of them',
      () async {
        // Build N+1 tables and a CTE that joins them all so the read_set
        // overflows the 64-table cap.
        const tableCount = _capReadTables + 5; // 69
        for (var i = 0; i < tableCount; i++) {
          await db.execute(
            'CREATE TABLE t$i(id INTEGER PRIMARY KEY, value INTEGER)',
          );
          await db.execute('INSERT INTO t$i(id, value) VALUES (?, ?)', [1, i]);
        }

        // UNION ALL across all N+1 tables — the authorizer fires
        // SQLITE_READ for every one, blowing the read_set cap.
        final unionParts = List.generate(
          tableCount,
          (i) => 'SELECT id, value, $i AS src FROM t$i',
        );
        final sql = '${unionParts.join(' UNION ALL ')} ORDER BY src';
        final probe = _StreamProbe(db.stream(sql));
        final initial = await probe.event(1);
        expect(initial, hasLength(tableCount));

        // Write to a table well past the cap — would have been silently
        // dropped without the polish (read_set capped at 64 missed
        // tables 64..68).
        await db.execute('UPDATE t68 SET value = ? WHERE id = 1', [4242]);
        final after = await probe.event(2);
        // The row from t68 should have the new value.
        final t68row = after.firstWhere((r) => r['src'] == 68);
        expect(t68row['value'], 4242);

        await probe.cancel();
      },
    );

    test(
      'transaction with > RESQLITE_MAX_DIRTY_TABLES dirty tables invalidates streams on each',
      () async {
        // Stream watches d68 — a table dirtied AFTER the cap is exceeded.
        // A pre-polish implementation that simply kept the first 64 dirty
        // tables would NOT include d68 in getDirtyTables, so the stream
        // would not invalidate and this test would fail. The polish flips
        // dirty_set.reliable to 0 when the cap is exceeded, getDirtyTables
        // returns RESQLITE_DEPENDENCY_COUNT_UNKNOWN, and StreamEngine
        // invalidates everything (including our stream watching d68).
        // Choosing a post-overflow table is what
        // makes this test exercise the unreliable-dirty-set fallback
        // rather than the lucky truncation case.
        //
        // Build N+5 separate tables.
        const dirtyTableCount = _capDirtyTables + 5; // 69
        for (var i = 0; i < dirtyTableCount; i++) {
          await db.execute('CREATE TABLE d$i(id INTEGER PRIMARY KEY)');
        }

        // Watch d68 — past the dirty-set cap of 64.
        final probe = _StreamProbe(db.stream('SELECT id FROM d68 ORDER BY id'));
        await probe.event(1);

        await db.transaction((tx) async {
          // Dirty d0..d68 in order. d0..d63 fill dirty_set; the insert to
          // d64 trips overflow → reliable = 0. Inserts to d64..d68 still
          // happen (the table writes go through), but their presence in
          // dirty_set is no longer required — the unreliable flag forces
          // invalidate-all on the Dart side.
          for (var i = 0; i < dirtyTableCount; i++) {
            await tx.execute('INSERT INTO d$i(id) VALUES (?)', [1]);
          }
        });

        final after = await probe.event(2);
        expect(after, hasLength(1));
        expect(after[0]['id'], 1);

        await probe.cancel();
      },
    );
  });
}
