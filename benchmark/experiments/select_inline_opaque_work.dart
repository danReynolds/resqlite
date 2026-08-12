// ignore_for_file: avoid_print

/// Adversarial probe for read routing that executes expensive work inside one
/// SQLite VM opcode while returning one small INTEGER cell.
///
/// `randomblob(?)` is evaluated by SQLite's built-in function callback. Its
/// byte generation is opaque to a VM-instruction budget, and `length(...)`
/// keeps the result below both the row and payload caps. The first two tiny
/// executions arm any history-based inline route; the large executions then
/// show whether a 1 ms timer can run before `select()` returns.
///
/// Usage:
///   dart run benchmark/experiments/select_inline_opaque_work.dart \
///     --bytes=33554432 --samples=5
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _sql = 'SELECT length(randomblob(?)) AS n';

Future<void> main(List<String> args) async {
  var bytes = 32 * 1024 * 1024;
  var samples = 5;
  for (final arg in args) {
    if (arg.startsWith('--bytes=')) {
      bytes = int.parse(arg.substring('--bytes='.length));
    } else if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  final temp = await Directory.systemTemp.createTemp('resqlite_inline_opaque_');
  final db = await Database.open('${temp.path}/probe.db');
  try {
    // Row-size memory forms its first opinion after two executions. Keep both
    // cheap so the third execution is the first one that tests opaque work.
    await db.select(_sql, [1]);
    await db.select(_sql, [1]);

    print('bytes=$bytes samples=$samples timer_ms=1');
    for (var sample = 0; sample < samples; sample++) {
      var timerFired = false;
      final timerDone = Completer<void>();
      Timer(const Duration(milliseconds: 1), () {
        timerFired = true;
        timerDone.complete();
      });

      final watch = Stopwatch()..start();
      final rows = await db.select(_sql, [bytes]);
      watch.stop();
      final firedBeforeReturn = timerFired;
      if (!timerFired) await timerDone.future;

      if (rows.single['n'] != bytes) {
        throw StateError('unexpected result: ${rows.single}');
      }
      print(
        'sample=${sample + 1} elapsed_us=${watch.elapsedMicroseconds} '
        'timer_fired_before_return=$firedBeforeReturn',
      );
    }
  } finally {
    await db.close();
    await temp.delete(recursive: true);
  }
}
