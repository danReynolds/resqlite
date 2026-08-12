// [EXP-270](../experiments/270-read-result-cache.md): a `select()` answered
// from memory is only as good as the rule that decides when to forget it, and
// every failure of that rule is silent — the caller gets rows, just the wrong
// ones. So these tests check *refusals* at least as hard as hits: a query the
// cache must never hold, a write it must always notice, and the boundary where
// it is provably wrong.
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/read_cache.dart';
import 'package:test/test.dart';

Future<void> _seed(Database db) async {
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT, qty INTEGER)',
  );
  await db.execute('CREATE TABLE other(id INTEGER PRIMARY KEY, note TEXT)');
  await db.executeBatch('INSERT INTO items(id, name, qty) VALUES (?, ?, ?)', [
    for (var i = 1; i <= 40; i++) [i, 'name$i', i],
  ]);
  await db.execute('INSERT INTO other(id, note) VALUES (1, ?)', ['n']);
}

/// Run [sql] until the cache has had every chance to hold it: a statement is
/// described on its second sighting, so the third execution is the first that
/// can be a hit.
Future<int> _hitsOverThreeReads(
  Database db,
  String sql, [
  List<Object?> params = const [],
]) async {
  ReadCache.resetStats();
  await db.select(sql, params);
  await db.select(sql, params);
  final before = ReadCache.hits;
  await db.select(sql, params);
  return ReadCache.hits - before;
}

