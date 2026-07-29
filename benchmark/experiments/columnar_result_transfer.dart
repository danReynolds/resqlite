// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../shared/stats.dart';

/// Focused A/B harness for exp 258 — the columnar typed-array result store.
///
/// Exp 055 (2026-04-15) *assessed but never implemented* per-column typed
/// arrays (`Int64List`/`Float64List`) as a replacement for the flat boxed
/// `List<Object?>` result backing store, estimating "~1.8x faster isolate
/// transfer" and "10-15% faster iteration" but rejecting on the grounds that
/// the throughput win looked too small versus the noise floor and the memory
/// win needed a profiling methodology that did not exist. Exp 081 later
/// measured a *row-major binary* slab and rejected it because per-cell access
/// on the main isolate got slower. Exp 224 (2026-07-12) showed the per-row FFI
/// crossing is already cheap and named "Dart object construction / allocation"
/// as a top remaining rows-path cost.
///
/// The columnar *transfer + box-on-access* trade-off itself has never been
/// measured. This harness isolates the three costs columnar moves between,
/// end-to-end across a real worker->main `SendPort` hop:
///
///   1. build   — worker-side wall to materialize the result container.
///                Flat boxes every numeric cell; columnar fills typed arrays
///                with no boxing. (Off the main isolate; wall only.)
///   2. hop     — main-observed round trip (worker build + serialize + the
///                structured-clone receive charged to the MAIN isolate). This
///                is the "1.8x faster transfer" claim: a flat `List<Object?>`
///                of boxed numbers deep-copies element by element and
///                re-allocates every box on the receiver; a `Float64List`/
///                `Int64List` column crosses as one `memcpy`.
///   3. consume — main-isolate wall to full-scan every cell *as `Object?`*
///                (what a `row['c']` consumer sees). Flat reads already-boxed
///                pointers; columnar boxes on access — exp 081's concern.
///
/// Net main-isolate cost is what resqlite's contract keys on (main-isolate
/// time is the primary metric), so the decision figure is `hop + consume`,
/// not build alone. A memory lane records peak RSS while holding many result
/// sets live, for the GC-pressure claim 055 could not measure.
///
/// This harness does not stand up SQLite: it feeds both paths identical raw
/// numeric source data so the delta is purely the container mechanism (build,
/// transfer, access), which is exactly the part 055 estimated and never ran.

const _rows = 10000;
const _inner = 60; // build/consume repetitions per sample
const _samples = 25; // hop samples per lane per pass
const _memHold = 40; // result sets held live in the memory lane

// --------------------------------------------------------------------------
// Source data + container shapes
// --------------------------------------------------------------------------

enum _Type { int_, double_ }

final class _Lane {
  const _Lane(
    this.label,
    this.cols,
    this.type, {
    this.textCols = 0,
    this.rows = _rows,
  });
  final String label;
  final int cols; // numeric columns
  final _Type type;
  final int textCols; // trailing text columns (mixed lane)
  final int rows;
  int get totalCols => cols + textCols;
  int get slots => rows * totalCols;
  bool get sacrifices => slots > _sacrificeSlots;
}

/// `values.length` (rows*cols) above which production sacrifices the reader
/// via `Isolate.exit` (zero-copy) instead of `SendPort.send`. Must mirror
/// `sacrificeSlotThreshold` in lib/src/reader/read_worker.dart (32*1024).
/// Lanes above this transfer for free in production, so their `hop` delta
/// here (a SendPort A/B) does NOT represent production — see the writeup.
const _sacrificeSlots = 32 * 1024;

