// ignore_for_file: avoid_print
//
// Focused memory decomposition for [EXP-263]: where does a `select()`'s
// resident memory actually go?
//
// [EXP-261](../../experiments/261-focused-memory-guard.md) measured the repo's
// canonical 6-column product row at 10k rows peaking at ~95 MB while the table
// holds roughly 1.5 MB of data, and flagged the ~60x ratio as never decomposed.
// Its own instrument cannot decompose it — process RSS cannot resolve anything
// below a doubling, and an AOT binary has no VM service to ask for heap
// composition.
//
// What process RSS *can* do is separate fixed cost from marginal cost, if the
// only thing that varies is the amount read. Every lane here seeds the same
// 20,000-row table and differs only in how many rows the timed statement
// returns, so a fit of peak RSS against row count gives the per-row marginal
// directly, and the intercept is everything that does not scale with the read
// (process, VM, connection, page cache, seeding).
//
// Three modes over the same rows isolate the parts:
//
//   select  — `select()`, the full Dart object graph (flat values list plus
//             the lazy `Row` facade over it).
//   bytes   — `selectBytes()`, the same rows serialized in C with no Dart
//             object graph at all. The difference between this and `select`
//             is what the Dart representation costs.
//   id      — `select()` of the INTEGER primary key alone. Smis live inline in
//             the values list, so this is structure without payload.
//
// The `select` sweep crosses `sacrificeSlotThreshold` (32768 structural slots,
// so 5,461 rows at 6 columns) between its 5,000 and 7,500 row lanes. Results
// above it return via `Isolate.exit` and end the worker; results below take a
// `SendPort`. Lanes are tagged with which path they took, because a
// discontinuity there is a transport artifact rather than a representation one
// ([EXP-258](../../experiments/258-columnar-result-store.md)).
//
// Per [EXP-261](../../experiments/261-focused-memory-guard.md): the reported
// figure is `maxRss`, and it is only per-lane clean when the lane had the
// process to itself. Run one lane per process with `--lane=`.
//
// Usage:
//   dart run benchmark/experiments/select_memory_decomposition.dart \
//     [--reads=21] [--lane=select-5000]
import 'dart:io';

import 'package:resqlite/resqlite.dart' as resqlite;

import '../shared/memory_probe.dart';

/// Rows seeded into every lane's table, held constant so the only variable is
/// how many of them the timed statement returns.
const _seedRows = 20000;

const _defaultReads = 21;
const _defaultWarmup = 5;

/// `sacrificeSlotThreshold` in `lib/src/reader/read_worker.dart`.
const _sacrificeSlots = 32 * 1024;

const _rowCounts = [1000, 2500, 5000, 7500, 10000, 20000];

enum _Mode {
  select('select', 6),
  bytes('bytes', 6),
  id('id', 1),

  /// Open the database and read nothing. Isolates the fixed floor — VM,
  /// native library, SQLite connections and the reader/writer isolate pool —
  /// from anything the result contributes. Ignores the row count.
  open('open', 0);

  const _Mode(this.label, this.columns);
  final String label;

  /// Structural slots a row of this mode occupies, for the sacrifice estimate.
  final int columns;
}

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

/// Bytes of actual cell data in one seeded row, so the report can state the
/// payload the marginal cost is measured against rather than estimating it.
int _payloadBytes(int i) {
  final row = _standardRow(i);
  var bytes = 8; // id, INTEGER
  for (final cell in row) {
    bytes += cell is String ? cell.length : 8;
  }
  return bytes;
}

