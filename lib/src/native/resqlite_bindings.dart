@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../dependency_tracking.dart';
import '../exceptions.dart';
import 'request_cache.dart';

// ---------------------------------------------------------------------------
// C-level connection handle
// ---------------------------------------------------------------------------

@ffi.Native<
  ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Int, ffi.Pointer<Utf8>)
>(symbol: 'resqlite_open', isLeaf: true)
external ffi.Pointer<ffi.Void> resqliteOpen(
  ffi.Pointer<Utf8> path,
  int maxReaders,
  ffi.Pointer<Utf8> encryptionKeyHex,
);

@ffi.Native<
  ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<Utf8>,
    ffi.Int,
    ffi.Pointer<Utf8>,
    ffi.Pointer<ffi.Pointer<ffi.Void>>,
    ffi.Int,
  )
>(symbol: 'resqlite_open_with_extensions', isLeaf: true)
external ffi.Pointer<ffi.Void> resqliteOpenWithExtensions(
  ffi.Pointer<Utf8> path,
  int maxReaders,
  ffi.Pointer<Utf8> encryptionKeyHex,
  ffi.Pointer<ffi.Pointer<ffi.Void>> extensionEntrypoints,
  int extensionCount,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_close',
  isLeaf: true,
)
external void resqliteClose(ffi.Pointer<ffi.Void> db);

@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_errmsg',
  isLeaf: true,
)
external ffi.Pointer<Utf8> resqliteErrmsg(ffi.Pointer<ffi.Void> db);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>)>(
  symbol: 'resqlite_exec',
  isLeaf: true,
)
external int resqliteExec(ffi.Pointer<ffi.Void> db, ffi.Pointer<Utf8> sql);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Int,
  )
>(symbol: 'resqlite_run_connection_setup', isLeaf: true)
external int resqliteRunConnectionSetup(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<Utf8> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
  int scope,
);

// Transaction-control fast path: pre-prepared BEGIN IMMEDIATE / COMMIT /
// ROLLBACK stmts in C, run via sqlite3_reset + sqlite3_step instead of
// sqlite3_exec's prepare+step+finalize per call
// ([EXP-101](../../../experiments/101-tx-stmt-cache.md)).
@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_tx_begin_immediate',
  isLeaf: true,
)
external int resqliteTxBeginImmediate(ffi.Pointer<ffi.Void> db);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_tx_commit',
  isLeaf: true,
)
external int resqliteTxCommit(ffi.Pointer<ffi.Void> db);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_tx_rollback',
  isLeaf: true,
)
external int resqliteTxRollback(ffi.Pointer<ffi.Void> db);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Pointer<
      ffi.Uint8
    >, // resqlite_write_result* (affected_rows + last_insert_id)
  )
>(symbol: 'resqlite_execute', isLeaf: true)
external int resqliteExecute(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<Utf8> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
  ffi.Pointer<ffi.Uint8> outResult,
);

@ffi.Native<ffi.Int Function()>(
  symbol: 'resqlite_write_completion_size',
  isLeaf: true,
)
external int resqliteWriteCompletionSize();

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_write_completion_init',
  isLeaf: true,
)
external void resqliteWriteCompletionInit(ffi.Pointer<ffi.Void> mailbox);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_write_completion_reset',
  isLeaf: true,
)
external void resqliteWriteCompletionReset(ffi.Pointer<ffi.Void> mailbox);

@ffi.Native<
  ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Int64, ffi.Int64)
>(symbol: 'resqlite_write_completion_publish', isLeaf: true)
external void resqliteWriteCompletionPublish(
  ffi.Pointer<ffi.Void> mailbox,
  int affectedRows,
  int lastInsertId,
  int writerSqliteUs,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Int>,
    ffi.Pointer<ffi.Int64>,
    ffi.Pointer<ffi.Int64>,
  )
>(symbol: 'resqlite_write_completion_try_read', isLeaf: true)
external int resqliteWriteCompletionTryRead(
  ffi.Pointer<ffi.Void> mailbox,
  ffi.Pointer<ffi.Int> outAffectedRows,
  ffi.Pointer<ffi.Int64> outLastInsertId,
  ffi.Pointer<ffi.Int64> outWriterSqliteUs,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Int,
  )
>(symbol: 'resqlite_run_batch', isLeaf: true)
external int resqliteRunBatch(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<Utf8> sql,
  ffi.Pointer<ffi.Uint8> paramSets,
  int paramCount,
  int setCount,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<Utf8>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Int,
  )
>(symbol: 'resqlite_run_batch_nested', isLeaf: true)
external int resqliteRunBatchNested(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<Utf8> sql,
  ffi.Pointer<ffi.Uint8> paramSets,
  int paramCount,
  int setCount,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Pointer<Utf8>>,
    ffi.Int,
  )
>(symbol: 'resqlite_get_dirty_tables', isLeaf: true)
external int resqliteGetDirtyTables(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.Pointer<Utf8>> outTables,
  int maxTables,
);

