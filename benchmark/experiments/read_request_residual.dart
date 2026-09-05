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
//             real-rec /         the same pair once more, over a reply whose
//             real-class         schema is also freshly built rather than a
//                                `const` literal list — object for object what
//                                a reader replies with. This is the pair the
//                                end-to-end A/B agrees with.
//             busy-rec /         real-rec / real-class once more, with the
//             busy-class         worker burning ~2.3 us before it replies —
//                                about what a point read's SQLite half costs.
//             fresh-rec-str /    the record and class envelopes again, over a
//             fresh-class-str    payload whose TEXT cells are freshly built
//                                rather than canonical literals — the shape a
//                                real decode produces. This pair is what the
//                                end-to-end A/B has to agree with.
//             fresh-rec /        the same three envelopes over a reply built
//             fresh-class /      FRESH on the worker for every message, which
//             fresh-list         is what a real reader does. Every lane above
//                                re-sends one long-lived instance; these are
//                                the ones to believe.

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

/// Code units of the two TEXT cells, so [_freshRow] can build strings the
/// receiving isolate has never seen. A `String` literal is canonical and
/// crosses a same-group boundary by reference (claim 245.1); a string a worker
/// just decoded out of SQLite is not, and has to be copied. Every lane built
/// from [_row] carries the cheap kind.
final List<int> _nameCodes = 'Widget'.codeUnits;
final List<int> _descCodes = 'A short description'.codeUnits;

/// The same row as [_row], but with both TEXT cells freshly allocated, which
/// is what `decodeQuery`'s `String.fromCharCodes` hands the reply.
List<Object?> _freshRow() => <Object?>[
  1,
  String.fromCharCodes(_nameCodes),
  19.99,
  String.fromCharCodes(_descCodes),
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

/// A `ReadReply`-shaped envelope: the class the candidate sends in place of
/// the `(result, sacrificed, error)` record.
final class _ClassEnv {
  _ClassEnv(this.result, this.sacrificed, this.error);
  final Object? result;
  final bool sacrificed;
  final Object? error;
}

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
const _markerFreshRec = 13;
const _markerFreshClass = 14;
const _markerFreshList = 15;
const _markerFreshRecStr = 16;
const _markerFreshClassStr = 17;
const _markerRealRec = 18;
const _markerRealClass = 19;
const _markerBusyRec = 20;
const _markerBusyClass = 21;

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
  // A worker caches one schema per SQL, so the fresh lanes reuse it too and
  // differ from each other only in the envelope.
  final freshSchema = RowSchema(_columns);

  // The real thing: a cached schema whose `names` list and column strings were
  // built at run time, exactly as `_schemaFor` builds them from
  // `sqlite3_column_name`. `_columns` is a `const` list of literals, which is
  // canonical and crosses for free; this one is not, and has to be copied.
  final realSchema = RowSchema(
    List<String>.generate(
      _columns.length,
      (i) => String.fromCharCodes(_columns[i].codeUnits),
      growable: false,
    ),
  );
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
      // The three lanes that matter most: a reply built FRESH per message,
      // the way a real reader builds one, differing only in the envelope.
      // The lanes above re-send one long-lived instance, which is not what
      // the library does and may not cost what the library pays.
      case _markerFreshRec:
        reply.send((ResultSet(_row(), freshSchema, 1), false, null));
      case _markerFreshClass:
        reply.send(_ClassEnv(ResultSet(_row(), freshSchema, 1), false, null));
      case _markerFreshList:
        reply.send(<Object?>[ResultSet(_row(), freshSchema, 1), false, null]);
      // The pair that decides the experiment: the same two envelopes over a
      // payload whose strings are new to the receiver, as a real read's are.
      case _markerFreshRecStr:
        reply.send((ResultSet(_freshRow(), freshSchema, 1), false, null));
      case _markerFreshClassStr:
        reply.send(
          _ClassEnv(ResultSet(_freshRow(), freshSchema, 1), false, null),
        );
      // Object for object, what a reader actually replies with: fresh cells,
      // a fresh values list, and a cached-but-not-canonical schema.
      case _markerRealRec:
        reply.send((ResultSet(_freshRow(), realSchema, 1), false, null));
      case _markerRealClass:
        reply.send(
          _ClassEnv(ResultSet(_freshRow(), realSchema, 1), false, null),
        );
      // The same pair with the worker doing ~2.3 us of work first, which is
      // roughly what a point read's SQLite half costs. An echo isolate that
      // replies instantly is the one thing no real worker ever does.
      case _markerBusyRec:
        _spin(4);
        reply.send((ResultSet(_freshRow(), realSchema, 1), false, null));
      case _markerBusyClass:
        _spin(4);
        reply.send(
          _ClassEnv(ResultSet(_freshRow(), realSchema, 1), false, null),
        );
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
      'fresh-rec' => _markerFreshRec,
      'fresh-class' => _markerFreshClass,
      'fresh-list' => _markerFreshList,
      'fresh-rec-str' => _markerFreshRecStr,
      'fresh-class-str' => _markerFreshClassStr,
      'real-rec' => _markerRealRec,
      'real-class' => _markerRealClass,
      'busy-rec' => _markerBusyRec,
      'busy-class' => _markerBusyClass,
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
  'fresh-rec',
  'fresh-class',
  'fresh-list',
  'fresh-rec-str',
  'fresh-class-str',
  'real-rec',
  'real-class',
  'busy-rec',
  'busy-class',
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
