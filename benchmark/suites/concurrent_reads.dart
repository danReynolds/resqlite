// ignore_for_file: avoid_print
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/config.dart';
import '../shared/seeder.dart';
import '../shared/stats.dart';

const _rowCount = 1000;
const _concurrencyLevels = [1, 2, 4, 8];

/// Concurrent reads benchmark: parallel Future.wait with varying concurrency.
Future<String> runConcurrentReadsBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Concurrent Reads (1000 rows per query)');
  markdown.writeln('');
  markdown.writeln('Multiple parallel `select()` calls via `Future.wait`. '
      'sqlite3 is excluded (synchronous, no concurrency).');
  markdown.writeln('');

  final tempDir = await Directory.systemTemp.createTemp('bench_concurrent_');
  try {
    final resqliteDb = await resqlite.Database.open('${tempDir.path}/resqlite.db');
    final asyncDb =
        sqlite_async.SqliteDatabase(path: '${tempDir.path}/async.db');
    await asyncDb.initialize();

    await seedResqlite(resqliteDb, _rowCount);
    await seedSqliteAsync(asyncDb, _rowCount);

    markdown.writeln(
      '| Concurrency | resqlite wall | resqlite/query | async wall | async/query |',
    );
    markdown.writeln('|---|---|---|---|---|');

    print('');
    print('=== Concurrent Reads ===');
    print('${'N'.padLeft(4)}  '
        '${'resqlite wall'.padLeft(14)}  ${'resqlite/qry'.padLeft(14)}  '
        '${'async wall'.padLeft(14)}  ${'async/qry'.padLeft(14)}');
    print('-' * 66);

    for (final n in _concurrencyLevels) {
      final tResqlite = BenchmarkTiming('resqlite');
      final tAsync = BenchmarkTiming('sqlite_async');

      // Warmup.
      for (var i = 0; i < defaultWarmup; i++) {
        await Future.wait([
          for (var j = 0; j < n; j++)
            resqliteDb.select(standardSelectSql),
        ]);
        await Future.wait([
          for (var j = 0; j < n; j++)
            asyncDb.getAll(standardSelectSql),
        ]);
      }

      // Benchmark resqlite.
      for (var i = 0; i < defaultIterations; i++) {
        final sw = Stopwatch()..start();
        await Future.wait([
          for (var j = 0; j < n; j++)
            resqliteDb.select(standardSelectSql),
        ]);
        sw.stop();
        tResqlite.recordWallOnly(sw.elapsedMicroseconds);
      }

      // Benchmark sqlite_async.
      for (var i = 0; i < defaultIterations; i++) {
        final sw = Stopwatch()..start();
        await Future.wait([
          for (var j = 0; j < n; j++)
            asyncDb.getAll(standardSelectSql),
        ]);
        sw.stop();
        tAsync.recordWallOnly(sw.elapsedMicroseconds);
      }

      final resqlitePerQuery = tResqlite.wall.medianMs / n;
      final asyncPerQuery = tAsync.wall.medianMs / n;

      print(
        '${n.toString().padLeft(4)}  '
        '${fmtMs(tResqlite.wall.medianMs)} ms  '
        '${fmtMs(resqlitePerQuery)} ms  '
        '${fmtMs(tAsync.wall.medianMs)} ms  '
        '${fmtMs(asyncPerQuery)} ms',
      );

      markdown.writeln(
        '| $n '
        '| ${tResqlite.wall.medianMs.toStringAsFixed(2)} '
        '| ${resqlitePerQuery.toStringAsFixed(2)} '
        '| ${tAsync.wall.medianMs.toStringAsFixed(2)} '
        '| ${asyncPerQuery.toStringAsFixed(2)} |',
      );
    }

    await resqliteDb.close();
    await asyncDb.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  markdown.writeln('');
  return markdown.toString();
}

Future<void> main() async {
  await runConcurrentReadsBenchmark();
}
