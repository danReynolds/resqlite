// ignore_for_file: avoid_print
//
// Wide-batch WAL checkpoint audit - exp 132 candidate.
//
// Splits the profiled COMMIT bucket into the passive checkpoint work hidden
// inside the writer wal hook, then compares the current 500-page threshold with
// deferred checkpoint policies. Run with:
//
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/wide_batch_wal_checkpoint.dart --markdown

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/profile_mode.dart';

final class _CheckpointScenario {
  const _CheckpointScenario(this.label, this.pages);

  final String label;
  final int pages;
}

final class _CheckpointProfileRow {
  _CheckpointProfileRow({
    required this.pass,
    required this.workload,
    required this.scenario,
    required this.wallUs,
    required this.profile,
    required this.walBytesAfterBatch,
    required this.manualPassiveCheckpointUs,
  });

  final int pass;
  final String workload;
  final String scenario;
  final int wallUs;
  final BatchWriteProfile profile;
  final int walBytesAfterBatch;
  final int manualPassiveCheckpointUs;

  int get commitMinusCheckpointUs {
    final result = profile.nativeTxCommitUs - profile.nativeCheckpointUs;
    return result < 0 ? 0 : result;
  }

  double get wallMs => wallUs / 1000.0;
}

final class _ReaderGuardrailRow {
  _ReaderGuardrailRow({
    required this.scenario,
    required this.writeWallUs,
    required this.readCount,
    required this.readMedianUs,
    required this.readP90Us,
    required this.readMaxUs,
    required this.walBytesAfterWrites,
    required this.manualPassiveCheckpointUs,
  });

  final String scenario;
  final int writeWallUs;
  final int readCount;
  final int readMedianUs;
  final int readP90Us;
  final int readMaxUs;
  final int walBytesAfterWrites;
  final int manualPassiveCheckpointUs;
}

final class _StreamGuardrailRow {
  _StreamGuardrailRow({
    required this.scenario,
    required this.expectedEmissions,
    required this.observedEmissions,
    required this.finalCount,
    required this.writeWallUs,
  });

  final String scenario;
  final int expectedEmissions;
  final int observedEmissions;
  final int finalCount;
  final int writeWallUs;
}

final class _SustainedProfileRow {
  _SustainedProfileRow({
    required this.scenario,
    required this.batchCount,
    required this.rowsPerBatch,
    required this.totalWallUs,
    required this.batchMedianUs,
    required this.batchP90Us,
    required this.batchMaxUs,
    required this.maxCommitUs,
    required this.checkpointedBatches,
    required this.totalCheckpointUs,
    required this.maxCheckpointUs,
    required this.maxWalPages,
    required this.walBytesAfterWrites,
    required this.manualPassiveCheckpointUs,
  });

  final String scenario;
  final int batchCount;
  final int rowsPerBatch;
  final int totalWallUs;
  final int batchMedianUs;
  final int batchP90Us;
  final int batchMaxUs;
  final int maxCommitUs;
  final int checkpointedBatches;
  final int totalCheckpointUs;
  final int maxCheckpointUs;
  final int maxWalPages;
  final int walBytesAfterWrites;
  final int manualPassiveCheckpointUs;
}

const _scenarios = [
  _CheckpointScenario('baseline hook (500 pages)', 500),
  _CheckpointScenario('candidate hook (1000 pages)', 1000),
  _CheckpointScenario('defer hook (5000 pages)', 5000),
  _CheckpointScenario('disable hook checkpoint', 0),
];

const _sustainedScenarios = [
  _CheckpointScenario('baseline hook (500 pages)', 500),
  _CheckpointScenario('candidate hook (1000 pages)', 1000),
  _CheckpointScenario('2000-page hook', 2000),
  _CheckpointScenario('5000-page hook', 5000),
  _CheckpointScenario('disable hook checkpoint', 0),
];

