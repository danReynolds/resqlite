// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:resqlite/resqlite.dart' as resqlite;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_async/sqlite_async.dart' as sqlite_async;

import '../shared/seeder.dart';
import '../shared/stats.dart';

/// Memory benchmark suite.
///
/// Measures process RSS (resident set size) delta around a workload. Uses
/// only `ProcessInfo.currentRss` / `maxRss` from `dart:io` — no VM service
/// dependency. This means the numbers are a **lower bound** on the real
/// allocation volume: the VM retains heap pages after GC, so a small
/// workload may show zero delta even though it allocated and freed
/// objects. A visible delta reduction here means the real allocation win
/// is at least that large.
///
/// Exists because experiments like [055 columnar typed arrays]
/// (75% memory win, 10000x fewer GC objects) are invisible to time-based
/// benchmarks. See plan at `.claude/plans/luminous-doodling-boole.md`.
Future<String> runMemoryBenchmark() async {
  final markdown = StringBuffer();
  markdown.writeln('## Memory');
  markdown.writeln('');
  markdown.writeln(
    'Process RSS delta around each workload. Values are a **lower bound** '
    'on real allocation volume because the Dart VM retains heap pages '
    'after GC. A visible reduction here implies the underlying '
    'allocation win is at least that large.',
  );
  markdown.writeln('');

  await _workloadMapsSelect(markdown);
  await _workloadBytesSelect(markdown);
  await _workloadBatchInsert(markdown);
  await _workloadStreamingFanout(markdown);

  return markdown.toString();
}

// ---------------------------------------------------------------------------
// Measurement helpers
// ---------------------------------------------------------------------------

const _outerRepeats = 15;
const _innerIterations = 10;
const _warmup = 3;
const _churnSize = 10000;
const _bootstrapSeed = 0xDEADBEEF;

class _MemStats {
  _MemStats(this.rssDeltaMB);
  final List<double> rssDeltaMB; // one sample per outer repeat
}

/// Pre-measurement churn loop. Allocates + drops [_churnSize] small maps
/// to stabilize the heap before baseline capture. Without this, heap pages
/// grow during the first warmup and contaminate the delta.
void _churnHeap() {
  final junk = <Map<String, Object?>>[];
  for (var i = 0; i < _churnSize; i++) {
    junk.add({'a': i, 'b': 'x$i', 'c': i * 1.5});
  }
  junk.clear();
}

double _rssMB() => ProcessInfo.currentRss / (1024 * 1024);

/// Runs [body] [_innerIterations] times after [_warmup] warmups and a
/// heap-churn pass. Returns the RSS delta from pre-baseline to post
/// (in MB).
Future<double> _measure(Future<void> Function() body) async {
  _churnHeap();
  for (var i = 0; i < _warmup; i++) {
    await body();
  }
  _churnHeap();
  final baseline = _rssMB();
  for (var i = 0; i < _innerIterations; i++) {
    await body();
  }
  final post = _rssMB();
  final delta = post - baseline;
  return delta < 0 ? 0.0 : delta;
}

Future<_MemStats> _repeatedMeasure(Future<void> Function() body) async {
  final deltas = <double>[];
  for (var r = 0; r < _outerRepeats; r++) {
    deltas.add(await _measure(body));
  }
  return _MemStats(deltas);
}

String _memRow(String label, _MemStats s) {
  final sorted = List<double>.from(s.rssDeltaMB)..sort();
  final med = medianOfSorted(sorted);
  final p90 = sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
  final ci = bootstrapMedianCI(s.rssDeltaMB, seed: _bootstrapSeed);
  // MDE in absolute MB (CI half-width). Reporting as MB rather than %
  // is honest because memory deltas are often 0 MB — a % MDE would
  // divide by zero or by a tiny number and become unreadable.
  final mdeMB = (ci.high - ci.low) / 2;
  return '| $label '
      '| ${med.toStringAsFixed(2)} '
      '| ${p90.toStringAsFixed(2)} '
      '| ${ci.low.toStringAsFixed(2)}..${ci.high.toStringAsFixed(2)} '
      '| ±${mdeMB.toStringAsFixed(2)} |';
}

void _writeSubsection(
  StringBuffer md,
  String title,
  Map<String, _MemStats> byLib,
) {
  md.writeln('### $title');
  md.writeln('');
  md.writeln(
    '| Library | RSS delta med (MB) | RSS delta p90 (MB) | 95% CI (MB) | MDE (MB) |',
  );
  md.writeln('|---|---|---|---|---|');
  for (final entry in byLib.entries) {
    md.writeln(_memRow(entry.key, entry.value));
  }
  md.writeln('');
}

// ---------------------------------------------------------------------------
// Workloads
// ---------------------------------------------------------------------------