// resqlite_write_result struct: {int affected_rows (4), pad (4), long long last_insert_id (8)} = 16 bytes
const int _writeResultSize = 16;
const int _writeResultOffAffected = 0;
const int _writeResultOffLastId = 8;
const int _sqliteRange = 25;

String _queryErrorMessage(
  ffi.Pointer<ffi.Void> dbHandle,
  int sqliteCode,
  int parameterCount,
) {
  if (sqliteCode == _sqliteRange) {
    return 'Incorrect number of parameters for SQL statement '
        '(received $parameterCount).';
  }
  try {
    return resqliteErrmsg(dbHandle).toDartString();
  } catch (_) {
    return 'unknown error';
  }
}

/// Result of a write operation returned by [Database.execute] and
/// [Transaction.execute].
final class WriteResult {
  const WriteResult(this.affectedRows, this.lastInsertId);

  /// The number of rows inserted, updated, or deleted by the statement.
  final int affectedRows;

  /// The ROWID of the last successful INSERT, or 0 for non-INSERT statements.
  final int lastInsertId;
}

/// Execute a write statement. Returns affected rows + last insert ID.
///
/// Uses nested try/finally so each allocation is protected by the time
/// the next one runs — if `allocateParams` or `calloc` throws (e.g. OOM),
/// the earlier resources are still released. Flat sequential allocation
/// would leak on allocator failure, which is rare but real.
WriteResult executeWrite(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  List<Object?> params,
) {
  final sqlNative = cachedSqlUtf8(sql);
  final paramsNative = allocateParams(params);
  try {
    final resultBuf = calloc<ffi.Uint8>(_writeResultSize);
    try {
      final rc = resqliteExecute(
        dbHandle,
        sqlNative,
        paramsNative,
        params.length,
        resultBuf,
      );
      if (rc != 0) {
        throw ResqliteQueryException(
          _queryErrorMessage(dbHandle, rc, params.length),
          sql: sql,
          parameters: params,
          sqliteCode: rc,
        );
      }
      final view = ByteData.sublistView(
        resultBuf.asTypedList(_writeResultSize),
      );
      return WriteResult(
        view.getInt32(_writeResultOffAffected, Endian.little),
        view.getInt64(_writeResultOffLastId, Endian.little),
      );
    } finally {
      calloc.free(resultBuf);
    }
  } finally {
    freeParams(paramsNative, params);
  }
}

/// Validates that every row in [paramSets] has the same length. The
/// C-level batch runner treats the flattened param array as a fixed-
/// shape matrix (`setCount × paramCount`), so non-uniform rows either
/// silently truncate or read past the allocated buffer depending on
/// which direction the shape drifts.
///
/// Callers should invoke this on the *main* isolate before sending the
/// paramSets to the writer — we want [ArgumentError] to surface
/// directly to the user rather than crossing the isolate boundary as
/// a generic "internal writer error".
void assertUniformParamSets(String sql, List<List<Object?>> paramSets) {
  if (paramSets.isEmpty) return;
  final paramCount = paramSets.first.length;
  for (var i = 0; i < paramSets.length; i++) {
    if (paramSets[i].length != paramCount) {
      throw ArgumentError.value(
        paramSets,
        'paramSets',
        'every row must have the same number of parameters. '
            'Row 0 has $paramCount, row $i has ${paramSets[i].length}. '
            'SQL: $sql',
      );
    }
  }
}

/// Execute a batch: one SQL, many param sets, wrapped in a fresh
/// BEGIN IMMEDIATE / COMMIT transaction.
void executeBatchWrite(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  List<List<Object?>> paramSets,
) {
  if (paramSets.isEmpty) return;
  final paramCount = paramSets.first.length;

  final sqlNative = cachedSqlUtf8(sql);
  final paramsNative = allocateBatchParams(paramSets);
  try {
    final rc = resqliteRunBatch(
      dbHandle,
      sqlNative,
      paramsNative,
      paramCount,
      paramSets.length,
    );
    if (rc != 0) {
      throw ResqliteQueryException(
        _queryErrorMessage(dbHandle, rc, paramCount),
        sql: sql,
        sqliteCode: rc,
      );
    }
  } finally {
    freeParamBuffer(paramsNative);
  }
}

/// Execute a batch inside an already-open transaction (top-level or savepoint).
/// The caller owns BEGIN / COMMIT / ROLLBACK — on error this helper throws
/// without issuing any rollback, so the caller can roll back at the correct
/// scope (full ROLLBACK vs ROLLBACK TO savepoint).
void executeNestedBatchWrite(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  List<List<Object?>> paramSets,
) {
  if (paramSets.isEmpty) return;
  final paramCount = paramSets.first.length;

  final sqlNative = cachedSqlUtf8(sql);
  final paramsNative = allocateBatchParams(paramSets);
  try {
    final rc = resqliteRunBatchNested(
      dbHandle,
      sqlNative,
      paramsNative,
      paramCount,
      paramSets.length,
    );
    if (rc != 0) {
      throw ResqliteQueryException(
        _queryErrorMessage(dbHandle, rc, paramCount),
        sql: sql,
        sqliteCode: rc,
      );
    }
  } finally {
    freeParamBuffer(paramsNative);
  }
}

