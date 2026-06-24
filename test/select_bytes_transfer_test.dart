import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

/// Pins the exp 174 behavior: `selectBytes` transfers the reader's native
/// `json_buf` as a view and never takes the "sacrifice" (Isolate.exit +
/// respawn) path, regardless of result size. The view must survive the
/// SendPort copy intact at every size, and the reader must stay usable for
/// repeated large byte queries (no respawn).
void main() {
  group('selectBytes transfer (exp 174)', () {
    late Directory tempDir;
    late Database db;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('resqlite_bytes_xfer_');
      db = await Database.open('${tempDir.path}/t.db');
      await db.execute(
        'CREATE TABLE t(id INTEGER PRIMARY KEY, body TEXT, n INTEGER)',
      );
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> seed(int rows, int bodyLen) async {
      final body = 'x' * bodyLen;
      await db.executeBatch(
        'INSERT INTO t(id, body, n) VALUES (?, ?, ?)',
        [for (var i = 0; i < rows; i++) [i, '$body-$i', i * 3]],
      );
    }

    test('small result (<256KB) round-trips and matches select()', () async {
      await seed(1000, 40);
      final result = await db.selectBytes('SELECT id, body, n FROM t ORDER BY id');
      expect(result.bytes.length, lessThan(256 * 1024));
      expect(result.rowCount, 1000);
      final decoded = jsonDecode(utf8.decode(result.bytes)) as List;
      expect(decoded, hasLength(1000));
      expect((decoded.first as Map)['id'], 0);
      final rows = await db.select('SELECT id, body, n FROM t ORDER BY id');
      expect((decoded[500] as Map)['body'], rows[500]['body']);
    });

    test('large result (>256KB, formerly sacrificed) is intact', () async {
      await seed(2000, 300);
      final result = await db.selectBytes('SELECT id, body, n FROM t ORDER BY id');
      expect(result.bytes.length, greaterThan(256 * 1024));
      expect(result.rowCount, 2000);
      final decoded = jsonDecode(utf8.decode(result.bytes)) as List;
      expect(decoded, hasLength(2000));
      expect((decoded.first as Map)['id'], 0);
      expect((decoded[1000] as Map)['body'], 'x' * 300 + '-1000');
      expect((decoded.last as Map)['n'], 1999 * 3);
      // cross-check against the rows API
      final rows = await db.select('SELECT id, body, n FROM t ORDER BY id');
      expect((decoded[1500] as Map)['body'], rows[1500]['body']);
    });

    test('reader survives repeated large byte queries (no respawn needed)',
        () async {
      await seed(2000, 300);
      const sql = 'SELECT id, body, n FROM t ORDER BY id';
      for (var i = 0; i < 10; i++) {
        final result = await db.selectBytes(sql);
        expect(result.bytes.length, greaterThan(256 * 1024));
        expect(result.rowCount, 2000);
        expect((jsonDecode(utf8.decode(result.bytes)) as List), hasLength(2000));
      }
      // interleave concurrent large byte reads — exercises every pooled reader
      final all = await Future.wait([for (var i = 0; i < 8; i++) db.selectBytes(sql)]);
      for (final r in all) {
        expect(r.rowCount, 2000);
        expect((jsonDecode(utf8.decode(r.bytes)) as List), hasLength(2000));
      }
    });

    test('empty result is a valid empty JSON array', () async {
      final result = await db.selectBytes('SELECT id, body, n FROM t WHERE id < 0');
      expect(jsonDecode(utf8.decode(result.bytes)), isEmpty);
      expect(result.rowCount, 0);
    });
  });
}
