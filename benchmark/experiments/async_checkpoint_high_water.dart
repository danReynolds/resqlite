// ignore_for_file: avoid_print
//
// Focused A/B harness for exp 250's high-water asynchronous checkpoint worker.
//
// Run this file unchanged on origin/main and the candidate checkout:
//
//   dart run benchmark/experiments/async_checkpoint_high_water.dart \
//     --label=baseline --repeats=5 --writes=3000
//
// The threshold lane reuses exp 132's 10k x 20 mixed-emoji batch, which
// produced 529 WAL pages and therefore crosses the current 500-page writer
// hook threshold in its first commit. The sustained lane uses awaited 8 KiB
// payload inserts so it crosses successive 500-page high-water deltas while
// periodically sampling foreground reads. SQLITE_CHECKPOINT_NOOP observes WAL
// progress without performing checkpoint work itself.

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';

const _defaultLabel = 'unlabeled';
const _defaultRepeats = 5;
const _defaultWrites = 3000;
const _defaultReadEvery = 100;
const _defaultSettleMs = 250;

const _wideBatchRows = 10000;
const _wideBatchParams = 20;
const _payloadBytes = 8192;
final _payload = 'x' * _payloadBytes;

Future<void> main(List<String> args) async {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('Argument error: ${error.message}');
    stderr.writeln('Use --help for usage.');
    exitCode = 64;
    return;
  }

  if (options.help) {
    print(_usage);
    return;
  }

  // Parameter construction is deliberately outside every timed region and is
  // shared across repeats. executeBatch only reads these values.
  final thresholdRows = [
    for (var i = 0; i < _wideBatchRows; i++) _wideBatchRow(i),
  ];

  final thresholdRuns = <_ThresholdRun>[];
  final sustainedRuns = <_SustainedRun>[];
  for (var repeat = 1; repeat <= options.repeats; repeat++) {
    thresholdRuns.add(
      await _runThresholdBatch(
        repeat: repeat,
        rows: thresholdRows,
        settle: options.settle,
      ),
    );
    sustainedRuns.add(
      await _runSustainedBurst(
        repeat: repeat,
        writes: options.writes,
        readEvery: options.readEvery,
        settle: options.settle,
      ),
    );
  }

  print(
    _renderMarkdown(
      options: options,
      thresholdRuns: thresholdRuns,
      sustainedRuns: sustainedRuns,
    ),
  );
}

