// ignore_for_file: avoid_print
//
// Multi-row INSERT ceiling audit - exp 133 candidate.
//
// Compares the current executeBatch shape (one VALUES row per sqlite3_step)
// against generated multi-row VALUES statements that bind N user rows per
// sqlite3_step. This is a ceiling harness, not a production SQL rewriter.
//
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/multi_row_insert_ceiling.dart --markdown

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/profile_mode.dart';

final class _Workload {
  const _Workload({
    required this.name,
    required this.createSql,
    required this.insertPrefix,
    required this.paramsPerRow,
    required this.row,
  });

  final String name;
  final String createSql;
  final String insertPrefix;
  final int paramsPerRow;
  final List<Object?> Function(int row) row;
}

final class _RunRow {
  _RunRow({
    required this.pass,
    required this.workload,
    required this.rows,
    required this.rowsPerStep,
    required this.chunkBuildUs,
    required this.wallUs,
    required this.profile,
  });

  final int pass;
  final String workload;
  final int rows;
  final int rowsPerStep;
  final int chunkBuildUs;
  final int wallUs;
  final BatchWriteProfile profile;

  int get effectiveTotalUs => chunkBuildUs + wallUs;
  int get expectedSteps => rows ~/ rowsPerStep;
  int get nativeMeasuredUs =>
      profile.nativeStmtUs +
      profile.nativeTxBeginUs +
      profile.nativeTxCommitUs +
      profile.nativeTxRollbackUs +
      profile.nativeBindUs +
      profile.nativeStepUs +
      profile.nativeResetUs;
  int get nativeResidualUs {
    final residual = profile.nativeWriteUs - nativeMeasuredUs;
    return residual < 0 ? 0 : residual;
  }

  double get wallMs => wallUs / 1000.0;
  double get effectiveMs => effectiveTotalUs / 1000.0;
  double get stepPerUserRowUs => rows == 0 ? 0.0 : profile.nativeStepUs / rows;
  double get bindPerUserRowUs => rows == 0 ? 0.0 : profile.nativeBindUs / rows;
  double get nativePerUserRowUs =>
      rows == 0 ? 0.0 : profile.nativeWriteUs / rows;
}

const _defaultRows = 10000;
const _rowsPerStepSweep = [1, 2, 4, 8, 16, 25, 50, 100, 200];

final _workloads = [
  _Workload(
    name: 'narrow 2 params',
    createSql: '''
CREATE TABLE narrow_batch(
  text_0 TEXT NOT NULL,
  int_1 INTEGER NOT NULL
)
''',
    insertPrefix: 'INSERT INTO narrow_batch(text_0, int_1) VALUES ',
    paramsPerRow: 2,
    row: (i) => ['text_$i', i],
  ),
  _Workload(
    name: 'wide mixed ASCII',
    createSql: _wideBatchCreateSql,
    insertPrefix: _wideBatchInsertPrefix,
    paramsPerRow: 20,
    row: (i) => _wideBatchRow(i, _TextMode.ascii),
  ),
  _Workload(
    name: 'wide mixed Unicode',
    createSql: _wideBatchCreateSql,
    insertPrefix: _wideBatchInsertPrefix,
    paramsPerRow: 20,
    row: (i) => _wideBatchRow(i, _TextMode.unicode),
  ),
  _Workload(
    name: 'wide mixed emoji',
    createSql: _wideBatchCreateSql,
    insertPrefix: _wideBatchInsertPrefix,
    paramsPerRow: 20,
    row: (i) => _wideBatchRow(i, _TextMode.emoji),
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
    insertPrefix:
        'INSERT INTO blob_batch(blob_0, blob_1, blob_2, blob_3, blob_4, blob_5, blob_6, blob_7) VALUES ',
    paramsPerRow: 8,
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
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; rerun with -DRESQLITE_PROFILE=true '
      'before comparing profile buckets.',
    );
  }

  final writeMarkdown = args.contains('--markdown');
  final repeats = _readIntArg(args, '--repeats=', 5);
  final rows = _readIntArg(args, '--rows=', _defaultRows);
  final rowsPerStepSweep = _readRowsPerStep(args);
  final results = <_RunRow>[];

  for (var pass = 1; pass <= repeats; pass++) {
    for (final workload in _workloads) {
      final sourceRows = [for (var i = 0; i < rows; i++) workload.row(i)];
      for (final rowsPerStep in rowsPerStepSweep) {
        if (rows % rowsPerStep != 0) continue;
        results.add(
          await _runScenario(
            pass: pass,
            workload: workload,
            sourceRows: sourceRows,
            rowsPerStep: rowsPerStep,
          ),
        );
      }
    }
  }

  final markdown = _renderMarkdown(
    rows: results,
    repeats: repeats,
    rowCount: rows,
    rowsPerStepSweep: rowsPerStepSweep,
  );
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-133-multi-row-insert-ceiling.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
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