/// Per-worker persistent buffer for dirty-table pointer marshalling.
/// Allocated once; reused across calls. Eliminates a ~512-byte calloc/free
/// pair on every write
/// ([EXP-070](../../../experiments/070-zero-row-change-shortcircuit.md)).
final ffi.Pointer<ffi.Pointer<Utf8>> _dirtyTablesBuf =
    calloc<ffi.Pointer<Utf8>>(64);

/// Mirrors `RESQLITE_DEPENDENCY_COUNT_UNKNOWN` in `native/resqlite.h`.
const _dependencyCountUnknown = -1;

// ---------------------------------------------------------------------------
// Read dependency tracking
// ---------------------------------------------------------------------------

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Pointer<Utf8>>,
    ffi.Int,
  )
>(symbol: 'resqlite_get_read_tables', isLeaf: true)
external int resqliteGetReadTables(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<ffi.Pointer<Utf8>> outTables,
  int maxTables,
);

// [EXP-106](../../../experiments/106-column-level-deps.md): column-level
// dependency tracking. The C layer captures structured table/column pairs
// alongside table dependencies; these bindings fetch them on the same cadence
// as the table-level FFI.
@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Pointer<Utf8>>,
    ffi.Pointer<ffi.Pointer<Utf8>>,
    ffi.Int,
  )
>(symbol: 'resqlite_get_read_columns', isLeaf: true)
external int resqliteGetReadColumns(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<ffi.Pointer<Utf8>> outTables,
  ffi.Pointer<ffi.Pointer<Utf8>> outColumns,
  int maxColumns,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Pointer<Utf8>>,
    ffi.Pointer<ffi.Pointer<Utf8>>,
    ffi.Int,
  )
>(symbol: 'resqlite_get_dirty_columns', isLeaf: true)
external int resqliteGetDirtyColumns(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.Pointer<Utf8>> outTables,
  ffi.Pointer<ffi.Pointer<Utf8>> outColumns,
  int maxColumns,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Int,
    ffi.Pointer<ffi.Int>,
    ffi.Pointer<ffi.Int>,
  )
>(symbol: 'resqlite_db_status_total', isLeaf: true)
external int resqliteDbStatusTotal(
  ffi.Pointer<ffi.Void> db,
  int op,
  int reset,
  ffi.Pointer<ffi.Int> outCurrent,
  ffi.Pointer<ffi.Int> outHighwater,
);

/// Brackets a read worker's request so `resqlite_db_status_total` never
/// reads this NOMUTEX connection from the main isolate while the worker
/// is using it. See `resqlite_reader_set_busy` in `native/resqlite.h`.
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Int)>(
  symbol: 'resqlite_reader_set_busy',
  isLeaf: true,
)
external void resqliteReaderSetBusy(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  int busy,
);

/// Sum of every reader's persistent `json_buf.cap`
/// ([EXP-183](../../../experiments/183-json-buf-retention-audit.md)).
/// Quantifies the bounded RSS high-water `selectBytes` retains after
/// exp 174 stopped sacrificing readers on the bytes path.
@ffi.Native<ffi.Int64 Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_reader_json_buf_total',
  isLeaf: true,
)
external int resqliteReaderJsonBufTotal(ffi.Pointer<ffi.Void> db);

/// High-threshold reclaim for the reader's persistent `json_buf`
/// ([EXP-183](../../../experiments/183-json-buf-retention-audit.md)).
/// Called by the reader worker AFTER `eventPort.send` returns on a
/// `selectBytes` reply — by then `SendPort` has snapshotted the bytes
/// into the receiver, so the native buffer can be realloc'd. Shrinks
/// only when the buffer is much larger than the last produced result
/// (1 MB cap threshold, 256 KB last-len guard) so back-to-back large
/// reads don't churn realloc. Returns the post-call capacity.
@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Int)>(
  symbol: 'resqlite_reader_maybe_shrink_json_buf',
  isLeaf: true,
)
external int resqliteReaderMaybeShrinkJsonBuf(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  int lastUsedLen,
);

/// Per-worker persistent buffer for read-table pointer marshalling.
/// Allocated once; reused across calls. Eliminates a ~512-byte
/// calloc/free pair per stream subscription
/// ([EXP-077](../../../experiments/077-cheap-check-first-sweep.md)).
/// Mirrors the `_dirtyTablesBuf` pattern introduced in
/// [EXP-070](../../../experiments/070-zero-row-change-shortcircuit.md).
final ffi.Pointer<ffi.Pointer<Utf8>> _readTablesBuf = calloc<ffi.Pointer<Utf8>>(
  64,
);

