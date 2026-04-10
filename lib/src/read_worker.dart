/// Read worker — query execution logic and isolate entrypoint.
///
/// Owns the FFI bindings for reading, the cell buffer constants, the
/// fastDecodeText helper, and the worker entrypoint. Builds the flat
/// List<Object?> + RowSchema format consumed by ResultSet.
///
/// The reader pool (reader_pool.dart) manages a fleet of these workers
/// and handles dispatch, busy tracking, and respawn lifecycle.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native/resqlite_bindings.dart';
import 'result_hash.dart';
import 'row.dart';

// ---------------------------------------------------------------------------
// Request types — sent from pool to worker via SendPort
// ---------------------------------------------------------------------------

/// Base class for read requests sent from the pool to a worker isolate.
///
/// Each subclass represents a different query mode. The worker replies with
/// a `(result, sacrificed, errorMessage)` record — see [readerEntrypoint].
///
/// Uses a sealed class hierarchy (not an enum + list) for type-safe
/// exhaustive switching in the worker and named field access in the pool.
sealed class ReadRequest {
  ReadRequest(this.replyPort, this.sql, this.parameters);
  final SendPort replyPort;
  final String sql;
  final List<Object?> parameters;
}

/// Standard row query — returns a [ResultSet].
final class SelectRequest extends ReadRequest {
  SelectRequest(super.replyPort, super.sql, super.parameters);
}

/// Row query that also captures read table dependencies via the SQLite
/// authorizer hook. Used for initial stream registration in [StreamEngine].
final class SelectWithDepsRequest extends ReadRequest {
  SelectWithDepsRequest(super.replyPort, super.sql, super.parameters);
}

/// JSON bytes query — serialized entirely in C, no Dart objects for result data.
final class SelectBytesRequest extends ReadRequest {
  SelectBytesRequest(super.replyPort, super.sql, super.parameters);
}

/// Stream re-query with worker-side hash comparison.
///
/// The worker computes a hash of the result and compares it against
/// [lastResultHash]. If unchanged, it returns `(hash, null)` instead of
/// the full [ResultSet], avoiding the SendPort transfer cost entirely.
final class SelectIfChangedRequest extends ReadRequest {
  SelectIfChangedRequest(
    super.replyPort, super.sql, super.parameters, this.lastResultHash,
  );
  final int lastResultHash;
}

/// Byte-size threshold for sacrifice. If the estimated transfer size of
/// a result exceeds this, the worker uses Isolate.exit (zero-copy) instead
/// of SendPort.send (memcpy). Below this threshold the copy is sub-millisecond;
/// above it the zero-copy transfer outweighs the ~2-5ms respawn cost.
///
/// Applies to both row results (estimated during the cell loop) and
/// selectBytes results (exact byte length of the JSON buffer).
const int sacrificeByteThreshold = 256 * 1024; // 256 KB

/// Per-worker cell buffer. Reused across queries to avoid calloc/free per query.
ffi.Pointer<ffi.Uint8> _cellsBuf = ffi.nullptr;
int _cellsBufColCount = 0;

ffi.Pointer<ffi.Uint8> _ensureCellBuffer(int colCount) {
  if (colCount <= _cellsBufColCount) return _cellsBuf;
  if (_cellsBuf != ffi.nullptr) calloc.free(_cellsBuf);
  _cellsBuf = calloc<ffi.Uint8>(_cellSize * colCount);
  _cellsBufColCount = colCount;
  return _cellsBuf;
}

/// Per-worker schema cache. Column names for the same SQL are always identical,
/// so we cache RowSchema keyed by SQL string to avoid N FFI calls + N String
/// allocations per query on cache hit. Each worker isolate has its own instance.
final Map<String, RowSchema> _schemaCache = {};

// ---------------------------------------------------------------------------
// Read worker isolate entrypoint
// ---------------------------------------------------------------------------

