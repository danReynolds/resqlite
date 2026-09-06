// ignore_for_file: avoid_print

/// [EXP-283] Rerun census for the release suite's reactive-stream shapes.
///
/// The three largest lanes in the release suite are reactive fan-out
/// workloads. Every write dirties some set of streams and each dirty stream
/// re-executes its query on a reader worker so the engine can learn whether
/// its result changed. Nothing has ever counted how many reruns those lanes
/// actually issue, what share of them change, or what a rerun costs — the
/// numbers a candidate that changes rerun work has to be sized against.
///
/// Reproduces each lane's stream/write shape (scaled to keep setup fast) and
/// reports the census from the main isolate's own view of `selectIfChanged`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';

Future<void> main(List<String> args) async {
  var lanes = <String>['keyed-pk', 'fanout', 'feed'];
  for (final arg in args) {
    if (arg.startsWith('--lane=')) {
      lanes = [arg.substring('--lane='.length)];
    }
  }
  for (final lane in lanes) {
    switch (lane) {
      case 'keyed-pk':
        await _keyedPk();
      case 'fanout':
        await _fanout();
      case 'feed':
        await _feed();
      default:
        throw ArgumentError('unknown lane: $lane');
    }
  }
}

void _resetCensus() {
  StreamEngine.tmpReruns = 0;
  StreamEngine.tmpChanged = 0;
  StreamEngine.tmpRerunUs = 0;
  StreamEngine.tmpChangedUs = 0;
  StreamEngine.tmpTrace.clear();
}

/// Replay the recorded per-stream outcome sequence through a candidate
/// predictor and report what it would have decided.
///
/// [enter] is how many consecutive changed reruns arm decode-first; it
/// disarms on the first unchanged rerun. `save` and `tax` are the measured
/// per-rerun figures from `stream_rerun_pass_price.dart` for this shape.
void _predictor(String lane, int enter, double save, double tax) {
  final streak = <int, int>{};
  var fired = 0;
  var hits = 0;
  var misses = 0;
  var missedWins = 0;
  for (final (key, changed) in StreamEngine.tmpTrace) {
    final armed = (streak[key] ?? 0) >= enter;
    if (armed) {
      fired++;
      if (changed) {
        hits++;
      } else {
        misses++;
      }
    } else if (changed) {
      missedWins++;
    }
    streak[key] = changed ? (streak[key] ?? 0) + 1 : 0;
  }
  final net = hits * save - misses * tax;
  print(
    '  predictor(enter=$enter): fired=$fired hits=$hits misses=$misses '
    'unarmed-changed=$missedWins '
    'modelled_net=${net.toStringAsFixed(0)}us '
    '(${(net / StreamEngine.tmpTrace.length).toStringAsFixed(2)}us/rerun)',
  );
}

void _report(String lane, int writes, int streams, double wallMs) {
  final reruns = StreamEngine.tmpReruns;
  final changed = StreamEngine.tmpChanged;
  final us = StreamEngine.tmpRerunUs;
  final changedUs = StreamEngine.tmpChangedUs;
  final unchanged = reruns - changed;
  final unchangedUs = us - changedUs;
  String per(int total, int n) =>
      n == 0 ? '-' : (total / n).toStringAsFixed(2);
  print(
    '$lane: streams=$streams writes=$writes '
    'wall=${wallMs.toStringAsFixed(1)}ms '
    'reruns=$reruns (${(reruns / writes).toStringAsFixed(1)}/write, '
    'max ${streams * writes}) '
    'changed=$changed '
    '(${reruns == 0 ? 0 : (100 * changed / reruns).toStringAsFixed(2)}%) '
    'rerun_us_mean=${per(us, reruns)} '
    'changed_us_mean=${per(changedUs, changed)} '
    'unchanged_us_mean=${per(unchangedUs, unchanged)}',
  );
}

Future<Database> _open(String tag) async {
  final dir = await Directory.systemTemp.createTemp('exp283_${tag}_');
  return Database.open('${dir.path}/t.db');
}

