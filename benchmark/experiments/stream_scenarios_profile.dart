// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';

const int _a6PostCount = 100000;
const int _a6PageSize = 50;
const int _a6LikeWrites = 100;
const int _a6Seed = 0xFEED;

const int _a7BulkRowCount = 50000;
const int _a7BulkChunkSize = 500;
const int _a7MergeRounds = 10;
const int _a7MergeRowsPerRound = 100;

const int _a11TableRowCount = 10000;
const int _a11StreamCount = 50;
const int _a11WriteCount = 200;
const int _a11Seed = 0xBEEF;

const int _a11bItemCount = 10000;
const int _a11bStreamCount = 100;
const int _a11bWriteCount = 200;
const int _a11bSeed = 0xCAFEF0;

Future<void> main(List<String> args) async {
  final outPath = _extractOutPath(args);
  final results = <String, Object?>{};

  final tempDir =
      await Directory.systemTemp.createTemp('resqlite_stream_scenarios_');
  try {
    results['generated_at'] = DateTime.now().toIso8601String();
    results['a6_feed_reactive'] =
        await _profileA6('${tempDir.path}/a6_feed_reactive.db');
    results['a7_sync_burst'] =
        await _profileA7('${tempDir.path}/a7_sync_burst.db');
    results['a11_keyed_pk'] =
        await _profileA11('${tempDir.path}/a11_keyed_pk.db');
    results['a11b_high_card_fanout'] =
        await _profileA11b('${tempDir.path}/a11b_high_card_fanout.db');
  } finally {
    await tempDir.delete(recursive: true);
  }

  const encoder = JsonEncoder.withIndent('  ');
  final json = encoder.convert(results);
  if (outPath != null) {
    await File(outPath).writeAsString('$json\n');
    print('Results written to: $outPath');
  } else {
    print(json);
  }
}

String? _extractOutPath(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--out=')) return arg.substring('--out='.length);
  }
  return null;
}

Future<Map<String, Object?>> _profileA6(String path) async {
  final db = await Database.open(path);
  try {
    await db.execute(
      'CREATE TABLE posts('
      'id INTEGER PRIMARY KEY, '
      'author_id INTEGER NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'body TEXT NOT NULL, '
      'like_count INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX posts_created_at_id ON posts(created_at DESC, id)',
    );

    final prng = math.Random(_a6Seed);
    const chunkSize = 10000;
    for (var offset = 0; offset < _a6PostCount; offset += chunkSize) {
      final n = math.min(chunkSize, _a6PostCount - offset);
      await db.executeBatch(
        'INSERT INTO posts(author_id, created_at, body, like_count) '
        'VALUES (?, ?, ?, ?)',
        [
          for (var i = 0; i < n; i++)
            [
              prng.nextInt(500) + 1,
              offset + i,
              'body_${offset + i}',
              0,
            ],
        ],
      );
    }

    var emissions = 0;
    var listenerUs = 0;
    final sub = db
        .stream(
          'SELECT id, author_id, created_at, body, like_count FROM posts '
          'ORDER BY created_at DESC, id DESC LIMIT ?',
          const [_a6PageSize],
        )
        .listen((_) {
          final sw = Stopwatch()..start();
          emissions++;
          sw.stop();
          listenerUs += sw.elapsedMicroseconds;
        });

    try {
      await _waitUntil(
        predicate: () => emissions >= 1,
        timeout: const Duration(seconds: 20),
        description: 'A6 initial feed emission',
      );

      final baselineEmissions = emissions;
      final baselineListenerUs = listenerUs;
      ProfileCounters.reset();
      final before = ProfileCounters.snapshot();

      final writePrng = math.Random(_a6Seed ^ 0xDEAD);
      final sw = Stopwatch()..start();
      for (var i = 0; i < _a6LikeWrites; i++) {
        final id = writePrng.nextInt(_a6PostCount) + 1;
        await db.execute(
          'UPDATE posts SET like_count = like_count + 1 WHERE id = ?',
          [id],
        );
      }
      await _awaitQuiet(
        quietWindow: const Duration(milliseconds: 100),
        timeout: const Duration(seconds: 20),
        sample: () => emissions,
      );
      sw.stop();

      return {
        'wall_us': sw.elapsedMicroseconds,
        'listener_us': listenerUs - baselineListenerUs,
        'post_baseline_emissions': emissions - baselineEmissions,
        'profile_counters_delta':
            ProfileCounters.diff(before, ProfileCounters.snapshot()),
      };
    } finally {
      await sub.cancel();
    }
  } finally {
    await db.close();
  }
}