// Small lanes stay under _sacrificeSlots -> production uses SendPort.send,
// so their hop delta is production-representative. Large lanes exceed it ->
// production zero-copies via Isolate.exit, neutralizing the transfer axis.
const _lanes = <_Lane>[
  _Lane('1k x 8 INTEGER (send)', 8, _Type.int_, rows: 1000),
  _Lane('1k x 8 REAL (send)', 8, _Type.double_, rows: 1000),
  _Lane('1.5k x 20 REAL (send)', 20, _Type.double_, rows: 1500),
  _Lane('10k x 8 INTEGER (exit)', 8, _Type.int_),
  _Lane('10k x 20 INTEGER (exit)', 20, _Type.int_),
  _Lane('10k x 8 REAL (exit)', 8, _Type.double_),
  _Lane('10k x 20 REAL (exit)', 20, _Type.double_),
  _Lane('10k x (16 REAL + 4 TEXT) mixed (exit)', 16, _Type.double_, textCols: 4),
];

// Raw numeric source: a flat Float64List of totalNumeric cells, plus a text
// column pool. Both paths read from this identical source.
final class _Source {
  _Source(this.lane)
    : numeric = Float64List(lane.rows * lane.cols),
      texts = List<String>.generate(
        lane.rows,
        (r) => 'row_${r}_val',
        growable: false,
      ) {
    for (var i = 0; i < numeric.length; i++) {
      // Deterministic values; integers stay exactly representable.
      numeric[i] = ((i % 97) * 31 + (i & 7)).toDouble();
    }
  }
  final _Lane lane;
  final Float64List numeric;
  final List<String> texts;
}

// --------------------------------------------------------------------------
// Builders (run worker-side)
// --------------------------------------------------------------------------

/// Flat boxed row-major store — mirrors `decodeQuery`'s output exactly:
/// one `List<Object?>` of length rows*cols with every numeric cell boxed.
List<Object?> _buildFlat(_Source s) {
  final lane = s.lane;
  final total = lane.totalCols;
  final rows = lane.rows;
  final values = List<Object?>.filled(rows * total, null);
  final num = s.numeric;
  final numCols = lane.cols;
  final isInt = lane.type == _Type.int_;
  var w = 0;
  for (var r = 0; r < rows; r++) {
    final nbase = r * numCols;
    for (var c = 0; c < numCols; c++) {
      final d = num[nbase + c];
      values[w++] = isInt ? d.toInt() : d; // box
    }
    for (var c = 0; c < lane.textCols; c++) {
      values[w++] = s.texts[r];
    }
  }
  return values;
}

/// Columnar store: one typed array per numeric column, a `List<String>` per
/// text column, gathered in a `List<Object>` (column-major). No boxing.
List<Object> _buildColumnar(_Source s) {
  final lane = s.lane;
  final numCols = lane.cols;
  final rows = lane.rows;
  final isInt = lane.type == _Type.int_;
  final columns = List<Object>.filled(lane.totalCols, const <int>[]);
  final num = s.numeric;
  for (var c = 0; c < numCols; c++) {
    if (isInt) {
      final col = Int64List(rows);
      for (var r = 0; r < rows; r++) {
        col[r] = num[r * numCols + c].toInt();
      }
      columns[c] = col;
    } else {
      final col = Float64List(rows);
      for (var r = 0; r < rows; r++) {
        col[r] = num[r * numCols + c];
      }
      columns[c] = col;
    }
  }
  for (var c = 0; c < lane.textCols; c++) {
    final col = List<String>.filled(rows, '');
    for (var r = 0; r < rows; r++) {
      col[r] = s.texts[r];
    }
    columns[numCols + c] = col;
  }
  return columns;
}

// --------------------------------------------------------------------------
// Consumers (run main-isolate) — read every cell AS Object?, like row['c'].
// --------------------------------------------------------------------------

int _iSink = 0;
double _dSink = 0;
int _sSink = 0;

void _consumeFlat(List<Object?> values, int totalCols) {
  for (var i = 0; i < values.length; i++) {
    final Object? v = values[i];
    if (v is int) {
      _iSink += v;
    } else if (v is double) {
      _dSink += v;
    } else if (v is String) {
      _sSink += v.length;
    }
  }
}