List<int> _readRowsPerStep(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--rows-per-step=')) {
      final raw = arg.substring('--rows-per-step='.length);
      final values =
          raw
              .split(',')
              .map((value) => int.tryParse(value.trim()))
              .whereType<int>()
              .where((value) => value > 0)
              .toSet()
              .toList()
            ..sort();
      if (values.isNotEmpty) return values;
    }
  }
  return _rowsPerStepSweep;
}

Future<_RunRow> _runScenario({
  required int pass,
  required _Workload workload,
  required List<List<Object?>> sourceRows,
  required int rowsPerStep,
}) async {
  final prepared = await _openPreparedDb(workload);
  final db = prepared.db;
  try {
    final chunkSw = Stopwatch()..start();
    final paramSets = rowsPerStep == 1
        ? sourceRows
        : _chunkParamSets(sourceRows, rowsPerStep);
    chunkSw.stop();

    final sql = _insertSql(
      workload.insertPrefix,
      workload.paramsPerRow,
      rowsPerStep,
    );
    final sw = Stopwatch()..start();
    final profile = executeBatchWriteProfiled(db.handle, sql, paramSets);
    sw.stop();

    return _RunRow(
      pass: pass,
      workload: workload.name,
      rows: sourceRows.length,
      rowsPerStep: rowsPerStep,
      chunkBuildUs: rowsPerStep == 1 ? 0 : chunkSw.elapsedMicroseconds,
      wallUs: sw.elapsedMicroseconds,
      profile: profile,
    );
  } finally {
    await _closePreparedDb(prepared);
  }
}

typedef _PreparedDb = ({Database db, Directory tempDir});

Future<_PreparedDb> _openPreparedDb(_Workload workload) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'multi_row_insert_ceiling_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute(workload.createSql);
    return (db: db, tempDir: tempDir);
  } catch (_) {
    await db.close();
    await tempDir.delete(recursive: true);
    rethrow;
  }
}

Future<void> _closePreparedDb(_PreparedDb prepared) async {
  try {
    await prepared.db.close();
  } finally {
    if (await prepared.tempDir.exists()) {
      await prepared.tempDir.delete(recursive: true);
    }
  }
}

List<List<Object?>> _chunkParamSets(
  List<List<Object?>> sourceRows,
  int rowsPerStep,
) {
  final chunks = <List<Object?>>[];
  for (var start = 0; start < sourceRows.length; start += rowsPerStep) {
    final chunk = <Object?>[];
    for (var row = 0; row < rowsPerStep; row++) {
      chunk.addAll(sourceRows[start + row]);
    }
    chunks.add(chunk);
  }
  return chunks;
}

String _insertSql(String insertPrefix, int paramsPerRow, int rowsPerStep) {
  final rowPlaceholders = '(${List.filled(paramsPerRow, '?').join(', ')})';
  return '$insertPrefix${List.filled(rowsPerStep, rowPlaceholders).join(', ')}';
}

enum _TextMode { ascii, unicode, emoji }

const _wideBatchCreateSql = '''
CREATE TABLE wide_batch(
  text_0 TEXT NOT NULL,
  int_1 INTEGER NOT NULL,
  real_2 REAL NOT NULL,
  blob_3 BLOB NOT NULL,
  text_4 TEXT NOT NULL,
  int_5 INTEGER NOT NULL,
  real_6 REAL NOT NULL,
  blob_7 BLOB NOT NULL,
  text_8 TEXT NOT NULL,
  int_9 INTEGER NOT NULL,
  real_10 REAL NOT NULL,
  blob_11 BLOB NOT NULL,
  text_12 TEXT NOT NULL,
  int_13 INTEGER NOT NULL,
  real_14 REAL NOT NULL,
  blob_15 BLOB NOT NULL,
  text_16 TEXT NOT NULL,
  int_17 INTEGER NOT NULL,
  real_18 REAL NOT NULL,
  blob_19 BLOB NOT NULL
)
''';