Future<void> main(List<String> args) async {
  if (!kProfileMode) {
    stderr.writeln(
      'WARNING: kProfileMode=false; rerun with -DRESQLITE_PROFILE=true '
      'before comparing against other profile artifacts.',
    );
  }

  final writeMarkdown = args.contains('--markdown');
  final repeats = _readIntArg(args, '--repeats=', 5);
  final rows = _readIntArg(args, '--rows=', 10000);
  final profileRows = <_CheckpointProfileRow>[];

  for (var pass = 1; pass <= repeats; pass++) {
    for (final textMode in _TextMode.values) {
      for (final scenario in _scenarios) {
        profileRows.add(
          await _runProfilePass(
            pass: pass,
            rows: rows,
            textMode: textMode,
            scenario: scenario,
          ),
        );
      }
    }
  }

  final readerGuardrails = <_ReaderGuardrailRow>[];
  for (final scenario in _scenarios) {
    readerGuardrails.add(await _runReaderGuardrail(scenario));
  }

  final streamGuardrails = <_StreamGuardrailRow>[];
  for (final scenario in _scenarios) {
    streamGuardrails.add(await _runStreamGuardrail(scenario));
  }

  final sustainedProfiles = <_SustainedProfileRow>[];
  for (final scenario in _sustainedScenarios) {
    sustainedProfiles.add(await _runSustainedProfile(scenario));
  }

  final markdown = _renderMarkdown(
    profileRows: profileRows,
    readerGuardrails: readerGuardrails,
    streamGuardrails: streamGuardrails,
    sustainedProfiles: sustainedProfiles,
    repeats: repeats,
    rows: rows,
  );
  print(markdown);

  if (writeMarkdown) {
    final outFile = File(
      'benchmark/profile/results/exp-132-wide-batch-wal-checkpoint.md',
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

Future<_CheckpointProfileRow> _runProfilePass({
  required int pass,
  required int rows,
  required _TextMode textMode,
  required _CheckpointScenario scenario,
}) async {
  final prepared = await _openPreparedDb(scenario);
  final db = prepared.db;
  try {
    final paramSets = [
      for (var i = 0; i < rows; i++) _wideBatchRow(i, textMode),
    ];

    final sw = Stopwatch()..start();
    final profile = executeBatchWriteProfiled(
      db.handle,
      _wideBatchInsertSql,
      paramSets,
    );
    sw.stop();

    final walBytesAfterBatch = _walBytes(prepared.path);
    final manualPassiveCheckpointUs = await _timeAsync(
      () => db.execute('PRAGMA wal_checkpoint(PASSIVE)'),
    );

    return _CheckpointProfileRow(
      pass: pass,
      workload: textMode.label,
      scenario: scenario.label,
      wallUs: sw.elapsedMicroseconds,
      profile: profile,
      walBytesAfterBatch: walBytesAfterBatch,
      manualPassiveCheckpointUs: manualPassiveCheckpointUs,
    );
  } finally {
    await _closePreparedDb(prepared);
  }
}

Future<_ReaderGuardrailRow> _runReaderGuardrail(
  _CheckpointScenario scenario,
) async {
  const batchCount = 8;
  const rowsPerBatch = 2000;
  final prepared = await _openPreparedDb(scenario);
  final db = prepared.db;
  var running = true;
  final readLatencies = <int>[];

  final readerDone = () async {
    while (running) {
      final readUs = await _timeAsync(
        () => db.select('SELECT COUNT(*) AS c FROM wide_batch'),
      );
      readLatencies.add(readUs);
      await Future<void>.delayed(Duration.zero);
    }
  }();

  try {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final writeSw = Stopwatch()..start();
    for (var batch = 0; batch < batchCount; batch++) {
      final offset = batch * rowsPerBatch;
      final paramSets = [
        for (var i = 0; i < rowsPerBatch; i++)
          _wideBatchRow(offset + i, _TextMode.emoji),
      ];
      await db.executeBatch(_wideBatchInsertSql, paramSets);
    }
    writeSw.stop();

    running = false;
    await readerDone;

    final walBytesAfterWrites = _walBytes(prepared.path);
    final manualPassiveCheckpointUs = await _timeAsync(
      () => db.execute('PRAGMA wal_checkpoint(PASSIVE)'),
    );

    return _ReaderGuardrailRow(
      scenario: scenario.label,
      writeWallUs: writeSw.elapsedMicroseconds,
      readCount: readLatencies.length,
      readMedianUs: _percentile(readLatencies, 50),
      readP90Us: _percentile(readLatencies, 90),
      readMaxUs: readLatencies.isEmpty ? 0 : readLatencies.reduce(_max),
      walBytesAfterWrites: walBytesAfterWrites,
      manualPassiveCheckpointUs: manualPassiveCheckpointUs,
    );
  } finally {
    running = false;
    await readerDone;
    await _closePreparedDb(prepared);
  }
}

Future<_StreamGuardrailRow> _runStreamGuardrail(
  _CheckpointScenario scenario,
) async {
  const batchCount = 5;
  const rowsPerBatch = 500;
  final prepared = await _openPreparedDb(scenario);
  final db = prepared.db;
  final emissions = <int>[];
  late final StreamSubscription<List<Map<String, Object?>>> subscription;
  subscription = db
      .stream('SELECT COUNT(*) AS c FROM wide_batch')
      .listen((rows) => emissions.add(rows.first['c'] as int));

  try {
    await _waitFor(() => emissions.length >= 1);
    final writeSw = Stopwatch()..start();
    for (var batch = 0; batch < batchCount; batch++) {
      final offset = batch * rowsPerBatch;
      final paramSets = [
        for (var i = 0; i < rowsPerBatch; i++)
          _wideBatchRow(offset + i, _TextMode.ascii),
      ];
      await db.executeBatch(_wideBatchInsertSql, paramSets);
      await _waitFor(() => emissions.length >= batch + 2);
    }
    writeSw.stop();

    return _StreamGuardrailRow(
      scenario: scenario.label,
      expectedEmissions: batchCount + 1,
      observedEmissions: emissions.length,
      finalCount: emissions.isEmpty ? -1 : emissions.last,
      writeWallUs: writeSw.elapsedMicroseconds,
    );
  } finally {
    await subscription.cancel();
    await _closePreparedDb(prepared);
  }
}

Future<_SustainedProfileRow> _runSustainedProfile(
  _CheckpointScenario scenario,
) async {
  const batchCount = 60;
  const rowsPerBatch = 2000;
  final prepared = await _openPreparedDb(scenario);
  final db = prepared.db;
  final batchWalls = <int>[];
  var checkpointedBatches = 0;
  var totalCheckpointUs = 0;
  var maxCheckpointUs = 0;
  var maxCommitUs = 0;
  var maxWalPages = 0;

  try {
    final totalSw = Stopwatch()..start();
    for (var batch = 0; batch < batchCount; batch++) {
      final offset = batch * rowsPerBatch;
      final paramSets = [
        for (var i = 0; i < rowsPerBatch; i++)
          _wideBatchRow(offset + i, _TextMode.emoji),
      ];
      final batchSw = Stopwatch()..start();
      final profile = executeBatchWriteProfiled(
        db.handle,
        _wideBatchInsertSql,
        paramSets,
      );
      batchSw.stop();
      batchWalls.add(batchSw.elapsedMicroseconds);

      if (profile.nativeCheckpointCount > 0) checkpointedBatches++;
      totalCheckpointUs += profile.nativeCheckpointUs;
      maxCheckpointUs = _max(maxCheckpointUs, profile.nativeCheckpointUs);
      maxCommitUs = _max(maxCommitUs, profile.nativeTxCommitUs);
      maxWalPages = _max(maxWalPages, profile.nativeWalPagesMax);
    }
    totalSw.stop();

    final walBytesAfterWrites = _walBytes(prepared.path);
    final manualPassiveCheckpointUs = await _timeAsync(
      () => db.execute('PRAGMA wal_checkpoint(PASSIVE)'),
    );

    return _SustainedProfileRow(
      scenario: scenario.label,
      batchCount: batchCount,
      rowsPerBatch: rowsPerBatch,
      totalWallUs: totalSw.elapsedMicroseconds,
      batchMedianUs: _percentile(batchWalls, 50),
      batchP90Us: _percentile(batchWalls, 90),
      batchMaxUs: batchWalls.isEmpty ? 0 : batchWalls.reduce(_max),
      maxCommitUs: maxCommitUs,
      checkpointedBatches: checkpointedBatches,
      totalCheckpointUs: totalCheckpointUs,
      maxCheckpointUs: maxCheckpointUs,
      maxWalPages: maxWalPages,
      walBytesAfterWrites: walBytesAfterWrites,
      manualPassiveCheckpointUs: manualPassiveCheckpointUs,
    );
  } finally {
    await _closePreparedDb(prepared);
  }
}

Future<void> _waitFor(bool Function() condition) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > const Duration(seconds: 5)) {
      throw StateError('Timed out waiting for stream guardrail emission');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<int> _timeAsync(Future<dynamic> Function() call) async {
  final sw = Stopwatch()..start();
  await call();
  sw.stop();
  return sw.elapsedMicroseconds;
}

typedef _PreparedDb = ({Database db, Directory tempDir, String path});

Future<_PreparedDb> _openPreparedDb(_CheckpointScenario scenario) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'wide_batch_wal_checkpoint_',
  );
  final path = '${tempDir.path}/test.db';
  final db = await Database.open(path);
  try {
    setWriterCheckpointPagesForProfile(db.handle, scenario.pages);
    await db.execute(_wideBatchCreateSql);
    return (db: db, tempDir: tempDir, path: path);
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

int _walBytes(String dbPath) {
  final wal = File('$dbPath-wal');
  return wal.existsSync() ? wal.lengthSync() : 0;
}

int _percentile(List<int> values, int pct) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * pct / 100).round();
  return sorted[index];
}

int _max(int a, int b) => a > b ? a : b;

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

String _renderMarkdown({
  required List<_CheckpointProfileRow> profileRows,
  required List<_ReaderGuardrailRow> readerGuardrails,
  required List<_StreamGuardrailRow> streamGuardrails,
  required List<_SustainedProfileRow> sustainedProfiles,
  required int repeats,
  required int rows,
}) {
  final buf = StringBuffer();
  buf.writeln('# Experiment 132 - Wide Batch WAL Checkpoint Audit');
  buf.writeln();
  buf.writeln(
    'Profile harness: `benchmark/profile/wide_batch_wal_checkpoint.dart`',
  );
  buf.writeln();
  buf.writeln('Command:');
  buf.writeln();
  buf.writeln('```text');
  buf.writeln(
    'dart run -DRESQLITE_PROFILE=true '
    'benchmark/profile/wide_batch_wal_checkpoint.dart --markdown '
    '--repeats=$repeats --rows=$rows',
  );
  buf.writeln('```');
  buf.writeln();
  _renderAggregateTable(buf, profileRows);
  _renderRawProfileRows(buf, profileRows);
  _renderReaderGuardrails(buf, readerGuardrails);
  _renderStreamGuardrails(buf, streamGuardrails);
  _renderSustainedProfiles(buf, sustainedProfiles);
  buf.writeln('## Reading the table');
  buf.writeln();
  buf.writeln(
    '- `checkpoint_us` is measured inside the native wal hook, so it is also '
    'included in `commit_us`.',
  );
  buf.writeln(
    '- `manual_passive_checkpoint_us` is the deferred cleanup cost paid after '
    'the measured write when the hook did not checkpoint during COMMIT.',
  );
  buf.writeln(
    '- Reader and stream guardrails use the public `Database` API path; profile '
    'rows use the native profile helper directly to isolate SQLite-side wall.',
  );
  buf.writeln(
    '- The sustained sweep repeats 60 emoji batches of 2,000 rows on one '
    'connection to expose periodic checkpoint tail latency.',
  );
  return buf.toString();
}

void _renderAggregateTable(StringBuffer buf, List<_CheckpointProfileRow> rows) {
  buf.writeln('## Median profile');
  buf.writeln();
  buf.writeln(
    '| workload | scenario | wall_ms | native_us | commit_us | '
    'checkpoint_us | commit_minus_checkpoint_us | wal_pages_max | '
    'wal_bytes | manual_checkpoint_us |',
  );
  buf.writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  final groups =
      <({String workload, String scenario}), List<_CheckpointProfileRow>>{};
  for (final row in rows) {
    groups
        .putIfAbsent((workload: row.workload, scenario: row.scenario), () => [])
        .add(row);
  }
  for (final entry in groups.entries) {
    final groupRows = entry.value;
    buf.writeln(
      '| ${entry.key.workload} | ${entry.key.scenario} | '
      '${(_median(groupRows.map((r) => r.wallUs)) / 1000.0).toStringAsFixed(2)} | '
      '${_median(groupRows.map((r) => r.profile.nativeWriteUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeTxCommitUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeCheckpointUs))} | '
      '${_median(groupRows.map((r) => r.commitMinusCheckpointUs))} | '
      '${_median(groupRows.map((r) => r.profile.nativeWalPagesMax))} | '
      '${_median(groupRows.map((r) => r.walBytesAfterBatch))} | '
      '${_median(groupRows.map((r) => r.manualPassiveCheckpointUs))} |',
    );
  }
  buf.writeln();
}

void _renderRawProfileRows(StringBuffer buf, List<_CheckpointProfileRow> rows) {
  buf.writeln('## Raw profile rows');
  buf.writeln();
  buf.writeln(
    '| pass | workload | scenario | wall_ms | native_us | commit_us | '
    'checkpoint_us | commit_minus_checkpoint_us | wal_hook_count | '
    'wal_pages_max | checkpoint_count | checkpoint_busy_count | '
    'checkpoint_pages | wal_bytes | manual_checkpoint_us |',
  );
  buf.writeln(
    '|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.pass} | ${row.workload} | ${row.scenario} | '
      '${row.wallMs.toStringAsFixed(2)} | ${row.profile.nativeWriteUs} | '
      '${row.profile.nativeTxCommitUs} | '
      '${row.profile.nativeCheckpointUs} | '
      '${row.commitMinusCheckpointUs} | '
      '${row.profile.nativeWalHookCount} | '
      '${row.profile.nativeWalPagesMax} | '
      '${row.profile.nativeCheckpointCount} | '
      '${row.profile.nativeCheckpointBusyCount} | '
      '${row.profile.nativeCheckpointPages} | '
      '${row.walBytesAfterBatch} | ${row.manualPassiveCheckpointUs} |',
    );
  }
  buf.writeln();
}

