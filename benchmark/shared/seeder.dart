import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

// ---------------------------------------------------------------------------
// Standard schema (6 columns, mixed types)
// ---------------------------------------------------------------------------

const standardCreateSql = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    value REAL NOT NULL,
    category TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
''';

const standardInsertSql =
    'INSERT INTO items(name, description, value, category, created_at) '
    'VALUES (?, ?, ?, ?, ?)';

const standardSelectSql = 'SELECT * FROM items';

List<Object?> standardRow(int i) => [
      'Item $i',
      'This is a description for item number $i with some padding text to simulate real data',
      i * 1.5,
      'category_${i % 10}',
      '2026-04-0${(i % 9) + 1}T12:00:00Z',
    ];

// ---------------------------------------------------------------------------
// Seeding functions per library
// ---------------------------------------------------------------------------

Future<void> seedResqlite(
  resqlite.Database db,
  int rowCount, {
  String createSql = standardCreateSql,
  String insertSql = standardInsertSql,
  List<Object?> Function(int i)? rowBuilder,
}) async {
  await db.execute(createSql);
  final builder = rowBuilder ?? standardRow;
  for (var i = 0; i < rowCount; i++) {
    await db.execute(insertSql, builder(i));
  }
}

void seedSqlite3(
  sqlite3.Database db,
  int rowCount, {
  String createSql = standardCreateSql,
  String insertSql = standardInsertSql,
  List<Object?> Function(int i)? rowBuilder,
}) {
  db.execute(createSql);
  final builder = rowBuilder ?? standardRow;
  final stmt = db.prepare(insertSql);
  for (var i = 0; i < rowCount; i++) {
    stmt.execute(builder(i));
  }
  stmt.close();
}

Future<void> seedSqliteAsync(
  sqlite_async.SqliteDatabase db,
  int rowCount, {
  String createSql = standardCreateSql,
  String insertSql = standardInsertSql,
  List<Object?> Function(int i)? rowBuilder,
}) async {
  await db.execute(createSql);
  final builder = rowBuilder ?? standardRow;
  final paramSets = [
    for (var i = 0; i < rowCount; i++) builder(i),
  ];
  await db.executeBatch(insertSql, paramSets);
}