const _largeRowCount = 10000;

Future<void> _workloadMapsSelect(StringBuffer md) async {
  final dir = await Directory.systemTemp.createTemp('bench_mem_maps_');
  try {
    final resqliteDb = await resqlite.Database.open('${dir.path}/resqlite.db');
    await seedResqlite(resqliteDb, _largeRowCount);
    final sqlite3Db = sqlite3.sqlite3.open('${dir.path}/sqlite3.db');
    sqlite3Db.execute('PRAGMA journal_mode = WAL');
    seedSqlite3(sqlite3Db, _largeRowCount);
    final asyncDb = sqlite_async.SqliteDatabase(path: '${dir.path}/async.db');
    await asyncDb.initialize();
    await seedSqliteAsync(asyncDb, _largeRowCount);

    final byLib = <String, _MemStats>{};

    byLib['resqlite select()'] = await _repeatedMeasure(() async {
      final r = await resqliteDb.select(standardSelectSql);
      _touchRows(r);
    });

    byLib['sqlite3 select()'] = await _repeatedMeasure(() async {
      final stmt = sqlite3Db.prepare(standardSelectSql);
      final rows = stmt.select();
      _touchSqlite3Rows(rows);
      stmt.close();
    });

    byLib['sqlite_async getAll()'] = await _repeatedMeasure(() async {
      final r = await asyncDb.getAll(standardSelectSql);
      _touchSqlite3Rows(r);
    });

    await resqliteDb.close();
    sqlite3Db.close();
    await asyncDb.close();

    _writeSubsection(md, 'Select 10k rows → Maps', byLib);
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<void> _workloadBytesSelect(StringBuffer md) async {
  final dir = await Directory.systemTemp.createTemp('bench_mem_bytes_');
  try {
    final resqliteDb = await resqlite.Database.open('${dir.path}/resqlite.db');
    await seedResqlite(resqliteDb, _largeRowCount);
    final sqlite3Db = sqlite3.sqlite3.open('${dir.path}/sqlite3.db');
    sqlite3Db.execute('PRAGMA journal_mode = WAL');
    seedSqlite3(sqlite3Db, _largeRowCount);
    final asyncDb = sqlite_async.SqliteDatabase(path: '${dir.path}/async.db');
    await asyncDb.initialize();
    await seedSqliteAsync(asyncDb, _largeRowCount);

    final byLib = <String, _MemStats>{};

    byLib['resqlite selectBytes()'] = await _repeatedMeasure(() async {
      final b = await resqliteDb.selectBytes(standardSelectSql);
      _touchBytes(b);
    });

    byLib['sqlite3 + jsonEncode'] = await _repeatedMeasure(() async {
      final stmt = sqlite3Db.prepare(standardSelectSql);
      final rows = stmt.select();
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(rows)));
      _touchBytes(bytes);
      stmt.close();
    });

    byLib['sqlite_async + jsonEncode'] = await _repeatedMeasure(() async {
      final r = await asyncDb.getAll(standardSelectSql);
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(r)));
      _touchBytes(bytes);
    });

    await resqliteDb.close();
    sqlite3Db.close();
    await asyncDb.close();

    _writeSubsection(md, 'Select 10k rows → JSON Bytes', byLib);
  } finally {
    await dir.delete(recursive: true);
  }
}

Future<void> _workloadBatchInsert(StringBuffer md) async {
  final byLib = <String, _MemStats>{};

  {
    final dir = await Directory.systemTemp.createTemp('bench_mem_ins_r_');
    try {
      byLib['resqlite executeBatch()'] = await _repeatedMeasure(() async {
        final db =
            await resqlite.Database.open('${dir.path}/resqlite_${_uid()}.db');
        await db.execute(standardCreateSql);
        await db.executeBatch(standardInsertSql, [
          for (var i = 0; i < _largeRowCount; i++) standardRow(i),
        ]);
        await db.close();
      });
    } finally {
      await dir.delete(recursive: true);
    }
  }

  {
    final dir = await Directory.systemTemp.createTemp('bench_mem_ins_s3_');
    try {
      byLib['sqlite3 prepared stmt'] = await _repeatedMeasure(() async {
        final db = sqlite3.sqlite3.open('${dir.path}/sqlite3_${_uid()}.db');
        db.execute('PRAGMA journal_mode = WAL');
        db.execute(standardCreateSql);
        final stmt = db.prepare(standardInsertSql);
        db.execute('BEGIN');
        for (var i = 0; i < _largeRowCount; i++) {
          stmt.execute(standardRow(i));
        }
        db.execute('COMMIT');
        stmt.close();
        db.close();
      });
    } finally {
      await dir.delete(recursive: true);
    }
  }

  {
    final dir = await Directory.systemTemp.createTemp('bench_mem_ins_a_');
    try {
      byLib['sqlite_async executeBatch()'] = await _repeatedMeasure(() async {
        final db = sqlite_async.SqliteDatabase(
          path: '${dir.path}/async_${_uid()}.db',
        );
        await db.initialize();
        await db.execute(standardCreateSql);
        await db.executeBatch(standardInsertSql, [
          for (var i = 0; i < _largeRowCount; i++) standardRow(i),
        ]);
        await db.close();
      });
    } finally {
      await dir.delete(recursive: true);
    }
  }

  _writeSubsection(md, 'Batch insert 10k rows', byLib);
}

