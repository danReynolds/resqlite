// ignore_for_file: avoid_print
//
// Exp 084 Phase 1 spike — validate that exp 055's micro-benchmark
// numbers still hold on the current Dart SDK + VM, before committing
// to a full columnar-storage integration in the decode path.
//
// Exp 055 (rejected 2026-04-15) documented:
//   - 3× per-element memory reduction (int): 24 B boxed → 8 B in Int64List
//   - 31× faster allocation: 339μs → 11μs for 100k elements
//   - 4.4× faster SendPort.send: 1,268μs → 285μs for 100k elements
//   - 2.8× faster Isolate.exit: 2,329μs → 820μs for 500k elements
//   - 10,000× fewer GC objects per 10k ints
//
// It was rejected at the time because these wins were invisible to the
// wall-time benchmark suite. Profile mode (exp 080) now captures RSS
// and allocation counters per workload, so a memory-axis experiment is
// finally measurable end-to-end.
//
// **This spike does NOT modify production code.** It constructs the
// two backing layouts in isolation and times / weighs each dimension,
// so we know whether the original exp 055 numbers reproduce on the
// current SDK before investing in the full decode-path integration.
//
// Measured dimensions:
//   1. Allocation time              (timed stopwatch)
//   2. Per-element RSS footprint    (ProcessInfo.currentRss delta)
//   3. Isolate transfer time        (spawn worker, send, await reply)
//   4. Iteration time               (sum all values)
//
// Usage:
//   dart run -DRESQLITE_PROFILE=true \
//     benchmark/profile/columnar_spike.dart

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Workload sizing — matches exp 055 for direct comparability.
// ---------------------------------------------------------------------------

const int _elementCount = 100000;
const int _rowCount = 10000;

/// How many parallel container instances to allocate and hold live
/// inside a single RSS-measurement section. Larger means more pressure
/// on the VM's arena allocator, so a given per-element overhead
/// produces a larger (and more measurable) RSS delta. Without this
/// multiplier, 100k × 16-byte heap boxes fit comfortably in young-gen
/// pages that were already mapped in, producing near-zero RSS delta
/// even when the allocations are real.
const int _rssHoldCount = 20;

// Representative mixed-schema workload: 2 int + 1 double + 2 string.
// This is the realistic-CRUD case; pure-int is the best case.
const int _mixedIntCols = 2;
const int _mixedFloatCols = 1;
const int _mixedTextCols = 2;

const int _outerRepeats = 5;
const int _churnSize = 10000;

Future<void> main() async {
  print('Exp 084 Phase 1 spike — columnar vs row-major micro-benchmarks');
  print('================================================================');
  print('');
  print('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  print('Dart:     ${Platform.version}');
  print('');

  await _section1Allocation();
  await _section2Rss();
  await _section2bRssLargeInts();
  await _section2cRssDoubles();
  await _section3IsolateTransfer();
  await _section4Iteration();
  await _section5MixedSchemaRss();

  print('');
  print('=== Interpretation guide ===');
  print('');
  print('Each section reports median of $_outerRepeats trials. For the');
  print('hypothesis to hold on current SDK:');
  print('  Section 1 (alloc):        typed ≥ 10× faster than boxed');
  print('  Section 2 (RSS small int):typed ≥ 2× smaller than boxed');
  print('  Section 2b (RSS big int): typed ≥ 2× smaller than boxed');
  print('  Section 2c (RSS double):  typed ≥ 2× smaller than boxed');
  print('  Section 3 (isolate xfer): typed ≥ 2× faster than boxed');
  print('  Section 4 (iter sum):     typed ≥ 1.5× faster than boxed');
  print('  Section 5 (mixed RSS):    columnar > 30% smaller than row-major');
  print('');
  print('See experiments/084-columnar-redux.md for full analysis.');
}

// ---------------------------------------------------------------------------
// Section 1: Allocation time
// ---------------------------------------------------------------------------
//
// Constructs and populates a container of [_elementCount] int values
// in each layout, times the whole thing. Captures both the "fresh
// allocation" (List.filled / Int64List.new) cost and the "populate
// from loop" cost.

Future<void> _section1Allocation() async {
  print('=== 1. Allocation time (${_elementCount} int elements) ===');
  print('');

  final boxed = _bench('List<Object?> (boxed ints)', _outerRepeats, () {
    _churnHeap();
    final sw = Stopwatch()..start();
    final list = List<Object?>.filled(_elementCount, null, growable: false);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = i;
    }
    sw.stop();
    // Force use so the compiler doesn't optimize away.
    if (list[0] == null) throw StateError('sink');
    return sw.elapsedMicroseconds;
  });

  final typed = _bench('Int64List (unboxed)', _outerRepeats, () {
    _churnHeap();
    final sw = Stopwatch()..start();
    final list = Int64List(_elementCount);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = i;
    }
    sw.stop();
    if (list[0] != 0) throw StateError('sink');
    return sw.elapsedMicroseconds;
  });

  _reportRatio('  speedup', boxed.toDouble(), typed.toDouble(),
      unit: 'μs', higherIsWorse: true);
  print('');
}

