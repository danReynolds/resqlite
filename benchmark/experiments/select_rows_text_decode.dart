// ignore_for_file: avoid_print
//
// Focused A/B harness for [EXP-259]: who should classify a TEXT cell as ASCII,
// the Dart decoder or the native step loop?
//
// `decodeQuery` has to know whether a TEXT payload is pure ASCII before it can
// pick `String.fromCharCodes` (a Latin-1 widen) over `utf8.decode`. Doing that
// in Dart costs a second `ExternalTypedData` view plus a bounds-checked scan
// for every TEXT cell; `resqlite_step_row` already holds the pointer and length
// and can answer with a branch-free SWAR pass.
//
// Lanes are chosen so the primary signal, the guard, and the control are all
// visible in one run:
//
//   text8-short / text8-mid / text4-long — ASCII TEXT at three payload widths.
//     Short cells are the common database shape (ids, names, categories) and
//     the one where today's Dart path is worst, because a value under 16 bytes
//     misses the word-at-a-time scan and goes byte by byte.
//   text8-cjk — GUARD. Non-ASCII values still take `utf8.decode`, but the
//     native scan now walks the whole value first instead of bailing at the
//     first high byte. If that extra pass costs more than the Dart scan it
//     replaced, this lane regresses.
//   mixed6 — the default product row shape (2 TEXT + REAL + TEXT + TEXT).
//   int8 — CONTROL. Contains no TEXT at all, so both arms run byte-identical
//     code. Per the JOURNAL lesson from exp 254, a same-sign move here across
//     the order flip means the two binaries carry a layout offset and the whole
//     comparison is untrustworthy.
//
// Usage:
//   dart run benchmark/experiments/select_rows_text_decode.dart \
//     [--warmup=10] [--samples=31] [--lane=text8-short]
//
// Emits one `shape=... median_us=... samples_us=...` line per lane, so two
// worktree runs can be paired into `benchmark/ab_drift_check.dart` input.
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

const _defaultWarmup = 10;
const _defaultSamples = 31;

final class _Lane {
  /// A lane whose table is `id INTEGER PRIMARY KEY` plus [columns] generated
  /// columns all of one affinity — the synthetic width/payload sweeps.
  const _Lane(
    this.label,
    this.columns,
    this.rows,
    this.cell, {
    this.type = 'TEXT',
  }) : createSql = null,
       insertSql = null,
       row = null;

  /// A lane that declares its own schema verbatim, so it can reproduce a
  /// canonical shape rather than approximate one.
  const _Lane.explicit(
    this.label,
    this.rows, {
    required String this.createSql,
    required String this.insertSql,
    required List<Object?> Function(int row) this.row,
  }) : columns = 0,
       type = '',
       cell = null;

  final String label;
  final int columns;
  final int rows;
  final String type;

  /// Cell value for column [col] of row [row]. Null on explicit lanes.
  final Object? Function(int row, int col)? cell;

  final String? createSql;
  final String? insertSql;
  final List<Object?> Function(int row)? row;
}

// The repo's canonical mixed row: 6 columns total (`id INTEGER PRIMARY KEY`,
// 4 TEXT, 1 REAL). Copied verbatim from `benchmark/shared/seeder.dart`, which
// is the source of truth — the neighbouring `select_rows_step_row_ffi.dart`
// keeps its own copy the same way, rather than importing the seeder and
// dragging the peer-library imports into a focused harness.
const _standardCreate = '''
  CREATE TABLE items(
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    value REAL NOT NULL,
    category TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
''';
const _standardInsert =
    'INSERT INTO items(name, description, value, category, created_at) '
    'VALUES (?, ?, ?, ?, ?)';
List<Object?> _standardRow(int i) => [
  'Item $i',
  'This is a description for item number $i with some padding text to '
      'simulate real data',
  i * 1.5,
  'category_${i % 10}',
  '2026-04-0${(i % 9) + 1}T12:00:00Z',
];

String _ascii(int len, int row, int col) {
  final seed = 'r${row}c$col';
  final buf = StringBuffer(seed);
  var i = 0;
  while (buf.length < len) {
    buf.write(String.fromCharCode(0x61 + (i + row + col) % 26));
    i++;
  }
  return buf.toString().substring(0, len);
}