void _consumeColumnar(List<Object> columns, int totalCols) {
  for (var c = 0; c < columns.length; c++) {
    final col = columns[c];
    if (col is Int64List) {
      for (var r = 0; r < col.length; r++) {
        final Object? v = col[r]; // box on access
        if (v is int) _iSink += v;
      }
    } else if (col is Float64List) {
      for (var r = 0; r < col.length; r++) {
        final Object? v = col[r]; // box on access
        if (v is double) _dSink += v;
      }
    } else if (col is List<String>) {
      for (var r = 0; r < col.length; r++) {
        final Object? v = col[r];
        if (v is String) _sSink += v.length;
      }
    }
  }
}

// --------------------------------------------------------------------------
// Worker isolate: builds a container on request and sends it back.
// --------------------------------------------------------------------------

final class _BuildReq {
  const _BuildReq(this.laneIndex, this.columnar, this.reply);
  final int laneIndex;
  final bool columnar;
  final SendPort reply;
}

void _workerMain(SendPort toMain) {
  final port = ReceivePort();
  toMain.send(port.sendPort);
  final sources = <int, _Source>{};
  port.listen((msg) {
    if (msg == 'stop') {
      port.close();
      return;
    }
    final req = msg as _BuildReq;
    final s = sources.putIfAbsent(req.laneIndex, () => _Source(_lanes[req.laneIndex]));
    final container = req.columnar ? _buildColumnar(s) : _buildFlat(s);
    req.reply.send(container);
  });
}

// --------------------------------------------------------------------------
// Timing
// --------------------------------------------------------------------------

double _median(List<double> xs) {
  final c = [...xs]..sort();
  return medianOfSorted(c);
}

/// Worker-side build wall: build `_inner` times locally, median ms.
double _buildWall(_Source s, bool columnar) {
  final samples = <double>[];
  for (var k = 0; k < _samples; k++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _inner; i++) {
      final c = columnar ? _buildColumnar(s) : _buildFlat(s);
      if (c.length == -1) print(c); // defeat DCE
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds / 1000.0 / _inner);
  }
  return _median(samples);
}

/// Main-observed round trip: request -> worker build+send -> main receive.
Future<double> _hopWall(SendPort worker, int laneIndex, bool columnar) async {
  final samples = <double>[];
  for (var k = 0; k < _samples; k++) {
    final reply = ReceivePort();
    final sw = Stopwatch()..start();
    worker.send(_BuildReq(laneIndex, columnar, reply.sendPort));
    await reply.first;
    sw.stop();
    reply.close();
    samples.add(sw.elapsedMicroseconds / 1000.0);
  }
  return _median(samples);
}

/// Main-isolate consume wall over one received container: `_inner` scans.
double _consumeWall(Object container, int totalCols, bool columnar) {
  final samples = <double>[];
  for (var k = 0; k < _samples; k++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < _inner; i++) {
      if (columnar) {
        _consumeColumnar(container as List<Object>, totalCols);
      } else {
        _consumeFlat(container as List<Object?>, totalCols);
      }
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds / 1000.0 / _inner);
  }
  return _median(samples);
}

Future<Object> _fetchOnce(SendPort worker, int laneIndex, bool columnar) async {
  final reply = ReceivePort();
  worker.send(_BuildReq(laneIndex, columnar, reply.sendPort));
  final c = await reply.first as Object;
  reply.close();
  return c;
}

// --------------------------------------------------------------------------
// Memory lane: hold `_memHold` result sets live, sample peak RSS.
// --------------------------------------------------------------------------

int _memLane(_Source s, bool columnar) {
  final held = <Object>[];
  for (var i = 0; i < _memHold; i++) {
    held.add(columnar ? _buildColumnar(s) : _buildFlat(s));
  }
  // Touch to keep live.
  var acc = 0;
  for (final c in held) {
    acc += (c as List).length;
  }
  final rss = ProcessInfo.currentRss;
  if (acc == -1) print('unreachable');
  held.clear();
  return rss;
}

