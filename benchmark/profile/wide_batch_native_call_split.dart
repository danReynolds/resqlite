// ignore_for_file: avoid_print
//
// Wide-batch native-call split audit - exp 130.
//
// Splits the native resqlite_run_batch* call into statement lookup/prepare,
// transaction control, bind, step, reset, and preupdate-hook wall. Run with:
//
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/wide_batch_native_call_split.dart --markdown

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

final class _NativeSplitRow {
  _NativeSplitRow({
    required this.pass,
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.counters,
  });

  final int pass;
  final String workload;
  final String shape;
  final int wallUs;
  final Map<String, int> counters;

  int get writeCallUs => counters['writer_write_call_us']!;
  int get nativeWriteUs => counters['writer_batch_native_write_us']!;
  int get stmtUs => counters['writer_batch_native_stmt_us']!;
  int get txBeginUs => counters['writer_batch_native_tx_begin_us']!;
  int get txCommitUs => counters['writer_batch_native_tx_commit_us']!;
  int get txRollbackUs => counters['writer_batch_native_tx_rollback_us']!;
  int get bindUs => counters['writer_batch_native_bind_us']!;
  int get stepUs => counters['writer_batch_native_step_us']!;
  int get resetUs => counters['writer_batch_native_reset_us']!;
  int get preupdateUs => counters['writer_batch_native_preupdate_us']!;
  int get setCount => counters['writer_batch_native_set_count']!;
  int get bindCount => counters['writer_batch_native_bind_count']!;
  int get stepCount => counters['writer_batch_native_step_count']!;
  int get resetCount => counters['writer_batch_native_reset_count']!;
  int get preupdateCount => counters['writer_batch_native_preupdate_count']!;

  int get txUs => txBeginUs + txCommitUs + txRollbackUs;
  int get measuredNativeUs => stmtUs + txUs + bindUs + stepUs + resetUs;
  int get nativeResidualUs {
    final residual = nativeWriteUs - measuredNativeUs;
    return residual < 0 ? 0 : residual;
  }

  double get wallMs => wallUs / 1000.0;
  double pctOfNative(int value) =>
      nativeWriteUs == 0 ? 0.0 : (value / nativeWriteUs) * 100.0;
  double pctOfStep(int value) => stepUs == 0 ? 0.0 : (value / stepUs) * 100.0;
  double perSet(int value) => setCount == 0 ? 0.0 : value / setCount;
}

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; writer counters will stay zero. '
      'Rerun with -DRESQLITE_PROFILE=true.',
    );
  }

  final writeMarkdown = args.contains('--markdown');
  final repeats = _readRepeats(args);
  final rows = <_NativeSplitRow>[];

  for (var pass = 1; pass <= repeats; pass++) {
    rows.add(await _runWideBatchAudit(pass, _TextMode.ascii));
    rows.add(await _runWideBatchAudit(pass, _TextMode.unicode));
    rows.add(await _runWideBatchAudit(pass, _TextMode.emoji));
  }

  final markdown = _renderMarkdown(rows, repeats);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-130-wide-batch-native-call-split.md',
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

Future<_NativeSplitRow> _runWideBatchAudit(int pass, _TextMode textMode) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'wide_batch_native_call_split_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute(_wideBatchCreateSql);

    final rows = [for (var i = 0; i < 10000; i++) _wideBatchRow(i, textMode)];

    ProfileCounters.reset();
    final sw = Stopwatch()..start();
    await db.executeBatch(_wideBatchInsertSql, rows);
    sw.stop();
    final counters = ProfileCounters.snapshot();

    return _NativeSplitRow(
      pass: pass,
      workload: textMode.label,
      shape: '10000 rows x 20 params',
      wallUs: sw.elapsedMicroseconds,
      counters: counters,
    );
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
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

String _renderMarkdown(List<_NativeSplitRow> rows, int repeats) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 130 - Wide Batch Native Call Split');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/wide_batch_native_call_split.dart`',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/wide_batch_native_call_split.dart --markdown '
    '--repeats=$repeats',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| pass | workload | wall_ms | native_write_us | stmt_us | tx_begin_us | '
    'tx_commit_us | tx_rollback_us | bind_us | step_us | reset_us | '
    'native_residual_us | preupdate_us | sets | binds | steps | resets | '
    'preupdates |',
  );
  buf.writeln(
    '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.nativeWriteUs} | ${row.stmtUs} | ${row.txBeginUs} | '
      '${row.txCommitUs} | ${row.txRollbackUs} | '
      '${row.bindUs} | ${row.stepUs} | ${row.resetUs} | '
      '${row.nativeResidualUs} | ${row.preupdateUs} | ${row.setCount} | '
      '${row.bindCount} | ${row.stepCount} | ${row.resetCount} | '
      '${row.preupdateCount} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived split');
  buf.writeln();
  buf.writeln(
    '| pass | workload | bind / native | step / native | reset / native | '
    'tx begin / native | tx commit / native | stmt / native | '
    'residual / native | preupdate / step | bind_us / set | step_us / set | '
    'reset_us / set |',
  );
  buf.writeln(
    '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | '
      '${row.pctOfNative(row.bindUs).toStringAsFixed(2)}% | '
      '${row.pctOfNative(row.stepUs).toStringAsFixed(2)}% | '
      '${row.pctOfNative(row.resetUs).toStringAsFixed(2)}% | '
      '${row.pctOfNative(row.txBeginUs).toStringAsFixed(2)}% | '
      '${row.pctOfNative(row.txCommitUs).toStringAsFixed(2)}% | '
      '${row.pctOfNative(row.stmtUs).toStringAsFixed(2)}% | '
      '${row.pctOfNative(row.nativeResidualUs).toStringAsFixed(2)}% | '
      '${row.pctOfStep(row.preupdateUs).toStringAsFixed(2)}% | '
      '${row.perSet(row.bindUs).toStringAsFixed(3)} | '
      '${row.perSet(row.stepUs).toStringAsFixed(3)} | '
      '${row.perSet(row.resetUs).toStringAsFixed(3)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `bind_us`, `step_us`, and `reset_us` are summed inside the native '
    '10,000-row batch loop.',
  );
  buf.writeln(
    '- `tx_begin_us`, `tx_commit_us`, and `tx_rollback_us` are cached '
    'transaction-control statement wall for the top-level batch. Nested '
    'batches report zero transaction wall.',
  );
  buf.writeln(
    '- `preupdate_us` is measured inside SQLite preupdate callbacks and is a '
    'subset of `step_us`, not an additive bucket.',
  );
  buf.writeln(
    '- `native_residual_us` is the Dart-observed native call wall minus the '
    'measured native buckets. Treat it as FFI crossing, loop bookkeeping, '
    'clock skew, and measurement overhead.',
  );
  return buf.toString();
}