// ~3 bytes per CJK code point, so 12 chars is ~36 bytes — deliberately close to
// the mid ASCII lane's width so the two are comparable.
String _cjk(int chars, int row, int col) {
  final buf = StringBuffer();
  for (var i = 0; i < chars; i++) {
    buf.write(String.fromCharCode(0x4E00 + (row * 31 + col * 7 + i) % 0x2000));
  }
  return buf.toString();
}

final _lanes = <_Lane>[
  _Lane('text8-short', 8, 10000, (r, c) => _ascii(10, r, c)),
  _Lane('text8-mid', 8, 10000, (r, c) => _ascii(40, r, c)),
  _Lane('text4-long', 4, 2000, (r, c) => _ascii(400, r, c)),
  _Lane('text8-cjk', 8, 10000, (r, c) => _cjk(12, r, c)),
  // GUARD, worst case for accumulate-then-test: a long value whose only
  // multibyte character sits at byte 0. The native scan walks all ~400 bytes
  // before answering, where the Dart scan it replaced bailed at the first word
  // and went straight to utf8.decode. If scanning to the end ever costs more
  // than it saves, it shows here or nowhere.
  _Lane(
    'text4-long-early-nonascii',
    4,
    2000,
    (r, c) => 'é${_ascii(398, r, c)}',
  ),
  _Lane.explicit(
    'mixed6',
    10000,
    createSql: _standardCreate,
    insertSql: _standardInsert,
    row: _standardRow,
  ),
  _Lane('int8', 8, 10000, (r, c) => r * 31 + c, type: 'INTEGER'),
];

Future<void> main(List<String> args) async {
  var warmup = _defaultWarmup;
  var samples = _defaultSamples;
  String? only;
  for (final arg in args) {
    if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--samples=')) {
      samples = int.parse(arg.substring('--samples='.length));
    } else if (arg.startsWith('--lane=')) {
      only = arg.substring('--lane='.length);
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  print('=== select() rows-path TEXT decode focused harness ===');
  print('warmup=$warmup samples=$samples');
  for (final lane in _lanes) {
    if (only != null && lane.label != only) continue;
    await _runLane(lane, warmup: warmup, samples: samples);
  }
}

Future<void> _runLane(
  _Lane lane, {
  required int warmup,
  required int samples,
}) async {
  final temp = await Directory.systemTemp.createTemp('bench_text_decode_');
  try {
    final db = await resqlite.Database.open('${temp.path}/test.db');

    final String createSql;
    final String insertSql;
    final List<Object?> Function(int row) row;
    if (lane.createSql != null) {
      createSql = lane.createSql!;
      insertSql = lane.insertSql!;
      row = lane.row!;
    } else {
      final cols = [for (var c = 0; c < lane.columns; c++) 'c$c ${lane.type}'];
      createSql =
          'CREATE TABLE items(id INTEGER PRIMARY KEY, ${cols.join(', ')})';
      final names = [for (var c = 0; c < lane.columns; c++) 'c$c'].join(', ');
      final placeholders = List.filled(lane.columns, '?').join(', ');
      insertSql = 'INSERT INTO items($names) VALUES ($placeholders)';
      row = (r) => [for (var c = 0; c < lane.columns; c++) lane.cell!(r, c)];
    }
    await db.execute(createSql);

    const chunk = 500;
    for (var start = 0; start < lane.rows; start += chunk) {
      final end = start + chunk < lane.rows ? start + chunk : lane.rows;
      await db.executeBatch(insertSql, [
        for (var r = start; r < end; r++) row(r),
      ]);
    }

    const sql = 'SELECT * FROM items';
    for (var i = 0; i < warmup; i++) {
      await db.select(sql);
    }

    final values = <int>[];
    for (var i = 0; i < samples; i++) {
      final sw = Stopwatch()..start();
      final result = await db.select(sql);
      sw.stop();
      if (result.length != lane.rows) {
        throw StateError('lane ${lane.label} returned ${result.length} rows');
      }
      values.add(sw.elapsedMicroseconds);
    }
    await db.close();

    final sorted = [...values]..sort();
    print(
      'shape=${lane.label} '
      'median_us=${_percentile(sorted, 0.50)} '
      'p10_us=${_percentile(sorted, 0.10)} '
      'p90_us=${_percentile(sorted, 0.90)} '
      'samples_us=${values.join(',')}',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];
