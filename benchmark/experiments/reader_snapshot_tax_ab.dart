// ignore_for_file: avoid_print

/// [EXP-289] End-to-end gate for post-commit reads and stream reruns, through
/// the public API.
///
/// `rerun_snapshot_tax.dart` prices the mechanism with no isolates: a reader
/// connection whose WAL snapshot moved since its last read discards its page
/// cache (and, with `mmap_size` set, unmaps and remaps the database file)
/// before its next statement steps, while the writer connection's cache
/// survives its own commits. This harness asks what that is worth to a caller.
/// Every lane except the controls interleaves a write with the operation it
/// times, because that is the shape a reactive application runs in: a rerun
/// exists because a commit preceded it.
///
/// Two things are A/B'd with it:
///
///   * the warm-rerun candidate (a stream rerun on the idle writer
///     connection) — build one bundle per arm by flipping `kWarmReruns` in
///     `lib/src/stream_engine.dart`, run them alternately, compare lanes;
///   * the reader `mmap_size` policy — `--mmap=readers` / `--mmap=all` apply
///     `PRAGMA mmap_size = 0` to the process's C connections right after
///     `Database.open`, before any query, through the setup path extensions
///     use.
///
/// Lanes (microseconds, median and p90 over iterations unless noted):
///
///   point-after-write    one-row select after an unrelated commit
///   page-after-write     50-row keyset page after an unrelated commit
///   scan-after-write     1,000-row scan after an unrelated commit
///   large-after-write    10,000-row x 4 scan after an unrelated commit
///   stream-latency       write that changes a 50-row stream -> its emission
///   stream-latency-1row  the same with a one-row stream
///   unchanged-fanout     1 canary + 10 unchanged streams, write -> canary emit
///   tx-latency           BEGIN, 3 writes, COMMIT changing a stream -> emit
///   burst-seq-stream     200 awaited writes each changing one 50-row stream;
///                        burst wall (ms) and emissions received (guard: the
///                        rerun must not serialise behind the next write)
///   burst-concurrent     100 concurrent writes, same stream; wall (ms)
///   many-streams-burst   50 streams, 200 awaited writes dirtying all of them;
///                        wall to burst end (ms)
///   long-text-fanout     the release suite's Long-Text Unchanged Fanout shape:
///                        8 unchanged 256-row x 4 KB streams and a full-table
///                        barrier stream; one 4 KB insert -> barrier emission
///   point-warm           control: one-row select, no writes
///   write-only           control: one UPDATE, no reads
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';

const _rows = 10000;
const _owners = 200; // 50 rows per owner

Future<void> main(List<String> args) async {
  var mmap = 'default';
  var iterations = 400;
  var label = '';
  Set<String>? lanes;
  for (final arg in args) {
    if (arg.startsWith('--mmap=')) {
      mmap = arg.substring('--mmap='.length);
    } else if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
    } else if (arg.startsWith('--lanes=')) {
      lanes = arg.substring('--lanes='.length).split(',').toSet();
    } else if (arg.startsWith('--label=')) {
      label = arg.substring('--label='.length);
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }
  if (!const {'default', 'readers', 'all'}.contains(mmap)) {
    throw ArgumentError('--mmap must be default, readers or all');
  }

  final all = <String, Future<List<double>> Function(Database, int)>{
    'point-after-write': _pointAfterWrite,
    'page-after-write': _pageAfterWrite,
    'scan-after-write': _scanAfterWrite,
    'large-after-write': _largeAfterWrite,
    'stream-latency': _streamLatency,
    'stream-latency-1row': _streamLatency1Row,
    'unchanged-fanout': _unchangedFanout,
    'tx-latency': _txLatency,
    'burst-seq-stream': _burstSeqStream,
    'burst-concurrent': _burstConcurrent,
    'many-streams-burst': _manyStreamsBurst,
    'long-text-fanout': _longTextFanout,
    'point-warm': _pointWarm,
    'write-only': _writeOnly,
  };
  for (final entry in all.entries) {
    if (lanes != null && !lanes.contains(entry.key)) continue;
    final dir = Directory.systemTemp.createTempSync('exp289_ab_');
    final db = await Database.open('${dir.path}/t.db');
    try {
      _applyMmap(db, mmap);
      await _seed(db);
      final iters = switch (entry.key) {
        'large-after-write' => (iterations ~/ 4).clamp(20, iterations),
        'burst-seq-stream' ||
        'burst-concurrent' ||
        'many-streams-burst' => (iterations ~/ 20).clamp(5, iterations),
        'long-text-fanout' => (iterations ~/ 4).clamp(30, iterations),
        _ => iterations,
      };
      final samples = await entry.value(db, iters);
      final unit = entry.key.startsWith('burst') || entry.key.startsWith('many')
          ? 'ms'
          : 'us';

      print(
        '${entry.key.padRight(20)} ${label.padRight(10)} mmap=${mmap.padRight(8)} '
        'p50=${_median(samples).toStringAsFixed(2)}$unit '
        'p90=${_p90(samples).toStringAsFixed(2)}$unit n=${samples.length}',
      );
    } finally {
      await db.close();
      dir.deleteSync(recursive: true);
    }
  }
}

