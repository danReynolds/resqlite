// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart';

import '../shared/stats.dart';

const _warmupIterations = 3;
const _measureIterations = 15;
const _rowCounts = <int>[100, 1000, 10000];

int _sink = 0;

enum _TransferMode { send, exit }

enum _DatasetKind { numeric, mixed }

enum _PayloadShape { current, materializedMaps, binaryRows }

final class _Config {
  const _Config(this.shape, this.dataset, this.rowCount);

  final _PayloadShape shape;
  final _DatasetKind dataset;
  final int rowCount;
}

final class _Sample {
  const _Sample({required this.transferUs, required this.consumeUs});

  final int transferUs;
  final int consumeUs;

  int get totalUs => transferUs + consumeUs;
}

final class _TimingSummary {
  _TimingSummary(this.label, this.samples);

  final String label;
  final List<_Sample> samples;

  Stats get transfer =>
      Stats([for (final sample in samples) sample.transferUs]);
  Stats get consume => Stats([for (final sample in samples) sample.consumeUs]);
  Stats get total => Stats([for (final sample in samples) sample.totalUs]);
}

void main() async {
  final runtime = bool.fromEnvironment('dart.vm.product')
      ? 'AOT/product'
      : 'JIT/profile-debug';

  print('');
  print('=== Isolate Message Graph ===');
  print('Runtime: $runtime');
  print(
    'Measures hand-off vs main-isolate row consumption for result-shaped payloads.',
  );
  print(
    '`exit` mode measures hand-off after spawn/handshake, not respawn lifecycle.',
  );
  print('');

  for (final dataset in _DatasetKind.values) {
    for (final rowCount in _rowCounts) {
      print('=== ${_datasetLabel(dataset)} / $rowCount rows ===');
      for (final mode in _TransferMode.values) {
        final results = <_TimingSummary>[];
        for (final shape in _PayloadShape.values) {
          final config = _Config(shape, dataset, rowCount);
          results.add(await _runCase(mode, config));
        }
        _printSection(_modeLabel(mode), results);
      }
      print('');
    }
  }

  if (_sink == 0x7fffffff) {
    print('ignore $_sink');
  }
}

Future<_TimingSummary> _runCase(_TransferMode mode, _Config config) async {
  final label = _shapeLabel(config.shape);
  final samples = <_Sample>[];

  switch (mode) {
    case _TransferMode.send:
      final worker = await _PersistentWorker.spawn(config);
      try {
        for (var i = 0; i < _warmupIterations; i++) {
          final rows = await worker.request();
          _consumeRows(rows);
        }
        for (var i = 0; i < _measureIterations; i++) {
          final swTransfer = Stopwatch()..start();
          final rows = await worker.request();
          swTransfer.stop();

          final swConsume = Stopwatch()..start();
          _consumeRows(rows);
          swConsume.stop();

          samples.add(
            _Sample(
              transferUs: swTransfer.elapsedMicroseconds,
              consumeUs: swConsume.elapsedMicroseconds,
            ),
          );
        }
      } finally {
        await worker.close();
      }
    case _TransferMode.exit:
      for (var i = 0; i < _warmupIterations; i++) {
        final rows = await _requestViaExit(config);
        _consumeRows(rows);
      }
      for (var i = 0; i < _measureIterations; i++) {
        final swTransfer = Stopwatch()..start();
        final rows = await _requestViaExit(config);
        swTransfer.stop();

        final swConsume = Stopwatch()..start();
        _consumeRows(rows);
        swConsume.stop();

        samples.add(
          _Sample(
            transferUs: swTransfer.elapsedMicroseconds,
            consumeUs: swConsume.elapsedMicroseconds,
          ),
        );
      }
  }

  return _TimingSummary(label, samples);
}

void _printSection(String title, List<_TimingSummary> results) {
  print(title);
  print(
    '| Shape | Transfer p50 | Transfer p90 | Consume p50 | Consume p90 | Total p50 | Total p90 |',
  );
  print('|---|---:|---:|---:|---:|---:|---:|');
  for (final result in results) {
    print(
      '| ${result.label} '
      '| ${result.transfer.medianMs.toStringAsFixed(3)} ms'
      '| ${result.transfer.p90Ms.toStringAsFixed(3)} ms'
      '| ${result.consume.medianMs.toStringAsFixed(3)} ms'
      '| ${result.consume.p90Ms.toStringAsFixed(3)} ms'
      '| ${result.total.medianMs.toStringAsFixed(3)} ms'
      '| ${result.total.p90Ms.toStringAsFixed(3)} ms |',
    );
  }
  print('');
}

