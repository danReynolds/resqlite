// ignore_for_file: avoid_print
/// resqlite subprocess for peer comparison benchmark.
/// Outputs JSON results to stdout.
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _seedRows = 100;
const _lookups = 500;
const _warmupLookups = 50;

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('bench_peer_resqlite_');
  final results = <String, dynamic>{};

  try {
    final db = await Database.open('${tempDir.path}/test.db');
    await db.execute('''
      CREATE TABLE items(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        value REAL NOT NULL,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Seed rows.
    await db.executeBatch(
      'INSERT INTO items(name, description, value, category, created_at) VALUES (?, ?, ?, ?, ?)',
      [
        for (var i = 0; i < _seedRows; i++)
          [
            'Item $i',
            'Description for item $i with padding text',
            i * 1.5,
            'category_${i % 10}',
            '2026-04-07T12:00:00Z',
          ],
      ],
    );

    const sql = 'SELECT * FROM items WHERE id = ?';

    // Warmup.
    final warmupSw = Stopwatch()..start();
    for (var i = 0; i < _warmupLookups; i++) {
      await db.select(sql, [(i % _seedRows) + 1]);
    }
    warmupSw.stop();
    results['warmup_total_us'] = warmupSw.elapsedMicroseconds;

    // Measured lookups — collect per-query timings.
    final perQuery = <int>[];
    final totalSw = Stopwatch()..start();
    for (var i = 0; i < _lookups; i++) {
      final sw = Stopwatch()..start();
      final rows = await db.select(sql, [(i % _seedRows) + 1]);
      sw.stop();
      // Verify we got exactly 1 row.
      assert(rows.length == 1, 'Expected 1 row, got ${rows.length}');
      perQuery.add(sw.elapsedMicroseconds);
    }
    totalSw.stop();

    perQuery.sort();
    results['total_500_us'] = totalSw.elapsedMicroseconds;
    results['per_query_median_us'] = perQuery[perQuery.length ~/ 2];
    results['per_query_p95_us'] = perQuery[(perQuery.length * 0.95).floor()];
    results['per_query_p99_us'] = perQuery[(perQuery.length * 0.99).floor()];
    results['per_query_min_us'] = perQuery.first;
    results['per_query_max_us'] = perQuery.last;
    results['per_query_mean_us'] =
        (perQuery.reduce((a, b) => a + b) / perQuery.length).round();

    // Build histogram.
    results['histogram'] = _histogram(perQuery);

    await db.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  print('RESULT_JSON:${jsonEncode(results)}');
  exit(0);
}

String _histogram(List<int> sorted) {
  final buckets = <String, int>{};
  for (final v in sorted) {
    final bucket = switch (v) {
      < 50 => '  <50 us',
      < 75 => ' 50-75 us',
      < 100 => ' 75-100 us',
      < 125 => '100-125 us',
      < 150 => '125-150 us',
      < 200 => '150-200 us',
      < 300 => '200-300 us',
      < 500 => '300-500 us',
      _ => '500+ us',
    };
    buckets[bucket] = (buckets[bucket] ?? 0) + 1;
  }

  final buf = StringBuffer();
  for (final entry in buckets.entries) {
    final bar = '#' * (entry.value * 50 ~/ sorted.length).clamp(1, 50);
    buf.writeln('  ${entry.key}: ${entry.value.toString().padLeft(4)} $bar');
  }
  return buf.toString().trimRight();
}