// ---------------------------------------------------------------------------
// Section 2: RSS footprint
// ---------------------------------------------------------------------------
//
// Churn heap → baseline RSS → allocate + hold reference → post RSS.
// Delta is a lower bound on per-element memory (VM holds freed pages).

Future<void> _section2Rss() async {
  print('=== 2. RSS footprint (holding $_rssHoldCount × '
      '$_elementCount small int elements) ===');
  print('');

  // Hold $_rssHoldCount copies simultaneously to push clearly past
  // the VM's arena pre-allocation. Per-element overhead of ~16 B
  // for a boxed big-int would be ~1.6 MB per copy, which fits in
  // an arena; $_rssHoldCount copies ≈ 32 MB total, which can't.
  _churnHeap();
  _churnHeap();
  final boxedBefore = _rssMB();
  final boxedLists = <List<Object?>>[];
  for (var k = 0; k < _rssHoldCount; k++) {
    final list = List<Object?>.filled(_elementCount, null, growable: false);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = i;
    }
    boxedLists.add(list);
  }
  final boxedAfter = _rssMB();
  final boxedDelta = boxedAfter - boxedBefore;
  final boxedTotalEls = _rssHoldCount * _elementCount;
  print('  List<Object?>   '
      'baseline=${boxedBefore.toStringAsFixed(2)} MB  '
      'after=${boxedAfter.toStringAsFixed(2)} MB  '
      'delta=${boxedDelta.toStringAsFixed(2)} MB '
      '(${(boxedDelta * 1024 * 1024 / boxedTotalEls).toStringAsFixed(1)} B/element)');

  _churnHeap();
  _churnHeap();
  final typedBefore = _rssMB();
  final typedLists = <Int64List>[];
  for (var k = 0; k < _rssHoldCount; k++) {
    final list = Int64List(_elementCount);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = i;
    }
    typedLists.add(list);
  }
  final typedAfter = _rssMB();
  final typedDelta = typedAfter - typedBefore;
  print('  Int64List       '
      'baseline=${typedBefore.toStringAsFixed(2)} MB  '
      'after=${typedAfter.toStringAsFixed(2)} MB  '
      'delta=${typedDelta.toStringAsFixed(2)} MB '
      '(${(typedDelta * 1024 * 1024 / boxedTotalEls).toStringAsFixed(1)} B/element)');

  _reportRatio('  RSS ratio', boxedDelta, typedDelta,
      unit: 'MB', higherIsWorse: true);

  // Keep references live past the measurement.
  if (boxedLists.first[0] == null || typedLists.first[0] != 0) {
    throw StateError('sink');
  }
  print('');
}

