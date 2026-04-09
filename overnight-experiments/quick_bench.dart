// ignore_for_file: avoid_print

// Quick benchmark for overnight experiments.
// Focuses on the key metrics that matter most, runs fast.
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _warmup = 5;
const _iterations = 30;

Future<Map<String, double>> runQuickBench() async {
  final results = <String, double>{};
  final tempDir = await Directory.systemTemp.createTemp('overnight_bench_');

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

    // Seed 5000 rows.
    await db.executeBatch(
      'INSERT INTO items(name, description, value, category, created_at) VALUES (?, ?, ?, ?, ?)',
      [
        for (var i = 0; i < 5000; i++)
          [
            'Item $i',
            'This is a description for item number $i with some padding text to simulate real data',
            i * 1.5,
            'category_${i % 10}',
            '2026-04-0${(i % 9) + 1}T12:00:00Z',
          ],
      ],
    );

    const sql = 'SELECT * FROM items';

    // --- select() 5000 rows ---
    for (var i = 0; i < _warmup; i++) {
      await db.select(sql);
    }
    final selectTimings = <int>[];
    final selectMainTimings = <int>[];
    for (var i = 0; i < _iterations; i++) {
      final swWall = Stopwatch()..start();
      final rows = await db.select(sql);
      final swMain = Stopwatch()..start();
      // Force materialization of all rows.
      for (final row in rows) {
        for (final key in row.keys) {
          row[key];
        }
      }
      swMain.stop();
      swWall.stop();
      selectTimings.add(swWall.elapsedMicroseconds);
      selectMainTimings.add(swMain.elapsedMicroseconds);
    }
    selectTimings.sort();
    selectMainTimings.sort();
    results['select_5k_wall_us'] = selectTimings[selectTimings.length ~/ 2].toDouble();
    results['select_5k_main_us'] = selectMainTimings[selectMainTimings.length ~/ 2].toDouble();

    // --- selectBytes() 5000 rows ---
    for (var i = 0; i < _warmup; i++) {
      await db.selectBytes(sql);
    }
    final bytesTimings = <int>[];
    for (var i = 0; i < _iterations; i++) {
      final sw = Stopwatch()..start();
      await db.selectBytes(sql);
      sw.stop();
      bytesTimings.add(sw.elapsedMicroseconds);
    }
    bytesTimings.sort();
    results['bytes_5k_wall_us'] = bytesTimings[bytesTimings.length ~/ 2].toDouble();

    // --- Concurrent reads (8x, 1000 rows) ---
    await db.execute('CREATE TABLE small(id INTEGER PRIMARY KEY, value INTEGER)');
    await db.executeBatch(
      'INSERT INTO small(value) VALUES (?)',
      [for (var i = 0; i < 1000; i++) [i]],
    );
    for (var i = 0; i < _warmup; i++) {
      await Future.wait([
        for (var j = 0; j < 8; j++) db.select('SELECT * FROM small'),
      ]);
    }
    final concTimings = <int>[];
    for (var i = 0; i < _iterations; i++) {
      final sw = Stopwatch()..start();
      await Future.wait([
        for (var j = 0; j < 8; j++) db.select('SELECT * FROM small'),
      ]);
      sw.stop();
      concTimings.add(sw.elapsedMicroseconds);
    }
    concTimings.sort();
    results['concurrent_8x_wall_us'] = concTimings[concTimings.length ~/ 2].toDouble();

    // --- Parameterized (100 queries × ~500 rows) ---
    await db.execute('CREATE INDEX idx_cat ON items(category)');
    for (var i = 0; i < _warmup; i++) {
      for (var c = 0; c < 10; c++) {
        await db.select('SELECT * FROM items WHERE category = ?', ['category_$c']);
      }
    }
    final paramTimings = <int>[];
    for (var i = 0; i < _iterations; i++) {
      final sw = Stopwatch()..start();
      for (var c = 0; c < 100; c++) {
        await db.select('SELECT * FROM items WHERE category = ?', ['category_${c % 10}']);
      }
      sw.stop();
      paramTimings.add(sw.elapsedMicroseconds);
    }
    paramTimings.sort();
    results['param_100q_wall_us'] = paramTimings[paramTimings.length ~/ 2].toDouble();

    // --- Single writes (100) ---
    await db.execute('CREATE TABLE writes(id INTEGER PRIMARY KEY, val TEXT)');
    for (var i = 0; i < _warmup; i++) {
      await db.execute('INSERT INTO writes(val) VALUES (?)', ['warmup']);
    }
    final writeTimings = <int>[];
    for (var i = 0; i < _iterations; i++) {
      final sw = Stopwatch()..start();
      for (var j = 0; j < 100; j++) {
        await db.execute('INSERT INTO writes(val) VALUES (?)', ['item_$j']);
      }
      sw.stop();
      writeTimings.add(sw.elapsedMicroseconds);
    }
    writeTimings.sort();
    results['write_100_wall_us'] = writeTimings[writeTimings.length ~/ 2].toDouble();

    // --- Batch write (1000 rows) ---
    for (var i = 0; i < _warmup; i++) {
      await db.executeBatch(
        'INSERT INTO writes(val) VALUES (?)',
        [for (var j = 0; j < 1000; j++) ['batch_$j']],
      );
    }
    final batchTimings = <int>[];
    for (var i = 0; i < _iterations; i++) {
      final sw = Stopwatch()..start();
      await db.executeBatch(
        'INSERT INTO writes(val) VALUES (?)',
        [for (var j = 0; j < 1000; j++) ['batch_$j']],
      );
      sw.stop();
      batchTimings.add(sw.elapsedMicroseconds);
    }
    batchTimings.sort();
    results['batch_1k_wall_us'] = batchTimings[batchTimings.length ~/ 2].toDouble();

    await db.close();
  } finally {
    await tempDir.delete(recursive: true);
  }

  return results;
}

String formatResults(Map<String, double> results) {
  final buf = StringBuffer();
  buf.writeln('| Metric | Value |');
  buf.writeln('|---|---|');
  for (final e in results.entries) {
    final ms = (e.value / 1000).toStringAsFixed(2);
    buf.writeln('| ${e.key} | $ms ms |');
  }
  return buf.toString();
}

Future<void> main() async {
  final results = await runQuickBench();
  print(jsonEncode(results));
  exit(0);
}
