// Cache-hit preservation tests for exp-106 polish.
//
// The C-side cache stores `read_tables_reliable` and
// `dep_columns_reliable` flags on each cached stmt entry. On cache
// hit, the FFI getter must serve the flag from the entry — not
// "recover" reliability by reading the freshly-reset scratch set
// (which would always be reliable on a cache-hit prepare because
// authorizer doesn't fire again). Without this preservation, a stream
// whose initial prepare overflowed would correctly land in the
// all-tables bucket, but a subsequent stream over the same SQL would
// mistakenly land in `_tableIndex` with a partial dep set →
// silent stuck stream on writes to the dropped tables.
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

const int _capColumns = 64;
const int _capReadTables = 64;

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
  group('Cache-hit reliability preservation', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp
          .createTemp('resqlite_cache_hit_reliability_');
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
      'second stream over wide-table SELECT * sees the same column-overflow fallback',
      () async {
        // First stream prepares the SELECT — read_columns overflows, cache
        // entry stores `dep_columns_reliable = 0`. We tear that stream
        // down so its query sits in the cache. A second stream over the
        // exact same SQL must hit the cache and inherit the unreliable
        // flag — without it, the second stream would land with a
        // partial column dep set (truncated to 64) and silently stick
        // when col 69 changes.
        const colCount = 70;
        final cols = List.generate(colCount, (i) => 'c$i').join(', ');
        final colDefs = List.generate(colCount, (i) => 'c$i INTEGER').join(', ');
        await db.execute('CREATE TABLE wide(id INTEGER PRIMARY KEY, $colDefs)');
        final placeholders = List.generate(colCount, (_) => '?').join(', ');
        await db.execute(
          'INSERT INTO wide(id, $cols) VALUES (?, $placeholders)',
          [1, ...List.generate(colCount, (i) => 0)],
        );

        const sql = 'SELECT * FROM wide WHERE id = 1';

        // First subscription: forces prepare → cache entry created with
        // overflow. Cancel before the second subscription so the cache
        // entry is the only handle to the prepared stmt.
        final first = _StreamProbe(db.stream(sql));
        await first.event(1);
        await first.cancel();

        // Wait for cancellation to propagate. The second subscription
        // should observe a cache hit on the same SQL.
        await Future.delayed(const Duration(milliseconds: 50));

        // Second subscription: must see the SAME overflow fallback.
        final second = _StreamProbe(db.stream(sql));
        await second.event(1);

        await db.execute(
          'UPDATE wide SET c69 = ? WHERE id = ?',
          [9999, 1],
        );
        // If the cache hit had silently reset reliability, this would
        // never re-emit. With preserved reliability, the second stream
        // is also in the all-tables bucket and re-emits.
        final after = await second.event(2);
        expect(after[0]['c69'], 9999);

        await second.cancel();
      },
    );

    test(
      'second stream over wide-join sees the same read-table overflow fallback',
      () async {
        // Mirror of the read_tables_reliable cache-hit test: the first
        // prepare overflows the read_set; the second prepare must hit
        // the cache and inherit -1 from getReadTables.
        const tableCount = _capReadTables + 5; // 69
        for (var i = 0; i < tableCount; i++) {
          await db.execute(
            'CREATE TABLE wt$i(id INTEGER PRIMARY KEY, value INTEGER)',
          );
          await db.execute(
            'INSERT INTO wt$i(id, value) VALUES (?, ?)',
            [1, i],
          );
        }
        final unionParts = List.generate(
          tableCount,
          (i) => 'SELECT id, value, $i AS src FROM wt$i',
        );
        final sql = '${unionParts.join(' UNION ALL ')} ORDER BY src';

        final first = _StreamProbe(db.stream(sql));
        await first.event(1);
        await first.cancel();
        await Future.delayed(const Duration(milliseconds: 50));

        final second = _StreamProbe(db.stream(sql));
        await second.event(1);

        // Write to a table past the cap; cache hit must preserve the
        // unreliable read_tables flag so the stream is in the
        // all-tables bucket.
        await db.execute(
          'UPDATE wt68 SET value = ? WHERE id = 1',
          [12345],
        );
        final after = await second.event(2);
        final t68row = after.firstWhere((r) => r['src'] == 68);
        expect(t68row['value'], 12345);

        await second.cancel();
      },
    );

    test(
      'a non-overflowing stream stays in the table index even after the cache fills with overflow entries',
      () async {
        // Sanity: the unreliable flag is per-cache-entry, not global.
        // A small SELECT prepared after a wide one keeps its precise
        // column dep set.
        await db.execute(
          'CREATE TABLE small(id INTEGER PRIMARY KEY, value INTEGER)',
        );
        await db.execute(
          'INSERT INTO small(id, value) VALUES (?, ?)',
          [1, 100],
        );
        // Prepare an overflowing stream first to seed the cache.
        const colCount = 70;
        final cols = List.generate(colCount, (i) => 'c$i').join(', ');
        final colDefs = List.generate(colCount, (i) => 'c$i INTEGER').join(', ');
        await db.execute('CREATE TABLE wide2(id INTEGER PRIMARY KEY, $colDefs)');
        final placeholders = List.generate(colCount, (_) => '?').join(', ');
        await db.execute(
          'INSERT INTO wide2(id, $cols) VALUES (?, $placeholders)',
          [1, ...List.generate(colCount, (i) => 0)],
        );
        final overflow = _StreamProbe(
          db.stream('SELECT * FROM wide2 WHERE id = 1'),
        );
        await overflow.event(1);
        await overflow.cancel();
        await Future.delayed(const Duration(milliseconds: 50));

        // Small stream: precise column tracking. A write to a different
        // (unrelated) table must NOT invalidate it.
        await db.execute(
          'CREATE TABLE other(id INTEGER PRIMARY KEY, name TEXT)',
        );
        final probe = _StreamProbe(
          db.stream('SELECT id, value FROM small WHERE id = 1'),
        );
        await probe.event(1);
        // Unrelated table write — should NOT trigger a re-emit.
        await db.execute('INSERT INTO other(id, name) VALUES (?, ?)', [1, 'x']);
        try {
          await probe.event(
            2,
            timeout: const Duration(milliseconds: 200),
          );
          fail(
            'Stream over reliable small SELECT should not re-emit on unrelated writes',
          );
        } on TimeoutException {
          // Expected — column elision works for the reliable stream.
        }

        // Sanity: a relevant write does re-emit.
        await db.execute(
          'UPDATE small SET value = ? WHERE id = 1',
          [200],
        );
        final after = await probe.event(2);
        expect(after[0]['value'], 200);
        await probe.cancel();
      },
    );
  });
}