// ---------------------------------------------------------------------------
// Section 2b: RSS with LARGE ints (outside SMI range)
// ---------------------------------------------------------------------------
//
// On 64-bit Dart, the VM tags small ints (SMIs) directly in the
// pointer slot — no heap allocation, 8 bytes per element total. Values
// outside the SMI range become heap-allocated Mint (big int) objects.
// The exp-055 24-byte-per-int claim assumed heap boxing for every int;
// modern Dart's SMI path invalidates that for small-int workloads.
//
// This section tests values in the Mint range — specifically 2^50 +
// offset, which forces every value out of SMI. If the hypothesis
// still holds for real-world large ints (epoch-ms timestamps,
// 64-bit IDs), we'd expect the boxed / typed RSS ratio to climb.

Future<void> _section2bRssLargeInts() async {
  print('=== 2b. RSS with large ints — $_rssHoldCount × '
      '$_elementCount elements (outside SMI range) ===');
  print('');
  // On 64-bit Dart VM (JIT or AOT with 64-bit compressed pointers
  // disabled), SMIs span 63 bits. Values > 2^62 are guaranteed
  // heap-allocated Mints with an ~16-byte box object + 8-byte
  // pointer slot = 24 bytes per element.
  const baseLarge = 1 << 62;

  _churnHeap();
  _churnHeap();
  final boxedBefore = _rssMB();
  final boxedLists = <List<Object?>>[];
  for (var k = 0; k < _rssHoldCount; k++) {
    final list = List<Object?>.filled(_elementCount, null, growable: false);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = baseLarge + i + (k * _elementCount);
    }
    boxedLists.add(list);
  }
  final boxedAfter = _rssMB();
  final boxedDelta = boxedAfter - boxedBefore;
  final totalEls = _rssHoldCount * _elementCount;
  print('  List<Object?>   '
      'baseline=${boxedBefore.toStringAsFixed(2)} MB  '
      'after=${boxedAfter.toStringAsFixed(2)} MB  '
      'delta=${boxedDelta.toStringAsFixed(2)} MB '
      '(${(boxedDelta * 1024 * 1024 / totalEls).toStringAsFixed(1)} B/element)');

  _churnHeap();
  _churnHeap();
  final typedBefore = _rssMB();
  final typedLists = <Int64List>[];
  for (var k = 0; k < _rssHoldCount; k++) {
    final list = Int64List(_elementCount);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = baseLarge + i + (k * _elementCount);
    }
    typedLists.add(list);
  }
  final typedAfter = _rssMB();
  final typedDelta = typedAfter - typedBefore;
  print('  Int64List       '
      'baseline=${typedBefore.toStringAsFixed(2)} MB  '
      'after=${typedAfter.toStringAsFixed(2)} MB  '
      'delta=${typedDelta.toStringAsFixed(2)} MB '
      '(${(typedDelta * 1024 * 1024 / totalEls).toStringAsFixed(1)} B/element)');

  _reportRatio('  RSS ratio', boxedDelta, typedDelta,
      unit: 'MB', higherIsWorse: true);

  if (boxedLists.first[0] == null || typedLists.first[0] != baseLarge) {
    throw StateError('sink');
  }
  print('');
}

// ---------------------------------------------------------------------------
// Section 2c: RSS with doubles
// ---------------------------------------------------------------------------
//
// Doubles are NEVER SMI-tagged — they're always heap-boxed when stored
// in a `List<Object?>`. So the columnar win for float columns should
// be larger than for int columns on modern Dart.

