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
///
/// [params] accepts either a `List<Object?>` (positional `?`
/// placeholders, the existing zero-overhead hot path) or a
/// `Map<String, Object?>` (named `:foo`/`@foo`/`$foo` placeholders).
/// Anything else throws.
///
/// The positional path calls `allocateParams` directly with no extra
/// record/closure allocations between the type check and the C call —
/// matching the byte-for-byte hot path that was in place before named
/// support was added.
WriteResult executeWrite(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  Object params,
) {
  // Inline-typed dispatch. Each branch matches the original positional
  // function's instruction sequence as closely as possible — the named
  // branch carries the full extra cost; the positional branch carries
  // exactly one extra `is List<Object?>` type check.
  final ffi.Pointer<ffi.Uint8> paramsNative;
  final int signedCount;
  if (params is List<Object?>) {
    paramsNative = allocateParams(params);
    signedCount = params.length;
  } else if (params is Map<String, Object?>) {
    final encoded = allocateNamedParams(params);
    paramsNative = encoded.buf;
    signedCount = -encoded.count;
  } else {
    throw ArgumentError.value(
      params,
      'parameters',
      'parameters must be either List<Object?> (positional) or '
          'Map<String, Object?> (named).',
    );
  }
  final sqlNative = cachedSqlUtf8(sql);
  try {
    final resultBuf = calloc<ffi.Uint8>(_writeResultSize);
    try {
      final rc = resqliteExecute(
        dbHandle,
        sqlNative,
        paramsNative,
        signedCount,
        resultBuf,
      );
      if (rc != 0) {
        throw ResqliteQueryException(
          _queryErrorMessage(dbHandle, rc, signedCount.abs()),
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
    freeParamBuffer(paramsNative);
  }
}

/// Validates that every row in [paramSets] has the same shape. For
/// positional rows (`List<Object?>`), this means the same length. For
/// named rows (`Map<String, Object?>`), this means the same key set.
/// Mixed positional/named rows are rejected — the C-level batch path
/// uses one struct shape for the whole batch.
///
/// Callers should invoke this on the *main* isolate before sending the
/// paramSets to the writer — we want [ArgumentError] to surface
/// directly to the user rather than crossing the isolate boundary as
/// a generic "internal writer error".
void assertUniformParamSets(String sql, List<Object> paramSets) {
  if (paramSets.isEmpty) return;
  final first = paramSets.first;

  if (first is List<Object?>) {
    final paramCount = first.length;
    for (var i = 0; i < paramSets.length; i++) {
      final row = paramSets[i];
      if (row is! List<Object?>) {
        throw ArgumentError.value(
          paramSets,
          'paramSets',
          'rows must all be the same shape. Row 0 is positional '
              '(List<Object?>), row $i is ${row.runtimeType}. '
              'SQL: $sql',
        );
      }
      if (row.length != paramCount) {
        throw ArgumentError.value(
          paramSets,
          'paramSets',
          'every row must have the same number of parameters. '
              'Row 0 has $paramCount, row $i has ${row.length}. '
              'SQL: $sql',
        );
      }
    }
    return;
  }

  if (first is Map<String, Object?>) {
    final firstKeys = first.keys.toList(growable: false);
    final firstKeySet = first.keys.toSet();
    for (var i = 0; i < paramSets.length; i++) {
      final row = paramSets[i];
      if (row is! Map<String, Object?>) {
        throw ArgumentError.value(
          paramSets,
          'paramSets',
          'rows must all be the same shape. Row 0 is named '
              '(Map<String, Object?>), row $i is ${row.runtimeType}. '
              'SQL: $sql',
        );
      }
      if (row.length != firstKeys.length ||
          !row.keys.every(firstKeySet.contains)) {
        throw ArgumentError.value(
          paramSets,
          'paramSets',
          'every named row must have the same key set. '
              'Row 0 keys: $firstKeys, row $i keys: ${row.keys.toList()}. '
              'SQL: $sql',
        );
      }
    }
    return;
  }

  throw ArgumentError.value(
    paramSets,
    'paramSets',
    'rows must be List<Object?> (positional) or '
        'Map<String, Object?> (named). Row 0 is ${first.runtimeType}. '
        'SQL: $sql',
  );
}

/// Encode a batch's param matrix into a contiguous native buffer for
/// either the positional or named binding path.
///
/// Returns `(buf, signedCount)` where `signedCount` is the per-row
/// param count, negated for named binding so the C dispatcher picks
/// the named binder.
///
/// Caller must pass a sharply-typed list — `List<List<Object?>>`
/// (positional) or `List<Map<String, Object?>>` (named). The writer
/// worker promotes the loose `List<Object>` SendPort payload before
/// calling this; the per-row `as` cast must NOT live in the encoder's
/// hot loop (each `as` adds enough work to regress 10k-row batch
/// insert by ~40% in benchmarks).
({ffi.Pointer<ffi.Uint8> buf, int signedCount}) encodeBatch(
  List<Object> paramSets,
) {
  if (paramSets.isEmpty) {
    return (buf: ffi.nullptr.cast(), signedCount: 0);
  }
  if (paramSets is List<List<Object?>>) {
    return (
      buf: allocateBatchParams(paramSets),
      signedCount: paramSets.first.length,
    );
  }
  if (paramSets is List<Map<String, Object?>>) {
    return _allocateBatchNamedParams(paramSets);
  }
  // Defensive fallback: a caller bypassed the writer's promote step
  // and handed us a loose `List<Object>`. Promote here so the encoder
  // still gets sharp types; this path is not exercised by the public
  // API.
  if (paramSets.first is Map<String, Object?>) {
    return _allocateBatchNamedParams(
      paramSets.cast<Map<String, Object?>>().toList(growable: false),
    );
  }
  return (
    buf: allocateBatchParams(
      paramSets.cast<List<Object?>>().toList(growable: false),
    ),
    signedCount: (paramSets.first as List<Object?>).length,
  );
}

({ffi.Pointer<ffi.Uint8> buf, int signedCount}) _allocateBatchNamedParams(
  List<Map<String, Object?>> rows,
) {
  if (rows.isEmpty) {
    return (buf: ffi.nullptr.cast(), signedCount: 0);
  }
  final paramCount = rows.first.length;
  if (paramCount == 0) {
    return (buf: ffi.nullptr.cast(), signedCount: 0);
  }
  final totalSlots = rows.length * paramCount;

  // Pass 1: encode every name (once per row — we do not assume keys are
  // identical across rows even though `assertUniformParamSets` checked
  // they are; matching insertion order also matters, so encoding
  // independently is simplest).
  final encodedNames = List<Uint8List>.filled(
    totalSlots,
    Uint8List(0),
    growable: false,
  );
  final encodedStrings = List<Uint8List?>.filled(totalSlots, null);
  var extraBytes = 0;
  var slotIndex = 0;
  for (final row in rows) {
    for (final entry in row.entries) {
      final nameBytes = utf8.encode(entry.key);
      encodedNames[slotIndex] = nameBytes;
      extraBytes += nameBytes.length;

      final value = entry.value;
      if (value is String) {
        final valBytes = utf8.encode(value);
        encodedStrings[slotIndex] = valBytes;
        extraBytes += valBytes.length;
      } else if (value is Uint8List) {
        extraBytes += value.length;
      }
      slotIndex++;
    }
  }

  final structsBytes = _namedParamStructSize * totalSlots;
  final totalBytes = structsBytes + extraBytes;
  final buf = allocateReusableParamStructBuf(totalBytes);
  final view = buf.asTypedList(totalBytes);
  final byteData = ByteData.sublistView(view);
  final bufAddr = buf.address;

  var dataOffset = structsBytes;
  slotIndex = 0;
  for (final row in rows) {
    for (final entry in row.entries) {
      final offset = slotIndex * _namedParamStructSize;
      final value = entry.value;
      final nameBytes = encodedNames[slotIndex];

      view.setRange(dataOffset, dataOffset + nameBytes.length, nameBytes);
      byteData.setInt32(offset + 4, nameBytes.length, Endian.little);
      byteData.setInt64(offset + 8, bufAddr + dataOffset, Endian.little);
      dataOffset += nameBytes.length;

      if (value == null) {
        byteData.setInt32(offset, 0, Endian.little);
      } else if (value is int) {
        byteData.setInt32(offset, 1, Endian.little);
        byteData.setInt64(offset + 16, value, Endian.little);
      } else if (value is double) {
        byteData.setInt32(offset, 2, Endian.little);
        byteData.setFloat64(offset + 16, value, Endian.little);
      } else if (value is String) {
        final bytes = encodedStrings[slotIndex]!;
        view.setRange(dataOffset, dataOffset + bytes.length, bytes);
        byteData.setInt32(offset, 3, Endian.little);
        byteData.setInt64(offset + 16, bufAddr + dataOffset, Endian.little);
        byteData.setInt32(offset + 24, bytes.length, Endian.little);
        dataOffset += bytes.length;
      } else if (value is Uint8List) {
        view.setRange(dataOffset, dataOffset + value.length, value);
        byteData.setInt32(offset, 4, Endian.little);
        byteData.setInt64(offset + 16, bufAddr + dataOffset, Endian.little);
        byteData.setInt32(offset + 24, value.length, Endian.little);
        dataOffset += value.length;
      } else {
        byteData.setInt32(offset, 0, Endian.little);
      }
      slotIndex++;
    }
  }

  return (buf: buf, signedCount: -paramCount);
}

/// Execute a batch: one SQL, many param sets, wrapped in a fresh
/// BEGIN IMMEDIATE / COMMIT transaction.
void executeBatchWrite(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  List<Object> paramSets,
) {
  if (paramSets.isEmpty) return;

  final encoded = encodeBatch(paramSets);
  final sqlNative = cachedSqlUtf8(sql);
  try {
    final rc = resqliteRunBatch(
      dbHandle,
      sqlNative,
      encoded.buf,
      encoded.signedCount,
      paramSets.length,
    );
    if (rc != 0) {
      throw ResqliteQueryException(
        _queryErrorMessage(dbHandle, rc, encoded.signedCount.abs()),
        sql: sql,
        sqliteCode: rc,
      );
    }
  } finally {
    freeParamBuffer(encoded.buf);
  }
}

/// Execute a batch inside an already-open transaction (top-level or savepoint).
/// The caller owns BEGIN / COMMIT / ROLLBACK — on error this helper throws
/// without issuing any rollback, so the caller can roll back at the correct
/// scope (full ROLLBACK vs ROLLBACK TO savepoint).
void executeNestedBatchWrite(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  List<Object> paramSets,
) {
  if (paramSets.isEmpty) return;

  final encoded = encodeBatch(paramSets);
  final sqlNative = cachedSqlUtf8(sql);
  try {
    final rc = resqliteRunBatchNested(
      dbHandle,
      sqlNative,
      encoded.buf,
      encoded.signedCount,
      paramSets.length,
    );
    if (rc != 0) {
      throw ResqliteQueryException(
        _queryErrorMessage(dbHandle, rc, encoded.signedCount.abs()),
        sql: sql,
        sqliteCode: rc,
      );
    }
  } finally {
    freeParamBuffer(encoded.buf);
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

/// Layout of `resqlite_named_param` in C. Larger than the positional struct
/// (24 → 32 bytes) to carry a name pointer + length, but only used on the
/// named binding path. The positional layout is unchanged so the existing
/// hot path stays byte-identical.
///
/// Field layout (matches `native/resqlite.h`'s `resqlite_named_param`):
///
/// ```
/// offset  size  field
/// 0       4     int32 type
/// 4       4     int32 name_len
/// 8       8     ptr   name           (into the same buffer's tail)
/// 16      16    union {              (same shape as positional, just shifted)
///                 int64 int_val
///                 float64 float_val
///                 { ptr data; int32 len; pad } text/blob
///               }
/// ```
const int _namedParamStructSize = 32;

/// Validate the public-API `Object parameters` argument shape on the
/// main isolate.
///
/// Throws [ArgumentError] when [parameters] is neither `List<Object?>`
/// (positional `?` placeholders) nor `Map<String, Object?>` (named
/// `:name`/`@name`/`$name` placeholders). Doing the check here keeps
/// the typed error in the caller's stack trace; if the bad value
/// instead reached the writer isolate, the writer would re-wrap it
/// as a generic `ResqliteException` and bury the diagnostic.
void checkParameters(Object parameters) {
  if (parameters is List<Object?>) return;
  if (parameters is Map<String, Object?>) return;
  throw ArgumentError.value(
    parameters,
    'parameters',
    'parameters must be either List<Object?> (positional) or '
        'Map<String, Object?> (named).',
  );
}

/// Encode a named-parameter map into the named layout described above.
///
/// Returns `(buf, count)` where `count` is the *positive* entry count;
/// callers that pass the buffer to FFI must negate it (`-count`) so the
/// C dispatch picks the named binder. We return the unsigned count here
/// so callers can size up reusable scratch state cleanly.
///
/// Map iteration order is the encoding order. The C side resolves each
/// name to its 1-based bind index via `sqlite3_bind_parameter_index`,
/// so the encoded order does not have to match SQL parameter order.
({ffi.Pointer<ffi.Uint8> buf, int count}) allocateNamedParams(
  Map<String, Object?> params,
) {
  if (params.isEmpty) {
    return (buf: ffi.nullptr.cast(), count: 0);
  }

  // Pass 1: encode every name + every string value up front so we know
  // the exact byte tail size before allocating. Names are encoded as
  // UTF-8 (no leading sigil normalization — SQLite's
  // `sqlite3_bind_parameter_index` expects the *full* placeholder text
  // as it appeared in the SQL, including the leading `:`/`@`/`$`).
  final entryCount = params.length;
  final encodedNames = List<Uint8List>.filled(
    entryCount,
    Uint8List(0),
    growable: false,
  );
  // String values get encoded eagerly so utf8.encode runs once total
  // across both passes — same trick as `allocateParams`.
  final encodedStrings = List<Uint8List?>.filled(entryCount, null);

  var extraBytes = 0;
  var i = 0;
  for (final entry in params.entries) {
    final name = entry.key;
    final nameBytes = utf8.encode(name);
    encodedNames[i] = nameBytes;
    extraBytes += nameBytes.length;

    final value = entry.value;
    if (value is String) {
      final valBytes = utf8.encode(value);
      encodedStrings[i] = valBytes;
      extraBytes += valBytes.length;
    } else if (value is Uint8List) {
      extraBytes += value.length;
    }
    i++;
  }

  final structsBytes = _namedParamStructSize * entryCount;
  final totalBytes = structsBytes + extraBytes;
  final buf = allocateReusableParamStructBuf(totalBytes);
  final view = buf.asTypedList(totalBytes);
  final byteData = ByteData.sublistView(view);
  final bufAddr = buf.address;

  // Pass 2: walk the entries in the same iteration order as pass 1 and
  // write structs. Tail layout: names first (so name pointers live next
  // to each other), then text/blob value bytes after.
  var dataOffset = structsBytes;
  i = 0;
  for (final entry in params.entries) {
    final offset = i * _namedParamStructSize;
    final value = entry.value;
    final nameBytes = encodedNames[i];

    // Name first.
    view.setRange(dataOffset, dataOffset + nameBytes.length, nameBytes);
    byteData.setInt32(offset + 4, nameBytes.length, Endian.little);
    byteData.setInt64(offset + 8, bufAddr + dataOffset, Endian.little);
    dataOffset += nameBytes.length;

    if (value == null) {
      byteData.setInt32(offset, 0, Endian.little);
    } else if (value is int) {
      byteData.setInt32(offset, 1, Endian.little);
      byteData.setInt64(offset + 16, value, Endian.little);
    } else if (value is double) {
      byteData.setInt32(offset, 2, Endian.little);
      byteData.setFloat64(offset + 16, value, Endian.little);
    } else if (value is String) {
      final bytes = encodedStrings[i]!;
      view.setRange(dataOffset, dataOffset + bytes.length, bytes);
      byteData.setInt32(offset, 3, Endian.little);
      byteData.setInt64(offset + 16, bufAddr + dataOffset, Endian.little);
      byteData.setInt32(offset + 24, bytes.length, Endian.little);
      dataOffset += bytes.length;
    } else if (value is Uint8List) {
      view.setRange(dataOffset, dataOffset + value.length, value);
      byteData.setInt32(offset, 4, Endian.little);
      byteData.setInt64(offset + 16, bufAddr + dataOffset, Endian.little);
      byteData.setInt32(offset + 24, value.length, Endian.little);
      dataOffset += value.length;
    } else {
      byteData.setInt32(offset, 0, Endian.little);
    }
    i++;
  }

  return (buf: buf, count: entryCount);
}

/// Encoded form of a single FFI exchange's parameter argument: either a
/// positional list buffer (count > 0) or a named buffer (count < 0).
/// Construct via [encodeParametersArg]. The negated count is what the C
/// dispatch reads to switch between positional and named binders.
typedef EncodedParameters = ({ffi.Pointer<ffi.Uint8> buf, int countSigned});

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

/// Pack a positional batch matrix into the same `[structs][bytes]`
/// layout that single-row `allocateParams` produces, but with all
/// `setCount` rows back-to-back.
///
/// [paramSets] is typed `List<List<Object?>>` so the two encode
/// passes below iterate strongly-typed rows with no per-row `as`
/// cast. The writer worker performs the public-API
/// `List<Object>` -> `List<List<Object?>>` promotion once at message
/// receive time (`_handleBatch`) — that keeps the per-row cast cost
/// out of the hot encode loop entirely.
ffi.Pointer<ffi.Uint8> allocateBatchParams(List<List<Object?>> paramSets) {
  if (paramSets.isEmpty) return ffi.nullptr.cast();
  final paramCount = paramSets.first.length;
  final totalCount = paramSets.length * paramCount;
  if (totalCount == 0) return ffi.nullptr.cast();

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

  final structsBytes = _paramStructSize * totalCount;
  final totalBytes = structsBytes + extraBytes;
  final buf = allocateReusableParamStructBuf(totalBytes);
  final view = buf.asTypedList(totalBytes);
  final byteData = ByteData.sublistView(view);
  final bufAddr = buf.address;

  var dataOffset = structsBytes;
  flatIndex = 0;
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
        final bytes = encodedStrings![flatIndex]!;
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

      flatIndex++;
    }
  }

  return buf;
}

void freeParamBuffer(ffi.Pointer<ffi.Uint8> buf) {
  if (buf == ffi.nullptr) return;
  freeReusableParamStructBuf(buf);
}

void freeParams(ffi.Pointer<ffi.Uint8> buf, List<Object?> _) {
  freeParamBuffer(buf);
}

/// Encode an `Object` parameters argument (positional list or named map)
/// for stmt-acquire callers (reader workers and the writer's transaction
/// read path). Returns the buffer pointer and the *signed* count to pass
/// to FFI — negative for named, positive for positional.
///
/// The positional path matches the original `allocateParams(list)` call
/// shape exactly: one type check + one delegation. No record allocation
/// in the hot path.
EncodedParameters encodeParametersArg(Object params) {
  if (params is List<Object?>) {
    return (buf: allocateParams(params), countSigned: params.length);
  }
  if (params is Map<String, Object?>) {
    final encoded = allocateNamedParams(params);
    return (buf: encoded.buf, countSigned: -encoded.count);
  }
  throw ArgumentError.value(
    params,
    'parameters',
    'parameters must be either List<Object?> (positional) or '
        'Map<String, Object?> (named).',
  );
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
  Object params,
) {
  final ffi.Pointer<ffi.Uint8> paramsNative;
  final int signedCount;
  if (params is List<Object?>) {
    paramsNative = allocateParams(params);
    signedCount = params.length;
  } else if (params is Map<String, Object?>) {
    final encoded = allocateNamedParams(params);
    paramsNative = encoded.buf;
    signedCount = -encoded.count;
  } else {
    throw ArgumentError.value(
      params,
      'parameters',
      'parameters must be either List<Object?> (positional) or '
          'Map<String, Object?> (named).',
    );
  }
  final sqlNative = cachedSqlUtf8(sql);
  final pBuf = calloc<ffi.Pointer<ffi.Uint8>>();
  final pLen = calloc<ffi.Int>();
  try {
    final rc = resqliteQueryBytes(
      dbHandle,
      readerId,
      sqlNative,
      paramsNative,
      signedCount,
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
    freeParamBuffer(paramsNative);
    calloc.free(pBuf);
    calloc.free(pLen);
  }
}