void _renderReaderGuardrails(StringBuffer buf, List<_ReaderGuardrailRow> rows) {
  buf.writeln('## Concurrent reader guardrail');
  buf.writeln();
  buf.writeln(
    '| scenario | write_wall_ms | read_count | read_median_us | read_p90_us | '
    'read_max_us | wal_bytes | manual_checkpoint_us |',
  );
  buf.writeln('|---|---:|---:|---:|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.scenario} | ${(row.writeWallUs / 1000.0).toStringAsFixed(2)} | '
      '${row.readCount} | ${row.readMedianUs} | ${row.readP90Us} | '
      '${row.readMaxUs} | ${row.walBytesAfterWrites} | '
      '${row.manualPassiveCheckpointUs} |',
    );
  }
  buf.writeln();
}

void _renderStreamGuardrails(StringBuffer buf, List<_StreamGuardrailRow> rows) {
  buf.writeln('## Stream guardrail');
  buf.writeln();
  buf.writeln(
    '| scenario | expected_emissions | observed_emissions | final_count | '
    'write_wall_ms |',
  );
  buf.writeln('|---|---:|---:|---:|---:|');
  for (final row in rows) {
    buf.writeln(
      '| ${row.scenario} | ${row.expectedEmissions} | '
      '${row.observedEmissions} | ${row.finalCount} | '
      '${(row.writeWallUs / 1000.0).toStringAsFixed(2)} |',
    );
  }
  buf.writeln();
}

