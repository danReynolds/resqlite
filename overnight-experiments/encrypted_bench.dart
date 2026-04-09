// ignore_for_file: avoid_print

// Benchmark: encrypted vs unencrypted performance.
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _warmup = 5;
const _iterations = 30;
const _key = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Future<Map<String, double>> _bench(Database db, String label) async {
  final results = <String, double>{};

  await db.execute('''
    CREATE TABLE IF NOT EXISTS items(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT NOT NULL,
      value REAL NOT NULL,
      category TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');

  // Check if already seeded.
  final existing = await db.select('SELECT COUNT(*) as cnt FROM items');
  if ((existing[0]['cnt'] as int) < 5000) {
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
  }

  const sql = 'SELECT * FROM items';

  // select 5k
  for (var i = 0; i < _warmup; i++) {
    await db.select(sql);
  }
  final selectTimings = <int>[];
  for (var i = 0; i < _iterations; i++) {
    final sw = Stopwatch()..start();
    await db.select(sql);
    sw.stop();
    selectTimings.add(sw.elapsedMicroseconds);
  }
  selectTimings.sort();
  results['${label}_select_5k_us'] = selectTimings[selectTimings.length ~/ 2].toDouble();

  // selectBytes 5k
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
  results['${label}_bytes_5k_us'] = bytesTimings[bytesTimings.length ~/ 2].toDouble();

  // write 100
  await db.execute('CREATE TABLE IF NOT EXISTS writes(id INTEGER PRIMARY KEY, val TEXT)');
  for (var i = 0; i < _warmup; i++) {
    await db.execute('INSERT INTO writes(val) VALUES (?)', ['w']);
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
  results['${label}_write_100_us'] = writeTimings[writeTimings.length ~/ 2].toDouble();

  return results;
}

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('enc_bench_');

  try {
    // Unencrypted.
    final plainDb = await Database.open('${tempDir.path}/plain.db');
    final plainResults = await _bench(plainDb, 'plain');
    await plainDb.close();

    // Encrypted.
    final encDb = await Database.open(
      '${tempDir.path}/encrypted.db',
      encryptionKey: _key,
    );
    final encResults = await _bench(encDb, 'encrypted');
    await encDb.close();

    // Print comparison.
    final all = {...plainResults, ...encResults};

    print('');
    print('=== Encryption Performance Impact ===');
    print('');
    print('${'Metric'.padRight(25)} ${'Plain'.padLeft(10)} ${'Encrypted'.padLeft(12)} ${'Overhead'.padLeft(10)}');
    print('-' * 60);

    void compare(String metric) {
      final plain = all['plain_$metric']!;
      final enc = all['encrypted_$metric']!;
      final overhead = (enc - plain) / plain * 100;
      print(
        '${metric.padRight(25)} '
        '${(plain / 1000).toStringAsFixed(2).padLeft(8)} ms '
        '${(enc / 1000).toStringAsFixed(2).padLeft(10)} ms '
        '${overhead >= 0 ? '+' : ''}${overhead.toStringAsFixed(1).padLeft(8)}%',
      );
    }

    compare('select_5k_us');
    compare('bytes_5k_us');
    compare('write_100_us');

    print('');
    print(jsonEncode(all));
  } finally {
    await tempDir.delete(recursive: true);
  }

  exit(0);
}