// --------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final flip = args.contains('--flip'); // consume/measure order flip for drift
  final fromMain = ReceivePort();
  await Isolate.spawn(_workerMain, fromMain.sendPort);
  final worker = await fromMain.first as SendPort;

  print('# Exp 258 — columnar result transfer A/B');
  print('inner=$_inner samples=$_samples sacrificeSlots=$_sacrificeSlots '
      'order=${flip ? "columnar-first" : "flat-first"}\n');

  final rows = <List<String>>[];
  for (var li = 0; li < _lanes.length; li++) {
    final lane = _lanes[li];
    final s = _Source(lane);

    double flatBuild = 0, colBuild = 0, flatHop = 0, colHop = 0;
    double flatConsume = 0, colConsume = 0;

    Future<void> flatPass() async {
      flatBuild = _buildWall(s, false);
      flatHop = await _hopWall(worker, li, false);
      final c = await _fetchOnce(worker, li, false);
      flatConsume = _consumeWall(c, lane.totalCols, false);
    }

    Future<void> colPass() async {
      colBuild = _buildWall(s, true);
      colHop = await _hopWall(worker, li, true);
      final c = await _fetchOnce(worker, li, true);
      colConsume = _consumeWall(c, lane.totalCols, true);
    }

    if (flip) {
      await colPass();
      await flatPass();
    } else {
      await flatPass();
      await colPass();
    }

    final flatNet = flatHop + flatConsume;
    final colNet = colHop + colConsume;
    double pct(double base, double cand) =>
        base == 0 ? 0 : (cand - base) / base * 100;

    rows.add([
      lane.label,
      flatBuild.toStringAsFixed(3),
      colBuild.toStringAsFixed(3),
      '${pct(flatBuild, colBuild).toStringAsFixed(1)}%',
      flatHop.toStringAsFixed(3),
      colHop.toStringAsFixed(3),
      '${pct(flatHop, colHop).toStringAsFixed(1)}%',
      flatConsume.toStringAsFixed(3),
      colConsume.toStringAsFixed(3),
      '${pct(flatConsume, colConsume).toStringAsFixed(1)}%',
      '${pct(flatNet, colNet).toStringAsFixed(1)}%',
    ]);
  }

  // Print table.
  const headers = [
    'lane',
    'fBuild',
    'cBuild',
    'bΔ',
    'fHop',
    'cHop',
    'hopΔ',
    'fCons',
    'cCons',
    'consΔ',
    'NET(hop+cons)Δ',
  ];
  print('| ${headers.join(' | ')} |');
  print('|${List.filled(headers.length, '---').join('|')}|');
  for (final r in rows) {
    print('| ${r.join(' | ')} |');
  }
  print('\nAll times are ms. Δ = columnar vs flat (negative = columnar '
      'faster). Build is worker-side (off main isolate); Hop is the '
      'main-observed round trip (build+serialize+receive); Cons is '
      'main-isolate full-scan. NET = hop+cons is the main-isolate-charged '
      'decision figure.');

  // Memory lane (separate, single-shot to avoid cross-contamination).
  print('\n## Memory lane (peak RSS holding $_memHold live result sets)\n');
  print('| lane | flat RSS (MB) | columnar RSS (MB) | Δ |');
  print('|---|---:|---:|---:|');
  for (final lane in _lanes) {
    final s = _Source(lane);
    final flatRss = _memLane(s, false) / (1024 * 1024);
    final colRss = _memLane(s, true) / (1024 * 1024);
    final d = flatRss == 0 ? 0 : (colRss - flatRss) / flatRss * 100;
    print('| ${lane.label} | ${flatRss.toStringAsFixed(1)} | '
        '${colRss.toStringAsFixed(1)} | ${d.toStringAsFixed(1)}% |');
  }
  print('\nRSS is process-wide and noisy; read only large, reproduced gaps.');

  worker.send('stop');
  fromMain.close();
  print('\nsink=${_iSink ^ _dSink.toInt() ^ _sSink}');
}
