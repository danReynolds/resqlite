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

  final warmRead = await _withDb(
    'bench_diag_read_',
    (db) async {
      await _seedItems(db, _seedRowCount);
      await _warmReaders(db);
      for (var i = 0; i < _pointLookups; i++) {
        await db.select(
          'SELECT * FROM items WHERE id = ?',
          [i % _seedRowCount + 1],
        );
      }
      return _snapshot(db);
    },
  );

  final stmtCache = await _withDb(
    'bench_diag_stmt_',
    (db) async {
      await _seedItems(db, _seedRowCount);
      await _warmReaders(db);
      for (var i = 0; i < _distinctStmtCount; i++) {
        await db.select(
          'SELECT * FROM items WHERE id = ? /* diag_stmt_$i */',
          [i % _seedRowCount + 1],
        );
      }
      return _snapshot(db);
    },
  );

  final walBurst = await _withDb(
    'bench_diag_wal_',
    (db) async {
      await _seedWriteBurst(db, _writeBurstRows);
      await _warmReaders(db);
      return _snapshot(db);
    },
  );

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
    await db.executeBatch(
      standardInsertSql,
      [for (var i = 0; i < count; i++) standardRow(offset + i)],
    );
  }
}

Future<void> _seedWriteBurst(Database db, int rowCount) async {
  await db.execute(standardCreateSql);
  await db.executeBatch(
    standardInsertSql,
    [for (var i = 0; i < rowCount; i++) standardRow(i)],
  );
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

void _writeSection(
  StringBuffer md,
  String title,
  _DiagnosticsReading reading,
) {
  md
    ..writeln('### $title')
    ..writeln()
    ..writeln(
      '| Library | SQLite total (KiB) | Page cache (KiB) | '
      'Schema (KiB) | Stmt (KiB) | WAL (KiB) | Readers busy |',
    )
    ..writeln('|---|---|---|---|---|---|---|')
    ..writeln(
      '| resqlite '
      '| ${reading.sqliteTotalKiB.toStringAsFixed(1)} '
      '| ${reading.pageCacheKiB.toStringAsFixed(1)} '
      '| ${reading.schemaKiB.toStringAsFixed(1)} '
      '| ${reading.stmtKiB.toStringAsFixed(1)} '
      '| ${reading.walKiB.toStringAsFixed(1)} '
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
      readersBusy: d.readersBusyAtSnapshot ? 1 : 0,
    );
  }

  final double sqliteTotalKiB;
  final double pageCacheKiB;
  final double schemaKiB;
  final double stmtKiB;
  final double walKiB;
  final int readersBusy;
}

Future<void> main() async {
  final md = await runSqliteDiagnosticsBenchmark();
  print(md);
}
