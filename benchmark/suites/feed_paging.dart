// ignore_for_file: avoid_print

/// A6 — Feed Paging (v1).
///
/// Two related measurements on a 100K-post social-feed table.
///
/// Part A — **Keyset pagination**: 20 sequential page requests of 50
/// posts each, walking backwards through `(created_at, id)`. Measures
/// the cost of paging through a real-world-sized feed. All three
/// peers (resqlite, sqlite3, sqlite_async) participate.
///
/// Part B — **Reactive feed under concurrent writes**: one stream
/// watches the latest-50 (top page). While the stream is active, 100
/// concurrent `like_count` increments target random posts (most NOT on
/// the latest page). Measures how well each library handles reactive
/// delivery when writes constantly invalidate but rarely change the
/// watched query's output. resqlite + sqlite_async only (sqlite3 has
/// no streams).
///
/// The two parts share the same seed DB so we only pay the 100K-row
/// insert cost once per peer.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../drift/feed_paging_db.dart';
import '../shared/peer.dart';
import '../shared/stats.dart';
import '../shared/workload.dart';

const WorkloadMeta feedPagingMeta = WorkloadMeta(
  slug: 'feed_paging',
  version: 1,
  title: 'Feed Paging',
  description: '100K posts. Part A: 20 keyset-paged queries of 50 posts '
      'each, all three peers. Part B: one reactive stream on latest-50 '
      'with 100 concurrent like_count writes, resqlite + sqlite_async. '
      'Models an infinite-scroll feed with live updates.',
);

const int _postCount = 100000;
const int _pageSize = 50;
const int _pageCount = 20;
const int _likeWrites = 100;
const int _pagingWarmup = 2;
const int _pagingIterations = 5;
const int _reactiveIterations = 3;
const int _prngSeed = 0xFEED;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<String> runFeedPagingBenchmark() async {
  final md = StringBuffer()
    ..writeln('## ${feedPagingMeta.sectionHeading}')
    ..writeln()
    ..writeln(feedPagingMeta.description)
    ..writeln();

  final pagingByPeer = <String, _PagingReading>{};
  final reactiveByPeer = <String, _ReactiveReading>{};

  final tempDir = await Directory.systemTemp.createTemp('bench_feed_');
  try {
    final peers = await PeerSet.open(
      tempDir.path,
      driftFactory: driftFactoryFor((exec) => FeedPagingDriftDb(exec)),
    );
    try {
      for (final peer in peers.all) {
        print('  running on ${peer.name}...');
        await _seed(peer);
        pagingByPeer[peer.label] = await _measurePaging(peer);
        if (peer.hasStreams) {
          reactiveByPeer[peer.label] = await _measureReactive(peer);
        }
      }
    } finally {
      await peers.closeAll();
    }
  } finally {
    await tempDir.delete(recursive: true);
  }

  _writePagingSection(md, pagingByPeer);
  _writeReactiveSection(md, reactiveByPeer);
  return md.toString();
}

// ---------------------------------------------------------------------------
// Seed
// ---------------------------------------------------------------------------