/// Build the final nested table dependency value from native table metadata
/// and optional per-table column detail.
///
/// Table metadata is authoritative. Column detail can only refine tables that
/// are already present in [tableBuf]; details for other tables are ignored.
TableDependencies _decodeTableDependencies(
  int count,
  ffi.Pointer<ffi.Pointer<Utf8>> tableBuf,
  List<TableDependency> columnDetails,
) {
  if (count == _dependencyCountUnknown) return TableDependencies.unknown;
  if (count == 0) return TableDependencies.none;

  final byTable = columnDetails.isEmpty
      ? null
      : <String, TableDependency>{
          for (final detail in columnDetails) detail.table: detail,
        };
  final tables = List<TableDependency>.filled(
    count,
    const TableDependency(''),
    growable: false,
  );
  for (var i = 0; i < count; i++) {
    final table = tableBuf[i].toDartString();
    tables[i] = byTable?[table] ?? TableDependency(table);
  }
  return TableDependencies.fixed(tables);
}

// [EXP-106](../../../experiments/106-column-level-deps.md): per-worker
// persistent buffers for column pointer marshalling. The C layer returns
// parallel table/column arrays so names with dots do not need escaping or
// ad-hoc parsing in Dart.
final ffi.Pointer<ffi.Pointer<Utf8>> _columnTablesBuf =
    calloc<ffi.Pointer<Utf8>>(64);
final ffi.Pointer<ffi.Pointer<Utf8>> _columnNamesBuf =
    calloc<ffi.Pointer<Utf8>>(64);

/// Decode table/column pointers into grouped column details.
///
/// Wildcard columns (`"*"`) collapse the table to a plain [TableDependency],
/// which means column-level precision is unavailable for that table.
List<TableDependency> _decodeColumnDetails(int count) {
  if (count <= 0) return const <TableDependency>[];
  final out = <TableDependency>[];
  for (var i = 0; i < count; i++) {
    final table = _columnTablesBuf[i].toDartString();
    final col = _columnNamesBuf[i].toDartString();
    final existingIndex = out.indexWhere((entry) => entry.table == table);

    if (col == '*') {
      final dependency = TableDependency(table);
      if (existingIndex == -1) {
        out.add(dependency);
      } else {
        out[existingIndex] = dependency;
      }
      continue;
    }

    if (existingIndex == -1) {
      out.add(TableColumnDependency(table, <String>{col}));
      continue;
    }

    switch (out[existingIndex]) {
      case TableColumnDependency(:final columns):
        columns.add(col);
      case TableDependency():
        // Table-level dependency already present — keep it.
        continue;
    }
  }
  return out;
}

/// Get per-reader column detail for the most recent acquired statement.
/// Wildcards collapse the table to a plain [TableDependency].
///
/// Repeated calls return metadata from the most recent acquired statement until
/// the reader runs another query or the entry is evicted.
///
/// Zero-entry short-circuit returns a const empty list to avoid allocations on
/// the hot streaming path.
List<TableDependency> _getReadColumnDetails(
  ffi.Pointer<ffi.Void> dbHandle,
  int readerId,
) {
  final count = resqliteGetReadColumns(
    dbHandle,
    readerId,
    _columnTablesBuf,
    _columnNamesBuf,
    64,
  );
  return _decodeColumnDetails(count);
}

/// Drain the writer's dirty-column accumulator as grouped table details.
///
/// Wildcards collapse to a plain [TableDependency] to signal that the table
/// changed without column-level precision.
List<TableDependency> _getDirtyColumnDetails(ffi.Pointer<ffi.Void> dbHandle) {
  final count = resqliteGetDirtyColumns(
    dbHandle,
    _columnTablesBuf,
    _columnNamesBuf,
    64,
  );
  return _decodeColumnDetails(count);
}

/// Read dependencies for the most recent acquired statement on [readerId].
///
/// The C layer exposes table and column metadata separately, but callers should
/// consume the nested [TableDependencies] value returned here.
TableDependencies getReadTableDependencies(
  ffi.Pointer<ffi.Void> dbHandle,
  int readerId,
) {
  final tableCount = resqliteGetReadTables(
    dbHandle,
    readerId,
    _readTablesBuf,
    64,
  );
  final columnDetails = _getReadColumnDetails(dbHandle, readerId);
  return _decodeTableDependencies(tableCount, _readTablesBuf, columnDetails);
}

/// Dirty dependencies for the completed write cycle, draining native state.
///
/// This drains both native dirty-table and dirty-column accumulators before
/// constructing a single [TableDependencies] value.
TableDependencies getDirtyTableDependencies(ffi.Pointer<ffi.Void> dbHandle) {
  final tableCount = resqliteGetDirtyTables(dbHandle, _dirtyTablesBuf, 64);
  final columnDetails = _getDirtyColumnDetails(dbHandle);
  return _decodeTableDependencies(tableCount, _dirtyTablesBuf, columnDetails);
}