Future<Map<String, Object?>> _profileA7(String path) async {
  final db = await Database.open(path);
  try {
    await db.execute(
      'CREATE TABLE items('
      'id INTEGER PRIMARY KEY, '
      'external_id INTEGER UNIQUE, '
      'payload TEXT NOT NULL)',
    );

    var emissions = 0;
    final sub = db.stream('SELECT COUNT(*) AS c FROM items').listen((_) {
      emissions++;
    });

    try {
      await _waitUntil(
        predicate: () => emissions >= 1,
        timeout: const Duration(seconds: 10),
        description: 'A7 initial COUNT(*) emission',
      );

      final baselineEmissions = emissions;
      ProfileCounters.reset();
      final before = ProfileCounters.snapshot();

      final totalSw = Stopwatch()..start();
      final bulkSw = Stopwatch()..start();
      for (var offset = 0; offset < _a7BulkRowCount; offset += _a7BulkChunkSize) {
        final n = (offset + _a7BulkChunkSize <= _a7BulkRowCount)
            ? _a7BulkChunkSize
            : _a7BulkRowCount - offset;
        await db.executeBatch(
          'INSERT INTO items(external_id, payload) VALUES (?, ?)',
          [
            for (var i = 0; i < n; i++) [offset + i, 'payload_${offset + i}'],
          ],
        );
      }
      bulkSw.stop();

      final mergeSw = Stopwatch()..start();
      for (var round = 0; round < _a7MergeRounds; round++) {
        await db.executeBatch(
          'INSERT OR REPLACE INTO items(external_id, payload) VALUES (?, ?)',
          [
            for (var i = 0; i < _a7MergeRowsPerRound; i++)
              [
                _a7BulkRowCount + round * _a7MergeRowsPerRound + i,
                'merge_${round}_$i',
              ],
          ],
        );
      }
      mergeSw.stop();

      await _awaitQuiet(
        quietWindow: const Duration(milliseconds: 200),
        timeout: const Duration(seconds: 10),
        sample: () => emissions,
      );
      totalSw.stop();

      return {
        'total_wall_us': totalSw.elapsedMicroseconds,
        'bulk_wall_us': bulkSw.elapsedMicroseconds,
        'merge_wall_us': mergeSw.elapsedMicroseconds,
        'post_baseline_emissions': emissions - baselineEmissions,
        'profile_counters_delta':
            ProfileCounters.diff(before, ProfileCounters.snapshot()),
      };
    } finally {
      await sub.cancel();
    }
  } finally {
    await db.close();
  }
}