void _applyMmap(Database db, String mmap) {
  if (mmap == 'default') return;
  final scope = mmap == 'readers' ? 2 : 0;
  final sql = 'PRAGMA mmap_size = 0'.toNativeUtf8();
  try {
    final rc = resqliteRunConnectionSetup(
      db.handle,
      sql,
      ffi.nullptr,
      0,
      scope,
    );
    if (rc != 0) throw StateError('mmap setup failed: $rc');
  } finally {
    calloc.free(sql);
  }
}

Future<void> _seed(Database db) async {
  await db.execute(
    'CREATE TABLE items(id INTEGER PRIMARY KEY, owner_id INTEGER NOT NULL, '
    'value INTEGER NOT NULL, body TEXT NOT NULL)',
  );
  await db.execute('CREATE INDEX items_owner ON items(owner_id)');
  await db.execute('CREATE TABLE noise(id INTEGER PRIMARY KEY, v INTEGER)');
  await db.execute('INSERT INTO noise(id, v) VALUES (1, 0)');
  await db.executeBatch(
    'INSERT INTO items(id, owner_id, value, body) VALUES (?, ?, ?, ?)',
    [
      for (var i = 1; i <= _rows; i++)
        [i, i % _owners, i, 'body text for row number $i'],
    ],
  );
  // Seed frames go to the main file so the lanes read what an application
  // reads: a checkpointed base plus the few WAL frames each write adds.
  await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  // Warm every reader's statement cache and page cache so the first
  // iteration is not a prepare.
  for (var i = 0; i < 16; i++) {
    await db.select(_pointSql, [7]);
    await db.select(_pageSql, [3]);
    await db.select(_scanSql);
  }
}

const _noiseWrite = 'UPDATE noise SET v = v + 1 WHERE id = 1';
const _pointSql = 'SELECT id, owner_id, value, body FROM items WHERE id = ?';
const _pageSql =
    'SELECT id, value, body FROM items WHERE owner_id = ? ORDER BY id LIMIT 50';
const _scanSql = 'SELECT id, value FROM items ORDER BY id LIMIT 1000';
const _largeSql = 'SELECT id, owner_id, value, body FROM items ORDER BY id';

Future<List<double>> _timedAfterWrite(
  Database db,
  int iterations,
  Future<void> Function() op, {
  bool write = true,
}) async {
  final out = <double>[];
  final sw = Stopwatch();
  final freq = sw.frequency;
  for (var i = 0; i < iterations; i++) {
    if (write) await db.execute(_noiseWrite);
    sw
      ..reset()
      ..start();
    await op();
    sw.stop();
    out.add(sw.elapsedTicks * 1e6 / freq);
  }
  return out;
}

Future<List<double>> _pointAfterWrite(Database db, int n) =>
    _timedAfterWrite(db, n, () => db.select(_pointSql, [7]));

Future<List<double>> _pageAfterWrite(Database db, int n) =>
    _timedAfterWrite(db, n, () => db.select(_pageSql, [3]));

