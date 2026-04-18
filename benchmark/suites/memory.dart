// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../drift/micro_items_db.dart';
import '../shared/peer.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Memory benchmark suite.
///
/// Measures process RSS (resident set size) delta around a workload. Uses
/// only `ProcessInfo.currentRss` / `maxRss` from `dart:io` — no VM service
/// dependency. This means the numbers are a **lower bound** on the real
/// allocation volume: the VM retains heap pages after GC, so a small
/// workload may show zero delta even though it allocated and freed
/// objects. A visible delta reduction here means the real allocation win
/// is at least that large.
///
/// Exists because experiments like [055 columnar typed arrays]
/// (75% memory win, 10000x fewer GC objects) are invisible to time-based
/// benchmarks. See plan at `.claude/plans/luminous-doodling-boole.md`.
Future<String> runMemoryBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Memory');
  markdown.writeln('');
  markdown.writeln(
    'Process RSS delta around each workload. Values are a **lower bound** '
    'on real allocation volume because the Dart VM retains heap pages '
    'after GC. A visible reduction here implies the underlying '
    'allocation win is at least that large.',
  );
  markdown.writeln('');

  await _workloadMapsSelect(markdown);
  await _workloadBytesSelect(markdown);
  await _workloadBatchInsert(markdown);
  await _workloadStreamingFanout(markdown);

  return markdown.toString();
}

// ---------------------------------------------------------------------------
// Measurement helpers
// ---------------------------------------------------------------------------

const _outerRepeats = 15;
const _innerIterations = 10;
const _warmup = 3;
const _churnSize = 10000;
const _bootstrapSeed = 0xDEADBEEF;

class _MemStats {
  _MemStats(this.rssDeltaMB);
  final List<double> rssDeltaMB; // one sample per outer repeat
}

/// Pre-measurement churn loop. Allocates + drops [_churnSize] small maps
/// to stabilize the heap before baseline capture. Without this, heap pages
/// grow during the first warmup and contaminate the delta.
void _churnHeap() {
  final junk = <Map<String, Object?>>[];
  for (var i = 0; i < _churnSize; i++) {
    junk.add({'a': i, 'b': 'x$i', 'c': i * 1.5});
  }
  junk.clear();
}

double _rssMB() => ProcessInfo.currentRss / (1024 * 1024);

/// Runs [body] [_innerIterations] times after [_warmup] warmups and a
/// heap-churn pass. Returns the RSS delta from pre-baseline to post
/// (in MB).
Future<double> _measure(Future<void> Function() body) async {
  _churnHeap();
  for (var i = 0; i < _warmup; i++) {
    await body();
  }
  _churnHeap();
  final baseline = _rssMB();
  for (var i = 0; i < _innerIterations; i++) {
    await body();
  }
  final post = _rssMB();
  final delta = post - baseline;
  return delta < 0 ? 0.0 : delta;
}

Future<_MemStats> _repeatedMeasure(Future<void> Function() body) async {
  final deltas = <double>[];
  for (var r = 0; r < _outerRepeats; r++) {
    deltas.add(await _measure(body));
  }
  return _MemStats(deltas);
}

String _memRow(String label, _MemStats s) {
  final sorted = List<double>.from(s.rssDeltaMB)..sort();
  final med = medianOfSorted(sorted);
  final p90 = sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
  final ci = bootstrapMedianCI(s.rssDeltaMB, seed: _bootstrapSeed);
  // MDE in absolute MB (CI half-width). Reporting as MB rather than %
  // is honest because memory deltas are often 0 MB — a % MDE would
  // divide by zero or by a tiny number and become unreadable.
  final mdeMB = (ci.high - ci.low) / 2;
  return '| $label '
      '| ${med.toStringAsFixed(2)} '
      '| ${p90.toStringAsFixed(2)} '
      '| ${ci.low.toStringAsFixed(2)}..${ci.high.toStringAsFixed(2)} '
      '| ±${mdeMB.toStringAsFixed(2)} |';
}

void _writeSubsection(
  StringBuffer md,
  String title,
  Map<String, _MemStats> byLib,
) {
  md.writeln('### $title');
  md.writeln('');
  md.writeln(
    '| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |',
  );
  md.writeln('|---|---|---|---|---|');
  for (final entry in byLib.entries) {
    md.writeln(_memRow(entry.key, entry.value));
  }
  md.writeln('');
}

// ---------------------------------------------------------------------------
// Workloads
// ---------------------------------------------------------------------------

const _largeRowCount = 10000;

