// ignore_for_file: avoid_print

/// [EXP-283] A/B harness for one-pass decode+hash on changed stream reruns.
///
/// A dirtied stream re-executes its query on a reader worker so the engine can
/// learn whether its result changed; today that is a hash pass, plus a second
/// step pass whenever the hash moved. This harness measures the shapes where
/// that second pass is and is not paid.
///
/// Each sample issues its write burst concurrently and then times a sentinel
/// write through to the one stream it is guaranteed to change. Every rerun the
/// burst scheduled — including the unchanged majority, which emits nothing and
/// so cannot be waited on directly — has to clear the queue before the
/// sentinel's own rerun runs, so the sentinel's emission prices the whole
/// backlog. An awaited write-by-write burst cannot: each rerun overlaps the
/// next write's latency and the wall reads as the write burst.
///
/// Lanes:
///   fanout      — 100 streams over 100-row partitions, 200 random writes.
///                 ~56% of its reruns change (see `stream_rerun_census.dart`),
///                 so this is the primary lane.
///   fanout-wide — 20 streams over 1,000-row partitions: same shape, ~8x the
///                 per-rerun step cost, so the mechanism's ceiling is visible.
///   keyed-pk    — 50 streams each on one PK, 200 random-PK writes over 10k
///                 rows. Under 1% of its reruns change, so the candidate must
///                 be inert: this is the miss-tax guard.
///   feed        — one latest-50 stream, 100 like_count writes that never
///                 touch the watched page. Zero reruns change; second guard.
///   writes      — the same write burst with nothing subscribed. Mechanically
///                 zero-ceiling, so the collection's own floor reads off it.
///
/// Run the same command in a baseline and a candidate worktree (exp 249: never
/// A/B stream dispatch with an in-process toggle) and compare medians.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';

Future<void> main(List<String> args) async {
  var samples = 15;
  var warmup = 3;
  var lanes = <String>['fanout', 'fanout-wide', 'keyed-pk', 'feed', 'writes'];
  var raw = false;
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--lane=')) {
      lanes = [arg.substring('--lane='.length)];
    } else if (arg == '--raw') {
      raw = true;
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }
  for (final lane in lanes) {
    final h = await _Lane.open(lane);
    try {
      for (var i = 0; i < warmup; i++) {
        await h.burst();
      }
      final samplesMs = <double>[];
      for (var i = 0; i < samples; i++) {
        samplesMs.add(await h.burst());
      }
      final s = [...samplesMs]..sort();
      final n = s.length;
      final median = n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
      print(
        '$lane median=${median.toStringAsFixed(3)}ms '
        'min=${s.first.toStringAsFixed(3)} max=${s.last.toStringAsFixed(3)} '
        'n=$n',
      );
      if (raw) print('$lane samples_ms=${samplesMs.join(',')}');
    } finally {
      await h.close();
    }
  }
}

class _Lane {
  _Lane(this.name, this._db, this._writeCount, this._write, this._sentinel);

  final String name;
  final Database _db;
  final int _writeCount;

  /// Issues write [i] of a burst; [i] is globally unique across bursts so no
  /// burst can re-write a value a previous one already stored (which would
  /// silently turn every rerun into an unchanged one).
  final Future<void> Function(Database db, math.Random rng, int i) _write;

  /// Issues a write that is guaranteed to change stream 0's result, or null
  /// for a lane with no streams.
  final Future<void> Function(Database db, int i)? _sentinel;

  final _subs = <StreamSubscription<Object?>>[];
  var _writeCursor = 0;
  Completer<void>? _sentinelWaiter;

  static Future<_Lane> open(String name) async {
    switch (name) {
      case 'fanout':
        return _fanout('fanout', owners: 100, perOwner: 100, writes: 200);
      case 'fanout-wide':
        return _fanout('fanout-wide', owners: 20, perOwner: 1000, writes: 200);
      case 'keyed-pk':
        return _keyedPk();
      case 'feed':
        return _feed();
      case 'writes':
        return _fanout(
          'writes',
          owners: 100,
          perOwner: 100,
          writes: 200,
          subscribe: false,
        );
      default:
        throw ArgumentError('unknown lane: $name');
    }
  }

  static Future<Database> _openDb(String tag) async {
    final dir = await Directory.systemTemp.createTemp('exp283_${tag}_');
    return Database.open('${dir.path}/t.db');
  }

