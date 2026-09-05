// ignore_for_file: avoid_print
//
// Decomposes the half of a point read's isolate hop that exp 279 could not
// account for ([EXP-282]).
//
// Exp 265 measured `select()`'s round trip at 6.3 us (claim 265.1). Exp 279
// priced the messages that carry it at 3.22 us (claim 279.3) and concluded the
// other ~3.1 us is "resqlite's own per-request work on the two sides of it",
// naming seven items and saying the next step was to measure them individually.
// This harness does that, and it also re-examines both ends of the subtraction,
// because a residual computed from two numbers is only as good as either one.
//
// Three parts, each selectable with `--part=`:
//
//   reply   Transport lanes over one echo isolate — no SQLite, no pool. Exp
//           279's `iso-result` lane sent a *stand-in* for a point read's reply:
//           plain lists, no `ResultSet`, no `RowSchema`, no name index. These
//           lanes walk from that stand-in up to the object graph `_WorkerSlot`
//           actually receives, so the difference says how much of the residual
//           was transport that the floor lane did not carry.
//
//             reply-echo         an int out, an int back. The floor.
//             reply-279          exp 279's `iso-result` payload, verbatim.
//             reply-values       `(List<Object?> of 6, false, null)`.
//             reply-nomap        + `ResultSet` over a schema with no name
//                                index (the shape exp 281 ships).
//             reply-real         + the `HashMap` name index: what main sends
//                                today, object for object.
//             reply-one          the smallest non-trivial reply there is: a
//                                one-slot `List<Object?>`. Against reply-echo
//                                this separates what a message costs because
//                                it is an object graph at all from what it
//                                costs because of what is in the graph.
//             reply-triple       `(1, false, null)` — a record of three
//                                constants, no list.
//             reply-list3        `<Object?>[1, false, null]` — the same three
//                                constants as a List. The pair with
//                                reply-triple isolates the *record* from what
//                                it holds.
//             reply-pair         `(1, false)` — a two-field record, for
//                                whether the cost scales with fields.
//             reply-bare         the real `ResultSet` with no envelope around
//                                it: the shape a reply would have if the
//                                `(result, sacrificed, error)` record were
//                                removed.
//             reply-listenv      the real reply with the envelope kept but
//                                carried as a `List` instead of a record: the
//                                candidate's actual wire shape.
//             reply-nest-rec /   a record inside a record against a list
//             reply-nest-list    inside a list, for whether the penalty is
//                                per record instance or once per message.
//             req-one            a one-slot list out, an int back: the same
//                                split on the request side.
//             req-real           a real `SelectRequest` out, an int back.
//             full-real          real request out, real reply back, one trip.
//             busy-0/4/8/20u     the real reply again, but the echo isolate
//                                burns N spin units first, so the caller is
//                                left with nothing to do exactly as it is
//                                while a reader steps SQLite. Subtract the
//                                `spin-Nu` item price and what remains is the
//                                round trip's overhead; if that rises with
//                                the wait, the cost is parking the caller,
//                                which no payload change can reach.
//
//   items   The seven named per-request items, each on its own, batched hard
//           because several are expected in the tens of nanoseconds. No isolate
//           in any lane; `setbusy` is the only one that touches native code.
//
//   e2e     The denominator, re-measured on current main: a point read through
//           the pool against the same read run inline on the calling isolate.
//           `hop = pool - inline`. Claim 265.1's 6.3 us predates exps 260, 264,
//           266, 267 and 278; a residual subtracted from a stale hop is a
//           residual of nothing.
//
// Usage:
//   dart run benchmark/experiments/read_request_residual.dart \
//     [--part=reply|items|e2e|all] [--samples=11] [--iterations=2000]
//
// Build it AOT for figures comparable with shipped code.
import 'dart:async';
import 'dart:collection';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/blob_transfer.dart' show blobTransfer;
import 'package:resqlite/src/native/resqlite_bindings.dart'
    show resqliteClose, resqliteExec, resqliteOpen, resqliteReaderSetBusy;
import 'package:resqlite/src/query_decoder.dart' show RowSizeMemory;
import 'package:resqlite/src/reader/read_worker.dart'
    show SelectRequest, executeQuery;

const _sql = 'SELECT * FROM products WHERE id = ?';
const _columns = <String>[
  'id',
  'name',
  'price',
  'description',
  'in_stock',
  'created_at',
];