Future<void> _workloadStreamingFanout(StringBuffer md) async {
  final dir = await Directory.systemTemp.createTemp('bench_mem_stream_');
  try {
    final resqliteDb = await resqlite.Database.open('${dir.path}/resqlite.db');
    await resqliteDb.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)',
    );
    await resqliteDb.executeBatch(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      [for (var i = 0; i < 100; i++) ['item_$i', i]],
    );

    final asyncDb = sqlite_async.SqliteDatabase(path: '${dir.path}/async.db');
    await asyncDb.initialize();
    await asyncDb.execute(
      'CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value INTEGER NOT NULL)',
    );
    await asyncDb.executeBatch(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      [for (var i = 0; i < 100; i++) ['item_$i', i]],
    );

    final byLib = <String, _MemStats>{};

    byLib['resqlite stream()'] = await _repeatedMeasure(() async {
      await _streamingFanoutResqlite(resqliteDb, streams: 10, writes: 100);
    });

    byLib['sqlite_async watch()'] = await _repeatedMeasure(() async {
      await _streamingFanoutAsync(asyncDb, streams: 10, writes: 100);
    });

    await resqliteDb.close();
    await asyncDb.close();

    _writeSubsection(md, 'Streaming fan-out (10 streams × 100 writes)', byLib);
  } finally {
    await dir.delete(recursive: true);
  }
}

// ---------------------------------------------------------------------------
// Workload internals
// ---------------------------------------------------------------------------

Future<void> _streamingFanoutResqlite(
  resqlite.Database db, {
  required int streams,
  required int writes,
}) async {
  final subs = <StreamSubscription<List<Map<String, Object?>>>>[];
  final counters = List<int>.filled(streams, 0);

  for (var i = 0; i < streams; i++) {
    final idx = i;
    subs.add(
      db.stream('SELECT COUNT(*) as cnt FROM items').listen((_) {
        counters[idx]++;
      }),
    );
  }

  // Let all streams emit their initial value before issuing writes.
  await Future<void>.delayed(const Duration(milliseconds: 5));

  var counter = 10000;
  for (var i = 0; i < writes; i++) {
    await db.execute(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      ['mem_$counter', counter],
    );
    counter++;
  }

  // Wait briefly for trailing re-emits, then cancel.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  for (final sub in subs) {
    await sub.cancel();
  }
}

Future<void> _streamingFanoutAsync(
  sqlite_async.SqliteDatabase db, {
  required int streams,
  required int writes,
}) async {
  final subs = <StreamSubscription<Object?>>[];
  final counters = List<int>.filled(streams, 0);

  for (var i = 0; i < streams; i++) {
    final idx = i;
    subs.add(
      db
          .watch(
            'SELECT COUNT(*) as cnt FROM items',
            throttle: Duration.zero,
          )
          .listen((_) {
        counters[idx]++;
      }),
    );
  }

  await Future<void>.delayed(const Duration(milliseconds: 5));

  var counter = 10000;
  for (var i = 0; i < writes; i++) {
    await db.execute(
      'INSERT INTO items(name, value) VALUES (?, ?)',
      ['mem_$counter', counter],
    );
    counter++;
  }

  await Future<void>.delayed(const Duration(milliseconds: 10));
  for (final sub in subs) {
    await sub.cancel();
  }
}

void _touchRows(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

void _touchSqlite3Rows(Iterable<Map<String, dynamic>> rows) {
  for (final row in rows) {
    for (final key in row.keys) {
      row[key];
    }
  }
}

int _touchBytes(Uint8List bytes) {
  // Force a walk through the buffer so the VM doesn't elide the decode.
  var s = 0;
  final n = bytes.length;
  for (var i = 0; i < n; i += 64) {
    s ^= bytes[i];
  }
  return s;
}

int _uidCounter = 0;
String _uid() => '${DateTime.now().microsecondsSinceEpoch}_${_uidCounter++}';

// Allow running standalone.
Future<void> main() async {
  final md = await runMemoryBenchmark();
  print(md);
}
