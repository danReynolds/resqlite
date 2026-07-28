// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

/// Focused A/B harness for [EXP-254]: read TEXT cells via `sqlite3_value_blob`
/// instead of `sqlite3_value_text` across the reader decode + JSON + stream-hash
/// paths. `value_text` forces `sqlite3VdbeMemNulTerminate`, which for an
/// ephemeral page-backed string mallocs a fresh buffer and copies the whole
/// cell to append a '\0' none of these consumers read (they all take an
/// explicit byte length — the invariant exp 191 audited). `value_blob` returns
/// the same UTF-8 bytes (UTF-8 connection) with no forced copy.
///
/// Expected signal: the win scales with bytes copied — largest on long-text,
/// text-column-heavy rowsets — and is confined to text. Lanes:
///   - select / long TEXT       : decode path, ~200-byte strings x 3 cols
///   - selectBytes / long TEXT  : JSON path, same shape
///   - select / short TEXT      : decode path, ~12-byte strings x 6 cols
///   - selectBytes / short TEXT : JSON path, same shape
///   - select / INTEGER control : no text cell -> must stay flat (proves the
///                                delta is text materialization, not noise)
const _warmup = 25;
const _iterations = 160;

double _median(List<double> xs) {
  xs.sort();
  final n = xs.length;
  return n.isOdd ? xs[n ~/ 2] : (xs[n ~/ 2 - 1] + xs[n ~/ 2]) / 2;
}

final class _Case {
  const _Case(
    this.label,
    this.createSql,
    this.insertSql,
    this.row,
    this.rows, {
    required this.bytesPath,
  });

  final String label;
  final String createSql;
  final String insertSql;
  final List<Object?> Function(int i) row;
  final int rows;

  /// When true, exercise `selectBytes()` (JSON encoder path); otherwise
  /// `select()` (Dart decode path).
  final bool bytesPath;
}

String _text(int len, int seed) {
  final b = StringBuffer();
  // Printable ASCII, deterministic, no escapes so json_write_string stays on
  // its fast span — isolates the value_text/value_blob delta, not escaping.
  for (var i = 0; i < len; i++) {
    b.writeCharCode(0x41 + ((seed + i) % 26));
  }
  return b.toString();
}

const _longText3Create = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    a TEXT NOT NULL, b TEXT NOT NULL, c TEXT NOT NULL
  )
''';
const _longText3Insert = 'INSERT INTO items(a, b, c) VALUES (?, ?, ?)';
List<Object?> _longText3Row(int i) => [
  _text(200, i),
  _text(200, i + 7),
  _text(200, i + 13),
];

const _shortText6Create = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    a TEXT, b TEXT, c TEXT, d TEXT, e TEXT, f TEXT
  )
''';
const _shortText6Insert =
    'INSERT INTO items(a, b, c, d, e, f) VALUES (?, ?, ?, ?, ?, ?)';
List<Object?> _shortText6Row(int i) => [
  _text(12, i),
  _text(12, i + 1),
  _text(12, i + 2),
  _text(12, i + 3),
  _text(12, i + 4),
  _text(12, i + 5),
];

const _int8Create = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    c1 INTEGER, c2 INTEGER, c3 INTEGER, c4 INTEGER,
    c5 INTEGER, c6 INTEGER, c7 INTEGER
  )
''';
const _int8Insert =
    'INSERT INTO items(c1, c2, c3, c4, c5, c6, c7) VALUES (?, ?, ?, ?, ?, ?, ?)';
List<Object?> _int8Row(int i) => [for (var j = 1; j < 8; j++) i * 31 + j];

final _cases = <_Case>[
  _Case(
    'select / 5k x 3 long TEXT (~200B)',
    _longText3Create,
    _longText3Insert,
    _longText3Row,
    5000,
    bytesPath: false,
  ),
  _Case(
    'selectBytes / 5k x 3 long TEXT (~200B)',
    _longText3Create,
    _longText3Insert,
    _longText3Row,
    5000,
    bytesPath: true,
  ),
  _Case(
    'select / 10k x 6 short TEXT (~12B)',
    _shortText6Create,
    _shortText6Insert,
    _shortText6Row,
    10000,
    bytesPath: false,
  ),
  _Case(
    'selectBytes / 10k x 6 short TEXT (~12B)',
    _shortText6Create,
    _shortText6Insert,
    _shortText6Row,
    10000,
    bytesPath: true,
  ),
  _Case(
    'select / 10k x 8 INTEGER control',
    _int8Create,
    _int8Insert,
    _int8Row,
    10000,
    bytesPath: false,
  ),
  _Case(
    'selectBytes / 10k x 8 INTEGER control',
    _int8Create,
    _int8Insert,
    _int8Row,
    10000,
    bytesPath: true,
  ),
];

Future<void> main() async {
  print('=== TEXT value_blob decode focused harness (exp 254) ===');
  print('warmup=$_warmup, iterations=$_iterations');
  print('');
  print('| Lane | p50 (ms) | p90 (ms) |');
  print('|---|---:|---:|');
  for (final c in _cases) {
    final tempDir = await Directory.systemTemp.createTemp('bench_text_vb_');
    try {
      final db = await resqlite.Database.open('${tempDir.path}/test.db');
      await db.execute(c.createSql);
      await db.execute('BEGIN');
      for (var i = 0; i < c.rows; i++) {
        await db.execute(c.insertSql, c.row(i));
      }
      await db.execute('COMMIT');

      const sql = 'SELECT * FROM items';
      for (var i = 0; i < _warmup; i++) {
        if (c.bytesPath) {
          await db.selectBytes(sql);
        } else {
          await db.select(sql);
        }
      }

      final samples = <double>[];
      for (var i = 0; i < _iterations; i++) {
        final sw = Stopwatch()..start();
        if (c.bytesPath) {
          await db.selectBytes(sql);
        } else {
          await db.select(sql);
        }
        sw.stop();
        samples.add(sw.elapsedMicroseconds / 1000.0);
      }
      samples.sort();
      final p50 = _median(List.of(samples));
      final p90 = samples[(samples.length * 0.9).floor()];
      print(
        '| ${c.label} | ${p50.toStringAsFixed(3)} | ${p90.toStringAsFixed(3)} |',
      );
      await db.close();
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
}
