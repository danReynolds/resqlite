import 'package:resqlite/src/writer/batch_insert_chunker.dart';
import 'package:test/test.dart';

void main() {
  group('chunkSimpleInsertBatch', () {
    test('plans full chunks and small non-divisible tail without copying', () {
      const sql = 'INSERT INTO items(id, name) VALUES (?, ?)';
      final plan = chunkSimpleInsertBatch(sql, _rows(2001))!;

      expect(plan.segments, hasLength(2));

      final full = plan.segments[0];
      expect(full.rowsPerStep, 100);
      expect(full.paramSets, hasLength(20));
      expect(full.paramSets.first, hasLength(200));
      expect(full.paramSets.first[0], 0);
      expect(full.paramSets.first[1], 'name_0');
      expect(full.paramSets.first[198], 99);
      expect(full.paramSets.first[199], 'name_99');

      final tail = plan.segments[1];
      expect(tail.sql, sql);
      expect(tail.rowsPerStep, 1);
      expect(tail.paramSets, hasLength(1));
      expect(tail.paramSets.first, [2000, 'name_2000']);
    });

    test('supports quoted identifiers while ignoring values inside names', () {
      const sql = 'INSERT INTO "values"("select", "name") VALUES (?, ?)';
      final plan = chunkSimpleInsertBatch(sql, _rows(2000))!;

      expect(plan.segments, hasLength(1));
      expect(plan.segments.single.rowsPerStep, 100);
      expect(
        plan.segments.single.sql,
        startsWith('INSERT INTO "values"("select", "name") VALUES '),
      );
      expect(plan.segments.single.sql, contains('(?, ?), (?, ?)'));
    });

    test('supports bracketed and backtick identifiers', () {
      const sql = 'INSERT INTO [values]([select], `name`) VALUES (?, ?)';
      final plan = chunkSimpleInsertBatch(sql, _rows(2000))!;

      expect(plan.segments.single.rowsPerStep, 100);
      expect(
        plan.segments.single.sql,
        startsWith('INSERT INTO [values]([select], `name`) VALUES '),
      );
    });

    test('keeps complex SQL on the original path', () {
      expect(
        chunkSimpleInsertBatch(
          'INSERT INTO items(id, name) VALUES (?, ?) RETURNING id',
          _rows(2000),
        ),
        isNull,
      );
      expect(
        chunkSimpleInsertBatch(
          'INSERT INTO items(id, name) /* comment */ VALUES (?, ?)',
          _rows(2000),
        ),
        isNull,
      );
      expect(
        chunkSimpleInsertBatch(
          'INSERT INTO items(id, name) VALUES (:id, :name)',
          _rows(2000),
        ),
        isNull,
      );
    });
  });
}

List<List<Object?>> _rows(int count) {
  return [
    for (var i = 0; i < count; i++) [i, 'name_$i'],
  ];
}
