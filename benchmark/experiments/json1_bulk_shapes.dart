import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

import '../shared/stats.dart';

const _warmupRuns = 3;
const _measuredRuns = 12;

const _createCustomersSql = '''
  CREATE TABLE customers(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL
  )
''';

const _insertRowSql = 'INSERT INTO customers(name, email) VALUES (?, ?)';

const _insertJson1Sql = '''
  WITH rows AS (
    SELECT
      json_extract(value, '\$[0]') AS name,
      json_extract(value, '\$[1]') AS email
    FROM json_each(?)
  )
  INSERT INTO customers(name, email)
  SELECT name, email FROM rows
''';

const _readJson1Sql = '''
  SELECT id, name, email
  FROM customers
  WHERE id IN (SELECT value FROM json_each(?))
  ORDER BY id
''';

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_json1_');
  try {
    print('=== JSON1 bulk-shape experiment ===');
    print('');
    print(
      'Compares normal bind-heavy shapes against JSON1 `json_each(?)` shapes,',
    );
    print(
      'including a split between encoding inside the measured path and using',
    );
    print('an already pre-encoded payload.');

    final insertRows = _buildCustomerRows(5000);
    final readDatasetRows = _buildCustomerRows(20000);

    final insertResults = await _runInsertExperiment(
      tempDir.path,
      rows: insertRows,
    );
    final read1000Results = await _runReadExperiment(
      tempDir.path,
      seedRows: readDatasetRows,
      ids: List<int>.generate(1000, (index) => index * 2 + 1),
    );
    final read5000Results = await _runReadExperiment(
      tempDir.path,
      seedRows: readDatasetRows,
      ids: List<int>.generate(5000, (index) => index * 2 + 1),
    );

    printComparisonTable(
      'JSON1 insert (5000 rows, lower is better)',
      insertResults,
    );
    printComparisonTable(
      'JSON1 read (1000 ids, lower is better)',
      read1000Results,
    );
    printComparisonTable(
      'JSON1 read (5000 ids, lower is better)',
      read5000Results,
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
  exit(0);
}

Future<List<BenchmarkTiming>> _runInsertExperiment(
  String dirPath, {
  required List<List<Object?>> rows,
}) async {
  final db = await Database.open('$dirPath/insert.db');
  await db.execute(_createCustomersSql);

  final batchRows = rows.map((row) => List<Object?>.from(row)).toList();
  final preEncoded = jsonEncode(rows);

  final baseline = BenchmarkTiming('executeBatch()');
  final json1Encode = BenchmarkTiming('JSON1 insert + encode');
  final json1PreEncoded = BenchmarkTiming('JSON1 insert + pre-encoded');

  await _measure(
    baseline,
    _warmupRuns + _measuredRuns,
    beforeEach: () async => db.execute('DELETE FROM customers'),
    run: () async {
      await db.executeBatch(_insertRowSql, batchRows);
      await _expectCount(db, batchRows.length);
    },
  );

  await _measure(
    json1Encode,
    _warmupRuns + _measuredRuns,
    beforeEach: () async => db.execute('DELETE FROM customers'),
    run: () async {
      final payload = jsonEncode(rows);
      await db.execute(_insertJson1Sql, [payload]);
      await _expectCount(db, rows.length);
    },
  );

  await _measure(
    json1PreEncoded,
    _warmupRuns + _measuredRuns,
    beforeEach: () async => db.execute('DELETE FROM customers'),
    run: () async {
      await db.execute(_insertJson1Sql, [preEncoded]);
      await _expectCount(db, rows.length);
    },
  );

  await db.close();
  return [baseline, json1Encode, json1PreEncoded];
}

Future<List<BenchmarkTiming>> _runReadExperiment(
  String dirPath, {
  required List<List<Object?>> seedRows,
  required List<int> ids,
}) async {
  final db = await Database.open('$dirPath/read_${ids.length}.db');
  await db.execute(_createCustomersSql);
  await db.executeBatch(_insertRowSql, seedRows);

  final placeholderSql =
      'SELECT id, name, email FROM customers WHERE id IN '
      '(${List<String>.filled(ids.length, '?').join(', ')}) ORDER BY id';
  final placeholderParams = ids.cast<Object?>().toList(growable: false);
  final preEncodedIds = jsonEncode(ids);

  final placeholders = BenchmarkTiming('placeholders IN (...)');
  final json1Encode = BenchmarkTiming('JSON1 read + encode');
  final json1PreEncoded = BenchmarkTiming('JSON1 read + pre-encoded');

  await _measure(
    placeholders,
    _warmupRuns + _measuredRuns,
    run: () async {
      final rows = await db.select(placeholderSql, placeholderParams);
      _expectLength(rows.length, ids.length);
    },
  );

  await _measure(
    json1Encode,
    _warmupRuns + _measuredRuns,
    run: () async {
      final payload = jsonEncode(ids);
      final rows = await db.select(_readJson1Sql, [payload]);
      _expectLength(rows.length, ids.length);
    },
  );

  await _measure(
    json1PreEncoded,
    _warmupRuns + _measuredRuns,
    run: () async {
      final rows = await db.select(_readJson1Sql, [preEncodedIds]);
      _expectLength(rows.length, ids.length);
    },
  );

  await db.close();
  return [placeholders, json1Encode, json1PreEncoded];
}

Future<void> _measure(
  BenchmarkTiming timing,
  int runs, {
  Future<void> Function()? beforeEach,
  required Future<void> Function() run,
}) async {
  for (var i = 0; i < runs; i++) {
    if (beforeEach != null) await beforeEach();
    final stopwatch = Stopwatch()..start();
    await run();
    stopwatch.stop();
    if (i >= _warmupRuns) {
      timing.recordWallOnly(stopwatch.elapsedMicroseconds);
    }
  }
}

List<List<Object?>> _buildCustomerRows(int count) {
  return List<List<Object?>>.generate(
    count,
    (index) => <Object?>[
      'Customer $index',
      'customer$index@example.com',
    ],
    growable: false,
  );
}

Future<void> _expectCount(Database db, int expected) async {
  final rows = await db.select('SELECT count(*) AS count FROM customers');
  final actual = rows.first['count'];
  if (actual != expected) {
    throw StateError('Expected $expected rows, found $actual');
  }
}

void _expectLength(int actual, int expected) {
  if (actual != expected) {
    throw StateError('Expected $expected rows, found $actual');
  }
}