/// Drain dirty dependency state when a write rolls back or is discarded.
void discardDirtyTableDependencies(ffi.Pointer<ffi.Void> dbHandle) {
  resqliteGetDirtyTables(dbHandle, _dirtyTablesBuf, 64);
  resqliteGetDirtyColumns(dbHandle, _columnTablesBuf, _columnNamesBuf, 64);
}

/// Read a sqlite3_db_status aggregate across the writer and any idle
/// readers, treating SQLITE_BUSY (reader mid-query) as a partial
/// snapshot rather than an error.
///
/// Returns `(current, highwater, partial)` where `partial` is true when
/// one or more readers were busy. The C layer populates the aggregate
/// for the idle subset even when it reports BUSY, so the partial
/// numbers are meaningful — just under-reported relative to the full
/// pool. Diagnostic callers should treat `partial == true` as a signal
/// to take snapshots between operations for clean numbers.
({int current, int highwater, bool partial}) getDbStatusTotalAllowBusy(
  ffi.Pointer<ffi.Void> dbHandle,
  int op, {
  bool reset = false,
}) {
  final outCurrent = calloc<ffi.Int>();
  final outHighwater = calloc<ffi.Int>();
  try {
    final rc = resqliteDbStatusTotal(
      dbHandle,
      op,
      reset ? 1 : 0,
      outCurrent,
      outHighwater,
    );
    // SQLITE_BUSY (5) is expected when a reader is mid-query. The C
    // helper has already aggregated the idle-subset totals into the
    // out pointers; we surface them with a partial flag instead of
    // dropping them.
    if (rc != 0 && rc != 5) {
      throw ResqliteQueryException(
        'db_status failed: ${resqliteErrmsg(dbHandle).toDartString()} '
        '(code $rc)',
        sql: 'sqlite3_db_status($op)',
        sqliteCode: rc,
      );
    }
    return (
      current: outCurrent.value,
      highwater: outHighwater.value,
      partial: rc == 5,
    );
  } finally {
    calloc.free(outCurrent);
    calloc.free(outHighwater);
  }
}

/// Read a sqlite3_db_status aggregate across the writer and any idle readers.
///
/// Throws on any non-SUCCESS return code including SQLITE_BUSY. Callers
/// that want BUSY-tolerant partial-snapshot semantics should use
/// [getDbStatusTotalAllowBusy].
({int current, int highwater}) getDbStatusTotal(
  ffi.Pointer<ffi.Void> dbHandle,
  int op, {
  bool reset = false,
}) {
  final outCurrent = calloc<ffi.Int>();
  final outHighwater = calloc<ffi.Int>();
  try {
    final rc = resqliteDbStatusTotal(
      dbHandle,
      op,
      reset ? 1 : 0,
      outCurrent,
      outHighwater,
    );
    if (rc != 0) {
      throw ResqliteQueryException(
        'db_status failed: ${resqliteErrmsg(dbHandle).toDartString()} (code $rc)',
        sql: 'sqlite3_db_status($op)',
        sqliteCode: rc,
      );
    }
    return (current: outCurrent.value, highwater: outHighwater.value);
  } finally {
    calloc.free(outCurrent);
    calloc.free(outHighwater);
  }
}

// ---------------------------------------------------------------------------
// Parameter struct layout (matches resqlite_param in C)
// ---------------------------------------------------------------------------

const int _paramStructSize = 24;

// Exp 125 targets large generated-statement-style batches. Exp 149 keeps the
// narrow 2-3 parameter paths generic, but admits repeated 6+ parameter batches
// where Tracelite profile merge rounds showed direct ASCII packing is material.
const int _asciiBatchMinParamCount = 6;
const int _asciiBatchMinTotalParamCount = 600;

typedef _BatchStringWriter =
    int Function(String value, Uint8List out, int offset, int flatIndex);

