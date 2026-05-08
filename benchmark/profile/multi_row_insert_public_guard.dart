// ignore_for_file: avoid_print
//
// Public executeBatch A/B for exp 133.
//
// Compares the guarded simple-INSERT chunker against the same public API with
// a comment-forced fallback path while preserving the same logical table and
// values. Quoted identifiers are measured separately because exp 133 now
// recognizes them.
//
//   dart run benchmark/profile/multi_row_insert_public_guard.dart --markdown

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';

final class _Workload {
  const _Workload({
    required this.name,
    required this.createSql,
    required this.optimizedSql,
    required this.quotedOptimizedSql,
    required this.fallbackSql,
    required this.row,
  });

  final String name;
  final String createSql;
  final String optimizedSql;
  final String quotedOptimizedSql;
  final String fallbackSql;
  final List<Object?> Function(int row) row;
}

final class _RunRow {
  const _RunRow({
    required this.pass,
    required this.workload,
    required this.mode,
    required this.rows,
    required this.wallUs,
  });

  final int pass;
  final String workload;
  final String mode;
  final int rows;
  final int wallUs;

  double get wallMs => wallUs / 1000.0;
}

const _defaultRows = 10000;

final _workloads = [
  _Workload(
    name: 'narrow 2 params',
    createSql: '''
CREATE TABLE narrow_batch(
  text_0 TEXT NOT NULL,
  int_1 INTEGER NOT NULL
)
''',
    optimizedSql: 'INSERT INTO narrow_batch(text_0, int_1) VALUES (?, ?)',
    quotedOptimizedSql:
        'INSERT INTO "narrow_batch"("text_0", "int_1") VALUES (?, ?)',
    fallbackSql:
        'INSERT INTO narrow_batch(text_0, int_1) /* fallback */ VALUES (?, ?)',
    row: (i) => ['text_$i', i],
  ),
  _Workload(
    name: 'wide mixed ASCII',
    createSql: _wideBatchCreateSql,
    optimizedSql: _wideBatchInsertSql('wide_batch'),
    quotedOptimizedSql: _wideBatchInsertSql('"wide_batch"', quoteColumns: true),
    fallbackSql: _wideBatchInsertSql('wide_batch', fallbackComment: true),
    row: (i) => _wideBatchRow(i),
  ),
  _Workload(
    name: 'blob-heavy 8 params',
    createSql: '''
CREATE TABLE blob_batch(
  blob_0 BLOB NOT NULL,
  blob_1 BLOB NOT NULL,
  blob_2 BLOB NOT NULL,
  blob_3 BLOB NOT NULL,
  blob_4 BLOB NOT NULL,
  blob_5 BLOB NOT NULL,
  blob_6 BLOB NOT NULL,
  blob_7 BLOB NOT NULL
)
''',
    optimizedSql: _blobBatchInsertSql('blob_batch'),
    quotedOptimizedSql: _blobBatchInsertSql('"blob_batch"', quoteColumns: true),
    fallbackSql: _blobBatchInsertSql('blob_batch', fallbackComment: true),
    row: (i) => [
      _wideBlob(i, 0),
      _wideBlob(i, 1),
      _wideBlob(i, 2),
      _wideBlob(i, 3),
      _wideBlob(i, 4),
      _wideBlob(i, 5),
      _wideBlob(i, 6),
      _wideBlob(i, 7),
    ],
  ),
];

Future<void> main(List<String> args) async {
  final writeMarkdown = args.contains('--markdown');
  final repeats = _readIntArg(args, '--repeats=', 7);
  final rows = _readIntArg(args, '--rows=', _defaultRows);
  final results = <_RunRow>[];

  for (var pass = 1; pass <= repeats; pass++) {
    for (final workload in _workloads) {
      final paramSets = [for (var i = 0; i < rows; i++) workload.row(i)];
      results.add(
        await _runScenario(
          pass: pass,
          workload: workload,
          mode: 'fallback comment',
          sql: workload.fallbackSql,
          paramSets: paramSets,
        ),
      );
      results.add(
        await _runScenario(
          pass: pass,
          workload: workload,
          mode: 'optimized',
          sql: workload.optimizedSql,
          paramSets: paramSets,
        ),
      );
      results.add(
        await _runScenario(
          pass: pass,
          workload: workload,
          mode: 'optimized quoted',
          sql: workload.quotedOptimizedSql,
          paramSets: paramSets,
        ),
      );
    }
  }

  final markdown = _renderMarkdown(results, repeats: repeats, rowCount: rows);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-133-multi-row-insert-public-guard.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

Future<_RunRow> _runScenario({
  required int pass,
  required _Workload workload,
  required String mode,
  required String sql,
  required List<List<Object?>> paramSets,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('resqlite_exp133_');
  final db = await Database.open('${tempDir.path}/bench.db');
  try {
    await db.execute(workload.createSql);
    final sw = Stopwatch()..start();
    await db.executeBatch(sql, paramSets);
    sw.stop();
    final count = await db.select(
      'SELECT COUNT(*) AS cnt FROM ${_tableName(workload)}',
    );
    if (count.single['cnt'] != paramSets.length) {
      throw StateError(
        'inserted ${count.single['cnt']} rows, expected ${paramSets.length}',
      );
    }
    return _RunRow(
      pass: pass,
      workload: workload.name,
      mode: mode,
      rows: paramSets.length,
      wallUs: sw.elapsedMicroseconds,
    );
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}

String _tableName(_Workload workload) {
  return switch (workload.name) {
    'narrow 2 params' => 'narrow_batch',
    'wide mixed ASCII' => 'wide_batch',
    'blob-heavy 8 params' => 'blob_batch',
    _ => throw StateError('unknown workload ${workload.name}'),
  };
}

int _readIntArg(List<String> args, String prefix, int fallback) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      final parsed = int.tryParse(arg.substring(prefix.length));
      if (parsed != null && parsed > 0) return parsed;
    }
  }
  return fallback;
}