/// One row of the six-column point read every lane here is about.
List<Object?> _row() => <Object?>[
  1,
  'Widget',
  19.99,
  'A short description',
  1,
  1735689600000,
];

int _sink = 0;

double _median(List<double> xs) {
  final sorted = List<double>.from(xs)..sort();
  return sorted[sorted.length ~/ 2];
}

// ---------------------------------------------------------------------------
// Part: reply — what the messages actually carry
// ---------------------------------------------------------------------------

/// A schema with the same fields as [RowSchema] minus the name index, so the
/// `reply-nomap` lane can be measured on `main` without depending on exp 281.
final class _SchemaNoMap {
  _SchemaNoMap(this.names);
  final List<String> names;
  // ignore: unused_field
  final Object? _indexByName = null;
}

/// A `ResultSet`-shaped holder over [_SchemaNoMap]; same field count and
/// arrangement as the real one.
final class _ResultSetNoMap {
  _ResultSetNoMap(this._values, this._schema, this._rowCount);
  // ignore: unused_field
  final List<Object?> _values;
  // ignore: unused_field
  final _SchemaNoMap _schema;
  // ignore: unused_field
  final int _rowCount;
  // ignore: unused_field
  final bool hasWrappedCells = false;
}

/// Shaped like `SelectRequest`, for the request-side lane in the echo isolate
/// (the real class cannot be constructed with a sentinel `rowHint` and also
/// stay a faithful shape, so both are sent — see `req-real` / `full-real`).
const _markerEcho = 0;
const _markerReply279 = 1;
const _markerValues = 2;
const _markerNoMap = 3;
const _markerReal = 4;
const _markerOne = 5;
const _markerTriple = 6;
const _markerList3 = 7;
const _markerPair = 8;
const _markerBare = 9;
const _markerListEnv = 10;
const _markerNestRec = 11;
const _markerNestList = 12;

/// Markers at or above this ask the echo isolate to burn `marker - _markerBusy`
/// spin units before sending the real reply. The marker is still one `int`, so
/// the busy lanes carry exactly the same payload as `reply-real` in both
/// directions and differ only in how long the caller is left with nothing to do.
const _markerBusy = 1000;

/// Iterations of [_spin]'s loop per unit. Sized so one unit lands near a
/// quarter of a microsecond; the exact figure is measured by the `spin-1u`
/// item lane rather than assumed.
const _spinIterationsPerUnit = 250;

int _spinSink = 0;

/// A deterministic loop the AOT compiler cannot fold away, standing in for the
/// SQLite work a real reader does between receiving a request and replying.
void _spin(int units) {
  var x = _spinSink;
  final n = units * _spinIterationsPerUnit;
  for (var i = 0; i < n; i++) {
    x = (x * 31 + i) & 0x3FFFFFFF;
  }
  _spinSink = x;
}

void _echoEntry(SendPort reply) {
  // Built once on the worker so a lane times transfer, not construction.
  final reply279 = (<List<Object?>>[_row()], _columns, false, null);
  final values = (_row(), false, null);
  final one = <Object?>[1];
  final triple = (1, false, null);
  final list3 = <Object?>[1, false, null];
  final pair = (1, false);
  final bare = ResultSet(_row(), RowSchema(_columns), 1);
  final listEnv = <Object?>[
    ResultSet(_row(), RowSchema(_columns), 1),
    false,
    null,
  ];
  final nestRec = ((1, 2, 3), false, null);
  final nestList = <Object?>[
    <Object?>[1, 2, 3],
    false,
    null,
  ];
  final noMap = (
    _ResultSetNoMap(_row(), _SchemaNoMap(_columns), 1),
    false,
    null,
  );
  final real = (ResultSet(_row(), RowSchema(_columns), 1), false, null);

  final commands = RawReceivePort();
  commands.handler = (Object? msg) {
    if (msg == null) {
      commands.close();
      return;
    }
    if (msg is List) {
      reply.send(msg.length);
      return;
    }
    if (msg is SelectRequest) {
      // rowHint == -1 marks the `full-real` lane: object out, reply back.
      reply.send(msg.rowHint == -1 ? real : msg.rowHint);
      return;
    }
    final marker = msg as int;
    if (marker >= _markerBusy) {
      _spin(marker - _markerBusy);
      reply.send(real);
      return;
    }
    switch (marker) {
      case _markerReply279:
        reply.send(reply279);
      case _markerValues:
        reply.send(values);
      case _markerNoMap:
        reply.send(noMap);
      case _markerReal:
        reply.send(real);
      case _markerOne:
        reply.send(one);
      case _markerTriple:
        reply.send(triple);
      case _markerList3:
        reply.send(list3);
      case _markerPair:
        reply.send(pair);
      case _markerBare:
        reply.send(bare);
      case _markerListEnv:
        reply.send(listEnv);
      case _markerNestRec:
        reply.send(nestRec);
      case _markerNestList:
        reply.send(nestList);
      default:
        reply.send(marker);
    }
  };
  reply.send(commands.sendPort);
}