void _renderSustainedProfiles(
  StringBuffer buf,
  List<_SustainedProfileRow> rows,
) {
  buf.writeln('## Sustained checkpoint sweep');
  buf.writeln();
  buf.writeln(
    '| scenario | batches | rows_per_batch | total_wall_ms | batch_median_us | '
    'batch_p90_us | batch_max_us | max_commit_us | checkpointed_batches | '
    'total_checkpoint_us | max_checkpoint_us | max_wal_pages | wal_bytes | '
    'manual_checkpoint_us |',
  );
  buf.writeln(
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
  );
  for (final row in rows) {
    buf.writeln(
      '| ${row.scenario} | ${row.batchCount} | ${row.rowsPerBatch} | '
      '${(row.totalWallUs / 1000.0).toStringAsFixed(2)} | '
      '${row.batchMedianUs} | ${row.batchP90Us} | ${row.batchMaxUs} | '
      '${row.maxCommitUs} | ${row.checkpointedBatches} | '
      '${row.totalCheckpointUs} | ${row.maxCheckpointUs} | '
      '${row.maxWalPages} | ${row.walBytesAfterWrites} | '
      '${row.manualPassiveCheckpointUs} |',
    );
  }
  buf.writeln();
}

int _median(Iterable<int> values) => _percentile(values.toList(), 50);