String _renderMarkdown(
  List<_RunRow> resultRows, {
  required int repeats,
  required int rowCount,
}) {
  final byWorkload = <String, List<_RunRow>>{};
  for (final row in resultRows) {
    byWorkload.putIfAbsent(row.workload, () => []).add(row);
  }

  final buffer = StringBuffer()
    ..writeln('# Experiment 133 - Public Multi-row INSERT Guard')
    ..writeln()
    ..writeln('Command:')
    ..writeln()
    ..writeln('```text')
    ..writeln(
      'dart run benchmark/profile/multi_row_insert_public_guard.dart '
      '--markdown --repeats=$repeats --rows=$rowCount',
    )
    ..writeln('```')
    ..writeln()
    ..writeln(
      '| workload | fallback_wall_ms | optimized_wall_ms | quoted_optimized_wall_ms | optimized_delta | quoted_delta |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|');

  for (final entry in byWorkload.entries) {
    final fallback = _median(
      entry.value
          .where((row) => row.mode == 'fallback comment')
          .map((row) => row.wallUs)
          .toList(),
    );
    final optimized = _median(
      entry.value
          .where((row) => row.mode == 'optimized')
          .map((row) => row.wallUs)
          .toList(),
    );
    final quotedOptimized = _median(
      entry.value
          .where((row) => row.mode == 'optimized quoted')
          .map((row) => row.wallUs)
          .toList(),
    );
    buffer.writeln(
      '| ${entry.key} | ${_ms(fallback)} | ${_ms(optimized)} | '
      '${_ms(quotedOptimized)} | ${_percent(optimized, fallback)} | '
      '${_percent(quotedOptimized, fallback)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Raw rows')
    ..writeln()
    ..writeln('| pass | workload | mode | wall_ms |')
    ..writeln('|---:|---|---|---:|');
  for (final row in resultRows) {
    buffer.writeln(
      '| ${row.pass} | ${row.workload} | ${row.mode} | ${row.wallMs.toStringAsFixed(2)} |',
    );
  }

  return buffer.toString();
}

int _median(List<int> values) {
  values.sort();
  return values[values.length ~/ 2];
}

String _ms(int us) => (us / 1000.0).toStringAsFixed(2);

String _percent(int value, int baseline) {
  final delta = ((value - baseline) / baseline) * 100.0;
  final sign = delta > 0 ? '+' : '';
  return '$sign${delta.toStringAsFixed(1)}%';
}

String _wideBatchInsertSql(
  String table, {
  bool quoteColumns = false,
  bool fallbackComment = false,
}) {
  final columns = [for (var i = 0; i < 20; i++) quoteColumns ? '"c$i"' : 'c$i'];
  final comment = fallbackComment ? ' /* fallback */' : '';
  return '''
INSERT INTO $table(
  ${columns.sublist(0, 5).join(', ')},
  ${columns.sublist(5, 10).join(', ')},
  ${columns.sublist(10, 15).join(', ')},
  ${columns.sublist(15, 20).join(', ')}
)$comment VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''';
}

String _blobBatchInsertSql(
  String table, {
  bool quoteColumns = false,
  bool fallbackComment = false,
}) {
  final columns = [
    for (var i = 0; i < 8; i++) quoteColumns ? '"blob_$i"' : 'blob_$i',
  ];
  final comment = fallbackComment ? ' /* fallback */' : '';
  return '''
INSERT INTO $table(
  ${columns.join(', ')}
)$comment VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''';
}

const _wideBatchCreateSql = '''
CREATE TABLE wide_batch(
  c0 TEXT NOT NULL,
  c1 INTEGER NOT NULL,
  c2 REAL NOT NULL,
  c3 BLOB NOT NULL,
  c4 TEXT NOT NULL,
  c5 INTEGER NOT NULL,
  c6 REAL NOT NULL,
  c7 BLOB NOT NULL,
  c8 TEXT NOT NULL,
  c9 INTEGER NOT NULL,
  c10 REAL NOT NULL,
  c11 BLOB NOT NULL,
  c12 TEXT NOT NULL,
  c13 INTEGER NOT NULL,
  c14 REAL NOT NULL,
  c15 BLOB NOT NULL,
  c16 TEXT NOT NULL,
  c17 INTEGER NOT NULL,
  c18 REAL NOT NULL,
  c19 BLOB NOT NULL
)
''';

List<Object?> _wideBatchRow(int i) => [
  'ascii_${i}_0',
  i,
  i + 0.125,
  _wideBlob(i, 3),
  'ascii_${i}_4',
  i * 2,
  i + 0.25,
  _wideBlob(i, 7),
  'ascii_${i}_8',
  i * 3,
  i + 0.5,
  _wideBlob(i, 11),
  'ascii_${i}_12',
  i * 4,
  i + 0.75,
  _wideBlob(i, 15),
  'ascii_${i}_16',
  i * 5,
  i + 0.875,
  _wideBlob(i, 19),
];

Uint8List _wideBlob(int row, int column) {
  return Uint8List.fromList([
    row & 0xff,
    (row >> 8) & 0xff,
    column,
    (row + column) & 0xff,
    0x7f,
    0x80,
    0xfe,
    0xff,
  ]);
}