String _modeLabel(_TransferMode mode) => switch (mode) {
  _TransferMode.send => 'SendPort.send (same-group copy path)',
  _TransferMode.exit => 'Isolate.exit (handoff after handshake)',
};

String _datasetLabel(_DatasetKind dataset) => switch (dataset) {
  _DatasetKind.numeric => 'numeric-heavy',
  _DatasetKind.mixed => 'mixed-schema',
};

String _shapeLabel(_PayloadShape shape) => switch (shape) {
  _PayloadShape.current => 'current ResultSet',
  _PayloadShape.materializedMaps => 'materialized maps',
  _PayloadShape.binaryRows => 'binary row facade',
};

Future<List<Map<String, Object?>>> _requestViaExit(_Config config) async {
  final port = ReceivePort();
  final handshake = Completer<SendPort>.sync();
  late final StreamSubscription<Object?> sub;
  final result = Completer<List<Map<String, Object?>>>.sync();
  sub = port.listen((message) {
    if (message is SendPort) {
      handshake.complete(message);
      return;
    }
    if (!result.isCompleted) {
      result.complete(message as List<Map<String, Object?>>);
    }
  });

  await Isolate.spawn(_exitWorkerMain, (port.sendPort, config));
  final commandPort = await handshake.future;
  commandPort.send(true);
  final rows = await result.future;
  await sub.cancel();
  port.close();
  return rows;
}

final class _PersistentWorker {
  _PersistentWorker(this._isolate, this._events, this._commandPort, this._sub);

  final Isolate _isolate;
  final ReceivePort _events;
  final SendPort _commandPort;
  final StreamSubscription<Object?> _sub;
  late final _PendingHolder _pending;

  static Future<_PersistentWorker> spawn(_Config config) async {
    final port = ReceivePort();
    final handshake = Completer<SendPort>.sync();
    final pending = _PendingHolder();
    final sub = port.listen((message) {
      if (message is SendPort && !handshake.isCompleted) {
        handshake.complete(message);
        return;
      }
      final completer = pending.value;
      if (completer == null) {
        return;
      }
      pending.value = null;
      completer.complete(message as List<Map<String, Object?>>);
    });

    final isolate = await Isolate.spawn(_sendWorkerMain, (
      port.sendPort,
      config,
    ));
    final commandPort = await handshake.future;
    final worker = _PersistentWorker(isolate, port, commandPort, sub);
    worker._pending = pending;
    return worker;
  }

  Future<List<Map<String, Object?>>> request() {
    if (_pending.value != null) {
      throw StateError('request already in flight');
    }
    final completer = Completer<List<Map<String, Object?>>>.sync();
    _pending.value = completer;
    _commandPort.send(true);
    return completer.future;
  }

