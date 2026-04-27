@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

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

// Transaction-control fast path: pre-prepared BEGIN IMMEDIATE / COMMIT /
// ROLLBACK stmts in C, run via sqlite3_reset + sqlite3_step instead of
// sqlite3_exec's prepare+step+finalize per call (experiment 101).
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
  final allParams = <Object?>[];
  for (final set in paramSets) {
    allParams.addAll(set);
  }
  final paramsNative = allocateParams(allParams);
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
    freeParams(paramsNative, allParams);
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
  final allParams = <Object?>[];
  for (final set in paramSets) {
    allParams.addAll(set);
  }
  final paramsNative = allocateParams(allParams);
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
    freeParams(paramsNative, allParams);
  }
}

/// Per-worker persistent buffer for dirty-table pointer marshalling.
/// Allocated once; reused across calls. Eliminates a ~512-byte calloc/free
/// pair on every write (experiment 070).
final ffi.Pointer<ffi.Pointer<Utf8>> _dirtyTablesBuf =
    calloc<ffi.Pointer<Utf8>>(64);

/// Mirrors `RESQLITE_DEPENDENCY_COUNT_UNKNOWN` in `native/resqlite.h`.
const _dependencyCountUnknown = -1;

/// Polish (post-2026-04): the C-side reliability flag's table-getter
/// return convention is encoded here once. A non-negative count is the
/// known dependency list; [_dependencyCountUnknown] is the unknown sentinel
/// returned when the C set overflowed / OOMed during prepare or the
/// preupdate hook merge.
///
/// Returned by [getReadTables] and [getDirtyTables]. The StreamEngine
/// branches subscribe-side and invalidate-side on `.all`:
///   * `.known(tables)` → use the `_tableIndex` per existing behavior.
///   * `.all()` → route into the global `_allTableEntries` bucket
///     (subscribe) or invalidate every active entry (invalidate).
final class TableDependencySet {
  /// Concrete list of tables — column elision can apply per [tables].
  const TableDependencySet.known(this.tables) : all = false;

  /// Unknown dependency set — fall back to the all-tables bucket.
  const TableDependencySet.all() : tables = const <String>[], all = true;

  /// The known table dependencies. Empty when [all] is true.
  final List<String> tables;

  /// `true` when the C-side set was unreliable; treat as "every table".
  final bool all;

  bool get isEmpty => !all && tables.isEmpty;
}

/// Read and clear the dirty tables set from the C connection.
///
/// Zero-row-change short-circuit (experiment 070): if the count is 0, skip
/// the `List<String>` allocation and return a [TableDependencySet.known]
/// with a const-empty backing list.
///
/// Polish (post-2026-04): [_dependencyCountUnknown] is the unknown sentinel
/// returned when the C-side dirty-table set overflowed / OOMed during
/// the write — interpreted by the StreamEngine as "every active stream
/// must invalidate".
TableDependencySet getDirtyTables(ffi.Pointer<ffi.Void> dbHandle) {
  final count = resqliteGetDirtyTables(dbHandle, _dirtyTablesBuf, 64);
  if (count == _dependencyCountUnknown) return const TableDependencySet.all();
  if (count == 0) return const TableDependencySet.known(<String>[]);
  final tables = List<String>.filled(count, '', growable: false);
  for (var i = 0; i < count; i++) {
    tables[i] = _dirtyTablesBuf[i].toDartString();
  }
  return TableDependencySet.known(tables);
}

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

// Experiment 106: column-level dependency tracking. The C layer captures
// structured table/column pairs alongside table dependencies; these bindings
// fetch them on the same cadence as the table-level FFI.
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

/// Per-worker persistent buffer for read-table pointer marshalling.
/// Allocated once; reused across calls. Eliminates a ~512-byte
/// calloc/free pair per stream subscription (experiment 077).
/// Mirrors the `_dirtyTablesBuf` pattern introduced in exp 070.
final ffi.Pointer<ffi.Pointer<Utf8>> _readTablesBuf = calloc<ffi.Pointer<Utf8>>(
  64,
);

/// Get the set of tables read by the most recent acquired statement on the
/// given reader.
///
/// Repeated calls return metadata from the same cached statement entry until
/// the reader runs another query or the entry is evicted.
///
/// Zero-table short-circuit: if the count is 0, skip the `List<String>`
/// allocation and return a [TableDependencySet.known] with a
/// const-empty backing list.
///
/// Polish (post-2026-04): [_dependencyCountUnknown] is the unknown sentinel —
/// the C-side `read_tables_reliable` flag flipped during prepare, so
/// the stream's true table dependencies are not known. Returns
/// [TableDependencySet.all]; the StreamEngine routes such streams into
/// the "all tables" fallback bucket so every write invalidates them.
TableDependencySet getReadTables(
  ffi.Pointer<ffi.Void> dbHandle,
  int readerId,
) {
  final count = resqliteGetReadTables(dbHandle, readerId, _readTablesBuf, 64);
  if (count == _dependencyCountUnknown) return const TableDependencySet.all();
  if (count == 0) return const TableDependencySet.known(<String>[]);
  final tables = List<String>.filled(count, '', growable: false);
  for (var i = 0; i < count; i++) {
    tables[i] = _readTablesBuf[i].toDartString();
  }
  return TableDependencySet.known(tables);
}