Future<void> _section2cRssDoubles() async {
  print('=== 2c. RSS with doubles — $_rssHoldCount × '
      '$_elementCount elements (always heap-boxed when boxed) ===');
  print('');

  _churnHeap();
  _churnHeap();
  final boxedBefore = _rssMB();
  final boxedLists = <List<Object?>>[];
  for (var k = 0; k < _rssHoldCount; k++) {
    final list = List<Object?>.filled(_elementCount, null, growable: false);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = (k * _elementCount + i) * 1.5;
    }
    boxedLists.add(list);
  }
  final boxedAfter = _rssMB();
  final boxedDelta = boxedAfter - boxedBefore;
  final totalEls = _rssHoldCount * _elementCount;
  print('  List<Object?>   '
      'baseline=${boxedBefore.toStringAsFixed(2)} MB  '
      'after=${boxedAfter.toStringAsFixed(2)} MB  '
      'delta=${boxedDelta.toStringAsFixed(2)} MB '
      '(${(boxedDelta * 1024 * 1024 / totalEls).toStringAsFixed(1)} B/element)');

  _churnHeap();
  _churnHeap();
  final typedBefore = _rssMB();
  final typedLists = <Float64List>[];
  for (var k = 0; k < _rssHoldCount; k++) {
    final list = Float64List(_elementCount);
    for (var i = 0; i < _elementCount; i++) {
      list[i] = (k * _elementCount + i) * 1.5;
    }
    typedLists.add(list);
  }
  final typedAfter = _rssMB();
  final typedDelta = typedAfter - typedBefore;
  print('  Float64List     '
      'baseline=${typedBefore.toStringAsFixed(2)} MB  '
      'after=${typedAfter.toStringAsFixed(2)} MB  '
      'delta=${typedDelta.toStringAsFixed(2)} MB '
      '(${(typedDelta * 1024 * 1024 / totalEls).toStringAsFixed(1)} B/element)');

  _reportRatio('  RSS ratio', boxedDelta, typedDelta,
      unit: 'MB', higherIsWorse: true);

  if (boxedLists.first[0] == null || typedLists.first[0] != 0.0) {
    throw StateError('sink');
  }
  print('');
}

// ---------------------------------------------------------------------------
// Section 3: Isolate transfer time
// ---------------------------------------------------------------------------
//
// Spawn a worker isolate, send the container, worker sends a
// confirmation reply. Measures round-trip cost including deep copy
// (for SendPort-normal) or memcpy (for TypedData).

Future<void> _section3IsolateTransfer() async {
  print('=== 3. Isolate transfer (${_elementCount} elements, '
      'SendPort.send) ===');
  print('');

  // Spawn one persistent echo worker and reuse it across all samples.
  // Isolate spawn itself costs ~10–50 ms; amortizing it over the
  // _outerRepeats samples would dominate a ~1ms send measurement.
  final handshake = Completer<SendPort>();
  final replies = <Completer<void>>[];
  final recvPort = ReceivePort();
  recvPort.listen((msg) {
    if (msg is SendPort) {
      handshake.complete(msg);
    } else {
      // Reply from worker — fulfill the oldest outstanding send.
      replies.removeAt(0).complete();
    }
  });
  final isolate = await Isolate.spawn(_echoWorker, recvPort.sendPort);
  final workerPort = await handshake.future;

  Future<int> sendAndWait(Object value) async {
    final replyCompleter = Completer<void>();
    replies.add(replyCompleter);
    final sw = Stopwatch()..start();
    workerPort.send(value);
    await replyCompleter.future;
    sw.stop();
    return sw.elapsedMicroseconds;
  }

  // Pre-build the payloads once — we want to measure send, not alloc.
  final boxedList = List<Object?>.filled(_elementCount, null, growable: false);
  for (var i = 0; i < _elementCount; i++) {
    boxedList[i] = i;
  }
  final typedList = Int64List(_elementCount);
  for (var i = 0; i < _elementCount; i++) {
    typedList[i] = i;
  }

  final boxed = await _benchAsync(
    'List<Object?> (SendPort deep-copy)',
    _outerRepeats,
    () => sendAndWait(boxedList),
  );

  final typed = await _benchAsync(
    'Int64List (SendPort TypedData memcpy)',
    _outerRepeats,
    () => sendAndWait(typedList),
  );

  _reportRatio('  speedup', boxed.toDouble(), typed.toDouble(),
      unit: 'μs', higherIsWorse: true);
  print('');

  recvPort.close();
  isolate.kill(priority: Isolate.immediate);
}

