// Focused workload for exp 248 — `stmt_cache_lookup_entry` move-to-back swap.
//
// NOTE: exp 267 raised `STMT_CACHE_MAX` from 32 to 128 and replaced the
// eviction memmove with in-place reclaim. The description below is the
// code this harness was written against; re-run it against current main
// only with that in mind.
//
// The C-side per-connection statement cache (`STMT_CACHE_MAX = 32`) keeps its
// MRU entry at `entries[count - 1]`. Before exp 248, a lookup that matched any
// other slot promoted it by swapping structs:
//
//     resqlite_cached_stmt tmp = c->entries[i];
//     c->entries[i] = c->entries[c->count - 1];
//     c->entries[c->count - 1] = tmp;
//
// `resqlite_cached_stmt` is ~1.6 KB (`read_tables[64]` = 512 B plus
// `dep_columns[64]` = 1 KB, both fixed-size arrays), so each promotion moves
// ~4.9 KB through three full-struct copies.
//
// Exp 207 and exp 071 both measured the *scan* half of this function on a
// single repeated SQL. That shape never pays the swap: the hot entry is
// already at the MRU tail, so `i == count - 1` and the promotion is skipped.
// The swap only fires when the workload alternates between two or more hot
// statements — every lookup then finds its entry away from the tail and pays
// a full promotion. That is the ordinary shape for several active streams, or
// DML touching more than one table.
//
// This harness measures that gap directly: `distinct` hot SQLs executed
// round-robin on one reader connection. `find_idle_reader` returns the lowest
// idle index, so sequential awaits stay pinned to reader 0 and share a single
// statement cache.
//
//   dart run benchmark/experiments/stmt_cache_interleaved.dart

import 'dart:io';

import 'package:resqlite/resqlite.dart';

class _Shape {
  const _Shape(this.label, this.distinct, this.coldCacheFill, this.rows);

  final String label;

  /// How many distinct SQLs are cycled round-robin. `1` is the exp 207 shape
  /// (entry already at MRU, swap never fires) and acts as the control.
  final int distinct;

  /// Extra cold entries parked in the cache. Raising this lengthens the
  /// promotion distance, so more of the array is copied per swap.
  final int coldCacheFill;

  final int rows;
}

const _shapes = <_Shape>[
  // Control: the exp 207 shape. One hot SQL sits at the MRU tail, so the
  // baseline never swaps and this lane must stay flat.
  _Shape('1 SQL (control, no swap) | cache=8', 1, 8, 1),
  _Shape('1 SQL (control, no swap) | cache=31', 1, 31, 1),
  // Primary lanes: alternating statements pay a promotion on every lookup.
  _Shape('2 SQL round-robin | cache=8', 2, 8, 1),
  _Shape('2 SQL round-robin | cache=31', 2, 31, 1),
  _Shape('4 SQL round-robin | cache=31', 4, 31, 1),
  _Shape('8 SQL round-robin | cache=31', 8, 31, 1),
  // Amortisation guard: the same promotion cost against a larger rowset, where
  // per-call decode dominates and the swap should fade into the noise.
  _Shape('4 SQL round-robin | cache=31 | 100 rows', 4, 31, 100),
];

const _callsPerSample = 1000;
const _samples = 11;

Future<void> main() async {
  final tmp = await Directory.systemTemp.createTemp('resqlite-exp248-');
  final dbPath = '${tmp.path}/exp248.db';
  final db = await Database.open(dbPath);

  stdout.writeln(
    'stmt-cache interleaved-statement promotion — '
    '$_callsPerSample calls/sample, $_samples samples\n',
  );
  stdout.writeln('| Shape | Median µs/call | Min | Max |');
  stdout.writeln('|---|---|---|---|');

  for (final shape in _shapes) {
    await _setupShape(db, shape);

    final hotSqls = [
      for (var i = 0; i < shape.distinct; i++) _hotSql(i, shape.rows),
    ];

    // Park cold entries first so the hot SQLs are promoted past them. Cold
    // SQLs match the hot SQLs' byte length, so the scan cannot short-circuit
    // on `sql_len` before reaching them.
    for (var i = 0; i < shape.coldCacheFill; i++) {
      await db.selectBytes(_coldSql(hotSqls.first.length, i));
    }

    for (var i = 0; i < 16; i++) {
      for (final sql in hotSqls) {
        await db.selectBytes(sql);
      }
    }

    final perCall = <double>[];
    for (var s = 0; s < _samples; s++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < _callsPerSample; i++) {
        await db.selectBytes(hotSqls[i % hotSqls.length]);
      }
      sw.stop();
      perCall.add(sw.elapsedMicroseconds / _callsPerSample);
    }
    perCall.sort();
    stdout.writeln(
      '| ${shape.label} '
      '| ${perCall[perCall.length ~/ 2].toStringAsFixed(3)} '
      '| ${perCall.first.toStringAsFixed(3)} '
      '| ${perCall.last.toStringAsFixed(3)} |',
    );

    await db.execute('DROP TABLE t');
  }

  await db.close();
  await tmp.delete(recursive: true);
}

Future<void> _setupShape(Database db, _Shape shape) async {
  await db.execute(
    'CREATE TABLE t(c0 INTEGER, c1 INTEGER, c2 INTEGER, c3 INTEGER)',
  );
  await db.executeBatch('INSERT INTO t VALUES (?, ?, ?, ?)', [
    for (var r = 0; r < shape.rows; r++) [r, r + 1, r + 2, r + 3],
  ]);
}

// Distinct hot SQLs of identical byte length. Each selects the same rows —
// only the aliased column name differs — so every lane decodes an identical
// payload and the measured delta is cache bookkeeping, not query work.
String _hotSql(int seed, int rows) {
  final alias = 'h${seed.toString().padLeft(3, '0')}';
  return 'SELECT c0 AS $alias, c1, c2, c3 FROM t';
}

// Cold filler padded to the hot SQL's byte length so the linear scan must
// memcmp each one before reaching a hot entry.
String _coldSql(int hotLen, int seed) {
  const prefix = 'SELECT c0 AS x FROM t WHERE c0 = ';
  final padTo = hotLen - prefix.length;
  if (padTo <= 0) {
    throw StateError('hotLen $hotLen too small for cold SQL template');
  }
  return '$prefix${seed.toString().padLeft(padTo, '0')}';
}
