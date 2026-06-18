// Focused workload for exp 186 — single-row INSERT with a large ASCII
// TEXT param. Stresses the bind path in [allocateParams] at sizes where
// the encoder cost (utf8.encode allocating a Uint8List + setRange copy)
// is no longer dominated by the writer round-trip floor.
//
// exp 179 showed the direct-ASCII rewrite of allocateParams is 37–58 %
// faster on a synthetic encoder loop, but the release suite (1-short-
// ASCII Parameterized Queries; 1-int Single Inserts) stayed flat. The
// signal map flagged the open question: "do not re-test single-row
// allocateParams direct encoding again without a representative large-
// single-row-ASCII-text-bind workload where the round-trip/result cost
// no longer hides the encoder."
//
//   dart run benchmark/experiments/single_row_large_text_bind.dart
//
// Reports median ms/100 INSERTs per text-size shape.
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _shapes = <int>[1024, 16 * 1024, 64 * 1024, 256 * 1024, 1024 * 1024];

const _writesPerSample = 100;
const _samples = 11;

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp186-');
  final dbPath = '${tmp.path}/exp186.db';
  final db = await Database.open(dbPath);

  await db.execute('CREATE TABLE doc(id INTEGER PRIMARY KEY, body TEXT)');

  stdout.writeln(
    'single-row large-text bind — '
    '$_writesPerSample writes/sample, $_samples samples\n',
  );
  stdout.writeln('| Text bytes | Median ms/$_writesPerSample | Min | Max |');
  stdout.writeln('|---|---|---|---|');

  for (final bytes in _shapes) {
    final text = _asciiOf(bytes);
    // Warm up: bind cache, statement cache, page cache.
    for (var i = 0; i < 5; i++) {
      await db.execute('INSERT INTO doc(body) VALUES (?)', [text]);
    }
    await db.execute('DELETE FROM doc');

    final medians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _writesPerSample; i++) {
        await db.execute('INSERT INTO doc(body) VALUES (?)', [text]);
      }
      sw.stop();
      medians.add(sw.elapsedMicroseconds / 1000.0);
      await db.execute('DELETE FROM doc');
    }
    medians.sort();
    final med = medians[medians.length ~/ 2];
    stdout.writeln(
      '| ${_bytesLabel(bytes)} '
      '| ${med.toStringAsFixed(2)} '
      '| ${medians.first.toStringAsFixed(2)} '
      '| ${medians.last.toStringAsFixed(2)} |',
    );
  }

  await db.close();
  await tmp.delete(recursive: true);
}

String _bytesLabel(int n) {
  if (n >= 1024 * 1024) return '${n ~/ (1024 * 1024)} MB';
  if (n >= 1024) return '${n ~/ 1024} KB';
  return '$n B';
}

String _asciiOf(int n) {
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.writeCharCode(0x61 + (i % 26));
  }
  return b.toString();
}
