// ignore_for_file: avoid_print
//
// Writer wall split audit - exp 123.
//
// This profile harness consumes the writer timing counters added for exp 123:
// main-isolate writer roundtrip, worker write-call wall, dirty-dependency
// fetch wall, and the existing invalidation counters. It answers whether the
// next writer/stream optimization should target native-write work,
// Dart/isolate dispatch overhead, dirty dependency fetch, or StreamEngine
// invalidation.
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/writer_wall_split_audit.dart --markdown

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';

import 'audit_workloads.dart';

final class _WriterWallRow {
  _WriterWallRow({
    required this.pass,
    required this.workload,
    required this.shape,
    required this.wallUs,
    required this.counters,
  });

  factory _WriterWallRow.fromScenario(int pass, AuditScenarioResult r) =>
      _WriterWallRow(
        pass: pass,
        workload: r.workload,
        shape: r.shape,
        wallUs: r.wallUs,
        counters: r.counters,
      );

  final int pass;
  final String workload;
  final String shape;
  final int wallUs;
  final Map<String, int> counters;

  int get requestCount => counters['writer_request_count']!;
  int get roundtripUs => counters['writer_roundtrip_us']!;
  int get writeCallUs => counters['writer_write_call_us']!;
  int get dirtyFetchUs => counters['writer_dirty_fetch_us']!;
  int get invalidateUs => counters['invalidate_us']!;
  int get invalidateCount => counters['invalidate_count']!;

  int get nonWriteResidualUs {
    final residual = roundtripUs - writeCallUs - dirtyFetchUs;
    return residual < 0 ? 0 : residual;
  }

  double get wallMs => wallUs / 1000.0;
  double get roundtripPerRequestUs =>
      requestCount == 0 ? 0.0 : roundtripUs / requestCount;

  double pctOfWall(int value) => wallUs == 0 ? 0.0 : (value / wallUs) * 100.0;
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
  final rows = <_WriterWallRow>[];

  for (var pass = 1; pass <= repeats; pass++) {
    rows.addAll(
      (await _runA11cAudit()).map(
        (row) => _WriterWallRow.fromScenario(pass, row),
      ),
    );
    rows.add(_WriterWallRow.fromScenario(pass, await runKeyedPkScenario()));
    rows.add(await _runWideBatchAudit(pass));
  }