Future<Map<String, Object?>> _profileA11(String path) async {
  final db = await Database.open(path);
  try {
    await db.execute(
      'CREATE TABLE items('
      'id INTEGER PRIMARY KEY, '
      'body TEXT NOT NULL, '
      'updated_at INTEGER NOT NULL)',
    );
    await db.executeBatch(
      'INSERT INTO items(body, updated_at) VALUES (?, ?)',
      [
        for (var i = 1; i <= _a11TableRowCount; i++) ['seed_body_$i', 0],
      ],
    );

    final watchedIds = _pickA11WatchedIds();
    final watchedSet = watchedIds.toSet();
    final emitCounts = List<int>.filled(_a11StreamCount, 0);
    var listenerUs = 0;
    final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
    for (var i = 0; i < _a11StreamCount; i++) {
      final idx = i;
      subs.add(
        db
            .stream(
              'SELECT id, body, updated_at FROM items WHERE id = ?',
              [watchedIds[i]],
            )
            .listen((_) {
              final sw = Stopwatch()..start();
              emitCounts[idx]++;
              sw.stop();
              listenerUs += sw.elapsedMicroseconds;
            }),
      );
    }

    try {
      await _waitUntil(
        predicate: () => emitCounts.every((c) => c >= 1),
        timeout: const Duration(seconds: 60),
        description: 'A11 initial emissions',
      );

      final baseline = [...emitCounts];
      final baselineListenerUs = listenerUs;
      ProfileCounters.reset();
      final before = ProfileCounters.snapshot();

      final prng = math.Random(_a11Seed);
      var observedHits = 0;
      final sw = Stopwatch()..start();
      for (var w = 0; w < _a11WriteCount; w++) {
        final pk = prng.nextInt(_a11TableRowCount) + 1;
        if (watchedSet.contains(pk)) observedHits++;
        await db.execute(
          'UPDATE items SET body = ?, updated_at = ? WHERE id = ?',
          ['body_$w', w, pk],
        );
      }
      await _awaitQuiet(
        quietWindow: const Duration(milliseconds: 200),
        timeout: const Duration(seconds: 60),
        sample: () => emitCounts.reduce((a, b) => a + b),
      );
      sw.stop();

      var totalPostBaseline = 0;
      for (var i = 0; i < _a11StreamCount; i++) {
        totalPostBaseline += emitCounts[i] - baseline[i];
      }

      return {
        'wall_us': sw.elapsedMicroseconds,
        'listener_us': listenerUs - baselineListenerUs,
        'post_baseline_emissions': totalPostBaseline,
        'observed_hits': observedHits,
        'profile_counters_delta':
            ProfileCounters.diff(before, ProfileCounters.snapshot()),
      };
    } finally {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
  } finally {
    await db.close();
  }
}

Future<Map<String, Object?>> _profileA11b(String path) async {
  final db = await Database.open(path);
  try {
    final itemsPerOwner = _a11bItemCount ~/ _a11bStreamCount;
    await db.execute(
      'CREATE TABLE items('
      'id INTEGER PRIMARY KEY, '
      'owner_id INTEGER NOT NULL, '
      'value INTEGER NOT NULL)',
    );
    await db.execute('CREATE INDEX items_owner ON items(owner_id)');
    await db.executeBatch(
      'INSERT INTO items(owner_id, value) VALUES (?, ?)',
      [
        for (var i = 0; i < _a11bItemCount; i++)
          [(i ~/ itemsPerOwner) + 1, 0],
      ],
    );

    final emitCounts = List<int>.filled(_a11bStreamCount, 0);
    var listenerUs = 0;
    final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
    for (var i = 0; i < _a11bStreamCount; i++) {
      final idx = i;
      final ownerId = i + 1;
      subs.add(
        db
            .stream(
              'SELECT id, value FROM items WHERE owner_id = ? ORDER BY id',
              [ownerId],
            )
            .listen((_) {
              final sw = Stopwatch()..start();
              emitCounts[idx]++;
              sw.stop();
              listenerUs += sw.elapsedMicroseconds;
            }),
      );
    }

    try {
      await _waitUntil(
        predicate: () => emitCounts.every((c) => c >= 1),
        timeout: const Duration(seconds: 120),
        description: 'A11b initial emissions',
      );

      final baseline = [...emitCounts];
      final baselineListenerUs = listenerUs;
      ProfileCounters.reset();
      final before = ProfileCounters.snapshot();

      final prng = math.Random(_a11bSeed);
      final sw = Stopwatch()..start();
      for (var w = 0; w < _a11bWriteCount; w++) {
        final pk = prng.nextInt(_a11bItemCount) + 1;
        await db.execute(
          'UPDATE items SET value = ? WHERE id = ?',
          [w, pk],
        );
      }
      await _awaitQuiet(
        quietWindow: const Duration(milliseconds: 200),
        timeout: const Duration(seconds: 120),
        sample: () => emitCounts.reduce((a, b) => a + b),
      );
      sw.stop();

      var totalPostBaseline = 0;
      for (var i = 0; i < _a11bStreamCount; i++) {
        totalPostBaseline += emitCounts[i] - baseline[i];
      }

      return {
        'wall_us': sw.elapsedMicroseconds,
        'listener_us': listenerUs - baselineListenerUs,
        'post_baseline_emissions': totalPostBaseline,
        'profile_counters_delta':
            ProfileCounters.diff(before, ProfileCounters.snapshot()),
      };
    } finally {
      for (final sub in subs) {
        await sub.cancel();
      }
    }
  } finally {
    await db.close();
  }
}

List<int> _pickA11WatchedIds() {
  final step = _a11TableRowCount ~/ _a11StreamCount;
  return [for (var i = 0; i < _a11StreamCount; i++) (i * step) + 1];
}

Future<void> _waitUntil({
  required bool Function() predicate,
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _awaitQuiet({
  required Duration quietWindow,
  required Duration timeout,
  required int Function() sample,
}) async {
  var last = sample();
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(quietWindow);
    final now = sample();
    if (now == last) return;
    last = now;
  }
}
