// ignore_for_file: avoid_print

/// resqlite-only SQLite internal diagnostics.
///
/// Captures stable `Database.diagnostics()` snapshots after three
/// representative workload shapes:
///
///   1. Warm read working set — page-cache-oriented steady state after a
///      seeded DB, reader warmup, and hot point-lookups.
///   2. Statement cache footprint — distinct SELECT texts to populate the
///      per-connection statement caches.
///   3. WAL after write burst — WAL growth and connection memory after a
///      batched insert burst.
///   4. JSON buffer reclaim — a one-off large `selectBytes` burst followed
///      by small byte reads, guarding exp 183's high-threshold shrink.
///
/// Values are snapshots of the writer plus idle readers in this
/// resqlite connection pool only. They are not process-global SQLite
/// totals. This section exists so internal SQLite counters trend in the
/// benchmark markdown/history alongside RSS and timing data.
library;

import 'dart:io';

import 'package:resqlite/resqlite.dart';

import '../shared/seeder.dart';

const int _seedRowCount = 20000;
const int _pointLookups = 2000;
const int _distinctStmtCount = 48;
const int _writeBurstRows = 1000;
const int _seedChunkSize = 1000;
const int _snapshotRetries = 10;
const int _jsonBufSmallRows = 50;
const int _jsonBufSmallBodyLength = 60;
const int _jsonBufLargeRows = 512;
const int _jsonBufLargeBodyLength = 4000;
const int _jsonBufLargeBurstReads = 8;
const int _jsonBufSettleReads = 64;
const double _jsonBufMaxAfterSettleKiB = 512.0;

Future<String> runSqliteDiagnosticsBenchmark() async {
  final md = StringBuffer()
    ..writeln('## SQLite Diagnostics')
    ..writeln()
    ..writeln(
      'resqlite-only internal SQLite counters captured via '
      '`Database.diagnostics()` after representative workloads. Values '
      'reflect the writer plus idle readers in this connection pool; '
      'they are not process-global SQLite totals.',
    )
    ..writeln();

  final warmRead = await _withDb('bench_diag_read_', (db) async {
    await _seedItems(db, _seedRowCount);
    await _warmReaders(db);
    for (var i = 0; i < _pointLookups; i++) {
      await db.select('SELECT * FROM items WHERE id = ?', [
        i % _seedRowCount + 1,
      ]);
    }
    return _snapshot(db);
  });

  final stmtCache = await _withDb('bench_diag_stmt_', (db) async {
    await _seedItems(db, _seedRowCount);
    await _warmReaders(db);
    for (var i = 0; i < _distinctStmtCount; i++) {
      await db.select('SELECT * FROM items WHERE id = ? /* diag_stmt_$i */', [
        i % _seedRowCount + 1,
      ]);
    }
    return _snapshot(db);
  });

  final walBurst = await _withDb('bench_diag_wal_', (db) async {
    await _seedWriteBurst(db, _writeBurstRows);
    await _warmReaders(db);
    return _snapshot(db);
  });

  final jsonBufReclaim = await _withDb('bench_diag_jsonbuf_', (db) async {
    await _seedJsonBufWorkload(db);
    await _exerciseJsonBufReclaim(db);
    final reading = await _snapshot(db);
    if (reading.jsonBufKiB > _jsonBufMaxAfterSettleKiB) {
      throw StateError(
        'json_buf high-water after selectBytes settle was '
        '${reading.jsonBufKiB.toStringAsFixed(1)} KiB; expected <= '
        '$_jsonBufMaxAfterSettleKiB KiB.',
      );
    }
    return reading;
  });

  _writeSection(
    md,
    'Warm read working set '
    '($_seedRowCount rows + $_pointLookups point lookups)',
    warmRead,
  );
  _writeSection(
    md,
    'Statement cache footprint ($_distinctStmtCount distinct SELECT texts)',
    stmtCache,
  );
  _writeSection(
    md,
    'WAL after write burst ($_writeBurstRows inserted rows)',
    walBurst,
  );
  _writeSection(
    md,
    'JSON buffer reclaim ($_jsonBufLargeBurstReads large selectBytes + '
    '$_jsonBufSettleReads small settles)',
    jsonBufReclaim,
  );
  return md.toString();
}