  final markdown = _renderMarkdown(rows, repeats);
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-123-writer-wall-split-aggregate.md',
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

Future<List<AuditScenarioResult>> _runA11cAudit() async {
  final setup = await setupA11cDb(prefix: 'writer_wall_split_a11c_');
  try {
    return [
      await runA11cScenario(
        setup.db,
        name: 'A11c baseline',
        streamCount: 0,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'b$writeIndex',
      ),
      await runA11cScenario(
        setup.db,
        name: 'A11c disjoint',
        streamCount: a11cStreamCount,
        updateSql: 'UPDATE wide SET c = ? WHERE id = ?',
        valueFor: (writeIndex) => 'd$writeIndex',
      ),
      await runA11cScenario(
        setup.db,
        name: 'A11c overlap',
        streamCount: a11cStreamCount,
        updateSql: 'UPDATE wide SET a = ? WHERE id = ?',
        valueFor: (writeIndex) => 'o$writeIndex',
      ),
    ];
  } finally {
    await setup.db.close();
    await setup.tempDir.delete(recursive: true);
  }
}

Future<_WriterWallRow> _runWideBatchAudit(int pass) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'writer_wall_split_wide_batch_',
  );
  final db = await Database.open('${tempDir.path}/test.db');
  try {
    await db.execute(_wideBatchCreateSql);

    final rows = [for (var i = 0; i < 10000; i++) _wideBatchRow(i)];

    ProfileCounters.reset();
    final sw = Stopwatch()..start();
    await db.executeBatch(_wideBatchInsertSql, rows);
    sw.stop();
    final counters = ProfileCounters.snapshot();

    return _WriterWallRow(
      pass: pass,
      workload: 'Wide batch insert',
      shape: '10000 rows x 20 params',
      wallUs: sw.elapsedMicroseconds,
      counters: counters,
    );
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
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

List<Object?> _wideBatchRow(int i) => [
      'text_${i}_0',
      i,
      i / 3.0,
      _blob(i, 3),
      'text_${i}_4',
      i + 5,
      i / 7.0,
      _blob(i, 7),
      'text_${i}_8',
      i + 9,
      i / 11.0,
      _blob(i, 11),
      'text_${i}_12',
      i + 13,
      i / 17.0,
      _blob(i, 15),
      'text_${i}_16',
      i + 17,
      i / 19.0,
      _blob(i, 19),
    ];

Uint8List _blob(int row, int salt) =>
    Uint8List.fromList([row & 0xff, (row >> 8) & 0xff, salt, 0x5a]);

String _renderMarkdown(List<_WriterWallRow> rows, int repeats) {
  final readerCount = readerPoolSize();
  final buf = StringBuffer();
  buf.writeln('# Experiment 123 - Writer Wall Split Audit');
  buf.writeln();
  buf.writeln(
    'Profile-mode harness: '
    '`benchmark/profile/writer_wall_split_audit.dart`',
  );
  buf.writeln();
  buf.writeln(
    'Reader pool size: $readerCount '
    '(`(Platform.numberOfProcessors - 1).clamp(2, 4)`)',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/writer_wall_split_audit.dart --markdown '
    '--repeats=$repeats',
  );
  buf.writeln('```');
  buf.writeln();
  buf.writeln('## Counters');
  buf.writeln();
  buf.writeln(
    '| pass | workload | shape | wall_ms | writer_requests | writer_roundtrip_us | '
    'writer_write_call_us | dirty_fetch_us | invalidate_us | '
    'invalidate_count |',
  );
  buf.writeln('|---:|---|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.shape} | ${row.wallMs.toStringAsFixed(2)} | '
      '${row.requestCount} | ${row.roundtripUs} | ${row.writeCallUs} | '
      '${row.dirtyFetchUs} | ${row.invalidateUs} | ${row.invalidateCount} |',
    );
  }
  buf.writeln();
  buf.writeln('## Derived split');
  buf.writeln();
  buf.writeln(
    '| pass | workload | roundtrip / wall | write call / roundtrip | '
    'dirty fetch / roundtrip | residual / roundtrip | invalidate / wall | '
    'us per writer request |',
  );
  buf.writeln('|---:|---|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.pctOfWall(row.roundtripUs).toStringAsFixed(2)}% | '
      '${row.pctOfRoundtrip(row.writeCallUs).toStringAsFixed(2)}% | '
      '${row.pctOfRoundtrip(row.dirtyFetchUs).toStringAsFixed(2)}% | '
      '${row.pctOfRoundtrip(row.nonWriteResidualUs).toStringAsFixed(2)}% | '
      '${row.pctOfWall(row.invalidateUs).toStringAsFixed(2)}% | '
      '${row.roundtripPerRequestUs.toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `writer_roundtrip_us` is measured on the main isolate around each '
    'writer request after the caller has entered the writer lock where '
    'applicable. It includes message copy/delivery, writer scheduling, '
    'worker execution, dirty-dependency fetch, and the reply.',
  );
  buf.writeln(
    '- `writer_write_call_us` is measured on the writer isolate around '
    '`executeWrite` / `executeBatchWrite`. It includes Dart parameter '
    'packing plus the FFI/native write call.',
  );
  buf.writeln(
    '- SQLite statement trace timing was researched for this experiment, '
    'but this build intentionally compiles SQLite with `SQLITE_OMIT_TRACE`. '
    'Changing that compile flag would alter the production SQLite build '
    'rather than adding a profile-only Dart counter.',
  );
  buf.writeln(
    '- `residual / roundtrip` is the remainder after subtracting write-call '
    'and dirty-fetch wall from main-isolate roundtrip wall. Treat it as '
    'isolate messaging, event-loop scheduling, reply copy, and small '
    'measurement skew.',
  );
  buf.writeln(
    '- `invalidate_us` is the existing `StreamEngine.onDependencyChanges` '
    'counter. It is outside writer roundtrip and is reported as a share '
    'of workload wall.',
  );
  return buf.toString();
}
