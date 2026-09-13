// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

/// Guards writer-side stream-rerun proposals against opaque SQLite work.
///
/// The query returns one row, but `randomblob` makes its execution time large
/// and invisible to row-count admission. Each sample opens a fresh database,
/// so it directly tests the archived candidate's unpriced first admission. The
/// first write invalidates the stream. A second write enters on the next event
/// turn, after an idle check may already have admitted the rerun. If a proposal
/// runs that rerun on the writer connection, the second write queues behind the
/// full synchronous SQLite statement. A history-based proposal also needs a
/// slow-after-fast mode; old timings cannot establish a hard future bound.
Future<void> main(List<String> args) async {
  var samples = 7;
  var payloadBytes = 16 * 1024 * 1024;
  for (final arg in args) {
    if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--payload-bytes=')) {
      payloadBytes = int.parse(arg.substring('--payload-bytes='.length));
    }
  }

  final waits = <int>[];
  print('samples=$samples payloadBytes=$payloadBytes');
  for (var sample = 0; sample < samples; sample++) {
    final wait = await _sample(payloadBytes);
    waits.add(wait);
    print('sample=${sample + 1} second_write_us=$wait');
  }

  final sorted = [...waits]..sort();
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  print(
    'min_us=${sorted.first} median_us=${median.toStringAsFixed(1)} '
    'max_us=${sorted.last}',
  );
}

Future<int> _sample(int payloadBytes) async {
  final dir = await Directory.systemTemp.createTemp('resqlite-rerun-guard-');
  final db = await Database.open('${dir.path}/probe.db');
  try {
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER)',
    );
    await db.execute('INSERT INTO items(value) VALUES (0)');

    final ready = Completer<void>();
    final subscription = db
        .stream(
          'SELECT value, length(randomblob(?)) AS n '
          'FROM items WHERE id = 1',
          [payloadBytes],
        )
        .listen(
          (_) {
            if (!ready.isCompleted) ready.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!ready.isCompleted) ready.completeError(error, stackTrace);
          },
        );
    await ready.future;

    await db.execute('UPDATE items SET value = value + 1 WHERE id = 1');
    final result = Completer<int>();
    Timer.run(() async {
      final stopwatch = Stopwatch()..start();
      try {
        await db.execute('UPDATE items SET value = value + 1 WHERE id = 1');
        stopwatch.stop();
        result.complete(stopwatch.elapsedMicroseconds);
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });

    try {
      return await result.future;
    } finally {
      await subscription.cancel();
    }
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}