const _wideBatchInsertPrefix = '''
INSERT INTO wide_batch(
  text_0, int_1, real_2, blob_3,
  text_4, int_5, real_6, blob_7,
  text_8, int_9, real_10, blob_11,
  text_12, int_13, real_14, blob_15,
  text_16, int_17, real_18, blob_19
) VALUES 
''';

List<Object?> _wideBatchRow(int i, _TextMode textMode) => [
  _text(i, 0, textMode),
  i,
  i / 3.0,
  _wideBlob(i, 3),
  _text(i, 4, textMode),
  i + 5,
  i / 7.0,
  _wideBlob(i, 7),
  _text(i, 8, textMode),
  i + 9,
  i / 11.0,
  _wideBlob(i, 11),
  _text(i, 12, textMode),
  i + 13,
  i / 17.0,
  _wideBlob(i, 15),
  _text(i, 16, textMode),
  i + 17,
  i / 19.0,
  _wideBlob(i, 19),
];

String _text(int row, int column, _TextMode mode) => switch (mode) {
  _TextMode.ascii => 'text_${row}_$column',
  _TextMode.unicode => 'cafe_${row}_${column}_\u00e9_\u0416',
  _TextMode.emoji => 'emoji_${row}_${column}_\u{1f680}_\u{1f9ea}',
};

Uint8List _wideBlob(int row, int salt) =>
    Uint8List.fromList([row & 0xff, (row >> 8) & 0xff, salt, 0x5a]);

String _renderMarkdown({
  required List<_RunRow> rows,
  required int repeats,
  required int rowCount,
  required List<int> rowsPerStepSweep,
}) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 133 - Multi-row INSERT Ceiling');
  buf.writeln();
  buf.writeln(
    'Profile harness: `benchmark/profile/multi_row_insert_ceiling.dart`',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/multi_row_insert_ceiling.dart --markdown '
    '--repeats=$repeats --rows=$rowCount '
    '--rows-per-step=${rowsPerStepSweep.join(',')}',
  );
  buf.writeln('```');
  buf.writeln();
  _renderMedianTable(buf, rows);
  _renderBestTable(buf, rows);
  _renderRawRows(buf, rows);
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `rows_per_step=1` is the current executeBatch shape: one user row per '
    '`sqlite3_step`.',
  );
  buf.writeln(
    '- `rows_per_step>1` generates a multi-row `INSERT ... VALUES (...), ...` '
    'statement and binds one chunk per native batch set.',
  );
  buf.writeln(
    '- `chunk_build_us` is prototype overhead for building chunked Dart param '
    'sets. A production implementation could pack directly from original rows, '
    'so `wall_ms` is the useful ceiling and `effective_ms` is a conservative '
    'prototype cost.',
  );
  return buf.toString();
}

void _renderMedianTable(StringBuffer buf, List<_RunRow> rows) {
  buf.writeln('## Median profile');
  buf.writeln();
  buf.writeln(
    '| workload | rows_per_step | wall_ms | effective_ms | native_us | '
    'param_pack_us | stmt_us | bind_us | step_us | reset_us | commit_us | '
    'steps | step_per_user_row_us | bind_per_user_row_us |',
  );
  buf.writeln(
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final entry in _groups(rows).entries) {
    final groupRows = entry.value;
    buf.writeln(
      '| ${entry.key.workload} | ${entry.key.rowsPerStep} | '
      '${(_median(groupRows.map((r) => r.wallUs)) / 1000.0).toStringAsFixed(2)} | '
      '${(_median(groupRows.map((r) => r.effectiveTotalUs)) / 1000.0).toStringAsFixed(2)} | '
      '${_median(groupRows.map((r) => r.profile.nativeWriteUs))} | '
      '${_median(groupRows.map((r) => r.profile.paramPackUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeStmtUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeBindUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeStepUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeResetUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeTxCommitUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeStepCount))} | '
      '${_medianDouble(groupRows.map((r) => r.stepPerUserRowUs)).toStringAsFixed(3)} | '
      '${_medianDouble(groupRows.map((r) => r.bindPerUserRowUs)).toStringAsFixed(3)} |',
    );
  }
  buf.writeln();
}