// Experiment 106: per-worker persistent buffers for column pointer
// marshalling. The C layer returns parallel table/column arrays so names with
// dots do not need escaping or ad-hoc parsing in Dart.
final ffi.Pointer<ffi.Pointer<Utf8>> _columnTablesBuf = calloc<ffi.Pointer<Utf8>>(
  64,
);
final ffi.Pointer<ffi.Pointer<Utf8>> _columnNamesBuf =
    calloc<ffi.Pointer<Utf8>>(64);

/// Per-table dirty / read column dependency map.
///
/// `null` for a given table means "any column matters" — emitted by the
/// writer authorizer for INSERT / DELETE (where SQLite does not surface
/// a column name) and by the reader path when an authorizer event
/// fires without a column (triggers, views).
typedef ColumnDependencyMap = Map<String, Set<String>?>;

/// Decode `count` parallel table/column pointers into a per-table column map.
/// Wildcard columns (`"*"`) collapse the table to `null`, signalling "any
/// column matters".
///
/// Shared between [getReadColumns] and [getDirtyColumns] — both decoders
/// are otherwise identical, the only difference is which FFI getter
/// produced the count + pointer fill.
ColumnDependencyMap _decodeColumnMap(int count) {
  if (count <= 0) return const <String, Set<String>?>{};
  final out = <String, Set<String>?>{};
  for (var i = 0; i < count; i++) {
    final table = _columnTablesBuf[i].toDartString();
    final col = _columnNamesBuf[i].toDartString();
    if (col == '*') {
      out[table] = null;
      continue;
    }
    final existing = out[table];
    if (existing == null && out.containsKey(table)) {
      // Wildcard already present — keep it.
      continue;
    }
    final set = existing ?? <String>{};
    set.add(col);
    out[table] = set;
  }
  return out;
}

/// Get the per-reader read-column metadata as a Dart map of
/// `table -> Set<column>`. Wildcards collapse the table to `null` in the
/// returned map, signalling "any column matters".
///
/// Repeated calls return metadata from the most recent acquired statement until
/// the reader runs another query or the entry is evicted.
///
/// Zero-entry short-circuit returns a `const {}` to avoid allocations on
/// the hot streaming path.
ColumnDependencyMap getReadColumns(
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
  return _decodeColumnMap(count);
}

/// Drain the writer's dirty-column accumulator. Wildcards collapse to `null`
/// to signal "all columns of this table are dirty".
ColumnDependencyMap getDirtyColumns(ffi.Pointer<ffi.Void> dbHandle) {
  final count = resqliteGetDirtyColumns(
    dbHandle,
    _columnTablesBuf,
    _columnNamesBuf,
    64,
  );
  return _decodeColumnMap(count);
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

  // Pass 1: encode strings up front so we know their byte lengths
  // before sizing the buffer. We hold onto the encoded bytes (rather
  // than re-encoding in pass 2) because Dart `utf8.encode` is the same
  // work that `String.toNativeUtf8` did internally on the old path.
  List<Uint8List?>? encodedStrings;
  var extraBytes = 0;
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    if (value is String) {
      encodedStrings ??= List<Uint8List?>.filled(params.length, null);
      final bytes = utf8.encode(value);
      encodedStrings[i] = bytes;
      extraBytes += bytes.length;
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
      final bytes = encodedStrings![i]!;
      view.setRange(dataOffset, dataOffset + bytes.length, bytes);
      byteData.setInt32(offset, 3, Endian.little);
      byteData.setInt64(offset + 8, bufAddr + dataOffset, Endian.little);
      byteData.setInt32(offset + 16, bytes.length, Endian.little);
      dataOffset += bytes.length;
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

void freeParams(ffi.Pointer<ffi.Uint8> buf, List<Object?> params) {
  if (buf == ffi.nullptr) return;
  freeReusableParamStructBuf(buf);
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
);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_free',
  isLeaf: true,
)
external void resqliteFree(ffi.Pointer<ffi.Void> ptr);

// ---------------------------------------------------------------------------
// High-level helpers
// ---------------------------------------------------------------------------

typedef NativeBuffer = ({ffi.Pointer<ffi.Uint8> ptr, int length});

NativeBuffer queryBytes(
  ffi.Pointer<ffi.Void> dbHandle,
  int readerId,
  String sql,
  List<Object?> params,
) {
  final sqlNative = cachedSqlUtf8(sql);
  final paramsNative = allocateParams(params);
  final pBuf = calloc<ffi.Pointer<ffi.Uint8>>();
  final pLen = calloc<ffi.Int>();
  try {
    final rc = resqliteQueryBytes(
      dbHandle,
      readerId,
      sqlNative,
      paramsNative,
      params.length,
      pBuf,
      pLen,
    );
    if (rc != 0) {
      // Don't free pBuf — it points to the reader's persistent json_buf,
      // which is owned by the C connection pool. The C code sets it to
      // NULL on error anyway, but even if it didn't, freeing it would
      // corrupt the reader's buffer for future queries.
      throw ResqliteQueryException(
        'resqlite_query_bytes failed with code $rc',
        sql: sql,
        parameters: params,
        sqliteCode: rc,
      );
    }
    return (ptr: pBuf.value, length: pLen.value);
  } finally {
    freeParams(paramsNative, params);
    calloc.free(pBuf);
    calloc.free(pLen);
  }
}