Future<void> main(List<String> args) async {
  var reads = _defaultReads;
  var warmup = _defaultWarmup;
  String? only;
  for (final arg in args) {
    if (arg.startsWith('--reads=')) {
      reads = int.parse(arg.substring('--reads='.length));
    } else if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
    } else if (arg.startsWith('--lane=')) {
      only = arg.substring('--lane='.length);
    } else {
      throw ArgumentError('unknown argument: $arg');
    }
  }

  print('=== select() memory decomposition ===');
  print('seed_rows=$_seedRows warmup=$warmup reads_per_lane=$reads');
  if (warmup == 0 && reads == 1) {
    print(
      'mode=single-live-result — one read, held alive across the sample, so '
      'the marginal is one result rather than accumulated retention',
    );
  }
  final avgPayload =
      List.generate(100, _payloadBytes).reduce((a, b) => a + b) / 100;
  print('avg_payload_bytes_per_row=${avgPayload.toStringAsFixed(1)}');

  for (final mode in _Mode.values) {
    for (final rows in mode == _Mode.open ? const [0] : _rowCounts) {
      final label = mode == _Mode.open ? 'open' : '${mode.label}-$rows';
      if (only != null && label != only) continue;
      await _runLane(
        mode,
        rows,
        reads: reads,
        warmup: warmup,
        laneIsolated: only != null,
      );
    }
  }
}

Future<void> _runLane(
  _Mode mode,
  int rows, {
  required int reads,
  required int warmup,
  required bool laneIsolated,
}) async {
  final temp = await Directory.systemTemp.createTemp('bench_memdecomp_');
  try {
    final db = await resqlite.Database.open('${temp.path}/test.db');
    await db.execute(_standardCreate);

    if (mode == _Mode.open) {
      // One trivial statement so the reader pool has actually spawned; the
      // pool is lazy and a floor measured before it exists is not the floor a
      // reading workload pays.
      await db.select('SELECT id FROM items LIMIT 1');
      final probe = MemoryProbe.start();
      probe.sample();
      final reading = probe.finish(laneIsolated: laneIsolated);
      await db.close();
      print(
        'shape=open mode=open rows=0 slots=0 sacrifices=false '
        '${reading.format()}',
      );
      return;
    }

    const chunk = 500;
    for (var start = 0; start < _seedRows; start += chunk) {
      final end = start + chunk < _seedRows ? start + chunk : _seedRows;
      await db.executeBatch(_standardInsert, [
        for (var r = start; r < end; r++) _standardRow(r),
      ]);
    }

    final sql = switch (mode) {
      _Mode.select => 'SELECT * FROM items ORDER BY id LIMIT ?',
      _Mode.bytes => 'SELECT * FROM items ORDER BY id LIMIT ?',
      _Mode.id => 'SELECT id FROM items ORDER BY id LIMIT ?',
      // Unreachable: the open lane returns above, before any statement.
      _Mode.open => throw StateError('open lane has no statement'),
    };
    final params = [rows];

    // The result is held in `live` across the sample. Without that the VM may
    // reclaim it before RSS is read, and the lane would measure a result that
    // no longer exists.
    Object? live;
    Future<int> read() async {
      if (mode == _Mode.bytes) {
        final r = await db.selectBytes(sql, params);
        live = r;
        return r.rowCount;
      }
      final r = await db.select(sql, params);
      live = r;
      // Read a cell from every row so the lazy `Row` facade actually
      // materializes. The cell *values* are built by `decodeQuery` either way
      // — what this adds is the per-row `Row` object a consumer holds.
      if (mode == _Mode.select) {
        for (final row in r) {
          if (row['name'] == null) throw StateError('null name');
        }
      }
      return r.length;
    }

    for (var i = 0; i < warmup; i++) {
      if (await read() != rows) {
        throw StateError('lane ${mode.label}-$rows returned the wrong count');
      }
    }
    live = null;

    final probe = MemoryProbe.start();
    for (var i = 0; i < reads; i++) {
      if (await read() != rows) {
        throw StateError('lane ${mode.label}-$rows returned the wrong count');
      }
      probe.sample();
    }
    if (live == null) throw StateError('result was not retained');
    final reading = probe.finish(laneIsolated: laneIsolated);
    await db.close();

    // `selectBytes` never sacrifices — the result is native bytes, so
    // `Isolate.exit` would need a copy first and saves nothing.
    final slots = rows * mode.columns;
    final sacrifices = mode != _Mode.bytes && slots > _sacrificeSlots;

    print(
      'shape=${mode.label}-$rows '
      'mode=${mode.label} '
      'rows=$rows '
      'slots=$slots '
      'sacrifices=$sacrifices '
      '${reading.format()}',
    );
  } finally {
    await temp.delete(recursive: true);
  }
}
