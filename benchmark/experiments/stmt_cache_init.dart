// ignore_for_file: avoid_print, implementation_imports
//
// Focused native-open harness for [EXP-268].
//
// `resqlite_db` is allocated with `calloc`, but `stmt_cache_init` historically
// zeroed every slot in every reader's prepared-statement cache again. After
// exp 267 raised the cache from 32 to 128 entries, optimized arm64 code still
// emitted a 273,408-byte `bzero` per reader. The normal four-reader database
// therefore dirtied 1,093,632 bytes before any statement entered a cache.
//
// The RSS lanes open one real native database in a fresh AOT process. The wall
// lanes amortize stopwatch resolution across several native opens while
// keeping close outside the timed region. Run one lane per process: max RSS is
// a process-lifetime high-water, per exp 261.
//
// Usage:
//   stmt_cache_init --lane=rss4
//   stmt_cache_init --lane=wall4 [--warmup=3] [--samples=31] [--opens=4]
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';

import '../shared/memory_probe.dart';

const _defaultWarmup = 3;
const _defaultSamples = 31;
const _defaultOpens = 4;

Future<void> main(List<String> args) async {
  String? lane;
  var warmup = _defaultWarmup;
  var samples = _defaultSamples;
  var opens = _defaultOpens;

  for (final arg in args) {
    if (arg.startsWith('--lane=')) {
      lane = arg.substring('--lane='.length);
    } else if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--opens=')) {
      opens = int.parse(arg.substring('--opens='.length));
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  if (lane == null) {
    throw ArgumentError(
      'pass one isolated lane with --lane=rss2|rss4|wall2|wall4',
    );
  }
  if (warmup < 0 || samples <= 0 || opens <= 0) {
    throw ArgumentError('warmup must be >= 0; samples and opens must be > 0');
  }

  final readers = switch (lane) {
    'rss2' || 'wall2' => 2,
    'rss4' || 'wall4' => 4,
    _ => throw ArgumentError('unknown lane: $lane'),
  };
  final temp = await Directory.systemTemp.createTemp('bench_stmt_init_');
  final path = '${temp.path}/test.db'.toNativeUtf8();

  try {
    if (lane.startsWith('rss')) {
      _runRss(lane, readers, path);
    } else {
      _runWall(
        lane,
        readers,
        path,
        warmup: warmup,
        samples: samples,
        opens: opens,
      );
    }
  } finally {
    calloc.free(path);
    await temp.delete(recursive: true);
  }
}

void _runRss(String lane, int readers, ffi.Pointer<Utf8> path) {
  final memory = MemoryProbe.start();
  final sw = Stopwatch()..start();
  final handle = _open(path, readers);
  sw.stop();
  memory.sample();
  final reading = memory.finish(laneIsolated: true);

  print(
    'shape=$lane readers=$readers open_us=${sw.elapsedMicroseconds} '
    '${reading.format()} '
    'rss_growth_bytes=${reading.peakRssBytes - reading.startRssBytes} '
    'max_rss_bytes=${reading.maxRssBytes}',
  );
  resqliteClose(handle);
}

void _runWall(
  String lane,
  int readers,
  ffi.Pointer<Utf8> path, {
  required int warmup,
  required int samples,
  required int opens,
}) {
  for (var i = 0; i < warmup; i++) {
    resqliteClose(_open(path, readers));
  }

  final values = <double>[];
  for (var sample = 0; sample < samples; sample++) {
    final sw = Stopwatch();
    for (var i = 0; i < opens; i++) {
      sw.start();
      final handle = _open(path, readers);
      sw.stop();
      // Closing is deliberately outside the measured region. The candidate
      // only changes initialization; cache disposal sees count == 0 here.
      resqliteClose(handle);
    }
    values.add(sw.elapsedMicroseconds / opens);
  }

  final sorted = [...values]..sort();
  print(
    'shape=$lane readers=$readers '
    'median_us=${_percentile(sorted, 0.50).toStringAsFixed(1)} '
    'p10_us=${_percentile(sorted, 0.10).toStringAsFixed(1)} '
    'p90_us=${_percentile(sorted, 0.90).toStringAsFixed(1)} '
    'warmup=$warmup samples=$samples opens_per_sample=$opens '
    'samples_us=${values.map((v) => v.toStringAsFixed(1)).join(',')}',
  );
}

ffi.Pointer<ffi.Void> _open(ffi.Pointer<Utf8> path, int readers) {
  final handle = resqliteOpen(path, readers, ffi.nullptr.cast<Utf8>());
  if (handle == ffi.nullptr) {
    throw StateError('resqlite_open failed');
  }
  return handle;
}

double _percentile(List<double> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];
