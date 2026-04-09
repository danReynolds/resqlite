// Probe SQLite connection-level status counters across resqlite's writer and
// idle readers to see whether page-cache or lookaside tuning is justified.

import 'dart:io';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart' as native;

import '../shared/seeder.dart';

const _dbStatusLookasideUsed = 0;
const _dbStatusCacheUsed = 1;
const _dbStatusLookasideHit = 4;
const _dbStatusLookasideMissSize = 5;
const _dbStatusLookasideMissFull = 6;
const _dbStatusCacheHit = 7;
const _dbStatusCacheMiss = 8;
const _dbStatusCacheSpill = 12;

typedef _Snapshot = Map<String, ({int current, int highwater})>;

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_db_status_');
  final dbPath = '${dir.path}/probe.db';
  final db = await Database.open(dbPath);
  await seedResqlite(db, 20000);
  await Future<void>.delayed(const Duration(milliseconds: 100));

  print('=== resqlite db_status probe ===\n');
  print('This aggregates sqlite3_db_status() across the writer and idle readers.');
  print('High cache hit rates and zero spill usually mean page-cache tuning is not urgent.\n');

  await _runWorkload(
    db,
    'Point lookups',
    2000,
    (i) => db.select('SELECT * FROM items WHERE id = ?', [i % 20000]),
  );

  await _runWorkload(
    db,
    'Parameterized page reads',
    800,
    (i) => db.select(
      'SELECT * FROM items WHERE category = ? ORDER BY id DESC LIMIT 20',
      ['category_${i % 10}'],
    ),
  );

  await _runWorkload(
    db,
    'Large result reads',
    80,
    (_) => db.select('SELECT * FROM items LIMIT 5000'),
  );

  await _runWriteBurst(db, 1500);

  await db.close();
  await dir.delete(recursive: true);
  exit(0);
}

Future<void> _runWorkload(
  Database db,
  String name,
  int iterations,
  Future<List<Map<String, Object?>>> Function(int i) query,
) async {
  final before = _snapshot(db);
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await query(i);
  }
  sw.stop();
  final after = _snapshot(db);
  _printWorkload(name, sw.elapsedMilliseconds, after, before);
}

Future<void> _runWriteBurst(Database db, int writes) async {
  final before = _snapshot(db);
  final sw = Stopwatch()..start();
  for (var i = 0; i < writes; i++) {
    await db.execute(standardInsertSql, standardRow(20000 + i));
  }
  sw.stop();
  final after = _snapshot(db);
  _printWorkload('Write burst', sw.elapsedMilliseconds, after, before);
}

_Snapshot _snapshot(Database db) => {
      'cache_used': native.getDbStatusTotal(db.handle, _dbStatusCacheUsed),
      'cache_hit': native.getDbStatusTotal(db.handle, _dbStatusCacheHit),
      'cache_miss': native.getDbStatusTotal(db.handle, _dbStatusCacheMiss),
      'cache_spill': native.getDbStatusTotal(db.handle, _dbStatusCacheSpill),
      'lookaside_used': native.getDbStatusTotal(db.handle, _dbStatusLookasideUsed),
      'lookaside_hit': native.getDbStatusTotal(db.handle, _dbStatusLookasideHit),
      'lookaside_miss_size': native.getDbStatusTotal(
        db.handle,
        _dbStatusLookasideMissSize,
      ),
      'lookaside_miss_full': native.getDbStatusTotal(
        db.handle,
        _dbStatusLookasideMissFull,
      ),
    };

void _printWorkload(
  String name,
  int elapsedMs,
  _Snapshot after,
  _Snapshot before,
) {
  final cacheHits = _delta(after, before, 'cache_hit');
  final cacheMisses = _delta(after, before, 'cache_miss');
  final hitRate = cacheHits + cacheMisses == 0
      ? 0.0
      : cacheHits / (cacheHits + cacheMisses) * 100;

  print('=== $name ===');
  print('Elapsed: ${elapsedMs}ms');
  print(
    'Cache: ${_formatBytes(after['cache_used']!.current)} current, '
    '${_formatBytes(after['cache_used']!.highwater)} highwater, '
    '${hitRate.toStringAsFixed(1)}% hit rate '
    '(${cacheHits.toString()} hits / ${cacheMisses.toString()} misses)',
  );
  print('Cache spill delta: ${_delta(after, before, 'cache_spill')}');
  print(
    'Lookaside: ${after['lookaside_used']!.current} current, '
    '${after['lookaside_used']!.highwater} highwater, '
    '${_delta(after, before, 'lookaside_hit')} hits, '
    '${_delta(after, before, 'lookaside_miss_size')} miss-size, '
    '${_delta(after, before, 'lookaside_miss_full')} miss-full',
  );
  print('');
}

int _delta(_Snapshot after, _Snapshot before, String key) =>
    after[key]!.current - before[key]!.current;

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}