Future<_ThresholdRun> _runThresholdBatch({
  required int repeat,
  required List<List<Object?>> rows,
  required Duration settle,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_exp250_threshold_',
  );
  try {
    final db = await Database.open('${tempDir.path}/threshold.db');
    try {
      await db.execute(_wideBatchCreateSql);

      final stopwatch = Stopwatch()..start();
      await db.executeBatch(_wideBatchInsertSql, rows);
      stopwatch.stop();

      final immediate = await _readWalState(db);
      await Future<void>.delayed(settle);
      final settled = await _readWalState(db);

      return _ThresholdRun(
        repeat: repeat,
        wallUs: stopwatch.elapsedMicroseconds,
        immediate: immediate,
        settled: settled,
      );
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<_SustainedRun> _runSustainedBurst({
  required int repeat,
  required int writes,
  required int readEvery,
  required Duration settle,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_exp250_sustained_',
  );
  try {
    final db = await Database.open('${tempDir.path}/sustained.db');
    try {
      await db.execute(_sustainedCreateSql);

      final writeUs = <int>[];
      final readUs = <int>[];
      for (var i = 0; i < writes; i++) {
        final writeStopwatch = Stopwatch()..start();
        await db.execute(_sustainedInsertSql, [_payload, i]);
        writeStopwatch.stop();
        writeUs.add(writeStopwatch.elapsedMicroseconds);

        final writeNumber = i + 1;
        if (writeNumber % readEvery == 0) {
          final readStopwatch = Stopwatch()..start();
          final rows = await db.select(_foregroundReadSql, [writeNumber - 100]);
          readStopwatch.stop();
          readUs.add(readStopwatch.elapsedMicroseconds);

          final expectedCount = writeNumber < 100 ? writeNumber : 100;
          final actualCount = rows.single['count'];
          if (actualCount != expectedCount) {
            throw StateError(
              'Foreground read returned $actualCount rows; '
              'expected $expectedCount.',
            );
          }
        }
      }

      final immediate = await _readWalState(db);
      await Future<void>.delayed(settle);
      final settled = await _readWalState(db);

      return _SustainedRun(
        repeat: repeat,
        writeUs: writeUs,
        readUs: readUs,
        immediate: immediate,
        settled: settled,
      );
    } finally {
      await db.close();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<_WalState> _readWalState(Database db) async {
  final rows = await db.select('PRAGMA wal_checkpoint(NOOP)');
  if (rows.length != 1) {
    throw StateError('Expected one WAL state row, got ${rows.length}.');
  }

  final row = rows.single;
  return _WalState(
    busy: _requireInt(row, 'busy'),
    log: _requireInt(row, 'log'),
    checkpointed: _requireInt(row, 'checkpointed'),
  );
}

int _requireInt(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is int) return value;
  throw StateError('Expected integer $key in WAL state row, got $value.');
}

String _renderMarkdown({
  required _Options options,
  required List<_ThresholdRun> thresholdRuns,
  required List<_SustainedRun> sustainedRuns,
}) {
  final output = StringBuffer()
    ..writeln('# Async checkpoint high-water benchmark (exp 250)')
    ..writeln()
    ..writeln(
      '| label | repeats | sustained writes / repeat | read every | settle window |',
    )
    ..writeln('|---|---:|---:|---:|---:|')
    ..writeln(
      '| ${_markdownCell(options.label)} '
      '| ${options.repeats} '
      '| ${options.writes} '
      '| ${options.readEvery} writes '
      '| ${options.settle.inMilliseconds} ms |',
    )
    ..writeln()
    ..writeln('## First 500-page threshold-crossing batch wall')
    ..writeln()
    ..writeln(
      'Known crossing shape: $_wideBatchRows rows x $_wideBatchParams '
      'mixed emoji parameters (529 WAL pages in exp 132).',
    )
    ..writeln()
    ..writeln('| label | samples | p50 ms | p95 ms | p99 ms | max ms |')
    ..writeln('|---|---:|---:|---:|---:|---:|');

  final thresholdWalls = [for (final run in thresholdRuns) run.wallUs];
  _writeLatencyRow(output, label: options.label, samples: thresholdWalls);

  output
    ..writeln()
    ..writeln('| repeat | wall ms |')
    ..writeln('|---:|---:|');
  for (final run in thresholdRuns) {
    output.writeln('| ${run.repeat} | ${_ms(run.wallUs)} |');
  }

  output
    ..writeln()
    ..writeln('## Sustained 8 KiB sequential write latency')
    ..writeln()
    ..writeln('| label | scope | samples | p50 ms | p95 ms | p99 ms | max ms |')
    ..writeln('|---|---|---:|---:|---:|---:|---:|');
  for (final run in sustainedRuns) {
    _writeLatencyRow(
      output,
      label: options.label,
      scope: 'repeat ${run.repeat}',
      samples: run.writeUs,
    );
  }
  _writeLatencyRow(
    output,
    label: options.label,
    scope: 'all repeats',
    samples: [for (final run in sustainedRuns) ...run.writeUs],
  );

  output
    ..writeln()
    ..writeln('## Foreground reads during the sustained burst')
    ..writeln()
    ..writeln('| label | scope | samples | p95 ms | max ms |')
    ..writeln('|---|---|---:|---:|---:|');
  for (final run in sustainedRuns) {
    _writeReadRow(
      output,
      label: options.label,
      scope: 'repeat ${run.repeat}',
      samples: run.readUs,
    );
  }
  _writeReadRow(
    output,
    label: options.label,
    scope: 'all repeats',
    samples: [for (final run in sustainedRuns) ...run.readUs],
  );

  output
    ..writeln()
    ..writeln('## WAL progress (observed with CHECKPOINT_NOOP)')
    ..writeln()
    ..writeln(
      '| phase | repeat | sample | busy | log | checkpointed | pending |',
    )
    ..writeln('|---|---:|---|---:|---:|---:|---:|');
  for (final run in thresholdRuns) {
    _writeWalRows(
      output,
      phase: 'threshold batch',
      repeat: run.repeat,
      immediate: run.immediate,
      settled: run.settled,
      settleMs: options.settle.inMilliseconds,
    );
  }
  for (final run in sustainedRuns) {
    _writeWalRows(
      output,
      phase: 'sustained burst',
      repeat: run.repeat,
      immediate: run.immediate,
      settled: run.settled,
      settleMs: options.settle.inMilliseconds,
    );
  }

  return output.toString().trimRight();
}

void _writeLatencyRow(
  StringBuffer output, {
  required String label,
  required List<int> samples,
  String? scope,
}) {
  final scopeCell = scope == null ? '' : '| ${_markdownCell(scope)} ';
  output.writeln(
    '| ${_markdownCell(label)} '
    '$scopeCell'
    '| ${samples.length} '
    '| ${_ms(_percentile(samples, 0.50))} '
    '| ${_ms(_percentile(samples, 0.95))} '
    '| ${_ms(_percentile(samples, 0.99))} '
    '| ${_ms(_percentile(samples, 1.00))} |',
  );
}

void _writeReadRow(
  StringBuffer output, {
  required String label,
  required String scope,
  required List<int> samples,
}) {
  output.writeln(
    '| ${_markdownCell(label)} '
    '| ${_markdownCell(scope)} '
    '| ${samples.length} '
    '| ${_ms(_percentile(samples, 0.95))} '
    '| ${_ms(_percentile(samples, 1.00))} |',
  );
}

void _writeWalRows(
  StringBuffer output, {
  required String phase,
  required int repeat,
  required _WalState immediate,
  required _WalState settled,
  required int settleMs,
}) {
  for (final entry in [
    (sample: 'immediate', state: immediate),
    (sample: 'after $settleMs ms', state: settled),
  ]) {
    final state = entry.state;
    output.writeln(
      '| $phase '
      '| $repeat '
      '| ${entry.sample} '
      '| ${state.busy} '
      '| ${state.log} '
      '| ${state.checkpointed} '
      '| ${state.pending} |',
    );
  }
}

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}

String _ms(int microseconds) => (microseconds / 1000).toStringAsFixed(3);

String _markdownCell(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll('|', r'\|')
    .replaceAll(RegExp(r'[\r\n]+'), ' ');

final class _ThresholdRun {
  const _ThresholdRun({
    required this.repeat,
    required this.wallUs,
    required this.immediate,
    required this.settled,
  });

  final int repeat;
  final int wallUs;
  final _WalState immediate;
  final _WalState settled;
}

final class _SustainedRun {
  const _SustainedRun({
    required this.repeat,
    required this.writeUs,
    required this.readUs,
    required this.immediate,
    required this.settled,
  });

  final int repeat;
  final List<int> writeUs;
  final List<int> readUs;
  final _WalState immediate;
  final _WalState settled;
}

final class _WalState {
  const _WalState({
    required this.busy,
    required this.log,
    required this.checkpointed,
  });

  final int busy;
  final int log;
  final int checkpointed;

  int get pending {
    final value = log - checkpointed;
    return value < 0 ? 0 : value;
  }
}

final class _Options {
  const _Options({
    required this.label,
    required this.repeats,
    required this.writes,
    required this.readEvery,
    required this.settle,
    required this.help,
  });

  factory _Options.parse(List<String> args) {
    var label = _defaultLabel;
    var repeats = _defaultRepeats;
    var writes = _defaultWrites;
    var readEvery = _defaultReadEvery;
    var settleMs = _defaultSettleMs;
    var help = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--help' || arg == '-h') {
        help = true;
        continue;
      }

      String readValue(String option) {
        if (arg.startsWith('$option=')) {
          return arg.substring(option.length + 1);
        }
        if (arg == option && i + 1 < args.length) {
          return args[++i];
        }
        throw FormatException('Unknown or incomplete option: $arg');
      }

      if (arg == '--label' || arg.startsWith('--label=')) {
        label = readValue('--label');
      } else if (arg == '--repeats' || arg.startsWith('--repeats=')) {
        repeats = _positiveInt('--repeats', readValue('--repeats'));
      } else if (arg == '--writes' || arg.startsWith('--writes=')) {
        writes = _positiveInt('--writes', readValue('--writes'));
      } else if (arg == '--read-every' || arg.startsWith('--read-every=')) {
        readEvery = _positiveInt('--read-every', readValue('--read-every'));
      } else if (arg == '--settle-ms' || arg.startsWith('--settle-ms=')) {
        settleMs = _nonNegativeInt('--settle-ms', readValue('--settle-ms'));
      } else {
        throw FormatException('Unknown option: $arg');
      }
    }

    if (label.trim().isEmpty) {
      throw const FormatException('--label must not be empty.');
    }
    if (readEvery > writes) {
      throw const FormatException(
        '--read-every must be less than or equal to --writes.',
      );
    }

    return _Options(
      label: label.trim(),
      repeats: repeats,
      writes: writes,
      readEvery: readEvery,
      settle: Duration(milliseconds: settleMs),
      help: help,
    );
  }

  final String label;
  final int repeats;
  final int writes;
  final int readEvery;
  final Duration settle;
  final bool help;
}

int _positiveInt(String option, String raw) {
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw FormatException('$option must be a positive integer, got "$raw".');
  }
  return value;
}

int _nonNegativeInt(String option, String raw) {
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw FormatException(
      '$option must be a non-negative integer, got "$raw".',
    );
  }
  return value;
}

const _usage =
    '''
Focused exp 250 high-water asynchronous checkpoint-worker benchmark.

Usage:
  dart run benchmark/experiments/async_checkpoint_high_water.dart [options]

Options:
  --label=<text>       A/B label printed in every summary row
                       (default: $_defaultLabel)
  --repeats=<n>        Fresh-database repetitions (default: $_defaultRepeats)
  --writes=<n>         Sustained 8 KiB writes per repeat
                       (default: $_defaultWrites)
  --read-every=<n>     Measure one foreground read every n writes
                       (default: $_defaultReadEvery)
  --settle-ms=<n>      Bounded wait before the second WAL NOOP probe
                       (default: $_defaultSettleMs)
  --help               Show this message
''';

const _sustainedCreateSql = '''
CREATE TABLE sustained_events(
  id INTEGER PRIMARY KEY,
  payload TEXT NOT NULL,
  sequence INTEGER NOT NULL
)
''';

const _sustainedInsertSql =
    'INSERT INTO sustained_events(payload, sequence) VALUES (?, ?)';

const _foregroundReadSql = '''
SELECT count(*) AS count
FROM sustained_events
WHERE id > ?
''';

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

List<Object?> _wideBatchRow(int row) => [
  _emojiText(row, 0),
  row,
  row / 3.0,
  _blob(row, 3),
  _emojiText(row, 4),
  row + 5,
  row / 7.0,
  _blob(row, 7),
  _emojiText(row, 8),
  row + 9,
  row / 11.0,
  _blob(row, 11),
  _emojiText(row, 12),
  row + 13,
  row / 17.0,
  _blob(row, 15),
  _emojiText(row, 16),
  row + 17,
  row / 19.0,
  _blob(row, 19),
];

String _emojiText(int row, int column) =>
    'emoji_${row}_${column}_\u{1f680}_\u{1f9ea}';

Uint8List _blob(int row, int salt) =>
    Uint8List.fromList([row & 0xff, (row >> 8) & 0xff, salt, 0x5a]);