Future<List<double>> _scanAfterWrite(Database db, int n) =>
    _timedAfterWrite(db, n, () => db.select(_scanSql));

Future<List<double>> _largeAfterWrite(Database db, int n) =>
    _timedAfterWrite(db, n, () => db.select(_largeSql));

Future<List<double>> _pointWarm(Database db, int n) =>
    _timedAfterWrite(db, n, () => db.select(_pointSql, [7]), write: false);

Future<List<double>> _writeOnly(Database db, int n) =>
    _timedAfterWrite(db, n, () => db.execute(_noiseWrite), write: false);

/// Subscribes, waits for the initial emission, then hands back a stream whose
/// every later emission completes the current waiter.
Future<(StreamSubscription<Object?>, Completer<void>? Function())> _watch(
  Database db,
  String sql,
  List<Object?> params,
) async {
  Completer<void>? waiter;
  final first = Completer<void>();
  final sub = db.stream(sql, params).listen((_) {
    if (!first.isCompleted) {
      first.complete();
    } else {
      waiter?.complete();
    }
  });
  await first.future;
  Completer<void>? arm() => waiter = Completer<void>();
  return (sub, arm);
}

Future<List<double>> _emitLatency(
  Database db,
  int n,
  String streamSql,
  List<Object?> streamParams,
  Future<void> Function() write,
) async {
  final (sub, arm) = await _watch(db, streamSql, streamParams);
  final out = <double>[];
  final sw = Stopwatch();
  final freq = sw.frequency;
  try {
    for (var i = 0; i < n; i++) {
      final w = arm()!;
      sw
        ..reset()
        ..start();
      await write();
      await w.future;
      sw.stop();
      out.add(sw.elapsedTicks * 1e6 / freq);
    }
  } finally {
    await sub.cancel();
  }
  return out;
}

/// Row 3 belongs to owner 3, so each write changes the 50-row stream.
Future<List<double>> _streamLatency(Database db, int n) => _emitLatency(
  db,
  n,
  _pageSql,
  [3],
  () => db.execute('UPDATE items SET value = value + 1 WHERE id = 3'),
);

Future<List<double>> _streamLatency1Row(Database db, int n) => _emitLatency(
  db,
  n,
  _pointSql,
  [3],
  () => db.execute('UPDATE items SET value = value + 1 WHERE id = 3'),
);

/// An interactive transaction that changes the stream; the rerun must wait for
/// COMMIT and must not read the writer mid-transaction.
Future<List<double>> _txLatency(Database db, int n) => _emitLatency(
  db,
  n,
  _pageSql,
  [3],
  () => db.transaction((tx) async {
    await tx.execute('UPDATE items SET value = value + 1 WHERE id = 3');
    await tx.execute(_noiseWrite);
    await tx.execute('UPDATE items SET value = value + 1 WHERE id = 203');
  }),
);

/// One canary stream plus ten streams the write dirties but does not change
/// (the release suite's Unchanged Fanout shape). Time write -> canary emit.
Future<List<double>> _unchangedFanout(Database db, int n) async {
  final subs = <StreamSubscription<Object?>>[];
  for (var owner = 10; owner < 20; owner++) {
    final (sub, _) = await _watch(db, _pageSql, [owner]);
    subs.add(sub);
  }
  try {
    return await _emitLatency(
      db,
      n,
      _pointSql,
      [1],
      () => db.execute('UPDATE items SET value = value + 1 WHERE id = 1'),
    );
  } finally {
    for (final s in subs) {
      await s.cancel();
    }
  }
}

/// 200 sequential awaited writes, each changing one 50-row stream. Reports the
/// burst wall in ms; prints emissions received during the burst once.
Future<List<double>> _burstSeqStream(Database db, int n) async {
  var emissions = 0;
  final (sub, _) = await _watch(db, _pageSql, [3]);
  final counter = db.stream(_pageSql, [3]).listen((_) => emissions++);
  final out = <double>[];
  final sw = Stopwatch();
  final freq = sw.frequency;
  try {
    for (var s = 0; s < n; s++) {
      emissions = 0;
      sw
        ..reset()
        ..start();
      for (var i = 0; i < 200; i++) {
        await db.execute('UPDATE items SET value = value + 1 WHERE id = 3');
      }
      sw.stop();
      out.add(sw.elapsedTicks * 1e3 / freq);
      if (s == n - 1) {
        // Let the tail drain so the count is the burst's, not a race.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        print('burst-seq-stream emissions-per-200-writes=$emissions');
      }
    }
  } finally {
    await counter.cancel();
    await sub.cancel();
  }
  return out;
}

