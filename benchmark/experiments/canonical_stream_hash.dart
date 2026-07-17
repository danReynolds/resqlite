// Focused A/B harness for exp 228's canonical stream-hash baseline.
//
// Each round establishes a native hash for 5,000 rows, appends 100 rows, and
// calls the public reader-worker `selectIfChanged` path twice. The first call
// must decode the grown result. The second call sees the exact same rows and
// should return the unchanged sentinel without decoding.
//
// The exp 077 baseline stores a prefix-only hash after growth, so the second
// call compares a canonical full hash with that partial baseline and decodes
// all 5,100 rows once more. A canonical-hash candidate reports zero redundant
// decodes while keeping the growth call close to baseline.

// ignore_for_file: avoid_print
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/reader/reader_pool.dart';

const _warmupRounds = 2;
const _measuredRounds = 9;
const _seedRows = 5000;
const _growthRows = 100;
const _bodyBytes = 64;
const _sql = 'SELECT id, body FROM items ORDER BY id';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp(
    'resqlite_canonical_stream_hash_',
  );
  final growthSamples = <int>[];
  final unchangedSamples = <int>[];
  final cycleSamples = <int>[];
  var redundantNoOpDecodes = 0;

  print('=== Canonical stream hash after result growth (exp 228) ===');
  print(
    '$_seedRows seed rows + $_growthRows appended rows, '
    '$_bodyBytes-byte TEXT, one reader, '
    '$_warmupRounds warmup + $_measuredRounds measured rounds',
  );
  print('');

  try {
    for (var round = 0; round < _warmupRounds + _measuredRounds; round++) {
      final result = await _runRound(dir.path, round);
      final measured = round >= _warmupRounds;
      final label = measured ? 'round ${round - _warmupRounds}' : 'warmup';
      print(
        '$label: growth=${_ms(result.growthUs)} ms, '
        'immediate-unchanged=${_ms(result.unchangedUs)} ms, '
        'redundant-decode=${result.redundantNoOpDecode}',
      );

      if (measured) {
        growthSamples.add(result.growthUs);
        unchangedSamples.add(result.unchangedUs);
        cycleSamples.add(result.growthUs + result.unchangedUs);
        redundantNoOpDecodes += result.redundantNoOpDecode;
      }
    }

    print('');
    print('| Lane | p50 (ms) | p90 (ms) |');
    print('|---|---:|---:|');
    _printStats('growth selectIfChanged', growthSamples);
    _printStats('immediate unchanged selectIfChanged', unchangedSamples);
    _printStats('combined cycle', cycleSamples);
    print('');
    print(
      'redundant immediate-unchanged decodes: $redundantNoOpDecodes '
      '/ $_measuredRounds',
    );
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<({int growthUs, int unchangedUs, int redundantNoOpDecode})> _runRound(
  String dirPath,
  int round,
) async {
  final runtime = await _ExperimentRuntime.open('$dirPath/round_$round.db');
  try {
    executeWrite(
      runtime.handle,
      'CREATE TABLE items(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
      const [],
    );
    executeBatchWrite(
      runtime.handle,
      'INSERT INTO items(id, body) VALUES (?, ?)',
      [
        for (var i = 1; i <= _seedRows; i++) [i, _body(i)],
      ],
    );

    final (initialRows, _, initialHash, initialCount) = await runtime.readerPool
        .selectWithDeps(_sql);
    if (initialRows.length != _seedRows || initialCount != _seedRows) {
      throw StateError('Unexpected initial row count: $initialCount.');
    }

    executeBatchWrite(
      runtime.handle,
      'INSERT INTO items(id, body) VALUES (?, ?)',
      [
        for (var i = 1; i <= _growthRows; i++)
          [_seedRows + i, _body(_seedRows + i)],
      ],
    );

    final growthWatch = Stopwatch()..start();
    final (grownRows, grownHash, grownCount) = await runtime.readerPool
        .selectIfChanged(_sql, const [], initialHash, initialCount);
    growthWatch.stop();
    if (grownRows == null || grownCount != _seedRows + _growthRows) {
      throw StateError('Growth query did not return the expected result.');
    }

    final unchangedWatch = Stopwatch()..start();
    final (sameRows, sameHash, sameCount) = await runtime.readerPool
        .selectIfChanged(_sql, const [], grownHash, grownCount);
    unchangedWatch.stop();
    if (sameCount != grownCount) {
      throw StateError('Immediate unchanged row count drifted.');
    }
    if (sameRows == null && sameHash != grownHash) {
      throw StateError('Unchanged sentinel returned a different hash.');
    }

    return (
      growthUs: growthWatch.elapsedMicroseconds,
      unchangedUs: unchangedWatch.elapsedMicroseconds,
      redundantNoOpDecode: sameRows == null ? 0 : 1,
    );
  } finally {
    await runtime.close();
  }
}

final class _ExperimentRuntime {
  _ExperimentRuntime(this.handle, this.readerPool);

  final ffi.Pointer<ffi.Void> handle;
  final ReaderPool readerPool;

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
      return _ExperimentRuntime(handle, readerPool);
    } catch (_) {
      resqliteClose(handle);
      rethrow;
    }
  }

  Future<void> close() async {
    await readerPool.close();
    resqliteClose(handle);
  }
}

String _body(int seed) {
  final prefix = 'row_$seed:';
  const chunk = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buffer = StringBuffer(prefix);
  while (buffer.length < _bodyBytes) {
    buffer.write(chunk);
  }
  return buffer.toString().substring(0, _bodyBytes);
}

void _printStats(String label, List<int> samples) {
  samples.sort();
  final p50 = samples[samples.length ~/ 2];
  final p90 = samples[(samples.length * 0.9).floor()];
  print('| $label | ${_ms(p50)} | ${_ms(p90)} |');
}

String _ms(int microseconds) => (microseconds / 1000).toStringAsFixed(3);
