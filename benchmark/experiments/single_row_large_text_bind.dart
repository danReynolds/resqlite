// Focused workload for exp 186/187 — single-row INSERT with a large
// TEXT param. Stresses the bind path in [allocateParams] at sizes where
// the encoder cost (utf8.encode allocating a Uint8List + setRange copy,
// or direct inline UTF-8 writing) is no longer dominated by the writer
// round-trip floor.
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
import 'dart:convert';
import 'dart:io';

import 'package:resqlite/resqlite.dart';

const _shapes = <int>[1024, 16 * 1024, 64 * 1024, 256 * 1024, 1024 * 1024];
const _kinds = <_PayloadKind>[_PayloadKind.ascii, _PayloadKind.cjk];

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
  stdout.writeln(
    '| Payload | UTF-8 bytes | Median ms/$_writesPerSample | Min | Max |',
  );
  stdout.writeln('|---|---:|---:|---:|---:|');

  for (final kind in _kinds) {
    for (final bytes in _shapes) {
      final text = _textOf(kind, bytes);
      final utf8Bytes = utf8.encode(text).length;
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
        '| ${_kindLabel(kind)} ${_bytesLabel(bytes)} '
        '| $utf8Bytes '
        '| ${med.toStringAsFixed(2)} '
        '| ${medians.first.toStringAsFixed(2)} '
        '| ${medians.last.toStringAsFixed(2)} |',
      );
    }
  }

  await db.close();
  await tmp.delete(recursive: true);
}

enum _PayloadKind { ascii, cjk }

String _bytesLabel(int n) {
  if (n >= 1024 * 1024) return '${n ~/ (1024 * 1024)} MB';
  if (n >= 1024) return '${n ~/ 1024} KB';
  return '$n B';
}

String _kindLabel(_PayloadKind kind) {
  switch (kind) {
    case _PayloadKind.ascii:
      return 'ASCII';
    case _PayloadKind.cjk:
      return 'CJK';
  }
}

String _textOf(_PayloadKind kind, int bytes) {
  switch (kind) {
    case _PayloadKind.ascii:
      return _asciiOf(bytes);
    case _PayloadKind.cjk:
      return _cjkOf(bytes);
  }
}

String _asciiOf(int n) {
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.writeCharCode(0x61 + (i % 26));
  }
  return b.toString();
}

String _cjkOf(int utf8Bytes) {
  const chars = ['日', '本', '語', '東', '京', '漢', '字'];
  final b = StringBuffer();
  var remaining = utf8Bytes;
  var i = 0;
  while (remaining >= 3) {
    b.write(chars[i++ % chars.length]);
    remaining -= 3;
  }
  for (var j = 0; j < remaining; j++) {
    b.writeCharCode(0x61 + j);
  }
  return b.toString();
}