void _echoWorker(SendPort mainPort) {
  final workerRecv = ReceivePort();
  mainPort.send(workerRecv.sendPort);
  workerRecv.listen((msg) {
    // Touch first element so the VM can't optimize away the receive.
    int sentinel;
    if (msg is List<Object?>) {
      sentinel = msg[0] as int? ?? 0;
    } else if (msg is Int64List) {
      sentinel = msg[0];
    } else {
      sentinel = 0;
    }
    mainPort.send(sentinel);
  });
}

// ---------------------------------------------------------------------------
// Section 4: Iteration (sum all values)
// ---------------------------------------------------------------------------

Future<void> _section4Iteration() async {
  print('=== 4. Iteration (sum ${_elementCount} ints) ===');
  print('');

  // Pre-build the containers once (outside the timed loop) so we
  // measure iteration cost only.
  final boxedList = List<Object?>.filled(_elementCount, null, growable: false);
  for (var i = 0; i < _elementCount; i++) {
    boxedList[i] = i;
  }
  final typedList = Int64List(_elementCount);
  for (var i = 0; i < _elementCount; i++) {
    typedList[i] = i;
  }

  final boxed = _bench('List<Object?> iter + as int', _outerRepeats, () {
    final sw = Stopwatch()..start();
    var sum = 0;
    for (var i = 0; i < _elementCount; i++) {
      sum += boxedList[i]! as int;
    }
    sw.stop();
    if (sum == 0) throw StateError('sink');
    return sw.elapsedMicroseconds;
  });

  final typed = _bench('Int64List iter (unboxed)', _outerRepeats, () {
    final sw = Stopwatch()..start();
    var sum = 0;
    for (var i = 0; i < _elementCount; i++) {
      sum += typedList[i];
    }
    sw.stop();
    if (sum == 0) throw StateError('sink');
    return sw.elapsedMicroseconds;
  });

  _reportRatio('  speedup', boxed.toDouble(), typed.toDouble(),
      unit: 'μs', higherIsWorse: true);
  print('');
}

// ---------------------------------------------------------------------------
// Section 5: Mixed schema RSS footprint
// ---------------------------------------------------------------------------
//
// Realistic CRUD schema: $_mixedIntCols int + $_mixedFloatCols double
// + $_mixedTextCols short text columns, repeated $_rowCount times.
// Compares flat row-major List<Object?> against parallel columnar
// typed arrays. Strings stay boxed in both (unavoidable).

Future<void> _section5MixedSchemaRss() async {
  print('=== 5. Mixed-schema RSS ($_rowCount rows × '
      '${_mixedIntCols + _mixedFloatCols + _mixedTextCols} cols: '
      '${_mixedIntCols}i + ${_mixedFloatCols}d + ${_mixedTextCols}s) ===');
  print('');
  print('Row-major: flat List<Object?> of length rowCount × colCount,');
  print('  boxing ints and doubles.');
  print('Columnar:  parallel Int64List / Float64List / List<String>,');
  print('  one per column.');
  print('');

  // Row-major layout.
  _churnHeap();
  _churnHeap();
  final rowBefore = _rssMB();
  final rowMajor = _buildRowMajor();
  final rowAfter = _rssMB();
  final rowDelta = rowAfter - rowBefore;
  print('  Row-major  '
      'baseline=${rowBefore.toStringAsFixed(2)} MB  '
      'after=${rowAfter.toStringAsFixed(2)} MB  '
      'delta=${rowDelta.toStringAsFixed(2)} MB '
      '(${(rowDelta * 1024 / _rowCount).toStringAsFixed(2)} KB/row)');

  // Columnar layout.
  _churnHeap();
  _churnHeap();
  final colBefore = _rssMB();
  final columnar = _buildColumnar();
  final colAfter = _rssMB();
  final colDelta = colAfter - colBefore;
  print('  Columnar   '
      'baseline=${colBefore.toStringAsFixed(2)} MB  '
      'after=${colAfter.toStringAsFixed(2)} MB  '
      'delta=${colDelta.toStringAsFixed(2)} MB '
      '(${(colDelta * 1024 / _rowCount).toStringAsFixed(2)} KB/row)');

  _reportRatio('  RSS ratio', rowDelta, colDelta,
      unit: 'MB', higherIsWorse: true);

  // Keep both live past the measurement.
  if (rowMajor.first == null || columnar.length == 0) {
    throw StateError('sink');
  }
  print('');
}