/// Pack params into a single buffer: `[struct0..N][text/blob bytes]`.
///
/// Text and blob bytes live inline at the tail of the same buffer that
/// holds the param structs, so a query with N text params requires one
/// native allocation total instead of `1 + N`. The `text.data` /
/// `blob.data` pointers in each struct are addresses *inside* the buffer.
///
/// Two side benefits:
///
/// 1. The actual UTF-8 byte length is written to `text.len` instead of
///    `-1`, so `sqlite3_bind_text` skips its internal `strlen` walk.
/// 2. Inline bytes don't need null termination — `bind_text` reads
///    exactly `len` bytes when `len >= 0`.
///
/// The reader/writer worker that calls this is single-threaded and
/// owns the bound stmt for the whole FFI exchange (acquire → step* →
/// reset all happen before the buffer is reused), so SQLITE_STATIC
/// pointers into the buffer remain valid for as long as SQLite needs
/// them. Buffers larger than `_maxReusableParamBufBytes` fall back to
/// a per-call calloc — still one allocation instead of `1 + N`.
ffi.Pointer<ffi.Uint8> allocateParams(List<Object?> params) {
  if (params.isEmpty) return ffi.nullptr.cast();

  // Pass 1: size the payload. Exp 179/186 extend the batch path's direct-ASCII
  // write (exp 125/149) to the single-row bind path: when every string param
  // is ASCII its UTF-8 byte length equals `String.length`, so we can size the
  // buffer from O(1) lengths and copy code units straight into it in pass 2.
  // Exp 187 keeps that ASCII-only fast path but uses the same direct UTF-8
  // writer as the batch encoder for non-ASCII lists, avoiding a temporary
  // `utf8.encode()` allocation plus a second copy into the native buffer.
  var extraBytes = 0;
  var allStringsAscii = true;
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    if (value is String) {
      final len = value.length;
      var utf8Bytes = len;
      for (var j = 0; j < len; j++) {
        if (value.codeUnitAt(j) > 0x7f) {
          allStringsAscii = false;
          utf8Bytes = _utf8Length(value);
          break;
        }
      }
      extraBytes += utf8Bytes;
    } else if (value is Uint8List) {
      extraBytes += value.length;
    }
  }

  final structsBytes = _paramStructSize * params.length;
  final totalBytes = structsBytes + extraBytes;
  final buf = allocateReusableParamStructBuf(totalBytes);
  final view = buf.asTypedList(totalBytes);
  final byteData = ByteData.sublistView(view);
  final bufAddr = buf.address;

  var dataOffset = structsBytes;
  for (var i = 0; i < params.length; i++) {
    final offset = i * _paramStructSize;
    final value = params[i];

    if (value == null) {
      byteData.setInt32(offset, 0, Endian.little);
    } else if (value is int) {
      byteData.setInt32(offset, 1, Endian.little);
      byteData.setInt64(offset + 8, value, Endian.little);
    } else if (value is double) {
      byteData.setInt32(offset, 2, Endian.little);
      byteData.setFloat64(offset + 8, value, Endian.little);
    } else if (value is String) {
      final start = dataOffset;
      if (allStringsAscii) {
        for (var j = 0; j < value.length; j++) {
          view[dataOffset++] = value.codeUnitAt(j);
        }
      } else {
        dataOffset = _writeUtf8(value, view, dataOffset);
      }
      byteData.setInt32(offset, 3, Endian.little);
      byteData.setInt64(offset + 8, bufAddr + start, Endian.little);
      byteData.setInt32(offset + 16, dataOffset - start, Endian.little);
    } else if (value is Uint8List) {
      view.setRange(dataOffset, dataOffset + value.length, value);
      byteData.setInt32(offset, 4, Endian.little);
      byteData.setInt64(offset + 8, bufAddr + dataOffset, Endian.little);
      byteData.setInt32(offset + 16, value.length, Endian.little);
      dataOffset += value.length;
    } else {
      byteData.setInt32(offset, 0, Endian.little);
    }
  }

  return buf;
}

ffi.Pointer<ffi.Uint8> allocateBatchParams(List<List<Object?>> paramSets) {
  if (paramSets.isEmpty) return ffi.nullptr.cast();
  final paramCount = paramSets.first.length;
  final totalCount = paramSets.length * paramCount;
  if (totalCount == 0) return ffi.nullptr.cast();

  if (paramCount >= _asciiBatchMinParamCount &&
      totalCount >= _asciiBatchMinTotalParamCount &&
      _firstBatchRowMayContainText(paramSets.first, paramCount)) {
    final payload = _measureBatchPayload(paramSets, paramCount);
    if (payload.hasString) {
      if (payload.isAscii) {
        return _allocateAsciiBatchParams(
          paramSets,
          paramCount,
          totalCount,
          payload.extraBytes,
        );
      }

      return _allocateUtf8BatchParams(
        paramSets,
        paramCount,
        totalCount,
        payload.extraBytes,
      );
    }
  }

  return _allocateBatchParamsGeneric(paramSets, paramCount, totalCount);
}

bool _firstBatchRowMayContainText(List<Object?> params, int paramCount) {
  for (var i = 0; i < paramCount; i++) {
    final value = params[i];
    if (value is String || value == null) return true;
  }
  return false;
}

({int extraBytes, bool hasString, bool isAscii}) _measureBatchPayload(
  List<List<Object?>> paramSets,
  int paramCount,
) {
  var extraBytes = 0;
  var hasString = false;
  var isAscii = true;

  for (final set in paramSets) {
    for (var i = 0; i < paramCount; i++) {
      final value = set[i];
      if (value is String) {
        hasString = true;
        if (isAscii) {
          final length = value.length;
          var stringIsAscii = true;
          for (var j = 0; j < length; j++) {
            if (value.codeUnitAt(j) > 0x7f) {
              stringIsAscii = false;
              isAscii = false;
              break;
            }
          }
          if (stringIsAscii) {
            extraBytes += length;
            continue;
          }
        }
        extraBytes += _utf8Length(value);
      } else if (value is Uint8List) {
        extraBytes += value.length;
      }
    }
  }

  return (extraBytes: extraBytes, hasString: hasString, isAscii: isAscii);
}

