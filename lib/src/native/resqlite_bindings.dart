@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../exceptions.dart';

// ---------------------------------------------------------------------------
// C-level connection handle
// ---------------------------------------------------------------------------

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Int, ffi.Pointer<Utf8>)>(
  symbol: 'resqlite_open',
  isLeaf: true,
)
external ffi.Pointer<ffi.Void> resqliteOpen(
  ffi.Pointer<Utf8> path,
  int maxReaders,
  ffi.Pointer<Utf8> encryptionKeyHex,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(symbol: 'resqlite_close', isLeaf: true)
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
    ffi.Pointer<ffi.Uint8>,  // resqlite_write_result* (affected_rows + last_insert_id)
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

/// Result of a write operation.
final class WriteResult {
  const WriteResult(this.affectedRows, this.lastInsertId);
  final int affectedRows;
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
  final sqlNative = sql.toNativeUtf8();
  try {
    final paramsNative = allocateParams(params);
    try {
      final resultBuf = calloc<ffi.Uint8>(_writeResultSize);
      try {
        final rc = resqliteExecute(
          dbHandle, sqlNative, paramsNative, params.length, resultBuf,
        );
        if (rc != 0) {
          // Read the error message carefully — if the connection is in a
          // bad state the pointer may be invalid.
          String errMsg;
          try {
            errMsg = resqliteErrmsg(dbHandle).toDartString();
          } catch (_) {
            errMsg = 'unknown error';
          }
          throw ResqliteQueryException(
            errMsg,
            sql: sql,
            parameters: params,
            sqliteCode: rc,
          );
        }
        final view =
            ByteData.sublistView(resultBuf.asTypedList(_writeResultSize));
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
  } finally {
    calloc.free(sqlNative);
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
void assertUniformParamSets(
  String sql,
  List<List<Object?>> paramSets,
) {
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

  final sqlNative = sql.toNativeUtf8();
  try {
    final allParams = <Object?>[];
    for (final set in paramSets) {
      allParams.addAll(set);
    }
    final paramsNative = allocateParams(allParams);
    try {
      final rc = resqliteRunBatch(
        dbHandle, sqlNative, paramsNative, paramCount, paramSets.length,
      );
      if (rc != 0) {
        throw ResqliteQueryException(
          resqliteErrmsg(dbHandle).toDartString(),
          sql: sql,
          sqliteCode: rc,
        );
      }
    } finally {
      freeParams(paramsNative, allParams);
    }
  } finally {
    calloc.free(sqlNative);
  }
}

/// Execute a batch inside an already-open transaction (top-level or savepoint).
/// The caller owns BEGIN / COMMIT / ROLLBACK — on error this helper throws
/// without issuing any rollback, so the caller can roll back at the correct
/// scope (full ROLLBACK vs ROLLBACK TO savepoint).
void executeBatchWriteNested(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  List<List<Object?>> paramSets,
) {
  if (paramSets.isEmpty) return;
  final paramCount = paramSets.first.length;

  final sqlNative = sql.toNativeUtf8();
  try {
    final allParams = <Object?>[];
    for (final set in paramSets) {
      allParams.addAll(set);
    }
    final paramsNative = allocateParams(allParams);
    try {
      final rc = resqliteRunBatchNested(
        dbHandle, sqlNative, paramsNative, paramCount, paramSets.length,
      );
      if (rc != 0) {
        throw ResqliteQueryException(
          resqliteErrmsg(dbHandle).toDartString(),
          sql: sql,
          sqliteCode: rc,
        );
      }
    } finally {
      freeParams(paramsNative, allParams);
    }
  } finally {
    calloc.free(sqlNative);
  }
}

/// Read and clear the dirty tables set from the C connection.
List<String> getDirtyTables(ffi.Pointer<ffi.Void> dbHandle) {
  final outTables = calloc<ffi.Pointer<Utf8>>(64);
  try {
    final count = resqliteGetDirtyTables(dbHandle, outTables, 64);
    final tables = <String>[];
    for (var i = 0; i < count; i++) {
      tables.add(outTables[i].toDartString());
    }
    return tables;
  } finally {
    calloc.free(outTables);
  }
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

/// Get the set of tables read by the last query on the given reader.
/// Clears after reading.
List<String> getReadTables(ffi.Pointer<ffi.Void> dbHandle, int readerId) {
  final outTables = calloc<ffi.Pointer<Utf8>>(64);
  try {
    final count = resqliteGetReadTables(dbHandle, readerId, outTables, 64);
    final tables = <String>[];
    for (var i = 0; i < count; i++) {
      tables.add(outTables[i].toDartString());
    }
    return tables;
  } finally {
    calloc.free(outTables);
  }
}

/// Read a sqlite3_db_status aggregate across the writer and any idle readers.
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

ffi.Pointer<ffi.Uint8> allocateParams(List<Object?> params) {
  if (params.isEmpty) return ffi.nullptr.cast();

  final buf = calloc<ffi.Uint8>(_paramStructSize * params.length);
  final view = buf.cast<ffi.Uint8>().asTypedList(_paramStructSize * params.length);
  final byteData = ByteData.sublistView(view);

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
      final encoded = value.toNativeUtf8();
      byteData.setInt32(offset, 3, Endian.little);
      byteData.setInt64(offset + 8, encoded.address, Endian.little);
      byteData.setInt32(offset + 16, -1, Endian.little);
    } else if (value is Uint8List) {
      final blob = calloc<ffi.Uint8>(value.length);
      blob.asTypedList(value.length).setAll(0, value);
      byteData.setInt32(offset, 4, Endian.little);
      byteData.setInt64(offset + 8, blob.address, Endian.little);
      byteData.setInt32(offset + 16, value.length, Endian.little);
    } else {
      byteData.setInt32(offset, 0, Endian.little);
    }
  }

  return buf;
}

void freeParams(ffi.Pointer<ffi.Uint8> buf, List<Object?> params) {
  if (buf == ffi.nullptr) return;

  final view = buf.asTypedList(_paramStructSize * params.length);
  final byteData = ByteData.sublistView(view);

  for (var i = 0; i < params.length; i++) {
    final offset = i * _paramStructSize;
    final type = byteData.getInt32(offset, Endian.little);
    if (type == 3 || type == 4) {
      final ptr = ffi.Pointer<ffi.Void>.fromAddress(
        byteData.getInt64(offset + 8, Endian.little),
      );
      calloc.free(ptr);
    }
  }
  calloc.free(buf);
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

@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(symbol: 'resqlite_free', isLeaf: true)
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
  final sqlNative = sql.toNativeUtf8();
  final paramsNative = allocateParams(params);
  final pBuf = calloc<ffi.Pointer<ffi.Uint8>>();
  final pLen = calloc<ffi.Int>();
  try {
    final rc = resqliteQueryBytes(
      dbHandle, readerId, sqlNative, paramsNative, params.length, pBuf, pLen,
    );
    if (rc != 0) {
      final bufPtr = pBuf.value;
      if (bufPtr != ffi.nullptr) resqliteFree(bufPtr.cast());
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
    calloc.free(sqlNative);
    calloc.free(pBuf);
    calloc.free(pLen);
  }
}
