/// Per-connection diagnostic snapshot.
///
/// Intended primarily for benchmark instrumentation and mobile memory
/// reporting. Aggregated across the writer connection and any idle
/// reader connections in the pool; see [readersBusyAtSnapshot].
///
/// Values come from SQLite's [`sqlite3_db_status`](https://sqlite.org/c3ref/db_status.html)
/// counters plus a filesystem-level read of the `-wal` sidecar. They
/// reflect the state of this connection pool only — global SQLite
/// memory counters are disabled (the library ships with
/// `SQLITE_DEFAULT_MEMSTATUS=0` for performance) so
/// `sqlite3_status64`-style per-process totals are not available.
final class Diagnostics {
  const Diagnostics({
    required this.sqlitePageCacheBytes,
    required this.sqliteSchemaBytes,
    required this.sqliteStmtBytes,
    required this.walBytes,
    required this.readersBusyAtSnapshot,
  });

  /// Total bytes used by the SQLite page cache across the writer and
  /// every idle reader connection. Corresponds to
  /// `SQLITE_DBSTATUS_CACHE_USED` summed across connections.
  ///
  /// A larger number means SQLite is holding more pages in memory, which
  /// may be good (better hit rate) or bad (contending with Flutter's
  /// working set on a low-RAM device).
  final int sqlitePageCacheBytes;

  /// Schema-related memory (parse trees, index info) across the writer
  /// and idle readers. Corresponds to `SQLITE_DBSTATUS_SCHEMA_USED`.
  ///
  /// Dominated by the schema parse result; grows with table/index count,
  /// not data size. A surprise spike here usually indicates schema
  /// re-preparation churn.
  final int sqliteSchemaBytes;

  /// Prepared-statement memory across the writer and idle readers.
  /// Corresponds to `SQLITE_DBSTATUS_STMT_USED`.
  ///
  /// Bounded by the per-connection statement cache (32 entries by
  /// default). Useful for verifying cache size tuning doesn't over-grow.
  final int sqliteStmtBytes;

  /// Size in bytes of the `-wal` sidecar file.
  ///
  /// Zero if not in WAL mode, the file doesn't exist yet (freshly
  /// opened, no writes), or the database is in-memory (`:memory:`).
  /// Growth over time indicates checkpoint pressure; a persistent large
  /// value means readers are pinning the WAL.
  final int walBytes;

  /// True when at least one reader in the pool was busy at snapshot time.
  /// That reader's contribution to [sqlitePageCacheBytes],
  /// [sqliteSchemaBytes], and [sqliteStmtBytes] is *excluded* from the
  /// totals above.
  ///
  /// For reliable numbers, take snapshots between operations when no
  /// concurrent work is in flight. Benchmark harnesses typically satisfy
  /// this naturally because timing loops are serial.
  final bool readersBusyAtSnapshot;

  /// Sum of SQLite per-connection memory counters — pages + schema +
  /// prepared statements. Excludes WAL (which is on-disk, not RAM).
  /// Useful as a single "how much memory is this connection set using"
  /// number for dashboards.
  int get sqliteTotalBytes =>
      sqlitePageCacheBytes + sqliteSchemaBytes + sqliteStmtBytes;

  @override
  String toString() => 'Diagnostics('
      'pageCache: $sqlitePageCacheBytes B, '
      'schema: $sqliteSchemaBytes B, '
      'stmt: $sqliteStmtBytes B, '
      'wal: $walBytes B'
      '${readersBusyAtSnapshot ? ', readersBusy: true' : ''}'
      ')';
}

/// SQLite `sqlite3_db_status` op codes used by [Diagnostics].
///
/// See https://sqlite.org/c3ref/c_dbstatus_options.html for the full list.
/// We only expose the handful that correspond to [Diagnostics] fields.
abstract final class SqliteDbStatusOp {
  /// `SQLITE_DBSTATUS_CACHE_USED` — bytes in the page cache.
  static const int cacheUsed = 1;

  /// `SQLITE_DBSTATUS_SCHEMA_USED` — bytes in schema parse results.
  static const int schemaUsed = 2;

  /// `SQLITE_DBSTATUS_STMT_USED` — bytes in prepared-statement VDBE.
  static const int stmtUsed = 3;
}
