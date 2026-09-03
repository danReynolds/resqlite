// ignore_for_file: avoid_print
//
// Prices the `RowSchema` name→index `HashMap` on both of the two paths it
// lives on ([EXP-281]): the cross-isolate hop it rides on every rows read, and
// the column lookup it exists to serve.
//
// Claim 279.3 broke a point read's 6.3 us hop into 3.22 us of transport and
// ~3.1 us of resqlite's own per-request work, and flagged its own reply lane as
// a floor: it sent "plain lists rather than `Row` facades". The real reply is a
// `ResultSet` holding a `RowSchema`, and a `RowSchema` holds a
// `HashMap<String, int>` built eagerly in its constructor. The worker caches the
// schema per SQL, so the map is built once — but `SendPort.send` copies the
// whole graph, so the map is *copied on every read*, forever, for a lookup
// structure the caller may never consult.
//
// Lanes, and what each is for:
//
//   wire-<cols>            One round trip carrying a point read's reply shape
//                          at <cols> columns, with the schema's `HashMap`
//                          present. PRIMARY: `wire-6` is the canonical point
//                          read's width.
//   nowire-<cols>          The identical reply with no map on the schema. The
//                          pair is the per-read wire price of the index, and
//                          nothing else differs between them.
//   lookup-literal-<cols>  `row['name']` with a source literal — what
//                          application code actually writes. The decoded column
//                          names come from `String.fromCharCodes`, so a literal
//                          is never `identical` to one: this pattern misses
//                          exp 158's identity scan and pays the hash.
//   lookup-interned-<cols> `row[names[i]]` — the schema's own name objects, as
//                          `for (final k in row.keys) row[k]` re-feeds them.
//                          The identity scan's best case (exp 158/176).
//   lookup-miss-<cols>     A key that is not a column at all. The worst case for
//                          a scan and the best case for a hash.
//
// The lookup lanes are the guard on removing the map: a scan has to be at least
// as fast as hash-and-probe at the widths results actually have, or the wire
// saving is paid back at every cell access.
//
// Usage:
//   dart run benchmark/experiments/schema_index_transfer.dart \
//     [--samples=11] [--iterations=2000] [--lanes=wire-6,nowire-6] [--flip]
//
// Build it AOT for figures comparable with shipped code.
import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

/// Column counts the lanes are built at: 6 is the canonical point read's
/// width, 21 the `point1-wide20` shape, 40 a wide reporting row.
const _widths = <int>[6, 21, 40];

const _defaultIterations = 2000;
const _defaultLookups = 200000;

// ---------------------------------------------------------------------------
// Stand-ins for the shipped types
// ---------------------------------------------------------------------------

/// `RowSchema` in its shipped form and in each candidate form, in one class so
/// a wire lane pair differs in exactly one field.
///
/// [indexByName] is the shipped eager `HashMap`; [hashes] is the candidate's
/// flat `Uint32List` of the same names' hash codes. A lane carries one, the
/// other, or neither.
final class _Schema {
  _Schema(this.names, {required bool withIndex, required bool withHashes})
    : indexByName = withIndex ? HashMap<String, int>() : null,
      hashes = withHashes ? Uint32List(names.length) : null {
    final index = indexByName;
    if (index != null) {
      for (var i = 0; i < names.length; i++) {
        index[names[i]] = i;
      }
    }
    final digests = hashes;
    if (digests != null) {
      for (var i = 0; i < names.length; i++) {
        digests[i] = names[i].hashCode;
      }
    }
  }

  final List<String> names;
  final Map<String, int>? indexByName;
  final Uint32List? hashes;

  /// Built on demand by [indexOfLazy], standing in for a map the reply no
  /// longer carries. Concrete `HashMap`, so the lookup devirtualizes the way
  /// the shipped final field did.
  HashMap<String, int>? _lazyIndex;

  /// The shipped lookup: identity scan for narrow schemas, then the map.
  int indexOfHashed(String name) {
    for (var i = 0; i < names.length; i++) {
      if (identical(names[i], name)) return i;
    }
    return indexByName![name] ?? -1;
  }

  /// Candidate A: one equality scan. `String.==` tests identity first, so this
  /// subsumes the identity scan rather than running after it.
  int indexOfScanned(String name) {
    for (var i = 0; i < names.length; i++) {
      if (names[i] == name) return i;
    }
    return -1;
  }

  /// Candidate B: the shipped shape with the map built on first fallback use
  /// instead of ridden across the hop.
  int indexOfLazy(String name) {
    for (var i = 0; i < names.length; i++) {
      if (identical(names[i], name)) return i;
    }
    var index = _lazyIndex;
    if (index == null) {
      index = _lazyIndex = HashMap<String, int>();
      for (var i = 0; i < names.length; i++) {
        index[names[i]] = i;
      }
    }
    return index[name] ?? -1;
  }

