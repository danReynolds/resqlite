// Benchmark: single-stream long-payload unchanged hash (exp 181).
//
// Targets `resqlite_query_hash`'s `fnv_combine_bytes` byte-stream loop without
// the eight-stream reader-pool parallelism from exp 173. The script creates an
// internal one-reader runtime, registers one unchanged long stream, then
// registers a cheap changed barrier stream behind it. Each invalidation hashes
// 64 rows of 64KB TEXT + 64KB BLOB cells (~8 MB) before the barrier can emit.
//
// Run the same script on both baseline and candidate checkouts. Compare the
// medians across rounds.

// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:resqlite/src/checkpoint_worker.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/reader/reader_pool.dart';
import 'package:resqlite/src/stream_engine.dart';
import 'package:resqlite/src/writer/writer.dart';

const _rounds = 9;
const _warmup = 2;
const _rowCount = 64;
const _payloadBytes = 64 * 1024;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp(
    'resqlite_single_long_payload_',
  );

  print('=== Single-stream long-payload unchanged hash (exp 181) ===');
  print(
    '1 unchanged stream x $_rowCount rows x '
    '${_payloadBytes ~/ 1024} KB TEXT + ${_payloadBytes ~/ 1024} KB BLOB, '
    '$_warmup warmup + $_rounds measured rounds',
  );
  print('');

  final measured = <int>[];
  try {
    for (var round = 0; round < _warmup + _rounds; round++) {
      final us = await _roundUs(dir.path, round);
      final tag = round < _warmup ? 'warmup' : 'round ${round - _warmup}';
      print('$tag : ${(us / 1000).toStringAsFixed(3)} ms');
      if (round >= _warmup) measured.add(us);
    }

    measured.sort();
    final median = measured[measured.length ~/ 2];
    final p90 = measured[(measured.length * 9) ~/ 10];
    final min = measured.first;
    final max = measured.last;

    print('');
    print('--- Results ---');
    print('median: ${(median / 1000).toStringAsFixed(3)} ms');
    print('p90   : ${(p90 / 1000).toStringAsFixed(3)} ms');
    print('min   : ${(min / 1000).toStringAsFixed(3)} ms');
    print('max   : ${(max / 1000).toStringAsFixed(3)} ms');
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<int> _roundUs(String dirPath, int round) async {
  final runtime = await _ExperimentRuntime.open('$dirPath/r$round.db');
  executeWrite(
    runtime.handle,
    'CREATE TABLE long_payload('
    'id INTEGER PRIMARY KEY, '
    'body TEXT NOT NULL, '
    'data BLOB NOT NULL, '
    'marker INTEGER NOT NULL)',
    const [],
  );
  const insertSql =
      'INSERT INTO long_payload(id, body, data, marker) VALUES (?, ?, ?, ?)';
  executeBatchWrite(runtime.handle, insertSql, [
    for (var i = 0; i < _rowCount; i++)
      [i, _textPayload(_payloadBytes, i), _blobPayload(_payloadBytes, i), i],
  ]);

  var emissions = 0;
  final ready = Completer<void>();
  final sub = runtime.streamEngine
      .stream(
        'SELECT id, body, data FROM long_payload '
        'WHERE id < $_rowCount ORDER BY id',
      )
      .listen((_) {
        emissions++;
        if (!ready.isCompleted) ready.complete();
      });

  final barrierReady = Completer<void>();
  Completer<void>? waitBarrier;
  final barrierSub = runtime.streamEngine
      .stream('SELECT COUNT(*) as cnt FROM long_payload')
      .listen((_) {
        if (!barrierReady.isCompleted) {
          barrierReady.complete();
        } else if (waitBarrier case final completer?
            when !completer.isCompleted) {
          completer.complete();
        }
      });

  try {
    await ready.future.timeout(const Duration(seconds: 60));
    await barrierReady.future.timeout(const Duration(seconds: 60));

    final before = emissions;
    waitBarrier = Completer<void>();
    final sw = Stopwatch()..start();
    final newId = 1_000_000 + round;
    final response = await runtime.writer.execute(insertSql, [
      newId,
      _textPayload(_payloadBytes, newId),
      _blobPayload(_payloadBytes, newId),
      round,
    ]);
    runtime.streamEngine.onDependencyChanges(response.modifications);
    await waitBarrier.future.timeout(const Duration(seconds: 60));
    sw.stop();

    // Give an accidental changed-result emission a turn to reach the listener.
    await Future<void>.delayed(Duration.zero);
    if (emissions != before) {
      throw StateError('Unchanged stream emitted unexpectedly.');
    }

    return sw.elapsedMicroseconds;
  } finally {
    await barrierSub.cancel();
    await sub.cancel();
    await runtime.close();
  }
}

final class _ExperimentRuntime {
  _ExperimentRuntime(
    this.handle,
    this.readerPool,
    this.streamEngine,
    this.checkpointWorker,
    this.writer,
  );

  final ffi.Pointer<ffi.Void> handle;
  final ReaderPool readerPool;
  final StreamEngine streamEngine;
  final CheckpointWorker checkpointWorker;
  final Writer writer;

  static Future<_ExperimentRuntime> open(String path) async {
    final pathNative = path.toNativeUtf8();
    ffi.Pointer<ffi.Void> handle;
    try {
      handle = resqliteOpen(pathNative, 1, ffi.nullptr.cast<Utf8>());
    } finally {
      calloc.free(pathNative);
    }
    if (handle == ffi.nullptr) {
      throw StateError('Failed to open benchmark database at $path.');
    }

    try {
      final readerPool = await ReaderPool.spawn(handle.address, 1);
      final streamEngine = StreamEngine(readerPool);
      final checkpointWorker = await CheckpointWorker.spawn(handle);
      final writer = await Writer.spawn(
        streamEngine,
        handle,
        checkpointWorker.sendPort,
      );
      return _ExperimentRuntime(
        handle,
        readerPool,
        streamEngine,
        checkpointWorker,
        writer,
      );
    } catch (_) {
      resqliteClose(handle);
      rethrow;
    }
  }

  Future<void> close() async {
    streamEngine.close();
    await readerPool.close();
    await writer.close();
    await checkpointWorker.close();
    resqliteClose(handle);
  }
}

String _textPayload(int targetBytes, int seed) {
  final prefix = 'seed_$seed:';
  const chunk = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buffer = StringBuffer(prefix);
  while (buffer.length < targetBytes) {
    buffer.write(chunk);
  }
  return buffer.toString().substring(0, targetBytes);
}

Uint8List _blobPayload(int targetBytes, int seed) {
  final bytes = Uint8List(targetBytes);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (seed + i) & 0xff;
  }
  return bytes;
}
