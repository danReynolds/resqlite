// Focused audit harness for exp 183 — `selectBytes` json_buf retention.
//
// Exp 174 stopped sacrificing readers on the bytes path (the only
// previous mechanism that reset per-reader json_buf capacity) and
// recorded a bounded ~+15MB RSS high-water as a known trade-off. The
// follow-up future-note in exp 174 is gated on a workload showing
// problematic retention: a high-threshold C-side reclaim only makes
// sense if a realistic shape actually leaves a pathologically large
// json_buf parked across many subsequent small queries.
//
// This harness traces the new `Diagnostics.readerJsonBufHighWaterBytes`
// counter through three shapes:
//
//   1. small-only — a long run of small (~4 KB JSON) selectBytes calls.
//      Establishes the baseline json_buf size for steady-state small
//      workloads (one reader's grown buffer × pool size).
//   2. one-shot-large — one big (~8 MB JSON) selectBytes followed by
//      many small calls. Measures how much json_buf stays parked on the
//      readers that served the one-off, and whether subsequent small
//      calls keep that pool of inflated buffers alive.
//   3. recurring-large — small calls interleaved with periodic large
//      ones, the realistic "occasional bulk export" pattern. The
//      high-water rises to the largest seen payload and plateaus there
//      — the question is whether this is acceptable or needs reclaim.
//
// Reports `json_buf_total` (across the 4-reader pool) at five
// checkpoints per shape (open, after warmup, mid-run, after burst,
// post-burst-settle) and RSS deltas at the same points. Print only;
// no acceptance gate — exp 183 reads the numbers and decides whether
// to implement the exp 174 reclaim follow-up or prune the candidate.

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _smallRows = 50;
const _smallBodyLen = 60; // ~4 KB JSON
const _largeRows = 1000;
const _largeBodyLen = 8000; // ~8 MB JSON
const _smallIters = 200;
const _interleaveLargeEvery = 50;
const _interleaveTotal = 300;

Future<void> main() async {
  print('=== json_buf retention audit (exp 183) ===\n');
  await _smallOnlyShape();
  await _oneShotLargeShape();
  await _recurringLargeShape();
}

Future<void> _smallOnlyShape() async {
  final dir = await Directory.systemTemp.createTemp('resq_json_buf_small_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    await _seed(db, _smallRows, _smallBodyLen);
    final sql = 'SELECT id, body FROM t ORDER BY id';
    final probe = (await db.selectBytes(sql)).bytes;
    print('## small-only (${_smallIters} x ~${probe.length}B selectBytes)');
    await _snap(db, 'open');
    for (var i = 0; i < 10; i++) {
      await db.selectBytes(sql);
    }
    await _snap(db, 'after warmup (10 small)');
    for (var i = 0; i < _smallIters; i++) {
      await db.selectBytes(sql);
    }
    await _snap(db, 'after $_smallIters small');
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _oneShotLargeShape() async {
  final dir = await Directory.systemTemp.createTemp('resq_json_buf_oneshot_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    // Seed both shapes.
    await db.execute(
      'CREATE TABLE small(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE big(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
    );
    final smallBody = 'x' * _smallBodyLen;
    final bigBody = 'B' * _largeBodyLen;
    await db.executeBatch('INSERT INTO small(id, body) VALUES (?, ?)', [
      for (var i = 0; i < _smallRows; i++) [i, '$smallBody-$i'],
    ]);
    await db.executeBatch('INSERT INTO big(id, body) VALUES (?, ?)', [
      for (var i = 0; i < _largeRows; i++) [i, '$bigBody-$i'],
    ]);

    final smallSql = 'SELECT id, body FROM small ORDER BY id';
    final bigSql = 'SELECT id, body FROM big ORDER BY id';
    final smallProbe = (await db.selectBytes(smallSql)).bytes;
    final bigProbe = (await db.selectBytes(bigSql)).bytes;

    print(
      '\n## one-shot-large (small ~${smallProbe.length}B '
      ', large ~${bigProbe.length}B; then $_smallIters small)',
    );
    await _snap(db, 'after seed + 1 small probe + 1 large probe');
    // Reset baseline with small-only warmup on a fresh pool: in practice
    // the probes above already touched the readers, so we just continue
    // from there.
    for (var i = 0; i < 10; i++) {
      await db.selectBytes(smallSql);
    }
    await _snap(db, 'after 10 small warmup');

    // The one-off large burst — exercise the full pool by issuing
    // concurrent calls so multiple readers grow.
    await Future.wait([for (var i = 0; i < 8; i++) db.selectBytes(bigSql)]);
    await _snap(db, 'after concurrent burst of 8 large');

    for (var i = 0; i < _smallIters; i++) {
      await db.selectBytes(smallSql);
    }
    await _snap(db, 'after $_smallIters small (post-burst settle)');
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _recurringLargeShape() async {
  final dir = await Directory.systemTemp.createTemp('resq_json_buf_recur_');
  final db = await Database.open('${dir.path}/t.db');
  try {
    await db.execute(
      'CREATE TABLE small(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE big(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
    );
    final smallBody = 'x' * _smallBodyLen;
    final bigBody = 'B' * _largeBodyLen;
    await db.executeBatch('INSERT INTO small(id, body) VALUES (?, ?)', [
      for (var i = 0; i < _smallRows; i++) [i, '$smallBody-$i'],
    ]);
    await db.executeBatch('INSERT INTO big(id, body) VALUES (?, ?)', [
      for (var i = 0; i < _largeRows; i++) [i, '$bigBody-$i'],
    ]);

    final smallSql = 'SELECT id, body FROM small ORDER BY id';
    final bigSql = 'SELECT id, body FROM big ORDER BY id';
    print(
      '\n## recurring-large (1 large per $_interleaveLargeEvery small, '
      '$_interleaveTotal total iterations)',
    );
    await _snap(db, 'after seed');
    for (var i = 0; i < _interleaveTotal; i++) {
      if (i % _interleaveLargeEvery == 0) {
        await db.selectBytes(bigSql);
      } else {
        await db.selectBytes(smallSql);
      }
    }
    await _snap(db, 'after $_interleaveTotal interleaved');
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _seed(Database db, int rows, int bodyLen) async {
  await db.execute(
    'CREATE TABLE t(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
  );
  final body = 'x' * bodyLen;
  await db.executeBatch('INSERT INTO t(id, body) VALUES (?, ?)', [
    for (var i = 0; i < rows; i++) [i, '$body-$i'],
  ]);
}

Future<void> _snap(Database db, String label) async {
  // Let any inflight reader settle so the diagnostic sees an idle pool.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  final d = await db.diagnostics();
  final rss = ProcessInfo.currentRss;
  print(
    '  $label\n'
    '    json_buf_total=${_fmtBytes(d.readerJsonBufHighWaterBytes)} '
    'rss=${_fmtBytes(rss)} '
    'pageCache=${_fmtBytes(d.sqlitePageCacheBytes)} '
    'wal=${_fmtBytes(d.walBytes)}',
  );
}

String _fmtBytes(int bytes) {
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(2)}MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(1)}KB';
  return '${bytes}B';
}