void _renderBestTable(StringBuffer buf, List<_RunRow> rows) {
  buf.writeln('## Best ceiling by workload');
  buf.writeln();
  buf.writeln(
    '| workload | baseline_wall_ms | best_rows_per_step | best_wall_ms | '
    'wall_delta | best_effective_ms | effective_delta | step_count_delta |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  final byWorkload = <String, List<_RunRow>>{};
  for (final row in rows) {
    byWorkload.putIfAbsent(row.workload, () => []).add(row);
  }
  for (final entry in byWorkload.entries) {
    final workloadRows = entry.value;
    final baseline = _median(
      workloadRows.where((r) => r.rowsPerStep == 1).map((r) => r.wallUs),
    );
    final baselineSteps = _median(
      workloadRows
          .where((r) => r.rowsPerStep == 1)
          .map((r) => r.profile.nativeStepCount),
    );
    final groups = _groups(workloadRows);
    ({int rowsPerStep, int wallUs, int effectiveUs, int steps})? best;
    for (final group in groups.entries) {
      final wall = _median(group.value.map((r) => r.wallUs));
      final effective = _median(group.value.map((r) => r.effectiveTotalUs));
      final steps = _median(group.value.map((r) => r.profile.nativeStepCount));
      if (best == null || wall < best.wallUs) {
        best = (
          rowsPerStep: group.key.rowsPerStep,
          wallUs: wall,
          effectiveUs: effective,
          steps: steps,
        );
      }
    }
    final resolved = best!;
    buf.writeln(
      '| ${entry.key} | ${(baseline / 1000.0).toStringAsFixed(2)} | '
      '${resolved.rowsPerStep} | ${(resolved.wallUs / 1000.0).toStringAsFixed(2)} | '
      '${_pctDelta(resolved.wallUs, baseline)} | '
      '${(resolved.effectiveUs / 1000.0).toStringAsFixed(2)} | '
      '${_pctDelta(resolved.effectiveUs, baseline)} | '
      '${baselineSteps} -> ${resolved.steps} |',
    );
  }
  buf.writeln();
}

void _renderRawRows(StringBuffer buf, List<_RunRow> rows) {
  buf.writeln('## Raw rows');
  buf.writeln();
  buf.writeln(
    '| pass | workload | rows_per_step | chunk_build_us | wall_ms | '
    'native_us | param_pack_us | stmt_us | bind_us | step_us | reset_us | '
    'commit_us | residual_us | steps | binds | resets |',
  );
  buf.writeln(
    '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.rowsPerStep} | '
      '${row.chunkBuildUs} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.profile.nativeWriteUs} | ${row.profile.paramPackUs} | '
      '${row.profile.nativeStmtUs} | ${row.profile.nativeBindUs} | '
      '${row.profile.nativeStepUs} | ${row.profile.nativeResetUs} | '
      '${row.profile.nativeTxCommitUs} | ${row.nativeResidualUs} | '
      '${row.profile.nativeStepCount} | ${row.profile.nativeBindCount} | '
      '${row.profile.nativeResetCount} |',
    );
  }
  buf.writeln();
}

Map<({String workload, int rowsPerStep}), List<_RunRow>> _groups(
  List<_RunRow> rows,
) {
  final groups = <({String workload, int rowsPerStep}), List<_RunRow>>{};
  for (final row in rows) {
    groups
        .putIfAbsent((
          workload: row.workload,
          rowsPerStep: row.rowsPerStep,
        ), () => [])
        .add(row);
  }
  return groups;
}

String _pctDelta(int candidate, int baseline) {
  if (baseline == 0) return '0.0%';
  final delta = ((candidate - baseline) / baseline) * 100.0;
  final sign = delta > 0 ? '+' : '';
  return '$sign${delta.toStringAsFixed(1)}%';
}

int _median(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  return sorted[sorted.length ~/ 2];
}

double _medianDouble(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  return sorted[sorted.length ~/ 2];
}
