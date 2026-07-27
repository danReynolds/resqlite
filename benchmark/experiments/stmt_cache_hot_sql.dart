// Focused workload for exp 207 — `stmt_cache_lookup_entry` hot-SQL fast
// path.
//
// The C-side per-connection statement cache (`STMT_CACHE_MAX = 32`) does a
// linear scan over every cached entry on every prepare. The post-match swap
// parks the matched entry at `entries[count - 1]`, so a workload that
// re-executes the same SQL repeatedly currently re-scans every other slot
// before re-finding it. Exp 207 adds a `last_lookup` pointer consulted
// before the linear scan; when the same SQL hits in a row, the scan is
// skipped entirely.
//
// The win is per-call FFI overhead inside `get_or_prepare_reader` /
// `get_or_prepare_writer`. It is invisible when the cache holds only the
// one SQL we are re-executing (`count == 1` → scan is already O(1)). It
// shows up only when the cache carries other cold entries that the scan
// has to step over before reaching the MRU entry. Exp 195's existing
// `select_bytes_repeated_calls.dart` exercises a single-SQL cache, so it
// is not the right denominator; this harness pre-fills the cache up to
// `STMT_CACHE_MAX` with cold prepared SQLs, then measures the hot SQL.
//
//   dart run benchmark/experiments/stmt_cache_hot_sql.dart
import 'dart:io';

import 'package:resqlite/resqlite.dart';

class _Shape {
  const _Shape(this.label, this.coldCacheFill, this.rows, this.cols);
  final String label;
  final int coldCacheFill;
  final int rows;
  final int cols;
}

const _shapes = <_Shape>[
  // Primary lane: cache full of unrelated SQLs, hot SQL on tiny rowsets
  // where per-call FFI prep overhead is a measurable fraction of wall.
  _Shape('cache=31 cold | 1 row × 8 cols', 31, 1, 8),
  _Shape('cache=31 cold | 1 row × 20 cols', 31, 1, 20),
  _Shape('cache=31 cold | 10 rows × 8 cols', 31, 10, 8),
  // Mid-pressure lane.
  _Shape('cache=15 cold | 1 row × 8 cols', 15, 1, 8),
  // Guard lanes: no cache pressure — the fast-path adds one wasted
  // compare relative to the original single-iteration scan, so these
  // should stay flat (or slightly faster) and never regress.
  _Shape('cache=0 cold | 1 row × 8 cols', 0, 1, 8),
  _Shape('cache=0 cold | 100 rows × 8 cols', 0, 100, 8),
];

const _callsPerSample = 1000;
const _samples = 11;

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp207-');
  final dbPath = '${tmp.path}/exp207.db';
  final db = await Database.open(dbPath);

  stdout.writeln(
    'stmt-cache hot-SQL fast path — '
    '$_callsPerSample calls/sample, $_samples samples\n',
  );
  stdout.writeln('| Shape | Median µs/call | Min | Max | Bytes |');
  stdout.writeln('|---|---|---|---|---|');

  for (final shape in _shapes) {
    await _setupShape(db, shape);
    final hotSql = _hotSql(shape);

    // Pre-fill the per-reader cache with unrelated cold SQLs so the
    // linear scan in `stmt_cache_lookup_entry` has to step over them.
    // Cold SQLs are sized to match the hot SQL's byte length so the
    // scan cannot short-circuit on `sql_len` and must actually memcmp
    // every cold entry — the worst case the fast-path is meant to skip.
    for (var i = 0; i < shape.coldCacheFill; i++) {
      await db.selectBytes(_coldSql(hotSql.length, i));
    }

    // Warm up: hot SQL preparation, json_buf capacity, page cache.
    for (var i = 0; i < 16; i++) {
      await db.selectBytes(hotSql);
    }
    final probe = (await db.selectBytes(hotSql)).bytes;

    final medians = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _callsPerSample; i++) {
        await db.selectBytes(hotSql);
      }
      sw.stop();
      medians.add(sw.elapsedMicroseconds / _callsPerSample);
    }
    medians.sort();
    final med = medians[medians.length ~/ 2];
    stdout.writeln(
      '| ${shape.label} '
      '| ${med.toStringAsFixed(3)} '
      '| ${medians.first.toStringAsFixed(3)} '
      '| ${medians.last.toStringAsFixed(3)} '
      '| ${probe.length} |',
    );
    await db.execute('DROP TABLE t');
  }

  await db.close();
  await tmp.delete(recursive: true);
}

Future<void> _setupShape(Database db, _Shape shape) async {
  final cols = StringBuffer();
  for (var i = 0; i < shape.cols; i++) {
    if (i > 0) cols.write(', ');
    cols.write('c$i INTEGER');
  }
  await db.execute('CREATE TABLE t($cols)');

  final valueLists = <List<Object?>>[];
  for (var r = 0; r < shape.rows; r++) {
    final row = <Object?>[];
    for (var i = 0; i < shape.cols; i++) {
      row.add(r * 1000 + i);
    }
    valueLists.add(row);
  }

  final placeholders = List.filled(shape.cols, '?').join(', ');
  await db.executeBatch('INSERT INTO t VALUES ($placeholders)', valueLists);
}

String _hotSql(_Shape shape) {
  final cols = StringBuffer();
  for (var i = 0; i < shape.cols; i++) {
    if (i > 0) cols.write(', ');
    cols.write('c$i');
  }
  return 'SELECT $cols FROM t';
}

// Distinct cold SQLs padded to the same byte length as the hot SQL, so
// the linear scan cannot short-circuit on `sql_len` and must actually
// memcmp every cold entry before reaching the hot one. The numeric
// literal differs between seeds, so SQLite treats them as distinct
// cache entries; the literal cannot match any real row's c0.
String _coldSql(int hotLen, int seed) {
  const prefix = 'SELECT c0 AS x FROM t WHERE c0 = ';
  final padTo = hotLen - prefix.length;
  if (padTo <= 0) {
    throw StateError('hotLen $hotLen too small for cold SQL template');
  }
  final literal = seed.toString().padLeft(padTo, '0');
  return '$prefix$literal';
}
