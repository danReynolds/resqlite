/// Named-parameter coverage for `Database.select`, `Database.execute`,
/// `Database.executeBatch`, `Database.transaction` (both `tx.execute` /
/// `tx.select`), `Database.stream`, and `Database.selectBytes`.
///
/// SQLite supports four placeholder syntaxes for named binds:
///
///   * `:name`
///   * `@name`
///   * `$name`
///   * `?NNN` (numbered positional, indexed-but-named at the C API)
///
/// All four forms resolve through `sqlite3_bind_parameter_index` on the
/// C side, so `Map<String, Object?>` whose keys exactly match those
/// placeholder strings work identically.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  group('Named parameters', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_named_');
      db = await Database.open('${tempDir.path}/test.db');
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, value REAL, '
        'data BLOB)',
      );
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

    // ---------------------------------------------------------------------
    // Placeholder syntaxes
    // ---------------------------------------------------------------------

    test('execute with `:name` placeholders', () async {
      final result = await db.execute(
        'INSERT INTO t(name, value) VALUES (:name, :value)',
        {':name': 'Ada', ':value': 1.5},
      );
      expect(result.affectedRows, 1);

      final rows = await db.select(
        'SELECT name, value FROM t WHERE name = :n',
        {':n': 'Ada'},
      );
      expect(rows, [
        {'name': 'Ada', 'value': 1.5},
      ]);
    });

    test('execute with `@name` placeholders', () async {
      final result = await db.execute(
        'INSERT INTO t(name, value) VALUES (@name, @value)',
        {'@name': 'Grace', '@value': 2.5},
      );
      expect(result.affectedRows, 1);

      final rows = await db.select(
        'SELECT name, value FROM t WHERE name = @n',
        {'@n': 'Grace'},
      );
      expect(rows, [
        {'name': 'Grace', 'value': 2.5},
      ]);
    });

    test(r'execute with `$name` placeholders', () async {
      final result = await db.execute(
        r'INSERT INTO t(name, value) VALUES ($name, $value)',
        {r'$name': 'Sonja', r'$value': 3.0},
      );
      expect(result.affectedRows, 1);

      final rows = await db.select(
        r'SELECT name, value FROM t WHERE name = $n',
        {r'$n': 'Sonja'},
      );
      expect(rows, [
        {'name': 'Sonja', 'value': 3.0},
      ]);
    });

    test('execute with `?NNN` placeholders', () async {
      // `?NNN` is indexed, but SQLite still exposes a name through
      // `sqlite3_bind_parameter_name` ('?1' for the first slot, etc.).
      // The C-side `bind_parameter_index` accepts those names, so the
      // map form works.
      final result = await db.execute(
        'INSERT INTO t(name, value) VALUES (?1, ?2)',
        {'?1': 'Linus', '?2': 4.0},
      );
      expect(result.affectedRows, 1);
    });

    test(r'mixed `:`, `@`, `$` placeholders in the same SQL', () async {
      await db.execute(
        r'INSERT INTO t(id, name, value) VALUES (:id, @name, $value)',
        {':id': 100, '@name': 'mixed', r'$value': 9.99},
      );
      final rows = await db.select(
        'SELECT id, name, value FROM t WHERE id = :id',
        {':id': 100},
      );
      expect(rows, [
        {'id': 100, 'name': 'mixed', 'value': 9.99},
      ]);
    });

    // ---------------------------------------------------------------------
    // Mixed value types
    // ---------------------------------------------------------------------

    test('all SQLite types via named binds (int, double, text, blob, null)',
        () async {
      final blob = Uint8List.fromList([1, 2, 3, 4, 5]);
      await db.execute(
        'INSERT INTO t(id, name, value, data) '
        'VALUES (:id, :name, :value, :data)',
        {':id': 1, ':name': 'first', ':value': 1.25, ':data': blob},
      );
      await db.execute(
        'INSERT INTO t(id, name, value, data) '
        'VALUES (:id, :name, :value, :data)',
        {':id': 2, ':name': null, ':value': null, ':data': null},
      );

      final rows = await db.select('SELECT * FROM t ORDER BY id');
      expect(rows.length, 2);
      expect(rows[0]['id'], 1);
      expect(rows[0]['name'], 'first');
      expect(rows[0]['value'], 1.25);
      expect(rows[0]['data'], blob);
      expect(rows[1]['name'], isNull);
      expect(rows[1]['value'], isNull);
      expect(rows[1]['data'], isNull);
    });

    test('unicode parameter values', () async {
      const samples = ['日本語', 'café', 'emoji-🌟', 'umlaut-ä'];
      for (var i = 0; i < samples.length; i++) {
        await db.execute(
          'INSERT INTO t(id, name) VALUES (:id, :name)',
          {':id': i, ':name': samples[i]},
        );
      }
      final rows = await db.select('SELECT name FROM t ORDER BY id');
      expect(
        rows.map((r) => r['name']).toList(),
        samples,
      );
    });

    test('empty string and zero-length blob via named binds', () async {
      await db.execute(
        'INSERT INTO t(id, name, data) VALUES (:id, :name, :data)',
        {':id': 1, ':name': '', ':data': Uint8List(0)},
      );
      final rows = await db.select('SELECT name, data FROM t');
      expect(rows.first['name'], '');
      expect(rows.first['data'], isA<Uint8List>());
      expect((rows.first['data'] as Uint8List).length, 0);
    });

    // ---------------------------------------------------------------------
    // Iteration order independence
    // ---------------------------------------------------------------------

    test('map insertion order does not have to match SQL parameter order',
        () async {
      // The SQL uses `:value` first, then `:name`, but the map binds in the
      // opposite order. SQLite resolves by name, not position.
      await db.execute(
        'INSERT INTO t(value, name) VALUES (:value, :name)',
        {':name': 'order-test', ':value': 7.0},
      );
      final rows = await db.select('SELECT name, value FROM t');
      expect(rows.first['name'], 'order-test');
      expect(rows.first['value'], 7.0);
    });

    // ---------------------------------------------------------------------
    // Reuse in the same Database instance across positional and named
    // ---------------------------------------------------------------------

    test('positional and named on same SQL coexist via stmt cache', () async {
      // First call: positional. Caches the prepared stmt.
      await db.execute(
        'INSERT INTO t(name, value) VALUES (?, ?)',
        ['pos', 1.0],
      );
      // Second call to the same SQL: positional again.
      await db.execute(
        'INSERT INTO t(name, value) VALUES (?, ?)',
        ['pos2', 2.0],
      );

      // Different SQL with named placeholders — different cache entry.
      await db.execute(
        'INSERT INTO t(name, value) VALUES (:n, :v)',
        {':n': 'named', ':v': 3.0},
      );

      // Mixing back: positional version still works after named call.
      await db.execute(
        'INSERT INTO t(name, value) VALUES (?, ?)',
        ['pos3', 4.0],
      );

      final rows = await db.select('SELECT name FROM t ORDER BY name');
      expect(
        rows.map((r) => r['name']).toList(),
        ['named', 'pos', 'pos2', 'pos3'],
      );
    });

    // ---------------------------------------------------------------------
    // Error cases
    // ---------------------------------------------------------------------

    test('unknown named parameter throws', () async {
      expect(
        () => db.execute(
          'INSERT INTO t(name) VALUES (:name)',
          {':bogus': 'x'},
        ),
        throwsA(isA<ResqliteQueryException>()),
      );
    });

    test('missing named parameter throws', () async {
      expect(
        () => db.execute(
          'INSERT INTO t(name, value) VALUES (:name, :value)',
          {':name': 'only-one'},
        ),
        throwsA(isA<ResqliteQueryException>()),
      );
    });

    test('extra named parameter throws', () async {
      expect(
        () => db.execute(
          'INSERT INTO t(name) VALUES (:name)',
          {':name': 'a', ':extra': 'b'},
        ),
        throwsA(isA<ResqliteQueryException>()),
      );
    });

    test('non-list, non-map parameters throw ArgumentError', () async {
      expect(
        () => db.execute('SELECT 1', 'not a list or map'),
        throwsA(isA<ArgumentError>()),
      );
    });

    // ---------------------------------------------------------------------
    // Long names + edge characters
    // ---------------------------------------------------------------------

    test('very long parameter name (over the on-stack threshold)', () async {
      // Long enough to overflow the 64-byte stack buffer the C-side
      // bind_params_named uses. SQLite's max identifier is 255-ish but
      // this works as long as the placeholder text matches.
      final longName = ':${'x' * 200}';
      await db.execute(
        'INSERT INTO t(name) VALUES ($longName)',
        {longName: 'long-name-value'},
      );
      final rows = await db.select('SELECT name FROM t');
      expect(rows.first['name'], 'long-name-value');
    });

    test('parameter name containing digits and underscores', () async {
      await db.execute(
        'INSERT INTO t(id, name) VALUES (:id_1, :user_name_2)',
        {':id_1': 42, ':user_name_2': 'underscores'},
      );
      final rows = await db.select('SELECT id, name FROM t');
      expect(rows.first['id'], 42);
      expect(rows.first['name'], 'underscores');
    });

    // ---------------------------------------------------------------------
    // executeBatch with named rows
    // ---------------------------------------------------------------------

    test('executeBatch with named rows', () async {
      await db.executeBatch(
        'INSERT INTO t(name, value) VALUES (:name, :value)',
        [
          {':name': 'a', ':value': 1.0},
          {':name': 'b', ':value': 2.0},
          {':name': 'c', ':value': 3.0},
        ],
      );
      final rows = await db.select('SELECT name, value FROM t ORDER BY name');
      expect(rows.length, 3);
      expect(rows[0], {'name': 'a', 'value': 1.0});
      expect(rows[1], {'name': 'b', 'value': 2.0});
      expect(rows[2], {'name': 'c', 'value': 3.0});
    });

    test('executeBatch named: every row must share the same key set',
        () async {
      expect(
        () => db.executeBatch(
          'INSERT INTO t(name, value) VALUES (:name, :value)',
          [
            {':name': 'a', ':value': 1.0},
            // Missing ':value' key.
            {':name': 'b'},
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('executeBatch rejects mixing positional and named rows', () async {
      expect(
        () => db.executeBatch(
          'INSERT INTO t(name, value) VALUES (?, ?)',
          [
            ['a', 1.0],
            {':name': 'b', ':value': 2.0},
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('executeBatch with named rows and mixed types per row', () async {
      final blob = Uint8List.fromList([7, 8, 9]);
      await db.executeBatch(
        'INSERT INTO t(id, name, value, data) '
        'VALUES (:id, :name, :value, :data)',
        [
          {':id': 1, ':name': 'a', ':value': 1.5, ':data': blob},
          {':id': 2, ':name': null, ':value': null, ':data': null},
          {':id': 3, ':name': 'c', ':value': 0.0, ':data': Uint8List(0)},
        ],
      );
      final rows = await db.select('SELECT * FROM t ORDER BY id');
      expect(rows[0]['data'], blob);
      expect(rows[1]['name'], isNull);
      expect(rows[2]['data'], isA<Uint8List>());
    });

    // ---------------------------------------------------------------------
    // Inside Database.transaction
    // ---------------------------------------------------------------------

    test('named params inside transaction body', () async {
      await db.transaction((tx) async {
        await tx.execute(
          'INSERT INTO t(name) VALUES (:n)',
          {':n': 'tx1'},
        );
        // Reads inside the transaction see uncommitted writes.
        final rows = await tx.select(
          'SELECT name FROM t WHERE name = :n',
          {':n': 'tx1'},
        );
        expect(rows, [
          {'name': 'tx1'},
        ]);
      });
      final rows = await db.select('SELECT name FROM t');
      expect(rows, [
        {'name': 'tx1'},
      ]);
    });

    test('named params via tx.executeBatch (nested batch)', () async {
      await db.transaction((tx) async {
        await tx.executeBatch(
          'INSERT INTO t(name, value) VALUES (:n, :v)',
          [
            {':n': 'a', ':v': 1.0},
            {':n': 'b', ':v': 2.0},
          ],
        );
      });
      final rows = await db.select('SELECT name FROM t ORDER BY name');
      expect(rows.length, 2);
    });

    // ---------------------------------------------------------------------
    // Inside Database.stream — exercises the authorizer + dependency path
    // ---------------------------------------------------------------------

    test('stream emits initial result for named params', () async {
      await db.execute('INSERT INTO t(name, value) VALUES (?, ?)',
          ['stream-1', 1.0]);

      final stream = db.stream(
        'SELECT name FROM t WHERE name = :n',
        {':n': 'stream-1'},
      );
      final first = await stream.first;
      expect(first, [
        {'name': 'stream-1'},
      ]);
    });

    test('stream re-emits when watched table changes (named params)',
        () async {
      final results = <List<Map<String, Object?>>>[];
      final completer = Completer<void>();

      final sub = db
          .stream(
            'SELECT name FROM t WHERE value > :min ORDER BY name',
            {':min': 0.0},
          )
          .listen((rows) {
        results.add(rows);
        if (results.length == 2) completer.complete();
      });

      // Wait for first emission.
      while (results.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(results.first, isEmpty);

      // A write that affects the watched table re-emits.
      await db.execute(
        'INSERT INTO t(name, value) VALUES (:n, :v)',
        {':n': 'fresh', ':v': 2.0},
      );

      await completer.future.timeout(const Duration(seconds: 5));
      expect(results.last, [
        {'name': 'fresh'},
      ]);

      await sub.cancel();
    });

    // ---------------------------------------------------------------------
    // Stream key dedup — same SQL + same named map (any order) shares stream
    // ---------------------------------------------------------------------

    test('two streams with equal SQL and equal named map share an entry',
        () async {
      // Both maps have the same key/value pairs, just inserted in
      // different orders.
      final s1 = db.stream(
        'SELECT * FROM t WHERE id = :id AND name = :n',
        {':id': 1, ':n': 'x'},
      );
      final s2 = db.stream(
        'SELECT * FROM t WHERE id = :id AND name = :n',
        {':n': 'x', ':id': 1},
      );
      // Both subscribers attach to the same StreamEntry; engine length
      // stays at 1.
      final sub1 = s1.listen((_) {});
      final sub2 = s2.listen((_) {});
      // Wait one microtask for registration.
      await Future<void>.delayed(Duration.zero);
      expect(db.streamEngine.length, 1);
      await sub1.cancel();
      await sub2.cancel();
    });

    // ---------------------------------------------------------------------
    // selectBytes still positional-only? It now accepts both. Sanity check.
    // ---------------------------------------------------------------------

    test('selectBytes with named params', () async {
      await db.execute(
        'INSERT INTO t(name) VALUES (:n)',
        {':n': 'json-row'},
      );
      final bytes = await db.selectBytes(
        'SELECT name FROM t WHERE name = :n',
        {':n': 'json-row'},
      );
      expect(bytes, isNotEmpty);
      // The bytes are JSON; just verify they reference the value.
      expect(String.fromCharCodes(bytes), contains('json-row'));
    });
  });
}
