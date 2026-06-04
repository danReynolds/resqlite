// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/stats.dart';

const _defaultWarmup = 5;
const _defaultIterations = 20;
const _defaultRows = <int>[100, 1000, 10000];
const _datasetNames = <String, _DatasetKind>{
  'numeric': _DatasetKind.numeric,
  'mixed': _DatasetKind.mixed,
};
const _consumerNames = <String, _ConsumerMode>{
  'length': _ConsumerMode.lengthOnly,
  'id': _ConsumerMode.idKey,
  'foreach': _ConsumerMode.forEachAll,
  'copy': _ConsumerMode.mapCopy,
};

int _sink = 0;

enum _DatasetKind { numeric, mixed }

enum _ConsumerMode { lengthOnly, idKey, forEachAll, mapCopy }

final class _Options {
  const _Options({
    required this.warmup,
    required this.iterations,
    required this.rows,
    required this.datasets,
    required this.consumers,
  });

  final int warmup;
  final int iterations;
  final List<int> rows;
  final List<_DatasetKind> datasets;
  final List<_ConsumerMode> consumers;

  static _Options parse(List<String> args) {
    var warmup = _defaultWarmup;
    var iterations = _defaultIterations;
    var rows = _defaultRows;
    var datasets = _DatasetKind.values;
    var consumers = _ConsumerMode.values;

    for (final arg in args) {
      if (arg.startsWith('--warmup=')) {
        warmup = int.parse(arg.substring('--warmup='.length));
      } else if (arg.startsWith('--iterations=')) {
        iterations = int.parse(arg.substring('--iterations='.length));
      } else if (arg.startsWith('--rows=')) {
        rows = _parseIntList(arg.substring('--rows='.length));
      } else if (arg.startsWith('--datasets=')) {
        datasets = _parseEnumList(
          arg.substring('--datasets='.length),
          _datasetNames,
          'dataset',
        );
      } else if (arg.startsWith('--consumers=')) {
        consumers = _parseEnumList(
          arg.substring('--consumers='.length),
          _consumerNames,
          'consumer',
        );
      } else if (arg == '--markdown') {
        // Output is already markdown-compatible. Kept for symmetry with
        // profile harnesses that are commonly invoked with --markdown.
      } else if (arg == '--help' || arg == '-h') {
        _printUsage();
        exit(0);
      } else {
        stderr.writeln('Unknown argument: $arg');
        _printUsage();
        exit(2);
      }
    }

    if (warmup < 0 || iterations <= 0 || rows.isEmpty) {
      stderr.writeln(
        'Expected warmup >= 0, iterations > 0, and at least one row count.',
      );
      exit(2);
    }

    return _Options(
      warmup: warmup,
      iterations: iterations,
      rows: rows,
      datasets: datasets,
      consumers: consumers,
    );
  }
}

final class _Sample {
  const _Sample({required this.selectUs, required this.consumeUs});

  final int selectUs;
  final int consumeUs;

  int get totalUs => selectUs + consumeUs;
}

final class _CaseResult {
  const _CaseResult({
    required this.dataset,
    required this.rowCount,
    required this.consumer,
    required this.samples,
  });

  final _DatasetKind dataset;
  final int rowCount;
  final _ConsumerMode consumer;
  final List<_Sample> samples;

