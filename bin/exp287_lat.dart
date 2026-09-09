// ignore_for_file: avoid_print

/// [EXP-249] Durable gate for invalidation-batched stream rerun dispatch.
///
/// Measures single-write emission latency under reactive fan-out: many streams
/// watch distinct partitions of one table, a write dirties all of them (column
/// -level invalidation) but changes exactly one, and we time from write-issue
/// to that partition's stream emitting. This is the user-visible metric the
/// batched dispatch (`StreamEngine._flushQueue` / `_requeryBatch`) targets:
/// packing the many cheap unchanged reruns into one message per worker instead
/// of one message each.
///
/// This is a single-sided harness — it measures the *shipped* behavior. To A/B
/// it against a baseline, run it in a candidate worktree and a baseline
/// worktree and compare (the exp 249 acceptance ran the two dispatch paths in
/// one process behind a temporary toggle; that scaffolding was removed before
/// merge). The heterogeneous scenario is the load-bearing guard: it verifies
/// the cost-gate (`_batchRowCountCap`) keeps a small stream's emission off the
/// critical path of a large partition's expensive re-hash.
///
///   * homogeneous — 100 small partitions (~100 rows each).
///   * heterogeneous — 10 large partitions (~2000 rows) + 90 small; targets are
///     small partitions, whose latency must not regress behind the large ones.
library;

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

Future<void> main(List<String> args) async {
  var trials = 60;
  var raw = false;
  for (final arg in args) {
    if (arg.startsWith('--trials=')) {
      trials = int.parse(arg.substring('--trials='.length));
    } else if (arg == '--raw') {
      raw = true;
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }
  if (trials < 1) throw ArgumentError('--trials must be >= 1');
  for (final hetero in [false, true]) {
    final label = hetero ? 'hetero-10large+90small' : 'homogeneous-100small';
    final h = await _LatencyHarness.open(hetero: hetero);
    try {
      final samples = await h.trials(trials: trials);
      _report(label, samples, raw: raw);
    } finally {
      await h.close();
    }
  }
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _p95(List<double> xs) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * 0.95).round()];
}

void _report(String label, List<double> samples, {required bool raw}) {
  print(
    '$label  single-write emit latency ms: '
    'p50=${_median(samples).toStringAsFixed(3)} '
    'p95=${_p95(samples).toStringAsFixed(3)} '
    '(n=${samples.length})',
  );
  if (raw) {
    print('$label samples_ms=${samples.join(',')}');
  }
}

class _LatencyHarness {
  _LatencyHarness(this._db, this._ownerRepId, this._targetOwners);
  final Database _db;

  /// owner_id -> a representative row id in that partition (to mutate).
  final Map<int, int> _ownerRepId;

  /// The owners whose emission latency we measure (small partitions).
  final List<int> _targetOwners;

  final _subs = <StreamSubscription<Object?>>[];
  late List<Completer<void>?> _emitWaiters;
  int _nextVal = 1000000;
  var _trialCursor = 0;

  static const int _smallRows = 100;
  static const int _largeRows = 2000;

  static Future<_LatencyHarness> open({required bool hetero}) async {
    final dir = await Directory.systemTemp.createTemp('exp249lat_');
    final db = await Database.open('${dir.path}/t.db');

    await db.execute(
      'CREATE TABLE items('
      'id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, value INTEGER)',
    );
    await db.execute('CREATE INDEX items_owner ON items(owner_id)');

    final rows = <List<Object?>>[];
    for (var owner = 1; owner <= 100; owner++) {
      final n = (hetero && owner <= 10) ? _largeRows : _smallRows;
      for (var r = 0; r < n; r++) {
        rows.add([owner, 0]);
      }
    }
    await db.executeBatch(
      'INSERT INTO items(owner_id, value) VALUES (?, ?)',
      rows,
    );

    final repId = <int, int>{};
    var id = 1;
    for (var owner = 1; owner <= 100; owner++) {
      final n = (hetero && owner <= 10) ? _largeRows : _smallRows;
      repId[owner] = id; // first id in this partition
      id += n;
    }

    final targets = <int>[
      for (var owner = 1; owner <= 100; owner++)
        if (!hetero || owner > 10) owner,
    ];

    final h = _LatencyHarness(db, repId, targets);
    await h._subscribe();
    return h;
  }

  Future<void> _subscribe() async {
    _emitWaiters = List<Completer<void>?>.filled(101, null);
    final drained = List<bool>.filled(101, false);
    for (var owner = 1; owner <= 100; owner++) {
      final o = owner;
      final sub = _db
          .stream(
            'SELECT id, value FROM items WHERE owner_id = ? ORDER BY id',
            [o],
          )
          .listen((_) {
            drained[o] = true;
            final w = _emitWaiters[o];
            if (w != null && !w.isCompleted) {
              _emitWaiters[o] = null;
              w.complete();
            }
          });
      _subs.add(sub);
    }
    await _waitUntil(() {
      for (var o = 1; o <= 100; o++) {
        if (!drained[o]) return false;
      }
      return true;
    });
  }

  Future<List<double>> trials({required int trials}) async {
    await _oneTrial(); // warmup (discarded)
    final out = <double>[];
    for (var t = 0; t < trials; t++) {
      out.add(await _oneTrial());
    }
    return out;
  }

  Future<double> _oneTrial() async {
    final target = _targetOwners[_trialCursor % _targetOwners.length];
    _trialCursor++;
    final waiter = _emitWaiters[target] = Completer<void>();
    final id = _ownerRepId[target]!;
    final sw = Stopwatch()..start();
    await _db.execute('UPDATE items SET value = ? WHERE id = ?', [
      _nextVal++,
      id,
    ]);
    await waiter.future;
    sw.stop();
    // Short inter-trial pause: keeps the reader pool warm (the sustained
    // burst regime batching targets) while letting most of the other
    // partitions' suppressed reruns clear, rather than idling the isolates
    // (which would measure cold-wakeup cost instead of dispatch cost).
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return sw.elapsedMicroseconds / 1000.0;
  }

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _db.close();
  }
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for predicate');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
