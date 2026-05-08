// ignore_for_file: avoid_print
//
// Wide-batch transaction-shape audit - exp 131.
//
// Compares a profiled top-level native batch against the same profiled nested
// batch wrapped in explicit native BEGIN/COMMIT. Run with:
//
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/wide_batch_transaction_shape.dart --markdown

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/profile_mode.dart';

final class _TransactionShapeRow {
  _TransactionShapeRow({
    required this.pass,
    required this.workload,
    required this.scenario,
    required this.wallUs,
    required this.txBeginUs,
    required this.txCommitUs,
    required this.batchProfile,
  });

  final int pass;
  final String workload;
  final String scenario;
  final int wallUs;
  final int txBeginUs;
  final int txCommitUs;
  final BatchWriteProfile batchProfile;

  int get paramPackUs => batchProfile.paramPackUs;
  int get batchNativeUs => batchProfile.nativeWriteUs;
  int get nativeStmtUs => batchProfile.nativeStmtUs;
  int get nativeBindUs => batchProfile.nativeBindUs;
  int get nativeStepUs => batchProfile.nativeStepUs;
  int get nativeResetUs => batchProfile.nativeResetUs;
  int get nativePreupdateUs => batchProfile.nativePreupdateUs;
  int get setCount => batchProfile.nativeSetCount;

  int get nativeTotalUs {
    final txWallIsInsideBatch =
        batchProfile.nativeTxBeginUs != 0 || batchProfile.nativeTxCommitUs != 0;
    return txWallIsInsideBatch
        ? batchNativeUs
        : txBeginUs + batchNativeUs + txCommitUs;
  }

  int get nativeResidualUs {
    final residual =
        nativeTotalUs -
        txBeginUs -
        txCommitUs -
        nativeStmtUs -
        nativeBindUs -
        nativeStepUs -
        nativeResetUs;
    return residual < 0 ? 0 : residual;
  }

  double get wallMs => wallUs / 1000.0;
  double pctOfNativeTotal(int value) =>
      nativeTotalUs == 0 ? 0.0 : (value / nativeTotalUs) * 100.0;
  double pctOfStep(int value) =>
      nativeStepUs == 0 ? 0.0 : (value / nativeStepUs) * 100.0;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; profiled native batch counters still run, '
      'but this harness should be compared with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');
  final repeats = _readRepeats(args);
  final rows = <_TransactionShapeRow>[];

  for (var pass = 1; pass <= repeats; pass++) {
    for (final textMode in _TextMode.values) {
      rows.add(await _runTopLevelBatch(pass, textMode));
      rows.add(await _runManualTransactionBatch(pass, textMode));
    }
  }

  final markdown = _renderMarkdown(rows, repeats);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-131-wide-batch-transaction-shape.md',
    );
    await outFile.writeAsString(markdown);
    print('Wrote ${outFile.path}');
  }
}

int _readRepeats(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--repeats=')) {
      final parsed = int.tryParse(arg.substring('--repeats='.length));
      if (parsed != null && parsed > 0) return parsed;
    }
  }
  return 5;
}

Future<_TransactionShapeRow> _runTopLevelBatch(
  int pass,
  _TextMode textMode,
) async {
  final prepared = await _openPreparedDb();
  final db = prepared.db;
  try {
    final rows = [for (var i = 0; i < 10000; i++) _wideBatchRow(i, textMode)];

    final sw = Stopwatch()..start();
    final profile = executeBatchWriteProfiled(
      db.handle,
      _wideBatchInsertSql,
      rows,
    );
    sw.stop();

    return _TransactionShapeRow(
      pass: pass,
      workload: textMode.label,
      scenario: 'top-level batch',
      wallUs: sw.elapsedMicroseconds,
      txBeginUs: profile.nativeTxBeginUs,
      txCommitUs: profile.nativeTxCommitUs,
      batchProfile: profile,
    );
  } finally {
    await _closePreparedDb(prepared);
  }
}

Future<_TransactionShapeRow> _runManualTransactionBatch(
  int pass,
  _TextMode textMode,
) async {
  final prepared = await _openPreparedDb();
  final db = prepared.db;
  try {
    final rows = [for (var i = 0; i < 10000; i++) _wideBatchRow(i, textMode)];

    final sw = Stopwatch()..start();
    final txBeginUs = _timeNativeCall(
      () => resqliteTxBeginImmediate(db.handle),
      'BEGIN IMMEDIATE',
    );
    final profile = executeNestedBatchWriteProfiled(
      db.handle,
      _wideBatchInsertSql,
      rows,
    );
    final txCommitUs = _timeNativeCall(
      () => resqliteTxCommit(db.handle),
      'COMMIT',
    );
    sw.stop();

    return _TransactionShapeRow(
      pass: pass,
      workload: textMode.label,
      scenario: 'manual tx + nested batch',
      wallUs: sw.elapsedMicroseconds,
      txBeginUs: txBeginUs,
      txCommitUs: txCommitUs,
      batchProfile: profile,
    );
  } finally {
    await _closePreparedDb(prepared);
  }
}