void main() {
  group('ReadCache (end to end)', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('read_cache_test_');
      db = await Database.open('${tempDir.path}/test.db');
      await _seed(db);
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
    });

    test('a repeated read is served without dispatching', () async {
      expect(
        await _hitsOverThreeReads(db, 'SELECT * FROM items WHERE id = ?', [7]),
        1,
      );
      final rows = await db.select('SELECT * FROM items WHERE id = ?', [7]);
      expect(rows.single['name'], 'name7');
    });

    test('a write to the read table is observed by the next read', () async {
      await _hitsOverThreeReads(db, 'SELECT * FROM items WHERE id = ?', [7]);

      await db.execute('UPDATE items SET name = ? WHERE id = ?', ['fresh', 7]);

      ReadCache.resetStats();
      final rows = await db.select('SELECT * FROM items WHERE id = ?', [7]);
      expect(rows.single['name'], 'fresh');
      expect(ReadCache.hits, 0, reason: 'the entry must not have survived');
    });

    test('a write to an unrelated table leaves the entry alone', () async {
      await _hitsOverThreeReads(db, 'SELECT * FROM items WHERE id = ?', [7]);

      await db.execute('UPDATE other SET note = ? WHERE id = 1', ['x']);

      ReadCache.resetStats();
      await db.select('SELECT * FROM items WHERE id = ?', [7]);
      expect(ReadCache.hits, 1);
    });

    test('read-your-writes holds for every write entry point', () async {
      const sql = 'SELECT qty FROM items WHERE id = ?';
      await _hitsOverThreeReads(db, sql, [7]);

      await db.execute('UPDATE items SET qty = 100 WHERE id = 7');
      expect((await db.select(sql, [7])).single['qty'], 100);

      await db.executeBatch('UPDATE items SET qty = ? WHERE id = ?', [
        [200, 7],
      ]);
      expect((await db.select(sql, [7])).single['qty'], 200);

      await db.transaction((tx) async {
        await tx.execute('UPDATE items SET qty = 300 WHERE id = 7');
      });
      expect((await db.select(sql, [7])).single['qty'], 300);
    });

    test('a rolled-back transaction does not disturb a cached read', () async {
      const sql = 'SELECT qty FROM items WHERE id = ?';
      await _hitsOverThreeReads(db, sql, [7]);

      await expectLater(
        db.transaction((tx) async {
          await tx.execute('UPDATE items SET qty = 999 WHERE id = 7');
          throw StateError('rollback');
        }),
        throwsA(isA<StateError>()),
      );

      expect((await db.select(sql, [7])).single['qty'], 7);
    });

    test('reads inside a transaction bypass the cache', () async {
      const sql = 'SELECT qty FROM items WHERE id = ?';
      await _hitsOverThreeReads(db, sql, [7]);

      await db.transaction((tx) async {
        await tx.execute('UPDATE items SET qty = 42 WHERE id = 7');
        // Uncommitted, so only the writer connection can see it. A cached
        // result served here would hide the transaction's own write from it.
        final rows = await tx.select(sql, [7]);
        expect(rows.single['qty'], 42);
      });
    });

    test('a non-deterministic function is never cached', () async {
      const sql = 'SELECT random() AS r FROM items WHERE id = ?';
      expect(await _hitsOverThreeReads(db, sql, [7]), 0);

      final a = await db.select(sql, [7]);
      final b = await db.select(sql, [7]);
      expect(a.single['r'], isNot(b.single['r']));
    });

    test('a statement with no table dependency is never cached', () async {
      // Nothing could ever invalidate it, so holding it would be a bet that the
      // value is constant — which for `SELECT 1` is true and for
      // `SELECT datetime('now')` is not. The cache does not try to tell them
      // apart.
      expect(await _hitsOverThreeReads(db, 'SELECT 1 AS one'), 0);
      expect(
        await _hitsOverThreeReads(db, "SELECT datetime('now') AS t"),
        0,
      );
    });

    test('an allowlisted deterministic function is cached', () async {
      expect(
        await _hitsOverThreeReads(
          db,
          'SELECT upper(name) AS u FROM items WHERE id = ?',
          [7],
        ),
        1,
      );
    });

    test('DDL retires the whole cache', () async {
      // `ALTER TABLE` fires no preupdate hook, so the write arrives with an
      // empty dirty set — indistinguishable from a write that changed nothing.
      await _hitsOverThreeReads(db, 'SELECT * FROM items WHERE id = ?', [7]);

      await db.execute('ALTER TABLE items ADD COLUMN extra TEXT');

      ReadCache.resetStats();
      await db.select('SELECT * FROM items WHERE id = ?', [7]);
      expect(ReadCache.hits, 0);
    });

    test('a write racing an in-flight read is not stored', () async {
      const sql = 'SELECT qty FROM items WHERE id = ?';
      await _hitsOverThreeReads(db, sql, [7]);
      await db.execute('UPDATE items SET qty = 1 WHERE id = 7');

      // Dispatch the read, then land a write before it returns. Whatever the
      // read observed, the result must not be retained as current.
      final inFlight = db.select(sql, [7]);
      await db.execute('UPDATE items SET qty = 2 WHERE id = 7');
      await inFlight;

      ReadCache.resetStats();
      expect((await db.select(sql, [7])).single['qty'], 2);
      expect(ReadCache.hits, 0);
    });

    test('a result past the retention cap retires its statement', () async {
      // 40 rows fits; the guard is the SQL that returns more than the cap.
      const sql = 'SELECT * FROM items';
      expect(await _hitsOverThreeReads(db, sql), 1);

      final big = 'SELECT * FROM items, items b, items c'; // 64,000 rows
      expect(await _hitsOverThreeReads(db, big), 0);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('entries are bounded', () async {
      const sql = 'SELECT * FROM items WHERE id = ?';
      await db.select(sql, [1]);
      for (var i = 1; i <= 40; i++) {
        await db.select(sql, [i]);
      }
      // 40 distinct parameter sets, cap 64 — all resident, none lost.
      ReadCache.resetStats();
      for (var i = 1; i <= 40; i++) {
        await db.select(sql, [i]);
      }
      expect(ReadCache.hits, 40);
    });

    test('a blob parameter misses rather than matching by value', () async {
      await db.execute('CREATE TABLE blobs(id INTEGER PRIMARY KEY, b BLOB)');
      await db.execute('INSERT INTO blobs(id, b) VALUES (1, ?)', [
        Uint8List.fromList([1, 2, 3]),
      ]);
      const sql = 'SELECT id FROM blobs WHERE b = ?';
      // Equal-but-distinct buffers hash by identity, so the second read cannot
      // reuse the first. Missing is the safe direction and this pins it.
      await db.select(sql, [Uint8List.fromList([1, 2, 3])]);
      await db.select(sql, [Uint8List.fromList([1, 2, 3])]);
      ReadCache.resetStats();
      final rows = await db.select(sql, [Uint8List.fromList([1, 2, 3])]);
      expect(rows.single['id'], 1);
      expect(ReadCache.hits, 0);
    });

    test('streams keep re-emitting alongside a cached read', () async {
      const sql = 'SELECT qty FROM items WHERE id = ?';
      await _hitsOverThreeReads(db, sql, [7]);

      final emissions = <int>[];
      final sub = db
          .stream(sql, [7])
          .listen((rows) => emissions.add(rows.single['qty']! as int));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.execute('UPDATE items SET qty = 77 WHERE id = 7');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(emissions, [7, 77]);
      expect((await db.select(sql, [7])).single['qty'], 77);
    });
  });

  group('ReadCache (unit)', () {
    ReadCacheDescription cacheable(List<String> tables) =>
        ReadCacheDescription.cacheable(tables);

    List<Map<String, Object?>> rows(int n) => [
      for (var i = 0; i < n; i++) <String, Object?>{'i': i},
    ];

    test('keys compare by SQL and parameter values', () {
      expect(
        ReadCacheKey('a', [1, 'x']),
        equals(ReadCacheKey('a', [1, 'x'])),
      );
      expect(
        ReadCacheKey('a', [1, 'x']).hashCode,
        equals(ReadCacheKey('a', [1, 'x']).hashCode),
      );
      expect(ReadCacheKey('a', [1]), isNot(equals(ReadCacheKey('a', [2]))));
      expect(ReadCacheKey('a', [1]), isNot(equals(ReadCacheKey('b', [1]))));
      expect(ReadCacheKey('a', [1]), isNot(equals(ReadCacheKey('a', [1, 1]))));
    });

    test('a version bump on any read table retires the entry', () {
      final cache = ReadCache();
      final description = cacheable(['items', 'tags']);
      final key = ReadCacheKey('sql', const []);
      cache.store(
        key,
        description,
        rows(1),
        cache.versionsOf(description),
        cache.epoch,
      );
      expect(cache.lookup(key), isNotNull);

      cache.onDependencyChanges(
        const TableDependenciesFixture(['tags']).value,
      );
      expect(cache.lookup(key), isNull);
      expect(cache.length, 0, reason: 'a stale entry is dropped on lookup');
    });

    test('an empty or unknown dirty set retires everything', () {
      for (final changes in [
        const TableDependenciesFixture([]).value,
        TableDependencies.unknown,
      ]) {
        final cache = ReadCache();
        final description = cacheable(['items']);
        final key = ReadCacheKey('sql', const []);
        cache.store(
          key,
          description,
          rows(1),
          cache.versionsOf(description),
          cache.epoch,
        );
        cache.onDependencyChanges(changes);
        expect(cache.lookup(key), isNull);
      }
    });

    test('an oversized result is refused and retires its SQL', () {
      final cache = ReadCache();
      final description = cacheable(['items']);
      final key = ReadCacheKey('sql', const []);
      cache.record(
        'sql',
        const TableDependenciesFixture(['items']).value,
        true,
      );
      expect(cache.describe('sql')!.cacheable, isTrue);

      cache.store(
        key,
        description,
        rows(maxCachedRows + 1),
        cache.versionsOf(description),
        cache.epoch,
      );
      expect(cache.lookup(key), isNull);
      expect(cache.describe('sql')!.cacheable, isFalse);
    });

    test('unreliable or empty dependencies are refused', () {
      final cache = ReadCache();
      expect(
        cache.record('a', TableDependencies.unknown, true).cacheable,
        isFalse,
      );
      expect(
        cache.record('b', TableDependencies.none, true).cacheable,
        isFalse,
      );
      expect(
        cache
            .record('c', const TableDependenciesFixture(['t']).value, false)
            .cacheable,
        isFalse,
      );
      expect(
        cache
            .record('d', const TableDependenciesFixture(['t']).value, true)
            .cacheable,
        isTrue,
      );
    });

    test('descriptions are bounded', () {
      final cache = ReadCache();
      for (var i = 0; i < readCacheMaxDescriptions + 20; i++) {
        cache.record(
          'sql$i',
          const TableDependenciesFixture(['t']).value,
          true,
        );
      }
      expect(cache.describe('sql0'), isNull);
      expect(
        cache.describe('sql${readCacheMaxDescriptions + 19}'),
        isNotNull,
      );
    });

    test('entries are bounded', () {
      final cache = ReadCache();
      final description = cacheable(['items']);
      for (var i = 0; i < readCacheMaxEntries + 10; i++) {
        cache.store(
          ReadCacheKey('sql', [i]),
          description,
          rows(1),
          cache.versionsOf(description),
          cache.epoch,
        );
      }
      expect(cache.length, lessThanOrEqualTo(readCacheMaxEntries));
      expect(cache.lookup(ReadCacheKey('sql', [0])), isNull);
    });
  });
}

/// Builds a plain table-level [TableDependencies] without repeating the
/// three-type construction in every unit test.
final class TableDependenciesFixture {
  const TableDependenciesFixture(this.tables);

  final List<String> tables;

  TableDependencies get value =>
      TableDependencies.fixed([for (final t in tables) TableDependency(t)]);
}