Future<T> _withDb<T>(
  String prefix,
  Future<T> Function(Database db) body,
) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  final db = await Database.open('${dir.path}/diag.db');
  try {
    return await body(db);
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _seedItems(Database db, int rowCount) async {
  await db.execute(standardCreateSql);
  for (var offset = 0; offset < rowCount; offset += _seedChunkSize) {
    final remaining = rowCount - offset;
    final count = remaining < _seedChunkSize ? remaining : _seedChunkSize;
    await db.executeBatch(standardInsertSql, [
      for (var i = 0; i < count; i++) standardRow(offset + i),
    ]);
  }
}

Future<void> _seedWriteBurst(Database db, int rowCount) async {
  await db.execute(standardCreateSql);
  await db.executeBatch(standardInsertSql, [
    for (var i = 0; i < rowCount; i++) standardRow(i),
  ]);
}

Future<void> _seedJsonBufWorkload(Database db) async {
  await db.execute(
    'CREATE TABLE small_bytes(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE large_bytes(id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
  );
  final smallBody = 's' * _jsonBufSmallBodyLength;
  final largeBody = 'L' * _jsonBufLargeBodyLength;
  await db.executeBatch('INSERT INTO small_bytes(id, body) VALUES (?, ?)', [
    for (var i = 0; i < _jsonBufSmallRows; i++) [i, '$smallBody-$i'],
  ]);
  await db.executeBatch('INSERT INTO large_bytes(id, body) VALUES (?, ?)', [
    for (var i = 0; i < _jsonBufLargeRows; i++) [i, '$largeBody-$i'],
  ]);
}

Future<void> _exerciseJsonBufReclaim(Database db) async {
  const smallSql = 'SELECT id, body FROM small_bytes ORDER BY id';
  const largeSql = 'SELECT id, body FROM large_bytes ORDER BY id';
  final largeProbe = (await db.selectBytes(largeSql)).bytes;
  if (largeProbe.length <= 1024 * 1024) {
    throw StateError(
      'large selectBytes diagnostic payload was ${largeProbe.length} bytes; '
      'expected > 1 MiB to cross the exp 183 shrink trigger.',
    );
  }

  await Future.wait([
    for (var i = 0; i < _jsonBufLargeBurstReads; i++) db.selectBytes(largeSql),
  ]);
  for (var i = 0; i < _jsonBufSettleReads; i++) {
    await db.selectBytes(smallSql);
  }
}

Future<void> _warmReaders(Database db) async {
  // ReaderPool dispatch is round-robin, so four serial reads touch the
  // default four-reader pool and load schema / one prepared statement on
  // each connection before we snapshot.
  for (var i = 0; i < 4; i++) {
    await db.select('SELECT * FROM items WHERE id = ?', [i + 1]);
  }
}

Future<_DiagnosticsReading> _snapshot(Database db) async {
  for (var attempt = 0; attempt < _snapshotRetries; attempt++) {
    final d = await db.diagnostics();
    if (!d.readersBusyAtSnapshot) {
      return _DiagnosticsReading.fromDiagnostics(d);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final d = await db.diagnostics();
  return _DiagnosticsReading.fromDiagnostics(d);
}

void _writeSection(StringBuffer md, String title, _DiagnosticsReading reading) {
  md
    ..writeln('### $title')
    ..writeln()
    ..writeln(
      '| Library | SQLite total (KiB) | Page cache (KiB) | '
      'Schema (KiB) | Stmt (KiB) | WAL (KiB) | JSON buf (KiB) | '
      'Readers busy |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|')
    ..writeln(
      '| resqlite '
      '| ${reading.sqliteTotalKiB.toStringAsFixed(1)} '
      '| ${reading.pageCacheKiB.toStringAsFixed(1)} '
      '| ${reading.schemaKiB.toStringAsFixed(1)} '
      '| ${reading.stmtKiB.toStringAsFixed(1)} '
      '| ${reading.walKiB.toStringAsFixed(1)} '
      '| ${reading.jsonBufKiB.toStringAsFixed(1)} '
      '| ${reading.readersBusy} |',
    )
    ..writeln();
}

final class _DiagnosticsReading {
  const _DiagnosticsReading({
    required this.sqliteTotalKiB,
    required this.pageCacheKiB,
    required this.schemaKiB,
    required this.stmtKiB,
    required this.walKiB,
    required this.jsonBufKiB,
    required this.readersBusy,
  });

  factory _DiagnosticsReading.fromDiagnostics(Diagnostics d) {
    double toKiB(int bytes) => bytes / 1024.0;

    return _DiagnosticsReading(
      sqliteTotalKiB: toKiB(d.sqliteTotalBytes),
      pageCacheKiB: toKiB(d.sqlitePageCacheBytes),
      schemaKiB: toKiB(d.sqliteSchemaBytes),
      stmtKiB: toKiB(d.sqliteStmtBytes),
      walKiB: toKiB(d.walBytes),
      jsonBufKiB: toKiB(d.readerJsonBufHighWaterBytes),
      readersBusy: d.readersBusyAtSnapshot ? 1 : 0,
    );
  }

  final double sqliteTotalKiB;
  final double pageCacheKiB;
  final double schemaKiB;
  final double stmtKiB;
  final double walKiB;
  final double jsonBufKiB;
  final int readersBusy;
}

Future<void> main() async {
  final md = await runSqliteDiagnosticsBenchmark();
  print(md);
}