  static Future<_Lane> _fanout(
    String name, {
    required int owners,
    required int perOwner,
    required int writes,
    bool subscribe = true,
  }) async {
    final db = await _openDb(name);
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, '
      'value INTEGER)',
    );
    await db.execute('CREATE INDEX items_owner ON items(owner_id)');
    await db.executeBatch('INSERT INTO items(owner_id, value) VALUES (?, ?)', [
      for (var o = 1; o <= owners; o++)
        for (var r = 0; r < perOwner; r++) [o, 0],
    ]);
    final rows = owners * perOwner;
    final lane = _Lane(
      name,
      db,
      writes,
      (d, rng, i) => d.execute('UPDATE items SET value = ? WHERE id = ?', [
        i,
        rng.nextInt(rows) + 1,
      ]),
      subscribe
          ? (d, i) => d.execute('UPDATE items SET value = ? WHERE id = ?', [
              -i - 1,
              1,
            ])
          : null,
    );
    if (subscribe) {
      await lane._subscribeAll(
        owners,
        (o) => (
          'SELECT id, value FROM items WHERE owner_id = ? ORDER BY id',
          <Object?>[o + 1],
        ),
      );
    }
    return lane;
  }

  static Future<_Lane> _keyedPk() async {
    const rowCount = 10000;
    const streamCount = 50;
    final db = await _openDb('keyedpk');
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER, '
      'label TEXT NOT NULL)',
    );
    await db.executeBatch(
      'INSERT INTO items(id, value, label) VALUES (?, ?, ?)',
      [
        for (var i = 1; i <= rowCount; i++) [i, i, 'row-$i'],
      ],
    );
    final lane = _Lane(
      'keyed-pk',
      db,
      200,
      (d, rng, i) => d.execute('UPDATE items SET value = ? WHERE id = ?', [
        i,
        rng.nextInt(rowCount) + 1,
      ]),
      (d, i) =>
          d.execute('UPDATE items SET value = ? WHERE id = ?', [-i - 1, 1]),
    );
    await lane._subscribeAll(
      streamCount,
      (s) => ('SELECT * FROM items WHERE id = ?', <Object?>[s + 1]),
    );
    return lane;
  }

  static Future<_Lane> _feed() async {
    const postCount = 20000;
    final db = await _openDb('feed');
    await db.execute(
      'CREATE TABLE posts(id INTEGER PRIMARY KEY, created_at INTEGER NOT NULL, '
      'like_count INTEGER NOT NULL, body TEXT NOT NULL)',
    );
    await db.execute('CREATE INDEX posts_created ON posts(created_at, id)');
    await db.executeBatch(
      'INSERT INTO posts(id, created_at, like_count, body) VALUES (?, ?, ?, ?)',
      [
        for (var i = 1; i <= postCount; i++) [i, i, 0, 'post body $i'],
      ],
    );
    // Writes target the oldest half, which the latest-50 page never contains.
    final lane = _Lane(
      'feed',
      db,
      100,
      (d, rng, i) => d.execute(
        'UPDATE posts SET like_count = like_count + 1 WHERE id = ?',
        [rng.nextInt(postCount ~/ 2) + 1],
      ),
      // The newest post is on the watched latest-50 page.
      (d, i) => d.execute('UPDATE posts SET like_count = ? WHERE id = ?', [
        i + 1,
        postCount,
      ]),
    );
    await lane._subscribeAll(
      1,
      (_) => (
        'SELECT id, created_at, like_count, body FROM posts '
            'ORDER BY created_at DESC, id DESC LIMIT 50',
        const <Object?>[],
      ),
    );
    return lane;
  }

  Future<void> _subscribeAll(
    int count,
    (String, List<Object?>) Function(int) query,
  ) async {
    final seen = List<bool>.filled(count, false);
    for (var i = 0; i < count; i++) {
      final k = i;
      final (sql, params) = query(k);
      _subs.add(
        _db.stream(sql, params).listen((_) {
          seen[k] = true;
          if (k == 0) {
            final w = _sentinelWaiter;
            if (w != null && !w.isCompleted) w.complete();
          }
        }),
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (seen.contains(false)) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('$name: timed out waiting for initial emissions');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// One measured burst: issue every write concurrently, then a sentinel write
  /// that must change stream 0, and stop when stream 0 emits.
  Future<double> burst() async {
    final rng = math.Random(0xCAFEF0);
    final sentinel = _sentinel;
    final waiter = sentinel == null
        ? null
        : (_sentinelWaiter = Completer<void>());
    final sw = Stopwatch()..start();
    final writes = <Future<void>>[
      for (var w = 0; w < _writeCount; w++) _write(_db, rng, _writeCursor++),
    ];
    await Future.wait(writes);
    if (sentinel != null) {
      await sentinel(_db, _writeCursor++);
      await waiter!.future;
    }
    sw.stop();
    _sentinelWaiter = null;
    return sw.elapsedMicroseconds / 1000.0;
  }

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _db.close();
  }
}
