// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/writer/writer.dart';

Future<void> main(List<String> args) async {
  if (!WriterCompletionCatchDiagnostics.enabled) {
    throw StateError('Run with -DRESQLITE_WRITE_COMPLETION_DIAGNOSTICS=true.');
  }
  final operations = args.isEmpty ? 5000 : int.parse(args.single);
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_exp271_diagnostics_',
  );
  final db = await Database.open('${tempDir.path}/diagnostics.db');
  try {
    await db.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, value INTEGER NOT NULL)',
    );
    await db.execute('INSERT INTO items(id, value) VALUES (1, 0)');
    for (var i = 0; i < 200; i++) {
      await db.execute('UPDATE items SET value = value WHERE id = 1');
    }

    WriterCompletionCatchDiagnostics.reset();
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < operations; i++) {
      await db.execute('UPDATE items SET value = value WHERE id = 1');
    }
    stopwatch.stop();
    await Future<void>.delayed(Duration.zero);

    final attempts = WriterCompletionCatchDiagnostics.attempts;
    final hits = WriterCompletionCatchDiagnostics.hits;
    print(
      jsonEncode(<String, Object?>{
        'operations': operations,
        'elapsed_us': stopwatch.elapsedMicroseconds,
        'us_per_write': stopwatch.elapsedMicroseconds / operations,
        'poll_attempts': attempts,
        'poll_hits': hits,
        'poll_misses': WriterCompletionCatchDiagnostics.misses,
        'catch_rate': attempts == 0 ? 0 : hits / attempts,
        'total_poll_us': WriterCompletionCatchDiagnostics.pollUs,
        'mean_poll_us': attempts == 0
            ? 0
            : WriterCompletionCatchDiagnostics.pollUs / attempts,
      }),
    );
  } finally {
    await db.close();
    await tempDir.delete(recursive: true);
  }
}