Future<(SendPort, RawReceivePort)> _spawnEcho() async {
  final ready = Completer<SendPort>.sync();
  final replies = RawReceivePort();
  replies.handler = (Object? msg) {
    if (msg is SendPort) ready.complete(msg);
  };
  await Isolate.spawn(_echoEntry, replies.sendPort);
  return (await ready.future, replies);
}

Future<void> _runReply(
  SendPort commands,
  RawReceivePort replies,
  int n,
  String lane,
) async {
  Completer<Object?>? pending;
  replies.handler = (Object? msg) => pending!.complete(msg);
  for (var i = 0; i < n; i++) {
    final completer = pending = Completer<Object?>.sync();
    commands.send(switch (lane) {
      'reply-echo' => _markerEcho,
      'reply-279' => _markerReply279,
      'reply-values' => _markerValues,
      'reply-nomap' => _markerNoMap,
      'reply-real' => _markerReal,
      'reply-one' => _markerOne,
      'reply-triple' => _markerTriple,
      'reply-list3' => _markerList3,
      'reply-pair' => _markerPair,
      'reply-bare' => _markerBare,
      'reply-listenv' => _markerListEnv,
      'reply-nest-rec' => _markerNestRec,
      'reply-nest-list' => _markerNestList,
      'req-one' => <Object?>[i],
      'req-real' => SelectRequest(_sql, <Object?>[i])..rowHint = i,
      'full-real' => SelectRequest(_sql, <Object?>[i])..rowHint = -1,
      _ => _markerBusy + _busyUnits[lane]!,
    });
    final result = await completer.future;
    _sink ^= result is int ? result : 1;
  }
}

/// Spin units the echo isolate burns before replying, per busy lane.
const _busyUnits = <String, int>{
  'busy-0u': 0,
  'busy-4u': 4,
  'busy-8u': 8,
  'busy-20u': 20,
};

const _replyLanes = <String>[
  'reply-echo',
  'reply-one',
  'reply-triple',
  'reply-list3',
  'reply-pair',
  'reply-bare',
  'reply-listenv',
  'reply-nest-rec',
  'reply-nest-list',
  'req-one',
  'reply-279',
  'reply-values',
  'reply-nomap',
  'reply-real',
  'req-real',
  'full-real',
  'busy-0u',
  'busy-4u',
  'busy-8u',
  'busy-20u',
];

/// Warms every lane before any is timed, then rotates which lane leads each
/// sample. A per-lane block measured `reply-echo` — a strict subset of every
/// other lane's work — as the slowest of the seven, which is how you know
/// blocks do not work here.
Future<void> _partReply(int iterations, int samples) async {
  final (commands, replies) = await _spawnEcho();
  print('=== part: reply (transport shapes, one echo isolate) ===');
  print('iterations=$iterations samples=$samples');
  for (var w = 0; w < 2; w++) {
    for (final lane in _replyLanes) {
      await _runReply(commands, replies, iterations ~/ 4, lane);
    }
  }
  final perCall = {for (final lane in _replyLanes) lane: <double>[]};
  for (var s = 0; s < samples; s++) {
    for (var k = 0; k < _replyLanes.length; k++) {
      final lane = _replyLanes[(s + k) % _replyLanes.length];
      final sw = Stopwatch()..start();
      await _runReply(commands, replies, iterations, lane);
      sw.stop();
      perCall[lane]!.add(
        sw.elapsedTicks * 1e6 / Stopwatch().frequency / iterations,
      );
    }
  }
  for (final lane in _replyLanes) {
    final sorted = List<double>.from(perCall[lane]!)..sort();
    print(
      'lane=$lane us_per_roundtrip=${_median(sorted).toStringAsFixed(3)} '
      'min=${sorted.first.toStringAsFixed(3)} '
      'max=${sorted.last.toStringAsFixed(3)}',
    );
  }
  commands.send(null);
  replies.close();
}