  /// Candidate C: identity scan, then a scan of precomputed hash codes with an
  /// equality check only on a hash match. `String.hashCode` is cached in the
  /// string, so a repeated literal key hashes once for its whole lifetime.
  int indexOfDigest(String name) {
    final digests = hashes!;
    for (var i = 0; i < names.length; i++) {
      if (identical(names[i], name)) return i;
    }
    final wanted = name.hashCode;
    for (var i = 0; i < digests.length; i++) {
      if (digests[i] == wanted && names[i] == name) return i;
    }
    return -1;
  }

  /// Discards a lazily built index so a lookup lane measures the same state on
  /// every iteration.
  void resetLazy() => _lazyIndex = null;
}

/// `ResultSet`'s transferred state — the flat values list, the schema, the row
/// count. `Row` facades are built on the receiving side and never cross.
final class _Result {
  _Result(this.values, this.schema, this.rowCount);

  final List<Object?> values;
  final _Schema schema;
  final int rowCount;
}

/// Column names as a real read produces them: decoded per query, never
/// canonicalized, so a source literal of the same text is a different object.
List<String> _decodedNames(int columns) => List<String>.generate(
  columns,
  (i) => String.fromCharCodes('column_name_$i'.codeUnits),
  growable: false,
);

/// Literals of the same text, standing in for what a caller writes.
List<String> _literalNames(int columns) =>
    List<String>.generate(columns, (i) => 'column_name_$i', growable: false);

List<Object?> _cells(int columns) => List<Object?>.generate(
  columns,
  (i) => switch (i % 3) {
    0 => i,
    1 => 'value $i',
    _ => 1.5 + i,
  },
  growable: false,
);

// ---------------------------------------------------------------------------
// Wire lanes
// ---------------------------------------------------------------------------

void _echoEntry(SendPort reply) {
  final built = <String, Object?>{};
  for (final columns in _widths) {
    final names = _decodedNames(columns);
    final cells = _cells(columns);
    // The `(result, sacrificed, error)` envelope `_WorkerSlot` receives.
    built['wire-$columns'] = (
      _Result(cells, _Schema(names, withIndex: true, withHashes: false), 1),
      false,
      null,
    );
    built['nowire-$columns'] = (
      _Result(cells, _Schema(names, withIndex: false, withHashes: false), 1),
      false,
      null,
    );
    built['digest-$columns'] = (
      _Result(cells, _Schema(names, withIndex: false, withHashes: true), 1),
      false,
      null,
    );
  }
  final commands = RawReceivePort();
  commands.handler = (Object? message) {
    if (message == null) {
      commands.close();
      return;
    }
    final payload = built[message as String];
    if (payload == null) throw ArgumentError('unknown lane: $message');
    reply.send(payload);
  };
  reply.send(commands.sendPort);
}

/// Consumed so AOT keeps every field alive. A field no one reads is dropped
/// from the class, and a dropped field is never copied — an untouched reply
/// measures nothing at all.
int _sink = 0;

Future<(SendPort, RawReceivePort)> _spawnEcho() async {
  final ready = Completer<SendPort>.sync();
  final replies = RawReceivePort();
  replies.handler = (Object? message) {
    if (message is SendPort) ready.complete(message);
  };
  await Isolate.spawn(_echoEntry, replies.sendPort);
  return (await ready.future, replies);
}

Future<double> _runWire(
  SendPort commands,
  RawReceivePort replies,
  String lane,
  int iterations,
) async {
  Completer<Object?>? pending;
  replies.handler = (Object? message) {
    if (message is (_Result, bool, Null)) {
      final result = message.$1;
      _sink +=
          result.rowCount +
          result.values.length +
          result.schema.names.length +
          (result.schema.indexByName?.length ?? 0) +
          (result.schema.hashes?.length ?? 0);
    }
    pending!.complete(message);
  };
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final completer = pending = Completer<Object?>.sync();
    commands.send(lane);
    await completer.future;
  }
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / iterations;
}

// ---------------------------------------------------------------------------
// Lookup lanes
// ---------------------------------------------------------------------------

double _runLookup(String lane, int iterations) {
  final parts = lane.split('-');
  final form = parts[0];
  final kind = parts[1];
  final columns = int.parse(parts[2]);
  final schema = _Schema(
    _decodedNames(columns),
    withIndex: true,
    withHashes: true,
  );
  final keys = switch (kind) {
    'interned' => schema.names,
    'miss' => List<String>.generate(columns, (i) => 'absent_column_$i'),
    _ => _literalNames(columns),
  };
  final stopwatch = Stopwatch()..start();
  var found = 0;
  for (var i = 0; i < iterations; i++) {
    final key = keys[i % columns];
    found += switch (form) {
      'hash' => schema.indexOfHashed(key),
      'scan' => schema.indexOfScanned(key),
      'digest' => schema.indexOfDigest(key),
      _ => schema.indexOfLazy(key),
    };
  }
  stopwatch.stop();
  _sink += found;
  return stopwatch.elapsedMicroseconds * 1000 / iterations;
}