  Stats get select => Stats([for (final sample in samples) sample.selectUs]);
  Stats get consume => Stats([for (final sample in samples) sample.consumeUs]);
  Stats get total => Stats([for (final sample in samples) sample.totalUs]);
}

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final runtime = bool.fromEnvironment('dart.vm.product')
      ? 'AOT/product'
      : 'JIT/profile-debug';

  print('');
  print('=== Result Consumer Cost Benchmark ===');
  print('');
  print('Runtime: $runtime');
  print('Warmup: ${options.warmup}');
  print('Iterations: ${options.iterations}');
  print('Rows: ${options.rows.join(', ')}');
  print('Datasets: ${options.datasets.map(_datasetLabel).join(', ')}');
  print('Consumers: ${options.consumers.map(_consumerLabel).join(', ')}');
  print('');
  print(
    'Measures SQLite-backed `db.select()` wall separately from main-isolate '
    'row consumption.',
  );
  print('');

  final tempDir = await Directory.systemTemp.createTemp(
    'result_consumer_cost_',
  );
  try {
    for (final dataset in options.datasets) {
      for (final rowCount in options.rows) {
        final dbPath = '${tempDir.path}/${_datasetSlug(dataset)}_$rowCount.db';
        final db = await resqlite.Database.open(dbPath);
        try {
          await _seed(db, dataset, rowCount);
          final results = <_CaseResult>[];
          for (final consumer in options.consumers) {
            results.add(
              await _runCase(
                db: db,
                dataset: dataset,
                rowCount: rowCount,
                consumer: consumer,
                warmup: options.warmup,
                iterations: options.iterations,
              ),
            );
          }
          _printSection(dataset, rowCount, results);
        } finally {
          await db.close();
        }
      }
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  if (_sink == 0x7fffffff) {
    print('ignore $_sink');
  }
}

Future<_CaseResult> _runCase({
  required resqlite.Database db,
  required _DatasetKind dataset,
  required int rowCount,
  required _ConsumerMode consumer,
  required int warmup,
  required int iterations,
}) async {
  final sql = _selectSql(dataset);
  for (var i = 0; i < warmup; i++) {
    final rows = await db.select(sql);
    _consume(rows, consumer);
  }

  final samples = <_Sample>[];
  for (var i = 0; i < iterations; i++) {
    final selectSw = Stopwatch()..start();
    final rows = await db.select(sql);
    selectSw.stop();

    final consumeSw = Stopwatch()..start();
    _consume(rows, consumer);
    consumeSw.stop();

    samples.add(
      _Sample(
        selectUs: selectSw.elapsedMicroseconds,
        consumeUs: consumeSw.elapsedMicroseconds,
      ),
    );
  }

  return _CaseResult(
    dataset: dataset,
    rowCount: rowCount,
    consumer: consumer,
    samples: samples,
  );
}

Future<void> _seed(
  resqlite.Database db,
  _DatasetKind dataset,
  int rowCount,
) async {
  await db.execute(_createSql(dataset));
  await db.executeBatch(_insertSql(dataset), _rowsFor(dataset, rowCount));
}

String _createSql(_DatasetKind dataset) => switch (dataset) {
  _DatasetKind.numeric =>
    '''
CREATE TABLE items(
  id INTEGER PRIMARY KEY,
  n0 INTEGER NOT NULL,
  n1 INTEGER NOT NULL,
  n2 INTEGER NOT NULL,
  n3 INTEGER NOT NULL,
  f0 REAL NOT NULL,
  f1 REAL NOT NULL,
  f2 REAL NOT NULL,
  f3 REAL NOT NULL
)''',
  _DatasetKind.mixed =>
    '''
CREATE TABLE items(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  score INTEGER NOT NULL,
  amount REAL NOT NULL,
  payload BLOB NOT NULL,
  note TEXT
)''',
};

String _insertSql(_DatasetKind dataset) => switch (dataset) {
  _DatasetKind.numeric =>
    '''
INSERT INTO items(id, n0, n1, n2, n3, f0, f1, f2, f3)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
  _DatasetKind.mixed =>
    '''
INSERT INTO items(id, name, category, score, amount, payload, note)
VALUES (?, ?, ?, ?, ?, ?, ?)''',
};

String _selectSql(_DatasetKind dataset) => switch (dataset) {
  _DatasetKind.numeric =>
    '''
SELECT id, n0, n1, n2, n3, f0, f1, f2, f3
FROM items
ORDER BY id''',
  _DatasetKind.mixed =>
    '''
SELECT id, name, category, score, amount, payload, note
FROM items
ORDER BY id''',
};

List<List<Object?>> _rowsFor(_DatasetKind dataset, int rowCount) => [
  for (var row = 0; row < rowCount; row++)
    switch (dataset) {
      _DatasetKind.numeric => <Object?>[
        row,
        row,
        row * 2,
        row * 3,
        row * 4,
        row / 10.0,
        row / 20.0,
        row / 30.0,
        row / 40.0,
      ],
      _DatasetKind.mixed => <Object?>[
        row,
        'name_$row',
        'cat_${row % 16}',
        row * 7,
        row / 3.0,
        Uint8List.fromList([
          row & 0xff,
          (row >> 8) & 0xff,
          (row >> 16) & 0xff,
          0xa5,
          row % 251,
          row % 241,
          row % 239,
          row % 233,
          row % 229,
          row % 227,
          row % 223,
          row % 211,
          row % 199,
          row % 197,
          row % 193,
          row % 191,
        ]),
        row.isEven ? 'note_$row' : null,
      ],
    },
];

void _consume(List<Map<String, Object?>> rows, _ConsumerMode mode) {
  var sum = 0;
  switch (mode) {
    case _ConsumerMode.lengthOnly:
      sum ^= rows.length;
    case _ConsumerMode.idKey:
      for (final row in rows) {
        sum = _mixValue(sum, row['id']);
      }
    case _ConsumerMode.forEachAll:
      for (final row in rows) {
        row.forEach((_, value) {
          sum = _mixValue(sum, value);
        });
      }
    case _ConsumerMode.mapCopy:
      for (final row in rows) {
        final copy = Map<String, Object?>.from(row);
        sum ^= copy.length;
        sum = _mixValue(sum, copy['id']);
      }
  }
  _sink ^= sum;
}

int _mixValue(int sum, Object? value) {
  if (value is int) return sum ^ value;
  if (value is double) return sum ^ value.toInt();
  if (value is String) return sum ^ value.length;
  if (value is Uint8List) return sum ^ value.length ^ value.first;
  if (value == null) return sum ^ 1;
  return sum ^ value.hashCode;
}

void _printSection(
  _DatasetKind dataset,
  int rowCount,
  List<_CaseResult> results,
) {
  print('## ${_datasetLabel(dataset)} / $rowCount rows');
  print('');
  print(
    '| Consumer | select p50 | consume p50 | total p50 | total p90 | consume % |',
  );
  print('|---|---:|---:|---:|---:|---:|');
  for (final result in results) {
    final selectMs = result.select.medianMs;
    final consumeMs = result.consume.medianMs;
    final totalMs = result.total.medianMs;
    final consumePct = totalMs == 0 ? 0 : (consumeMs / totalMs) * 100;
    print(
      '| ${_consumerLabel(result.consumer)} '
      '| ${selectMs.toStringAsFixed(3)} ms '
      '| ${consumeMs.toStringAsFixed(3)} ms '
      '| ${totalMs.toStringAsFixed(3)} ms '
      '| ${result.total.p90Ms.toStringAsFixed(3)} ms '
      '| ${consumePct.toStringAsFixed(1)}% |',
    );
  }
  print('');
}

String _datasetLabel(_DatasetKind dataset) => switch (dataset) {
  _DatasetKind.numeric => 'numeric',
  _DatasetKind.mixed => 'mixed',
};

String _datasetSlug(_DatasetKind dataset) => _datasetLabel(dataset);

String _consumerLabel(_ConsumerMode consumer) => switch (consumer) {
  _ConsumerMode.lengthOnly => 'length only',
  _ConsumerMode.idKey => 'id key per row',
  _ConsumerMode.forEachAll => 'forEach all cells',
  _ConsumerMode.mapCopy => 'Map copy',
};

List<int> _parseIntList(String raw) {
  final values = raw
      .split(',')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => int.parse(part.trim()))
      .toList(growable: false);
  return values;
}

List<T> _parseEnumList<T>(String raw, Map<String, T> values, String label) {
  final parsed = <T>[];
  for (final part in raw.split(',')) {
    final name = part.trim();
    if (name.isEmpty) continue;
    final value = values[name];
    if (value == null) {
      stderr.writeln(
        'Unknown $label: $name (expected one of ${values.keys.join(', ')})',
      );
      exit(2);
    }
    parsed.add(value);
  }
  if (parsed.isEmpty) {
    stderr.writeln('Expected at least one $label.');
    exit(2);
  }
  return parsed;
}

void _printUsage() {
  print(
    'Usage: dart run benchmark/experiments/result_consumer_cost.dart '
    '[--warmup=N] [--iterations=N] [--rows=100,1000,10000] '
    '[--datasets=${_datasetNames.keys.join(',')}] '
    '[--consumers=${_consumerNames.keys.join(',')}]',
  );
}