Future<void> _workloadMapsSelect(StringBuffer md) async {
  final dir = await Directory.systemTemp.createTemp('bench_mem_maps_');
  try {
    final peers = await PeerSet.open(
      dir.path,
      driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
    );
    final byLib = <String, _MemStats>{};
    try {
      for (final peer in peers.all) {
        await seedPeer(peer, _largeRowCount);
      }
      for (final peer in peers.all) {
        byLib['${peer.label} select()'] = await _repeatedMeasure(() async {
          final r = await peer.select(standardSelectSql);
          _touchRows(r);
        });
      }
    } finally {
      await peers.closeAll();
    }
    _writeSubsection(md, 'Select 10k rows → Maps', byLib);
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<void> _workloadBytesSelect(StringBuffer md) async {
  final dir = await Directory.systemTemp.createTemp('bench_mem_bytes_');
  try {
    final byLib = <String, _MemStats>{};

    // resqlite native selectBytes() path (the feature being showcased).
    // Kept separate from the PeerSet loop because no other peer offers
    // an equivalent — they all go through the select + jsonEncode path
    // below, including resqlite (reported as "resqlite + jsonEncode").
    final resqliteDb = await resqlite.Database.open(
      '${dir.path}/resqlite_native.db',
    );
    try {
      await seedResqlite(resqliteDb, _largeRowCount);
      byLib['resqlite selectBytes()'] = await _repeatedMeasure(() async {
        final b = await resqliteDb.selectBytes(standardSelectSql);
        _touchBytes(b);
      });
    } finally {
      await resqliteDb.close();
    }

    // Peer path: select() + utf8.encode(jsonEncode(...)). Every peer
    // (including drift) goes through this, so readers see the full
    // cross-library picture for the path everyone has to run.
    final peersSubdir = await Directory('${dir.path}/peers').create();
    final peers = await PeerSet.open(
      peersSubdir.path,
      driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        await seedPeer(peer, _largeRowCount);
      }
      for (final peer in peers.all) {
        byLib['${peer.label} + jsonEncode'] =
            await _repeatedMeasure(() async {
          final r = await peer.select(standardSelectSql);
          final bytes = Uint8List.fromList(utf8.encode(jsonEncode(r)));
          _touchBytes(bytes);
        });
      }
    } finally {
      await peers.closeAll();
    }

    _writeSubsection(md, 'Select 10k rows → JSON Bytes', byLib);
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<void> _workloadBatchInsert(StringBuffer md) async {
  final dir =
      await Directory.systemTemp.createTemp('bench_mem_batch_insert_');
  final byLib = <String, _MemStats>{};
  try {
    // The RSS measurement opens a fresh DB per iteration so we observe
    // per-burst allocation churn, not steady-state. Using the peer
    // set's fixed db files would reuse the same file across all
    // iterations, collapsing the measurement. Instead, we open a new
    // peer set per outer iteration with a unique subdir.
    //
    // The per-peer label matches the prior "executeBatch()" naming
    // convention so history-comparison aligns; sqlite3 keeps its
    // "prepared stmt" label because its peer path doesn't go through
    // executeBatch on the BenchmarkPeer interface.
    Future<_MemStats> measurePeer(String label,
        Future<void> Function(String path) body) async {
      return _repeatedMeasure(() async {
        final iterDir =
            await Directory('${dir.path}/${_uid()}').create(recursive: true);
        try {
          await body(iterDir.path);
        } finally {
          await iterDir.delete(recursive: true);
        }
      });
    }

    byLib['resqlite executeBatch()'] = await measurePeer(
      'resqlite executeBatch()',
      (path) async {
        final peers = await PeerSet.open(
          path,
          driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
          require: (p) => p.name == 'resqlite',
        );
        try {
          for (final peer in peers.all) {
            await seedPeer(peer, _largeRowCount);
          }
        } finally {
          await peers.closeAll();
        }
      },
    );
    byLib['sqlite3 executeBatch()'] = await measurePeer(
      'sqlite3 executeBatch()',
      (path) async {
        final peers = await PeerSet.open(
          path,
          require: (p) => p.name == 'sqlite3',
        );
        try {
          for (final peer in peers.all) {
            await seedPeer(peer, _largeRowCount);
          }
        } finally {
          await peers.closeAll();
        }
      },
    );
    byLib['sqlite_async executeBatch()'] = await measurePeer(
      'sqlite_async executeBatch()',
      (path) async {
        final peers = await PeerSet.open(
          path,
          require: (p) => p.name == 'sqlite_async',
        );
        try {
          for (final peer in peers.all) {
            await seedPeer(peer, _largeRowCount);
          }
        } finally {
          await peers.closeAll();
        }
      },
    );
    byLib['drift batch()'] = await measurePeer(
      'drift batch()',
      (path) async {
        final peers = await PeerSet.open(
          path,
          driftFactory: driftFactoryFor((exec) => MicroItemsDriftDb(exec)),
          require: (p) => p.name == 'drift',
        );
        try {
          for (final peer in peers.all) {
            await seedPeer(peer, _largeRowCount);
          }
        } finally {
          await peers.closeAll();
        }
      },
    );
  } finally {
    await dir.delete(recursive: true);
  }
  _writeSubsection(md, 'Batch insert 10k rows', byLib);
}

Future<void> _workloadStreamingFanout(StringBuffer md) async {
  final dir = await Directory.systemTemp.createTemp('bench_mem_stream_');
  try {
    final resqliteDb = await resqlite.Database.open('${dir.path}/resqlite.db');
    await resqliteDb.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)',
    );
    await resqliteDb.executeBatch(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      [for (var i = 0; i < 100; i++) ['item_$i', i]],
    );

    final asyncDb = sqlite_async.SqliteDatabase(path: '${dir.path}/async.db');
    await asyncDb.initialize();
    await asyncDb.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)',
    );
    await asyncDb.executeBatch(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      [for (var i = 0; i < 100; i++) ['item_$i', i]],
    );

    final byLib = <String, _MemStats>{};

    byLib['resqlite stream()'] = await _repeatedMeasure(() async {
      await _streamingFanoutResqlite(resqliteDb, streams: 10, writes: 100);
    });

    byLib['sqlite_async watch()'] = await _repeatedMeasure(() async {
      await _streamingFanoutAsync(asyncDb, streams: 10, writes: 100);
    });

    await resqliteDb.close();
    await asyncDb.close();

    _writeSubsection(md, 'Streaming fan-out (10 streams × 100 writes)', byLib);
  } finally {
    await dir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// Workload internals
// ---------------------------------------------------------------------------

Future<void> _streamingFanoutResqlite(
  resqlite.Database db, {
  required int streams,
  required int writes,
}) async {
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
  final counters = List<int>.filled(streams, 0);
  final initials = <Completer<void>>[];

  for (var i = 0; i < streams; i++) {
    final idx = i;
    final initialC = Completer<void>();
    initials.add(initialC);
    subs.add(
      db.stream('SELECT COUNT(*) as cnt FROM items').listen((_) {
        if (!initialC.isCompleted) {
          initialC.complete();
        } else {
          counters[idx]++;
        }
      }),
    );
  }

  // Deterministic barrier: wait until every stream has emitted its
  // initial value before issuing writes. Fixed sleeps (previously 5 ms)
  // race on loaded machines; completers don't.
  await Future.wait(initials.map((c) => c.future));

  var counter = 10000;
  for (var i = 0; i < writes; i++) {
    await db.execute(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      ['mem_$counter', counter],
    );
    counter++;
  }

  // Drain any trailing re-emits in flight. Yields until the emit counts
  // stabilize across two consecutive checks, capped by a generous
  // wall-clock budget. Preserves the "no fixed sleeps" property of the
  // pre-write barrier above.
  await _drainUntilIdle(() => counters.fold<int>(0, (a, b) => a + b));

  for (final sub in subs) {
    await sub.cancel();
  }
}

Future<void> _streamingFanoutAsync(
  sqlite_async.SqliteDatabase db, {
  required int streams,
  required int writes,
}) async {
  final subs = <StreamSubscription<Object?>>[];
  final counters = List<int>.filled(streams, 0);
  final initials = <Completer<void>>[];

  for (var i = 0; i < streams; i++) {
    final idx = i;
    final initialC = Completer<void>();
    initials.add(initialC);
    subs.add(
      db
          .watch(
            'SELECT COUNT(*) as cnt FROM items',
            throttle: Duration.zero,
          )
          .listen((_) {
        if (!initialC.isCompleted) {
          initialC.complete();
        } else {
          counters[idx]++;
        }
      }),
    );
  }

  await Future.wait(initials.map((c) => c.future));

  var counter = 10000;
  for (var i = 0; i < writes; i++) {
    await db.execute(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      ['mem_$counter', counter],
    );
    counter++;
  }

  await _drainUntilIdle(() => counters.fold<int>(0, (a, b) => a + b));
  for (final sub in subs) {
    await sub.cancel();
  }
}

/// Wait until [probe]'s return value is unchanged across two consecutive
/// microtask-ish yields, or until the wall-clock budget expires.
///
/// Used by the streaming fan-out workloads to drain trailing re-emits
/// without relying on fixed-duration sleeps (which race on loaded
/// machines). The budget is generous (200 ms) because the memory suite's
/// outer-repeat loop tolerates occasional slow samples better than it
/// tolerates dropped emits contaminating subsequent iterations.
Future<void> _drainUntilIdle(
  int Function() probe, {
  Duration budget = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(budget);
  var lastCount = probe();
  var stableCycles = 0;
  while (DateTime.now().isBefore(deadline)) {
    // Yield twice per cycle to let both the microtask queue and the
    // event loop drain anything scheduled by the previous yield.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final currentCount = probe();
    if (currentCount == lastCount) {
      stableCycles++;
      if (stableCycles >= 2) return;
    } else {
      stableCycles = 0;
      lastCount = currentCount;
    }
  }
}

void _touchRows(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

int _touchBytes(Uint8List bytes) {
  // Force a walk through the buffer so the VM doesn't elide the decode.
  var s = 0;
  final n = bytes.length;
  for (var i = 0; i < n; i += 64) {
    s ^= bytes[i];
  }
  return s;
}

int _uidCounter = 0;
String _uid() => '${DateTime.now().microsecondsSinceEpoch}_${_uidCounter++}';

// Allow running standalone.
Future<void> main() async {
  final md = await runMemoryBenchmark();
  print(md);
}