ffi.Pointer<ffi.Uint8> _allocateAsciiBatchParams(
  List<List<Object?>> paramSets,
  int paramCount,
  int totalCount,
  int extraBytes,
) {
  return _allocatePackedBatchParams(
    paramSets,
    paramCount,
    totalCount,
    extraBytes,
    (value, out, offset, _) {
      for (var j = 0; j < value.length; j++) {
        out[offset + j] = value.codeUnitAt(j);
      }
      return offset + value.length;
    },
  );
}

ffi.Pointer<ffi.Uint8> _allocateUtf8BatchParams(
  List<List<Object?>> paramSets,
  int paramCount,
  int totalCount,
  int extraBytes,
) {
  return _allocatePackedBatchParams(
    paramSets,
    paramCount,
    totalCount,
    extraBytes,
    (value, out, offset, _) => _writeUtf8(value, out, offset),
  );
}

ffi.Pointer<ffi.Uint8> _allocatePackedBatchParams(
  List<List<Object?>> paramSets,
  int paramCount,
  int totalCount,
  int extraBytes,
  _BatchStringWriter writeString,
) {
  final structsBytes = _paramStructSize * totalCount;
  final totalBytes = structsBytes + extraBytes;
  final buf = allocateReusableParamStructBuf(totalBytes);
  final view = buf.asTypedList(totalBytes);
  final byteData = ByteData.sublistView(view);
  final bufAddr = buf.address;

  var dataOffset = structsBytes;
  var flatIndex = 0;
  for (final set in paramSets) {
    for (var i = 0; i < paramCount; i++) {
      final offset = flatIndex * _paramStructSize;
      final value = set[i];

      if (value == null) {
        byteData.setInt32(offset, 0, Endian.little);
      } else if (value is int) {
        byteData.setInt32(offset, 1, Endian.little);
        byteData.setInt64(offset + 8, value, Endian.little);
      } else if (value is double) {
        byteData.setInt32(offset, 2, Endian.little);
        byteData.setFloat64(offset + 8, value, Endian.little);
      } else if (value is String) {
        final start = dataOffset;
        dataOffset = writeString(value, view, dataOffset, flatIndex);
        byteData.setInt32(offset, 3, Endian.little);
        byteData.setInt64(offset + 8, bufAddr + start, Endian.little);
        byteData.setInt32(offset + 16, dataOffset - start, Endian.little);
      } else if (value is Uint8List) {
        view.setRange(dataOffset, dataOffset + value.length, value);
        byteData.setInt32(offset, 4, Endian.little);
        byteData.setInt64(offset + 8, bufAddr + dataOffset, Endian.little);
        byteData.setInt32(offset + 16, value.length, Endian.little);
        dataOffset += value.length;
      } else {
        byteData.setInt32(offset, 0, Endian.little);
      }

      flatIndex++;
    }
  }

  return buf;
}