/// Worker entrypoint args:
///   [SendPort mainPort, int dbHandleAddr, int readerId, SendPort controlPort]
///
/// Receives [ReadRequest] messages via RawReceivePort. Small results are
/// sent back via the per-request replyPort (SendPort.send). Large results
/// are sent via Isolate.exit to [controlPort] for zero-copy transfer —
/// the pool routes onExit to the same control port, so the data message
/// is guaranteed to arrive before the exit notification (same-port FIFO).
void readerEntrypoint(List<Object> args) {
  final mainPort = args[0] as SendPort;
  final dbHandleAddr = args[1] as int;
  final readerId = args[2] as int;
  final controlPort = args[3] as SendPort;

  final receivePort = RawReceivePort();
  mainPort.send(receivePort.sendPort);

  receivePort.handler = (Object? message) {
    if (message == null) {
      receivePort.close();
      return;
    }

    final request = message as ReadRequest;

    try {
      final Object? result;
      final bool sacrifice;

      switch (request) {
        case SelectRequest(:final sql, :final parameters):
          final raw = executeQuery(dbHandleAddr, readerId, sql, parameters);
          sacrifice = raw.estimatedBytes > sacrificeByteThreshold;
          // On sacrifice, send raw components (primitives only) for reliable
          // Isolate.exit transfer. The pool reconstructs ResultSet on receipt.
          // On SendPort path, wrap eagerly — no transfer risk.
          result = sacrifice
              ? (raw.values, raw.schema.names, raw.rowCount)
              : ResultSet(raw.values, raw.schema, raw.rowCount);

        case SelectWithDepsRequest(:final sql, :final parameters):
          final (raw, readTables) = executeQueryWithDeps(
            dbHandleAddr, readerId, sql, parameters,
          );
          sacrifice = raw.estimatedBytes > sacrificeByteThreshold;
          result = sacrifice
              ? (raw.values, raw.schema.names, raw.rowCount, readTables)
              : (
                  ResultSet(raw.values, raw.schema, raw.rowCount)
                      as List<Map<String, Object?>>,
                  readTables,
                );

        case SelectBytesRequest(:final sql, :final parameters):
          final bytes = executeQueryBytes(dbHandleAddr, readerId, sql, parameters);
          result = bytes;
          sacrifice = bytes.length > sacrificeByteThreshold;

        case SelectIfChangedRequest(
          :final sql,
          :final parameters,
          :final lastResultHash,
        ):
          final raw = executeQuery(dbHandleAddr, readerId, sql, parameters);
          final newHash = hashRawResult(raw);
          if (newHash == lastResultHash) {
            result = (newHash, null);
            sacrifice = false;
          } else {
            sacrifice = raw.estimatedBytes > sacrificeByteThreshold;
            result = sacrifice
                ? (newHash, raw.values, raw.schema.names, raw.rowCount)
                : (newHash, ResultSet(raw.values, raw.schema, raw.rowCount)
                    as List<Map<String, Object?>>);
          }
      }

      if (sacrifice) {
        // Zero-copy transfer via Isolate.exit to the control port.
        // The pool's onExit is routed to the same port, so the VM's
        // same-port FIFO ordering guarantees this data arrives before
        // the onExit null notification.
        receivePort.close();
        Isolate.exit(controlPort, (result, true, null));
      }
      request.replyPort.send((result, false, null));
    } catch (e) {
      request.replyPort.send((null, false, e.toString()));
    }
  };
}

// ---------------------------------------------------------------------------
// FFI bindings for read path
// ---------------------------------------------------------------------------

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_column_count',
  isLeaf: true,
)
external int _sqlite3ColumnCount(ffi.Pointer<ffi.Void> stmt);

@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_name',
  isLeaf: true,
)
external ffi.Pointer<Utf8> _sqlite3ColumnName(
  ffi.Pointer<ffi.Void> stmt,
  int n,
);

// Dedicated reader variant — no pool mutex.
@ffi.Native<
  ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
  )