/// 100 concurrent writes changing the same stream (group commit path).
Future<List<double>> _burstConcurrent(Database db, int n) async {
  final (sub, _) = await _watch(db, _pageSql, [3]);
  final out = <double>[];
  final sw = Stopwatch();
  final freq = sw.frequency;
  try {
    for (var s = 0; s < n; s++) {
      sw
        ..reset()
        ..start();
      await Future.wait([
        for (var i = 0; i < 100; i++)
          db.execute('UPDATE items SET value = value + 1 WHERE id = 3'),
      ]);
      sw.stop();
      out.add(sw.elapsedTicks * 1e3 / freq);
    }
  } finally {
    await sub.cancel();
  }
  return out;
}

/// 50 streams over 50 partitions; 200 awaited writes each dirty all of them
/// (every stream projects `value`) and change one. Wall to the end of the
/// burst; the reruns the burst leaves behind settle before the next sample.
Future<List<double>> _manyStreamsBurst(Database db, int n) async {
  final subs = <StreamSubscription<Object?>>[];
  for (var owner = 0; owner < 50; owner++) {
    final (sub, _) = await _watch(db, _pageSql, [owner]);
    subs.add(sub);
  }
  final out = <double>[];
  final sw = Stopwatch();
  final freq = sw.frequency;
  try {
    for (var s = 0; s < n; s++) {
      sw
        ..reset()
        ..start();
      for (var i = 0; i < 200; i++) {
        await db.execute(
          'UPDATE items SET value = value + 1 WHERE id = ${1 + (i % 50)}',
        );
      }
      sw.stop();
      out.add(sw.elapsedTicks * 1e3 / freq);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  } finally {
    for (final s in subs) {
      await s.cancel();
    }
  }
  return out;
}

/// The release suite's `Long-Text Unchanged Fanout (8 unchanged streams,
/// 256 rows x 4KB TEXT)` lane, reproduced so it can be A/B'd in AOT: the
/// caller awaits an emission rather than a write, so every idle signal the
/// engine has says the writer is free while the next iteration's write is
/// about to arrive.
Future<List<double>> _longTextFanout(Database db, int n) async {
  const rows = 256;
  const textBytes = 4096;
  String payload(int seed) {
    final buffer = StringBuffer('seed_$seed:');
    while (buffer.length < textBytes) {
      buffer.write('abcdefghijklmnopqrstuvwxyz0123456789');
    }
    return buffer.toString().substring(0, textBytes);
  }

  await db.execute(
    'CREATE TABLE long_items(id INTEGER PRIMARY KEY, body TEXT NOT NULL, '
    'marker INTEGER NOT NULL)',
  );
  await db.executeBatch(
    'INSERT INTO long_items(id, body, marker) VALUES (?, ?, ?)',
    [
      for (var i = 0; i < rows; i++) [i, payload(i), i],
    ],
  );
  final subs = <StreamSubscription<Object?>>[];
  for (var s = 0; s < 8; s++) {
    final (sub, _) = await _watch(
      db,
      'SELECT id, body, $s as sid FROM long_items WHERE id < $rows ORDER BY id',
      const [],
    );
    subs.add(sub);
  }
  var counter = 100000;
  try {
    return await _emitLatency(
      db,
      n,
      'SELECT id, body FROM long_items ORDER BY id',
      const [],
      () => db.execute(
        'INSERT INTO long_items(id, body, marker) VALUES (?, ?, ?)',
        [counter, payload(counter++), counter],
      ),
    );
  } finally {
    for (final s in subs) {
      await s.cancel();
    }
  }
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _p90(List<double> xs) {
  final s = [...xs]..sort();
  return s[((s.length - 1) * 0.9).round()];
}