int _utf8Length(String value) {
  var bytes = 0;
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    if (codeUnit <= 0x7f) {
      bytes++;
    } else if (codeUnit <= 0x7ff) {
      bytes += 2;
    } else if (_isLeadSurrogate(codeUnit)) {
      if (i + 1 < value.length && _isTrailSurrogate(value.codeUnitAt(i + 1))) {
        bytes += 4;
        i++;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

int _writeUtf8(String value, Uint8List out, int offset) {
  for (var i = 0; i < value.length; i++) {
    final codeUnit = value.codeUnitAt(i);
    if (codeUnit <= 0x7f) {
      out[offset++] = codeUnit;
    } else if (codeUnit <= 0x7ff) {
      out[offset++] = 0xc0 | (codeUnit >> 6);
      out[offset++] = 0x80 | (codeUnit & 0x3f);
    } else if (_isLeadSurrogate(codeUnit)) {
      if (i + 1 < value.length) {
        final next = value.codeUnitAt(i + 1);
        if (_isTrailSurrogate(next)) {
          final codePoint =
              0x10000 + ((codeUnit - 0xd800) << 10) + (next - 0xdc00);
          out[offset++] = 0xf0 | (codePoint >> 18);
          out[offset++] = 0x80 | ((codePoint >> 12) & 0x3f);
          out[offset++] = 0x80 | ((codePoint >> 6) & 0x3f);
          out[offset++] = 0x80 | (codePoint & 0x3f);
          i++;
          continue;
        }
      }
      offset = _writeReplacementCharacter(out, offset);
    } else if (_isTrailSurrogate(codeUnit)) {
      offset = _writeReplacementCharacter(out, offset);
    } else {
      out[offset++] = 0xe0 | (codeUnit >> 12);
      out[offset++] = 0x80 | ((codeUnit >> 6) & 0x3f);
      out[offset++] = 0x80 | (codeUnit & 0x3f);
    }
  }
  return offset;
}

int _writeReplacementCharacter(Uint8List out, int offset) {
  out[offset++] = 0xef;
  out[offset++] = 0xbf;
  out[offset++] = 0xbd;
  return offset;
}

bool _isLeadSurrogate(int codeUnit) => codeUnit >= 0xd800 && codeUnit <= 0xdbff;

bool _isTrailSurrogate(int codeUnit) =>
    codeUnit >= 0xdc00 && codeUnit <= 0xdfff;

ffi.Pointer<ffi.Uint8> _allocateBatchParamsGeneric(
  List<List<Object?>> paramSets,
  int paramCount,
  int totalCount,
) {
  List<Uint8List?>? encodedStrings;
  var extraBytes = 0;
  var flatIndex = 0;
  for (final set in paramSets) {
    for (var i = 0; i < paramCount; i++) {
      final value = set[i];
      if (value is String) {
        encodedStrings ??= List<Uint8List?>.filled(totalCount, null);
        final bytes = utf8.encode(value);
        encodedStrings[flatIndex] = bytes;
        extraBytes += bytes.length;
      } else if (value is Uint8List) {
        extraBytes += value.length;
      }
      flatIndex++;
    }
  }

  return _allocatePackedBatchParams(
    paramSets,
    paramCount,
    totalCount,
    extraBytes,
    (value, out, offset, flatIndex) {
      final bytes = encodedStrings![flatIndex]!;
      out.setRange(offset, offset + bytes.length, bytes);
      return offset + bytes.length;
    },
  );
}

void freeParamBuffer(ffi.Pointer<ffi.Uint8> buf) {
  if (buf == ffi.nullptr) return;
  freeReusableParamStructBuf(buf);
}

void freeParams(ffi.Pointer<ffi.Uint8> buf, List<Object?> _) {
  freeParamBuffer(buf);
}

// ---------------------------------------------------------------------------
// Query functions using C-level connection + statement cache
// ---------------------------------------------------------------------------

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<Utf8>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
    ffi.Pointer<ffi.Pointer<ffi.Uint8>>,
    ffi.Pointer<ffi.Int>,
    ffi.Pointer<ffi.Int>,
  )
>(symbol: 'resqlite_query_bytes', isLeaf: true)
external int resqliteQueryBytes(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<Utf8> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>> outBuf,
  ffi.Pointer<ffi.Int> outLen,
  ffi.Pointer<ffi.Int> outRowCount,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_free',
  isLeaf: true,
)
external void resqliteFree(ffi.Pointer<ffi.Void> ptr);

// ---------------------------------------------------------------------------
// High-level helpers
// ---------------------------------------------------------------------------

typedef NativeBuffer = ({ffi.Pointer<ffi.Uint8> ptr, int length, int rowCount});

// [EXP-211] Persistent per-isolate out-parameter slots for [queryBytes].
// resqlite_query_bytes writes three values every call — the json_buf view
// pointer, its length, and the row count — so the slot boxes never carry
// state between calls. Reader workers process one request at a time, so a
// pair of shared per-isolate slots is safe. Retries the exp 108 shape now
// that select_bytes_repeated_calls.dart (exp 195) resolves µs-scale
// per-query setup wins the release suite (ms precision) could not see.
final ffi.Pointer<ffi.Pointer<ffi.Uint8>> _queryBytesOutBuf =
    calloc<ffi.Pointer<ffi.Uint8>>();
final ffi.Pointer<ffi.Int> _queryBytesOutLen = calloc<ffi.Int>();
final ffi.Pointer<ffi.Int> _queryBytesOutRowCount = calloc<ffi.Int>();

NativeBuffer queryBytes(
  ffi.Pointer<ffi.Void> dbHandle,
  int readerId,
  String sql,
  List<Object?> params,
) {
  final sqlNative = cachedSqlUtf8(sql);
  final paramsNative = allocateParams(params);
  try {
    final rc = resqliteQueryBytes(
      dbHandle,
      readerId,
      sqlNative,
      paramsNative,
      params.length,
      _queryBytesOutBuf,
      _queryBytesOutLen,
      _queryBytesOutRowCount,
    );
    if (rc != 0) {
      // The reader's persistent json_buf is C-owned; even on success we
      // never free the pointer written into _queryBytesOutBuf. C sets all
      // three slots to zero/NULL on every error path, so the values from a
      // prior successful call are never observable to error handlers.
      throw ResqliteQueryException(
        'resqlite_query_bytes failed with code $rc',
        sql: sql,
        parameters: params,
        sqliteCode: rc,
      );
    }
    return (
      ptr: _queryBytesOutBuf.value,
      length: _queryBytesOutLen.value,
      rowCount: _queryBytesOutRowCount.value,
    );
  } finally {
    freeParams(paramsNative, params);
  }
}