// ---------------------------------------------------------------------------
// Part: items — the seven named per-request costs, one at a time
// ---------------------------------------------------------------------------

/// Stands in for `ReaderPool._workers`: four slots, first one free.
final class _Slot {
  bool busy = false;
  bool get isAvailable => !busy;
}

/// Stands in for `_WorkerSlot`'s reply envelope destructure.
typedef _Envelope = (Object?, bool, ResqliteException?);

/// A 128-entry row-hint map, the size `ReaderPool.rowSizeMemoryMax` allows.
Map<String, RowSizeMemory> _buildHints() {
  final hints = LinkedHashMap<String, RowSizeMemory>();
  for (var i = 0; i < 127; i++) {
    hints['SELECT * FROM t$i WHERE id = ?'] = RowSizeMemory()
      ..record(1)
      ..record(1);
  }
  hints[_sql] = RowSizeMemory()
    ..record(1)
    ..record(1);
  return hints;
}

/// Warms every lane, then rotates which one leads each sample, for the same
/// reason [_partReply] does.
List<double> _timeItems(
  List<void Function()> bodies,
  int iterations,
  int samples,
) {
  for (final body in bodies) {
    for (var w = 0; w < iterations; w++) {
      body();
    }
  }
  final perCall = List.generate(bodies.length, (_) => <double>[]);
  for (var s = 0; s < samples; s++) {
    for (var k = 0; k < bodies.length; k++) {
      final lane = (s + k) % bodies.length;
      final body = bodies[lane];
      final sw = Stopwatch()..start();
      for (var i = 0; i < iterations; i++) {
        body();
      }
      sw.stop();
      perCall[lane].add(
        sw.elapsedTicks * 1e9 / Stopwatch().frequency / iterations,
      );
    }
  }
  return [for (final s in perCall) _median(s)];
}

void _partItems(int handleAddr, int iterations, int samples) {
  final hints = _buildHints();
  final memory = hints[_sql]!;
  final slots = List.generate(4, (_) => _Slot());
  final waiters = Queue<Completer<void>>();
  final values = _row();
  final schema = RowSchema(_columns);
  final resultSet = ResultSet(values, schema, 1);
  final rows = resultSet as List<Map<String, Object?>>;
  final db = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
  var preferred = 0;

  final lanes = <String, void Function()>{
    // ReaderPool.select's `_rowHints[sql]` before the dispatch.
    'hint-lookup': () {
      _sink ^= hints[_sql]!.hint;
    },
    // Request construction plus _dispatch's two-field stamp.
    'request-build': () {
      final request = SelectRequest(_sql, const <Object?>[1]);
      request.rowHint = memory.hint;
      request.initialRowHint = memory.initialRows;
      _sink ^= request.rowHint;
    },
    // _dispatch's scan for an available worker, first slot free.
    'dispatch-scan': () {
      for (var attempt = 0; attempt < 4; attempt++) {
        final index = (preferred + attempt) % 4;
        if (slots[index].isAvailable) {
          preferred = index;
          _sink ^= index;
          break;
        }
      }
    },
    // _WorkerSlot.request's sync completer, and its resolution.
    'completer': () {
      final completer = Completer<Object?>.sync();
      completer.complete(1);
      _sink ^= completer.isCompleted ? 1 : 0;
    },
    // The worker's `eventPort.send((result, false, null))` allocation and the
    // handler's destructure of it, plus the empty-waiter-queue check.
    'reply-envelope': () {
      final _Envelope envelope = (resultSet, false, null);
      final (result, sacrificed, error) = envelope;
      if (waiters.isNotEmpty) waiters.removeFirst().complete();
      _sink ^= sacrificed || error != null ? 0 : (result == null ? 0 : 1);
    },
    // ReaderPool._record on the hit path.
    'record': () {
      memory.record(1);
      _sink ^= memory.hint;
    },
    // blobTransfer.materializeCells on a result with no wrapped cells.
    'materialize': () {
      blobTransfer.materializeCells(rows);
      _sink ^= rows.length;
    },
    // The worker's setBusy bracket: two leaf FFI calls per request.
    'setbusy': () {
      resqliteReaderSetBusy(db, 0, 1);
      resqliteReaderSetBusy(db, 0, 0);
    },
    // _toRows: RawQueryResult.toResultSet's one allocation.
    'to-resultset': () {
      _sink ^= ResultSet(values, schema, 1).length;
    },
    // Calibration for the busy lanes: what one spin unit actually costs, so
    // `busy-Nu` minus N units of spin is a real overhead figure.
    'spin-1u': () => _spin(1),
    'spin-4u': () => _spin(4),
  };

  print('=== part: items (per-request work, no isolate) ===');
  print('iterations=$iterations samples=$samples');
  final names = lanes.keys.toList();
  final medians = _timeItems(lanes.values.toList(), iterations, samples);
  var total = 0.0;
  for (var i = 0; i < names.length; i++) {
    // The spin lanes calibrate `part: reply`'s busy lanes; they are not part
    // of a read's per-request work and must not enter the sum.
    if (!names[i].startsWith('spin-')) total += medians[i];
    print('item=${names[i]} ns_per_call=${medians[i].toStringAsFixed(1)}');
  }
  print('items_total_ns=${total.toStringAsFixed(1)}');
}