Future<void> _seed(BenchmarkPeer peer) async {
  // IF NOT EXISTS because drift auto-creates the table + index from its
  // @DriftDatabase schema at open; bare CREATE would throw "already
  // exists" on the drift peer. Schema must match
  // benchmark/drift/feed_paging_db.dart exactly.
  await peer.execute(
    'CREATE TABLE IF NOT EXISTS posts('
    'id INTEGER PRIMARY KEY, '
    'author_id INTEGER NOT NULL, '
    'created_at INTEGER NOT NULL, '
    'body TEXT NOT NULL, '
    'like_count INTEGER NOT NULL)',
  );
  // Keyset pagination order: most-recent first, id as tie-breaker.
  await peer.execute(
    'CREATE INDEX IF NOT EXISTS posts_created_at_id ON posts(created_at DESC, id)',
  );

  final prng = math.Random(_prngSeed);
  // Chunked batch insert so the harness doesn't allocate a single
  // massive paramSets array. 100K rows / 10K chunk = 10 batches.
  const chunkSize = 10000;
  for (var offset = 0; offset < _postCount; offset += chunkSize) {
    final n = math.min(chunkSize, _postCount - offset);
    await peer.executeBatch(
      'INSERT INTO posts(author_id, created_at, body, like_count) '
      'VALUES (?, ?, ?, ?)',
      [
        for (var i = 0; i < n; i++)
          [
            prng.nextInt(500) + 1,
            offset + i, // monotonic created_at
            'body_${offset + i}',
            0,
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Part A — keyset paging
// ---------------------------------------------------------------------------

final class _PagingReading {
  _PagingReading({required this.label, required this.timing});
  final String label;
  final BenchmarkTiming timing;
}

Future<_PagingReading> _measurePaging(BenchmarkPeer peer) async {
  final timing = BenchmarkTiming(peer.label);

  for (var iter = 0; iter < _pagingWarmup + _pagingIterations; iter++) {
    final record = iter >= _pagingWarmup;

    int? lastCreatedAt;
    int? lastId;

    for (var page = 0; page < _pageCount; page++) {
      final swWall = Stopwatch()..start();
      final result = page == 0
          ? await peer.select(
              'SELECT id, author_id, created_at, body, like_count '
              'FROM posts ORDER BY created_at DESC, id DESC LIMIT ?',
              [_pageSize],
            )
          : await peer.select(
              'SELECT id, author_id, created_at, body, like_count '
              'FROM posts '
              'WHERE (created_at, id) < (?, ?) '
              'ORDER BY created_at DESC, id DESC LIMIT ?',
              [lastCreatedAt, lastId, _pageSize],
            );
      final wallUs = swWall.elapsedMicroseconds;
      final swMain = Stopwatch()..start();
      _consume(result);
      swMain.stop();
      swWall.stop();

      // Advance the keyset cursor. Result rows are Maps with `id` and
      // `created_at` keys.
      if (result.isNotEmpty) {
        final last = result.last;
        lastCreatedAt = last['created_at'] as int?;
        lastId = last['id'] as int?;
      }

      if (record) {
        if (peer.isSynchronous) {
          timing.recordWallOnly(swWall.elapsedMicroseconds);
        } else {
          timing.record(
            wallMicroseconds: wallUs,
            mainMicroseconds: swMain.elapsedMicroseconds,
          );
        }
      }
    }
  }

  return _PagingReading(label: peer.label, timing: timing);
}

void _consume(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    for (final v in row.values) {
      if (identical(v, v)) continue;
    }
  }
}

// ---------------------------------------------------------------------------
// Part B — reactive feed under concurrent writes
// ---------------------------------------------------------------------------

final class _ReactiveReading {
  _ReactiveReading({
    required this.label,
    required this.timing,
    required this.medianEmissions,
  });
  final String label;
  final BenchmarkTiming timing;

  /// Post-baseline emission count. With 100 `like_count` updates
  /// scattered across 100K posts, only ~1 update per iteration will
  /// target a row on the latest-50 page. Hash-based suppression
  /// (resqlite exp 031/033) can further reduce emissions to ~0 if the
  /// projected column set is unchanged. Over-fire on sqlite_async is
  /// the expected baseline.
  final int medianEmissions;
}

Future<_ReactiveReading> _measureReactive(BenchmarkPeer peer) async {
  final timing = BenchmarkTiming(peer.label);
  final emissionsByIter = <int>[];

  for (var iter = 0;
      iter < _pagingWarmup + _reactiveIterations;
      iter++) {
    final r = await _singleReactiveIteration(peer);
    if (iter >= _pagingWarmup) {
      timing.record(
        wallMicroseconds: r.wallMicroseconds,
        mainMicroseconds: r.listenerMicroseconds,
      );
      emissionsByIter.add(r.postBaselineEmissions);
    }
  }

  return _ReactiveReading(
    label: peer.label,
    timing: timing,
    medianEmissions: _median(emissionsByIter),
  );
}

final class _ReactiveIterResult {
  _ReactiveIterResult({
    required this.wallMicroseconds,
    required this.listenerMicroseconds,
    required this.postBaselineEmissions,
  });
  final int wallMicroseconds;
  final int listenerMicroseconds;
  final int postBaselineEmissions;
}

Future<_ReactiveIterResult> _singleReactiveIteration(
  BenchmarkPeer peer,
) async {
  final prng = math.Random(_prngSeed ^ 0xDEAD);

  var emissions = 0;
  var listenerUs = 0;
  final sub = peer.watch(
    'SELECT id, author_id, created_at, body, like_count FROM posts '
    'ORDER BY created_at DESC, id DESC LIMIT ?',
    params: [_pageSize],
    readsFrom: const {'posts'},
  ).listen((_) {
    final sw = Stopwatch()..start();
    emissions++;
    sw.stop();
    listenerUs += sw.elapsedMicroseconds;
  });

  try {
    // Drain initial emission.
    await _waitUntil(
      predicate: () => emissions >= 1,
      timeout: const Duration(seconds: 20),
      description: 'initial feed emission',
    );
    final baseline = emissions;
    final baselineListenerUs = listenerUs;

    final sw = Stopwatch()..start();
    // 100 random like_count writes spread across the full 100K-post range.
    for (var i = 0; i < _likeWrites; i++) {
      final id = prng.nextInt(_postCount) + 1;
      await peer.execute(
        'UPDATE posts SET like_count = like_count + 1 WHERE id = ?',
        [id],
      );
    }

    // Settle.
    var lastEmits = emissions;
    const quietWindow = Duration(milliseconds: 100);
    final quietDeadline =
        DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(quietDeadline)) {
      await Future<void>.delayed(quietWindow);
      if (emissions == lastEmits) break;
      lastEmits = emissions;
    }
    sw.stop();

    return _ReactiveIterResult(
      wallMicroseconds: sw.elapsedMicroseconds,
      listenerMicroseconds: listenerUs - baselineListenerUs,
      postBaselineEmissions: emissions - baseline,
    );
  } finally {
    await sub.cancel();
  }
}

// ---------------------------------------------------------------------------
// Markdown output
// ---------------------------------------------------------------------------

void _writePagingSection(
  StringBuffer md,
  Map<String, _PagingReading> byPeer,
) {
  md
    ..writeln('### Keyset pagination ($_pageCount pages × $_pageSize rows)')
    ..writeln()
    ..writeln('| Library | Wall med (ms) | Wall p90 (ms) | '
        'Main med (ms) | Main p90 (ms) |')
    ..writeln('|---|---|---|---|---|');
  for (final reading in byPeer.values) {
    md.writeln(
      '| ${reading.label} '
      '| ${reading.timing.wall.medianMs.toStringAsFixed(3)} '
      '| ${reading.timing.wall.p90Ms.toStringAsFixed(3)} '
      '| ${reading.timing.main.medianMs.toStringAsFixed(3)} '
      '| ${reading.timing.main.p90Ms.toStringAsFixed(3)} |',
    );
  }
  md
    ..writeln()
    ..writeln('Keyset pagination walks backwards through the feed via '
        '`(created_at, id) < (?, ?)` rather than `OFFSET`, which scales '
        'with position rather than degrading on deep pages. Per-page '
        'timing is reported; reading the p90 catches occasional slow '
        'pages that would be invisible in a wall-aggregate.')
    ..writeln();
}

void _writeReactiveSection(
  StringBuffer md,
  Map<String, _ReactiveReading> byPeer,
) {
  if (byPeer.isEmpty) return;
  md
    ..writeln('### Reactive feed with $_likeWrites concurrent writes')
    ..writeln()
    ..writeln('| Library | Wall med (ms) | Wall p90 (ms) | '
        'Main med (ms) | Main p90 (ms) | Emissions |')
    ..writeln('|---|---|---|---|---|---|');
  for (final reading in byPeer.values) {
    md.writeln(
      '| ${reading.label} '
      '| ${reading.timing.wall.medianMs.toStringAsFixed(3)} '
      '| ${reading.timing.wall.p90Ms.toStringAsFixed(3)} '
      '| ${reading.timing.main.medianMs.toStringAsFixed(3)} '
      '| ${reading.timing.main.p90Ms.toStringAsFixed(3)} '
      '| ${reading.medianEmissions} |',
    );
  }
  md
    ..writeln()
    ..writeln('One stream on latest-50. $_likeWrites `like_count` '
        'writes against random posts — most do not intersect the '
        'watched page. `Main med` is aggregate listener-callback time '
        '(UI thread cost, see METHODOLOGY.md § Measurement). '
        '`Emissions` is post-baseline; a library with hash-based '
        'unchanged suppression can stay near 0 when the watched page '
        'does not change.')
    ..writeln();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

int _median(List<int> xs) {
  final sorted = [...xs]..sort();
  return sorted[sorted.length ~/ 2];
}

Future<void> _waitUntil({
  required bool Function() predicate,
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(description, timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// Standalone entry.
Future<void> main() async {
  final md = await runFeedPagingBenchmark();
  print(md);
}
