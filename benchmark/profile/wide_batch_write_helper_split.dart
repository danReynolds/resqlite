// ignore_for_file: avoid_print
//
// Wide-batch write-helper split audit - exp 129.
//
// Splits the wide executeBatch helper wall into Dart parameter-matrix packing
// versus the native resqlite_run_batch* call. Run with:
//
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/wide_batch_write_helper_split.dart --markdown

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

final class _WideBatchRow {
  _WideBatchRow({
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

  int get requestCount => counters['writer_request_count']!;
  int get roundtripUs => counters['writer_roundtrip_us']!;
  int get writeCallUs => counters['writer_write_call_us']!;
  int get paramPackUs => counters['writer_batch_param_pack_us']!;
  int get nativeWriteUs => counters['writer_batch_native_write_us']!;
  int get dirtyFetchUs => counters['writer_dirty_fetch_us']!;

  int get writeResidualUs {
    final residual = writeCallUs - paramPackUs - nativeWriteUs;
    return residual < 0 ? 0 : residual;
  }

  int get roundtripResidualUs {
    final residual = roundtripUs - writeCallUs - dirtyFetchUs;
    return residual < 0 ? 0 : residual;
  }

  double get wallMs => wallUs / 1000.0;
  double pctOfWall(int value) => wallUs == 0 ? 0.0 : (value / wallUs) * 100.0;
  double pctOfWrite(int value) =>
      writeCallUs == 0 ? 0.0 : (value / writeCallUs) * 100.0;
  double pctOfRoundtrip(int value) =>
      roundtripUs == 0 ? 0.0 : (value / roundtripUs) * 100.0;
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
  final rows = <_WideBatchRow>[];

  for (var pass = 1; pass <= repeats; pass++) {
    rows.add(await _runWideBatchAudit(pass, _TextMode.ascii));
    rows.add(await _runWideBatchAudit(pass, _TextMode.unicode));
    rows.add(await _runWideBatchAudit(pass, _TextMode.emoji));
  }

  final markdown = _renderMarkdown(rows, repeats);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-129-wide-batch-helper-split.md',
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
  return 3;
}

Future<_WideBatchRow> _runWideBatchAudit(int pass, _TextMode textMode) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'wide_batch_write_helper_split_',
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

    return _WideBatchRow(
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

String _renderMarkdown(List<_WideBatchRow> rows, int repeats) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 129 - Wide Batch Write Helper Split');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/wide_batch_write_helper_split.dart`',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/wide_batch_write_helper_split.dart --markdown '
    '--repeats=$repeats',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| pass | workload | shape | wall_ms | writer_requests | '
    'roundtrip_us | write_call_us | param_pack_us | native_write_us | '
    'write_residual_us | dirty_fetch_us | roundtrip_residual_us |',
  );
  buf.writeln('|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.shape} | '
      '${row.wallMs.toStringAsFixed(2)} | ${row.requestCount} | '
      '${row.roundtripUs} | ${row.writeCallUs} | ${row.paramPackUs} | '
      '${row.nativeWriteUs} | ${row.writeResidualUs} | ${row.dirtyFetchUs} | '
      '${row.roundtripResidualUs} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived split');
  buf.writeln();
  buf.writeln(
    '| pass | workload | roundtrip / wall | write call / roundtrip | '
    'param pack / write call | native write / write call | '
    'write residual / write call | param pack / wall | native write / wall |',
  );
  buf.writeln('|---:|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | '
      '${row.pctOfWall(row.roundtripUs).toStringAsFixed(2)}% | '
      '${row.pctOfRoundtrip(row.writeCallUs).toStringAsFixed(2)}% | '
      '${row.pctOfWrite(row.paramPackUs).toStringAsFixed(2)}% | '
      '${row.pctOfWrite(row.nativeWriteUs).toStringAsFixed(2)}% | '
      '${row.pctOfWrite(row.writeResidualUs).toStringAsFixed(2)}% | '
      '${row.pctOfWall(row.paramPackUs).toStringAsFixed(2)}% | '
      '${row.pctOfWall(row.nativeWriteUs).toStringAsFixed(2)}% |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `param_pack_us` is Dart-side batch matrix construction: row walking, '
    'string byte measurement/encoding, blob copying, struct writes, and the '
    'single native buffer allocation.',
  );
  buf.writeln(
    '- `native_write_us` is the `resqlite_run_batch*` call after params are '
    'packed: SQLite transaction control, binding, stepping, and statement '
    'reset work.',
  );
  buf.writeln(
    '- `write_residual_us` is the remainder inside the write helper, mostly '
    'Dart wrapper overhead and freeing the packed parameter buffer.',
  );
  return buf.toString();
}