// ---------------------------------------------------------------------------
// Part: e2e — today's hop
// ---------------------------------------------------------------------------

Future<void> _partE2e(
  Database db,
  int handleAddr,
  int iterations,
  int samples,
) async {
  Future<double> pool() async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      _sink ^= (await db.select(_sql, <Object?>[1])).length;
    }
    sw.stop();
    return sw.elapsedTicks * 1e6 / Stopwatch().frequency / iterations;
  }

  double inline() {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      final raw = executeQuery(handleAddr, 0, _sql, <Object?>[1], 0, 1);
      final rows = raw.toResultSet() as List<Map<String, Object?>>;
      blobTransfer.materializeCells(rows);
      _sink ^= rows.length;
    }
    sw.stop();
    return sw.elapsedTicks * 1e6 / Stopwatch().frequency / iterations;
  }

  // Warm both arms before either is timed.
  await pool();
  inline();

  final poolUs = <double>[];
  final inlineUs = <double>[];
  // Alternate arms every sample so drift lands on both equally.
  for (var s = 0; s < samples; s++) {
    if (s.isEven) {
      poolUs.add(await pool());
      inlineUs.add(inline());
    } else {
      inlineUs.add(inline());
      poolUs.add(await pool());
    }
  }
  final p = _median(poolUs);
  final i = _median(inlineUs);
  print('=== part: e2e (today\'s hop) ===');
  print('iterations=$iterations samples=$samples');
  print('lane=pool us_per_read=${p.toStringAsFixed(3)}');
  print('lane=inline us_per_read=${i.toStringAsFixed(3)}');
  print('hop_us=${(p - i).toStringAsFixed(3)}');
}

// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  var part = 'all';
  var samples = 11;
  var iterations = 2000;
  for (final arg in args) {
    if (arg.startsWith('--part=')) {
      part = arg.substring('--part='.length);
    } else if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  if (part == 'reply' || part == 'all') {
    await _partReply(iterations, samples);
  }
  if (part == 'reply') return;

  final tmp = await Directory.systemTemp.createTemp('resqlite-exp282-');
  final path = '${tmp.path}/d.db';

  // A raw handle on the same file backs the inline and setbusy lanes; the
  // Database below opens its own connections, and both only read.
  final pathUtf8 = path.toNativeUtf8();
  final keyUtf8 = ''.toNativeUtf8();
  final handle = resqliteOpen(pathUtf8, 1, keyUtf8);
  calloc.free(pathUtf8);
  calloc.free(keyUtf8);
  if (handle == ffi.nullptr) throw StateError('open failed');

  void exec(String sql) {
    final s = sql.toNativeUtf8();
    final rc = resqliteExec(handle, s.cast());
    calloc.free(s);
    if (rc != 0) throw StateError('exec rc=$rc: $sql');
  }

  exec('PRAGMA journal_mode=WAL');
  exec(
    'CREATE TABLE products(id INTEGER PRIMARY KEY, name TEXT, price REAL, '
    'description TEXT, in_stock INTEGER, created_at INTEGER)',
  );
  exec(
    'WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<1000) '
    "INSERT INTO products SELECT x, 'Widget', 19.99, "
    "'A short description', 1, 1735689600000 FROM cnt",
  );

  if (part == 'items' || part == 'all') {
    _partItems(handle.address, iterations * 10, samples);
  }
  if (part == 'e2e' || part == 'all') {
    final db = await Database.open(path);
    await _partE2e(db, handle.address, iterations ~/ 4, samples);
    await db.close();
  }

  resqliteClose(handle);
  await tmp.delete(recursive: true);
  if (_sink == -1) print(_sink);
}