  Future<void> close() async {
    _commandPort.send(null);
    await _sub.cancel();
    _events.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

final class _PendingHolder {
  Completer<List<Map<String, Object?>>>? value;
}

void _sendWorkerMain((SendPort, _Config) args) {
  final (eventPort, config) = args;
  final payload = _buildPayload(config);
  final commands = RawReceivePort();
  eventPort.send(commands.sendPort);
  commands.handler = (message) {
    if (message == null) {
      commands.close();
      return;
    }
    eventPort.send(payload);
  };
}

void _exitWorkerMain((SendPort, _Config) args) {
  final (eventPort, config) = args;
  final payload = _buildPayload(config);
  final commands = RawReceivePort();
  eventPort.send(commands.sendPort);
  commands.handler = (message) {
    if (message == null) {
      commands.close();
      return;
    }
    commands.close();
    Isolate.exit(eventPort, payload);
  };
}

List<Map<String, Object?>> _buildPayload(_Config config) {
  final (schema, values) = _buildFlatValues(config.dataset, config.rowCount);
  switch (config.shape) {
    case _PayloadShape.current:
      return ResultSet(values, schema, config.rowCount, hasWrappedCells: false)
          as List<Map<String, Object?>>;
    case _PayloadShape.materializedMaps:
      final rows = List<Map<String, Object?>>.generate(config.rowCount, (row) {
        final map = LinkedHashMap<String, Object?>();
        final offset = row * schema.columnCount;
        for (var col = 0; col < schema.columnCount; col++) {
          map[schema.names[col]] = values[offset + col];
        }
        return map;
      }, growable: false);
      return rows;
    case _PayloadShape.binaryRows:
      return _buildBinaryRows(schema, values, config.rowCount);
  }
}

(RowSchema, List<Object?>) _buildFlatValues(
  _DatasetKind dataset,
  int rowCount,
) {
  return switch (dataset) {
    _DatasetKind.numeric => _buildNumericValues(rowCount),
    _DatasetKind.mixed => _buildMixedValues(rowCount),
  };
}

(RowSchema, List<Object?>) _buildNumericValues(int rowCount) {
  final schema = RowSchema([
    'id',
    'n0',
    'n1',
    'n2',
    'n3',
    'f0',
    'f1',
    'f2',
    'f3',
  ]);
  final values = List<Object?>.filled(
    rowCount * schema.columnCount,
    null,
    growable: false,
  );
  var writeIdx = 0;
  for (var i = 0; i < rowCount; i++) {
    values[writeIdx++] = i;
    values[writeIdx++] = i;
    values[writeIdx++] = i * 2;
    values[writeIdx++] = i * 3;
    values[writeIdx++] = i * 4;
    values[writeIdx++] = i / 10.0;
    values[writeIdx++] = i / 20.0;
    values[writeIdx++] = i / 30.0;
    values[writeIdx++] = i / 40.0;
  }
  return (schema, values);
}

(RowSchema, List<Object?>) _buildMixedValues(int rowCount) {
  final schema = RowSchema([
    'id',
    'name',
    'category',
    'score',
    'amount',
    'note',
  ]);
  final values = List<Object?>.filled(
    rowCount * schema.columnCount,
    null,
    growable: false,
  );
  var writeIdx = 0;
  for (var i = 0; i < rowCount; i++) {
    values[writeIdx++] = i;
    values[writeIdx++] = 'name_$i';
    values[writeIdx++] = 'cat_${i % 16}';
    values[writeIdx++] = i * 7;
    values[writeIdx++] = i / 3.0;
    values[writeIdx++] = i.isEven ? 'note_$i' : null;
  }
  return (schema, values);
}

List<Map<String, Object?>> _buildBinaryRows(
  RowSchema schema,
  List<Object?> flatValues,
  int rowCount,
) {
  final columnKinds = List<_BinaryColumnKind>.generate(schema.columnCount, (
    col,
  ) {
    var sawInt = false;
    var sawDouble = false;
    var sawOther = false;
    for (var row = 0; row < rowCount; row++) {
      final value = flatValues[row * schema.columnCount + col];
      if (value == null) {
        continue;
      } else if (value is int) {
        sawInt = true;
      } else if (value is double) {
        sawDouble = true;
      } else {
        sawOther = true;
        break;
      }
    }
    if (!sawOther && sawInt && !sawDouble) return _BinaryColumnKind.int64;
    if (!sawOther && !sawInt && sawDouble) return _BinaryColumnKind.float64;
    return _BinaryColumnKind.object;
  }, growable: false);

  return _BenchBinaryResultSet.fromFlat(
        schema,
        flatValues,
        rowCount,
        columnKinds,
      )
      as List<Map<String, Object?>>;
}

void _consumeRows(List<Map<String, Object?>> rows) {
  var sum = 0;
  for (final row in rows) {
    for (final entry in row.entries) {
      final value = entry.value;
      if (value is int) {
        sum ^= value;
      } else if (value is double) {
        sum ^= value.toInt();
      } else if (value is String) {
        sum ^= value.length;
      } else if (value is List<int>) {
        sum ^= value.length;
      } else if (value == null) {
        sum ^= 1;
      }
    }
  }
  _sink ^= sum;
}

enum _BinaryColumnKind { int64, float64, object }

final class _BinaryColumn {
  const _BinaryColumn(this.kind, this.slot);

  final _BinaryColumnKind kind;
  final int slot;
}

final class _BenchBinaryResultSet with ListMixin<_BenchBinaryRow> {
  _BenchBinaryResultSet(
    this._schema,
    this._columns,
    this._fixedBytes,
    this._nullBitmap,
    this._objects,
    this._rowCount,
    this._fixedColumnCount,
    this._objectColumnCount,
  ) : _rowStrideBytes = _fixedColumnCount * 8;

  factory _BenchBinaryResultSet.fromFlat(
    RowSchema schema,
    List<Object?> values,
    int rowCount,
    List<_BinaryColumnKind> kinds,
  ) {
    final columns = List<_BinaryColumn>.filled(
      schema.columnCount,
      const _BinaryColumn(_BinaryColumnKind.object, 0),
    );
    var fixedColumnCount = 0;
    var objectColumnCount = 0;
    for (var col = 0; col < schema.columnCount; col++) {
      switch (kinds[col]) {
        case _BinaryColumnKind.int64:
          columns[col] = _BinaryColumn(
            _BinaryColumnKind.int64,
            fixedColumnCount++,
          );
        case _BinaryColumnKind.float64:
          columns[col] = _BinaryColumn(
            _BinaryColumnKind.float64,
            fixedColumnCount++,
          );
        case _BinaryColumnKind.object:
          columns[col] = _BinaryColumn(
            _BinaryColumnKind.object,
            objectColumnCount++,
          );
      }
    }

    final rowStrideBytes = fixedColumnCount * 8;
    final fixedBytes = Uint8List(rowStrideBytes * rowCount);
    final fixedData = ByteData.sublistView(fixedBytes);
    final nullBitmap = Uint8List(((rowCount * fixedColumnCount) + 7) >> 3);
    final objects = List<Object?>.filled(
      rowCount * objectColumnCount,
      null,
      growable: false,
    );

    for (var row = 0; row < rowCount; row++) {
      final base = row * schema.columnCount;
      for (var col = 0; col < schema.columnCount; col++) {
        final value = values[base + col];
        final column = columns[col];
        switch (column.kind) {
          case _BinaryColumnKind.int64:
            final bitIndex = row * fixedColumnCount + column.slot;
            if (value == null) {
              nullBitmap[bitIndex >> 3] |= 1 << (bitIndex & 7);
            } else {
              fixedData.setInt64(
                row * rowStrideBytes + column.slot * 8,
                value as int,
                Endian.host,
              );
            }
          case _BinaryColumnKind.float64:
            final bitIndex = row * fixedColumnCount + column.slot;
            if (value == null) {
              nullBitmap[bitIndex >> 3] |= 1 << (bitIndex & 7);
            } else {
              fixedData.setFloat64(
                row * rowStrideBytes + column.slot * 8,
                value as double,
                Endian.host,
              );
            }
          case _BinaryColumnKind.object:
            objects[row * objectColumnCount + column.slot] = value;
        }
      }
    }

    return _BenchBinaryResultSet(
      schema,
      columns,
      fixedBytes,
      nullBitmap,
      objects,
      rowCount,
      fixedColumnCount,
      objectColumnCount,
    );
  }

  final RowSchema _schema;
  final List<_BinaryColumn> _columns;
  final Uint8List _fixedBytes;
  final Uint8List _nullBitmap;
  final List<Object?> _objects;
  final int _rowCount;
  final int _fixedColumnCount;
  final int _objectColumnCount;
  final int _rowStrideBytes;

  late final ByteData _fixedData = ByteData.sublistView(_fixedBytes);

  @override
  int get length => _rowCount;

  @override
  set length(int value) => throw UnsupportedError('Fixed-length list');

  @override
  _BenchBinaryRow operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _BenchBinaryRow(this, index);
  }

  @override
  void operator []=(_index, _BenchBinaryRow value) =>
      throw UnsupportedError('Unmodifiable');

  Object? cellAt(int rowIndex, int columnIndex) {
    final column = _columns[columnIndex];
    switch (column.kind) {
      case _BinaryColumnKind.object:
        return _objects[rowIndex * _objectColumnCount + column.slot];
      case _BinaryColumnKind.int64:
        final bitIndex = rowIndex * _fixedColumnCount + column.slot;
        if ((_nullBitmap[bitIndex >> 3] & (1 << (bitIndex & 7))) != 0) {
          return null;
        }
        return _fixedData.getInt64(
          rowIndex * _rowStrideBytes + column.slot * 8,
          Endian.host,
        );
      case _BinaryColumnKind.float64:
        final bitIndex = rowIndex * _fixedColumnCount + column.slot;
        if ((_nullBitmap[bitIndex >> 3] & (1 << (bitIndex & 7))) != 0) {
          return null;
        }
        return _fixedData.getFloat64(
          rowIndex * _rowStrideBytes + column.slot * 8,
          Endian.host,
        );
    }
  }
}

final class _BenchBinaryRow with MapMixin<String, Object?> {
  _BenchBinaryRow(this._owner, this._rowIndex);

  final _BenchBinaryResultSet _owner;
  final int _rowIndex;

  @override
  Object? operator [](Object? key) {
    if (key is! String) return null;
    final idx = _owner._schema.indexOf(key);
    if (idx < 0) return null;
    return _owner.cellAt(_rowIndex, idx);
  }

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('Unmodifiable');

  @override
  void clear() => throw UnsupportedError('Unmodifiable');

  @override
  Iterable<String> get keys => _owner._schema.names;

  @override
  Object? remove(Object? key) => throw UnsupportedError('Unmodifiable');

  @override
  bool containsKey(Object? key) =>
      key is String && _owner._schema.indexOf(key) >= 0;

  @override
  void forEach(void Function(String key, Object? value) action) {
    final names = _owner._schema.names;
    for (var i = 0; i < names.length; i++) {
      action(names[i], _owner.cellAt(_rowIndex, i));
    }
  }

  @override
  int get length => _owner._schema.columnCount;
}