List<Object?> _buildRowMajor() {
  final colCount = _mixedIntCols + _mixedFloatCols + _mixedTextCols;
  final values = List<Object?>.filled(_rowCount * colCount, null);
  var idx = 0;
  for (var r = 0; r < _rowCount; r++) {
    for (var c = 0; c < _mixedIntCols; c++) {
      values[idx++] = r * 100 + c;
    }
    for (var c = 0; c < _mixedFloatCols; c++) {
      values[idx++] = r * 1.5 + c * 0.3;
    }
    for (var c = 0; c < _mixedTextCols; c++) {
      values[idx++] = 's${r}_$c';
    }
  }
  return values;
}

List<Object> _buildColumnar() {
  final intColumns = List.generate(_mixedIntCols, (_) => Int64List(_rowCount));
  final floatColumns =
      List.generate(_mixedFloatCols, (_) => Float64List(_rowCount));
  final textColumns = List.generate(
    _mixedTextCols,
    (_) => List<String>.filled(_rowCount, ''),
  );
  for (var r = 0; r < _rowCount; r++) {
    for (var c = 0; c < _mixedIntCols; c++) {
      intColumns[c][r] = r * 100 + c;
    }
    for (var c = 0; c < _mixedFloatCols; c++) {
      floatColumns[c][r] = r * 1.5 + c * 0.3;
    }
    for (var c = 0; c < _mixedTextCols; c++) {
      textColumns[c][r] = 's${r}_$c';
    }
  }
  // Return a flat list holding every column so the caller can verify
  // length and hold the references live.
  return [...intColumns, ...floatColumns, ...textColumns];
}

// ---------------------------------------------------------------------------
// Timing + stats helpers
// ---------------------------------------------------------------------------

int _bench(String label, int repeats, int Function() body) {
  // Warmup.
  for (var i = 0; i < 3; i++) {
    body();
  }
  final samples = <int>[];
  for (var i = 0; i < repeats; i++) {
    samples.add(body());
  }
  samples.sort();
  final median = samples[samples.length ~/ 2];
  print('  ${label.padRight(40)}median=${median}μs  '
      'min=${samples.first}μs  max=${samples.last}μs');
  return median;
}

Future<int> _benchAsync(
    String label, int repeats, Future<int> Function() body) async {
  for (var i = 0; i < 3; i++) {
    await body();
  }
  final samples = <int>[];
  for (var i = 0; i < repeats; i++) {
    samples.add(await body());
  }
  samples.sort();
  final median = samples[samples.length ~/ 2];
  print('  ${label.padRight(40)}median=${median}μs  '
      'min=${samples.first}μs  max=${samples.last}μs');
  return median;
}

void _reportRatio(
  String label,
  double boxed,
  double typed, {
  required String unit,
  required bool higherIsWorse,
}) {
  if (typed <= 0 || boxed <= 0) {
    print('$label: N/A (zero measurement)');
    return;
  }
  final ratio = higherIsWorse ? boxed / typed : typed / boxed;
  final typedWins = higherIsWorse ? typed < boxed : typed > boxed;
  final verdict = typedWins ? 'typed wins' : 'boxed wins';
  print('$label: ${ratio.toStringAsFixed(2)}×  ($verdict)');
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

double _rssMB() => ProcessInfo.currentRss / (1024 * 1024);

void _churnHeap() {
  final junk = <Map<String, Object?>>[];
  for (var i = 0; i < _churnSize; i++) {
    junk.add({'a': i, 'b': 'x$i', 'c': i * 1.5});
  }
  junk.clear();
}