int _timeNativeCall(int Function() call, String label) {
  final sw = Stopwatch()..start();
  final rc = call();
  sw.stop();
  if (rc != 0) {
    throw StateError('$label failed with sqlite code $rc');
  }
  return sw.elapsedMicroseconds;
}

typedef _PreparedDb = ({Database db, Directory tempDir});

Future<_PreparedDb> _openPreparedDb() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'wide_batch_transaction_shape_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute(_wideBatchCreateSql);
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

enum _TextMode {
  ascii('mixed ASCII text'),
  unicode('mixed Unicode text'),
  emoji('mixed emoji text');

  const _TextMode(this.label);
  final String label;
}

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

const _wideBatchInsertSql = '''
INSERT INTO wide_batch(
  text_0, int_1, real_2, blob_3,
  text_4, int_5, real_6, blob_7,
  text_8, int_9, real_10, blob_11,
  text_12, int_13, real_14, blob_15,
  text_16, int_17, real_18, blob_19
) VALUES (
  ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?, ?,
  ?, ?, ?, ?
)
''';

List<Object?> _wideBatchRow(int i, _TextMode textMode) => [
  _text(i, 0, textMode),
  i,
  i / 3.0,
  _blob(i, 3),
  _text(i, 4, textMode),
  i + 5,
  i / 7.0,
  _blob(i, 7),
  _text(i, 8, textMode),
  i + 9,
  i / 11.0,
  _blob(i, 11),
  _text(i, 12, textMode),
  i + 13,
  i / 17.0,
  _blob(i, 15),
  _text(i, 16, textMode),
  i + 17,
  i / 19.0,
  _blob(i, 19),
];

String _text(int row, int column, _TextMode mode) => switch (mode) {
  _TextMode.ascii => 'text_${row}_$column',
  _TextMode.unicode => 'cafe_${row}_${column}_\u00e9_\u0416',
  _TextMode.emoji => 'emoji_${row}_${column}_\u{1f680}_\u{1f9ea}',
};

Uint8List _blob(int row, int salt) =>
    Uint8List.fromList([row & 0xff, (row >> 8) & 0xff, salt, 0x5a]);

String _renderMarkdown(List<_TransactionShapeRow> rows, int repeats) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 131 - Wide Batch Transaction Shape');
  buf.writeln();
  buf.writeln(
    'Profile harness: `benchmark/profile/wide_batch_transaction_shape.dart`',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/wide_batch_transaction_shape.dart --markdown '
    '--repeats=$repeats',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| pass | workload | scenario | wall_ms | native_total_us | '
    'batch_call_us | param_pack_us | tx_begin_us | tx_commit_us | stmt_us | '
    'bind_us | step_us | reset_us | residual_us | preupdate_us | sets |',
  );
  buf.writeln(
    '|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.scenario} | '
      '${row.wallMs.toStringAsFixed(2)} | ${row.nativeTotalUs} | '
      '${row.batchNativeUs} | ${row.paramPackUs} | ${row.txBeginUs} | '
      '${row.txCommitUs} | ${row.nativeStmtUs} | ${row.nativeBindUs} | '
      '${row.nativeStepUs} | ${row.nativeResetUs} | '
      '${row.nativeResidualUs} | ${row.nativePreupdateUs} | '
      '${row.setCount} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived split');
  buf.writeln();
  buf.writeln(
    '| pass | workload | scenario | bind / native | step / native | '
    'commit / native | reset / native | residual / native | '
    'preupdate / step |',
  );
  buf.writeln('|---:|---|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.scenario} | '
      '${row.pctOfNativeTotal(row.nativeBindUs).toStringAsFixed(2)}% | '
      '${row.pctOfNativeTotal(row.nativeStepUs).toStringAsFixed(2)}% | '
      '${row.pctOfNativeTotal(row.txCommitUs).toStringAsFixed(2)}% | '
      '${row.pctOfNativeTotal(row.nativeResetUs).toStringAsFixed(2)}% | '
      '${row.pctOfNativeTotal(row.nativeResidualUs).toStringAsFixed(2)}% | '
      '${row.pctOfStep(row.nativePreupdateUs).toStringAsFixed(2)}% |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `top-level batch` calls `resqlite_run_batch_profiled`, so '
    '`batch_call_us` includes the profiled native BEGIN and COMMIT.',
  );
  buf.writeln(
    '- `manual tx + nested batch` calls native BEGIN, '
    '`resqlite_run_batch_nested_profiled`, then native COMMIT. Its '
    '`batch_call_us` is row-loop work without transaction-control wall; '
    '`native_total_us` adds the external BEGIN/COMMIT stopwatches back in.',
  );
  buf.writeln(
    '- Both scenarios bypass writer-isolate and stream invalidation overhead; '
    'this is a native transaction-shape audit, not an end-to-end API benchmark.',
  );
  return buf.toString();
}