/// What one lazily built index costs, which is the per-read price candidate B
/// pays in exchange for keeping the map off the wire. Measured per build, not
/// per lookup: a `ResultSet` builds at most one.
double _runBuild(String lane, int iterations) {
  final columns = int.parse(lane.split('-')[1]);
  final schema = _Schema(
    _decodedNames(columns),
    withIndex: false,
    withHashes: false,
  );
  final key = _literalNames(columns)[0];
  final stopwatch = Stopwatch()..start();
  var found = 0;
  for (var i = 0; i < iterations; i++) {
    schema.resetLazy();
    found += schema.indexOfLazy(key);
  }
  stopwatch.stop();
  _sink += found;
  return stopwatch.elapsedMicroseconds * 1000 / iterations;
}

// ---------------------------------------------------------------------------

double _median(List<double> xs) {
  final sorted = List<double>.from(xs)..sort();
  return sorted[sorted.length ~/ 2];
}

Future<void> main(List<String> args) async {
  var samples = 11;
  var iterations = _defaultIterations;
  var lookups = _defaultLookups;
  var flip = false;
  List<String>? only;
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
    } else if (arg.startsWith('--lookups=')) {
      lookups = int.parse(arg.substring('--lookups='.length));
    } else if (arg.startsWith('--lanes=')) {
      only = arg.substring('--lanes='.length).split(',');
    } else if (arg == '--flip') {
      flip = true;
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  final wireLanes = <String>[
    for (final columns in _widths) ...[
      'wire-$columns',
      'nowire-$columns',
      'digest-$columns',
    ],
  ];
  final lookupLanes = <String>[
    for (final kind in ['literal', 'interned', 'miss'])
      for (final columns in _widths) ...[
        'hash-$kind-$columns',
        'scan-$kind-$columns',
        'lazy-$kind-$columns',
        'digest-$kind-$columns',
      ],
  ];
  final buildLanes = <String>[for (final c in _widths) 'build-$c'];
  bool wanted(String lane) => only == null || only.contains(lane);

  final (commands, replies) = await _spawnEcho();

  print('=== schema index transfer ===');
  print('iterations=$iterations lookups=$lookups samples=$samples flip=$flip');

  final wire = wireLanes.where(wanted).toList();
  final wireOrder = flip ? wire.reversed.toList() : wire;
  for (final lane in wireOrder) {
    await _runWire(commands, replies, lane, iterations ~/ 4);
  }
  final wireTimes = {for (final lane in wireOrder) lane: <double>[]};
  for (var sample = 0; sample < samples; sample++) {
    for (final lane in wireOrder) {
      wireTimes[lane]!.add(
        await _runWire(commands, replies, lane, iterations),
      );
    }
  }
  for (final lane in wire) {
    final sorted = List<double>.from(wireTimes[lane]!)..sort();
    print(
      'lane=$lane us_per_roundtrip=${_median(sorted).toStringAsFixed(3)} '
      'min=${sorted.first.toStringAsFixed(3)} '
      'max=${sorted.last.toStringAsFixed(3)}',
    );
  }

  commands.send(null);
  replies.close();

  final lookup = lookupLanes.where(wanted).toList();
  final lookupOrder = flip ? lookup.reversed.toList() : lookup;
  for (final lane in lookupOrder) {
    _runLookup(lane, lookups ~/ 4);
  }
  final lookupTimes = {for (final lane in lookupOrder) lane: <double>[]};
  for (var sample = 0; sample < samples; sample++) {
    for (final lane in lookupOrder) {
      lookupTimes[lane]!.add(_runLookup(lane, lookups));
    }
  }
  for (final lane in lookup) {
    final sorted = List<double>.from(lookupTimes[lane]!)..sort();
    print(
      'lane=$lane ns_per_lookup=${_median(sorted).toStringAsFixed(2)} '
      'min=${sorted.first.toStringAsFixed(2)} '
      'max=${sorted.last.toStringAsFixed(2)}',
    );
  }
  final build = buildLanes.where(wanted).toList();
  for (final lane in build) {
    _runBuild(lane, lookups ~/ 40);
    final times = <double>[];
    for (var sample = 0; sample < samples; sample++) {
      times.add(_runBuild(lane, lookups ~/ 10));
    }
    final sorted = List<double>.from(times)..sort();
    print(
      'lane=$lane ns_per_build=${_median(sorted).toStringAsFixed(2)} '
      'min=${sorted.first.toStringAsFixed(2)} '
      'max=${sorted.last.toStringAsFixed(2)}',
    );
  }

  if (_sink == 0) throw StateError('unreachable: results were never consumed');
}