>(symbol: 'resqlite_stmt_acquire_on', isLeaf: true)
external ffi.Pointer<ffi.Void> _resqliteStmtAcquireOn(
  ffi.Pointer<ffi.Void> db,
  int readerId,
  ffi.Pointer<ffi.Void> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_step_row', isLeaf: true)
external int _resqliteStepRow(
  ffi.Pointer<ffi.Void> stmt,
  int colCount,
  ffi.Pointer<ffi.Uint8> cells,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'strlen',
  isLeaf: true,
)
external int _strlen(ffi.Pointer<ffi.Void> s);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int _sqliteRow = 100;
const int _sqliteInteger = 1;
const int _sqliteFloat = 2;
const int _sqliteText = 3;
const int _sqliteBlob = 4;

// Cell buffer layout: 16 bytes per cell (union-based).
const int _cellSize = 16;
const int _cellOffType = 0;
const int _cellOffLen = 4;
const int _cellOffVal = 8;

const int _asciiMask = 0x8080808080808080;

// Pre-computed typed-index strides.
const int _cellI32s = _cellSize ~/ 4; // 4
const int _cellI64s = _cellSize ~/ 8; // 2
const int _typeI32 = _cellOffType ~/ 4; // 0
const int _lenI32 = _cellOffLen ~/ 4; // 1
const int _valI64 = _cellOffVal ~/ 8; // 1

// ---------------------------------------------------------------------------
// Text decode
// ---------------------------------------------------------------------------

/// Fast text decode: ASCII fast-path with word-at-a-time check,
/// falls back to utf8.decode for multi-byte sequences.
@pragma('vm:prefer-inline')
String _fastDecodeText(ffi.Pointer<ffi.Uint8> ptr, int len) {
  final list = ptr.asTypedList(len);
  if (len >= 16 && ptr.address & 7 == 0) {
    final words = ptr.cast<ffi.Int64>().asTypedList(len >> 3);
    for (var i = 0; i < words.length; i++) {
      if (words[i] & _asciiMask != 0) return utf8.decode(list);
    }
    for (var i = (len >> 3) << 3; i < len; i++) {
      if (list[i] >= 0x80) return utf8.decode(list);
    }
  } else {
    for (var i = 0; i < len; i++) {
      if (list[i] >= 0x80) return utf8.decode(list);
    }
  }
  return String.fromCharCodes(list);
}

// ---------------------------------------------------------------------------
// Query execution — builds flat List<Object?> + RowSchema
// ---------------------------------------------------------------------------

/// Raw query result before wrapping in ResultSet.
final class RawQueryResult {
  RawQueryResult(
    this.values, this.schema, this.rowCount, this.colCount,
    this.estimatedBytes,
  );
  final List<Object?> values;
  final RowSchema schema;
  final int rowCount;
  final int colCount;

  /// Estimated byte size of the result data for sacrifice decisions.
  /// Accumulated during the cell loop: 8 bytes per int/double, byte length
  /// per string/blob, 0 per null. Cheap to compute — no second pass needed.
  final int estimatedBytes;
}

/// Execute a SELECT query on a dedicated reader (no pool mutex).
RawQueryResult executeQuery(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) {
  return _executeQueryImpl(handleAddr, readerId, sql, parameters).$1;
}

/// Hash a raw query result using the shared FNV-1a implementation.
int hashRawResult(RawQueryResult raw) =>
    hashValues(raw.rowCount, raw.values);

/// Execute a query returning JSON-encoded bytes on a dedicated reader.
Uint8List executeQueryBytes(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) {
  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
  final result = queryBytes(dbHandle, readerId, sql, parameters);
  // Copy from persistent reader buffer. Don't free — reader owns it.
  return Uint8List.fromList(result.ptr.asTypedList(result.length));
}

/// Execute a query on a dedicated reader and capture read dependencies.
(RawQueryResult, List<String>) executeQueryWithDeps(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) {
  final (raw, tables) = _executeQueryImpl(
    handleAddr, readerId, sql, parameters,
    captureReadTables: true,
  );
  return (raw, tables!);
}

/// Shared implementation for [executeQuery] and [executeQueryWithDeps].
///
/// Uses a dedicated reader (no pool mutex). Caller guarantees exclusive access
/// to this reader via the Dart pool's busy tracking.
(RawQueryResult, List<String>?) _executeQueryImpl(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters, {
  bool captureReadTables = false,
}) {
  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
  final sqlNative = sql.toNativeUtf8();
  final paramsNative = allocateParams(parameters);
  ffi.Pointer<ffi.Void> stmt;
  try {
    stmt = _resqliteStmtAcquireOn(
      dbHandle,
      readerId,
      sqlNative.cast(),
      paramsNative,
      parameters.length,
    );
    if (stmt == ffi.nullptr) throw StateError('Failed to acquire statement');
  } finally {
    // Only free SQL string here. Params must stay alive until after stepping
    // because bind_params uses SQLITE_STATIC (no copy).
    calloc.free(sqlNative);
  }

  try {
    final colCount = _sqlite3ColumnCount(stmt);
    final schema = _schemaCache[sql] ?? () {
      final s = RowSchema(List<String>.generate(colCount, (i) {
        final namePtr = _sqlite3ColumnName(stmt, i);
        final nameLen = _strlen(namePtr.cast());
        return _fastDecodeText(namePtr.cast<ffi.Uint8>(), nameLen);
      }, growable: false));
      _schemaCache[sql] = s;
      return s;
    }();

    final cellsBuf = _ensureCellBuffer(colCount);
    final cellsTyped = cellsBuf.asTypedList(_cellSize * colCount);
    final cellsI32 = Int32List.view(
      cellsTyped.buffer,
      cellsTyped.offsetInBytes,
      cellsTyped.length ~/ 4,
    );
    final cellsI64 = Int64List.view(
      cellsTyped.buffer,
      cellsTyped.offsetInBytes,
      cellsTyped.length ~/ 8,
    );
    final cellsF64 = Float64List.view(
      cellsTyped.buffer,
      cellsTyped.offsetInBytes,
      cellsTyped.length ~/ 8,
    );

    final values = List<Object?>.filled(colCount * 256, null, growable: true);
    var writeIdx = 0;
    var rowCount = 0;
    var byteEstimate = 0;

    try {
      while (_resqliteStepRow(stmt, colCount, cellsBuf) == _sqliteRow) {
        rowCount++;
        if (writeIdx + colCount > values.length) {
          values.length = values.length * 2;
        }
        for (var i = 0; i < colCount; i++) {
          final i32Base = i * _cellI32s;
          final i64Base = i * _cellI64s;
          final type = cellsI32[i32Base + _typeI32];

          switch (type) {
            case _sqliteInteger:
              values[writeIdx++] = cellsI64[i64Base + _valI64];
              byteEstimate += 8;
            case _sqliteFloat:
              values[writeIdx++] = cellsF64[i64Base + _valI64];
              byteEstimate += 8;
            case _sqliteText:
              final textAddr = cellsI64[i64Base + _valI64];
              final textLen = cellsI32[i32Base + _lenI32];
              byteEstimate += textLen;
              if (textLen == 0) {
                values[writeIdx++] = '';
              } else {
                values[writeIdx++] = _fastDecodeText(
                  ffi.Pointer<ffi.Uint8>.fromAddress(textAddr),
                  textLen,
                );
              }
            case _sqliteBlob:
              final blobAddr = cellsI64[i64Base + _valI64];
              final blobLen = cellsI32[i32Base + _lenI32];
              byteEstimate += blobLen;
              if (blobLen == 0) {
                values[writeIdx++] = Uint8List(0);
              } else {
                values[writeIdx++] = Uint8List.fromList(
                  ffi.Pointer<ffi.Uint8>.fromAddress(
                    blobAddr,
                  ).asTypedList(blobLen),
                );
              }
            default:
              values[writeIdx++] = null;
          }
        }
      }
    } finally {
      // Cell buffer persists across queries — no free.
    }

    values.length = writeIdx;
    final raw = RawQueryResult(values, schema, rowCount, colCount, byteEstimate);

    // Capture read dependencies before releasing the reader (if requested).
    final readTables = captureReadTables
        ? getReadTables(dbHandle, readerId)
        : null;

    return (raw, readTables);
  } finally {
    // Free params after stepping — SQLITE_STATIC bindings hold pointers into
    // the params buffer, so it must stay alive for the duration of the query.
    freeParams(paramsNative, parameters);
  }
}