/// A11 shape: 50 streams each on one PK, 200 random-PK writes over 10k rows.
Future<void> _keyedPk() async {
  const rowCount = 10000;
  const streamCount = 50;
  const writeCount = 200;
  final db = await _open('keyedpk');
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER, '
    'label TEXT NOT NULL)',
  );
  await db.executeBatch(
    'INSERT INTO items(id, value, label) VALUES (?, ?, ?)',
    [for (var i = 1; i <= rowCount; i++) [i, i, 'row-$i']],
  );
  final subs = <StreamSubscription<Object?>>[];
  final seen = List<bool>.filled(streamCount, false);
  for (var s = 0; s < streamCount; s++) {
    final i = s;
    subs.add(
      db
          .stream('SELECT * FROM items WHERE id = ?', [i + 1])
          .listen((_) => seen[i] = true),
    );
  }
  await _waitUntil(() => !seen.contains(false));

  final rng = math.Random(0xA11);
  _resetCensus();
  final sw = Stopwatch()..start();
  for (var w = 0; w < writeCount; w++) {
    await db.execute('UPDATE items SET value = ? WHERE id = ?', [
      w,
      rng.nextInt(rowCount) + 1,
    ]);
  }
  await _quiesce(db);
  sw.stop();
  _report('keyed-pk', writeCount, streamCount, sw.elapsedMicroseconds / 1000);
  for (final enter in [1, 2, 3]) {
    _predictor('keyed-pk', enter, 0.97, 0.17);
  }
  for (final s in subs) {
    await s.cancel();
  }
  await db.close();
}

/// A11b shape: 100 streams over 100 owner partitions, 200 random-item writes.
Future<void> _fanout() async {
  const owners = 100;
  const perOwner = 100;
  const writeCount = 200;
  final db = await _open('fanout');
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, '
    'value INTEGER)',
  );
  await db.execute('CREATE INDEX items_owner ON items(owner_id)');
  await db.executeBatch('INSERT INTO items(owner_id, value) VALUES (?, ?)', [
    for (var o = 1; o <= owners; o++)
      for (var r = 0; r < perOwner; r++) [o, 0],
  ]);
  // Control: the same write burst with nothing subscribed, so the fan-out
  // tax is readable as a difference rather than assumed.
  {
    final rngC = math.Random(0xCAFEF0);
    final swC = Stopwatch()..start();
    for (var w = 0; w < writeCount; w++) {
      await db.execute('UPDATE items SET value = ? WHERE id = ?', [
        -w - 1,
        rngC.nextInt(owners * perOwner) + 1,
      ]);
    }
    swC.stop();
    print(
      'fanout-control (no streams): writes=$writeCount '
      'wall=${(swC.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
      '(${(swC.elapsedMicroseconds / writeCount).toStringAsFixed(1)}us/write)',
    );
  }

  final subs = <StreamSubscription<Object?>>[];
  final seen = List<bool>.filled(owners, false);
  for (var o = 0; o < owners; o++) {
    final i = o;
    subs.add(
      db
          .stream('SELECT id, value FROM items WHERE owner_id = ? ORDER BY id', [
            i + 1,
          ])
          .listen((_) => seen[i] = true),
    );
  }
  await _waitUntil(() => !seen.contains(false));

  final rng = math.Random(0xCAFEF0);
  _resetCensus();
  final sw = Stopwatch()..start();
  for (var w = 0; w < writeCount; w++) {
    await db.execute('UPDATE items SET value = ? WHERE id = ?', [
      w,
      rng.nextInt(owners * perOwner) + 1,
    ]);
  }
  await _quiesce(db);
  sw.stop();
  _report('fanout', writeCount, owners, sw.elapsedMicroseconds / 1000);
  for (final enter in [1, 2, 3]) {
    _predictor('fanout', enter, 4.22, 1.95);
  }
  for (final s in subs) {
    await s.cancel();
  }
  await db.close();
}

/// A6 Part B shape: one latest-50 stream, 100 random like_count writes.
Future<void> _feed() async {
  const postCount = 20000;
  const writeCount = 100;
  final db = await _open('feed');
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
  var seen = false;
  final sub = db
      .stream(
        'SELECT id, created_at, like_count, body FROM posts '
        'ORDER BY created_at DESC, id DESC LIMIT 50',
        const [],
      )
      .listen((_) => seen = true);
  await _waitUntil(() => seen);

  final rng = math.Random(0xFEED);
  _resetCensus();
  final sw = Stopwatch()..start();
  for (var w = 0; w < writeCount; w++) {
    await db.execute(
      'UPDATE posts SET like_count = like_count + 1 WHERE id = ?',
      [rng.nextInt(postCount) + 1],
    );
  }
  await _quiesce(db);
  sw.stop();
  _report('feed', writeCount, 1, sw.elapsedMicroseconds / 1000);
  for (final enter in [1, 2, 3]) {
    _predictor('feed', enter, 3.91, 3.02);
  }
  await sub.cancel();
  await db.close();
}

/// Let every rerun the write burst scheduled actually run.
Future<void> _quiesce(Database db) async {
  var stable = 0;
  var last = -1;
  while (stable < 5) {
    await Future<void>.delayed(const Duration(milliseconds: 4));
    final n = StreamEngine.tmpReruns;
    if (n == last) {
      stable++;
    } else {
      stable = 0;
      last = n;
    }
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
