/// Shared query result decoding — used by both reader and writer workers.
///
/// Contains the cell buffer, schema cache, fast text decode, and the
/// stepped-query decode loop. Each isolate gets its own copy of the
/// file-level globals (Dart isolates don't share top-level state).
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'row.dart';

// ---------------------------------------------------------------------------
// FFI bindings for the decode path
// ---------------------------------------------------------------------------

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_column_count',
  isLeaf: true,
)
external int sqlite3ColumnCount(ffi.Pointer<ffi.Void> stmt);

@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_name',
  isLeaf: true,
)
external ffi.Pointer<Utf8> sqlite3ColumnName(ffi.Pointer<ffi.Void> stmt, int n);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_step_row', isLeaf: true)
external int resqliteStepRow(
  ffi.Pointer<ffi.Void> stmt,
  int colCount,
  ffi.Pointer<ffi.Uint8> cells,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Int,
    ffi.Pointer<ffi.Uint8>,
    ffi.Pointer<ffi.Int>,
  )
>(symbol: 'resqlite_step_rows', isLeaf: true)
external int resqliteStepRows(
  ffi.Pointer<ffi.Void> stmt,
  int colCount,
  int maxRows,
  ffi.Pointer<ffi.Uint8> cells,
  ffi.Pointer<ffi.Int> outRowCount,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Uint8>,
    ffi.Pointer<ffi.Uint64>,
  )
>(symbol: 'resqlite_step_row_hash', isLeaf: true)
external int resqliteStepRowHash(
  ffi.Pointer<ffi.Void> stmt,
  int colCount,
  ffi.Pointer<ffi.Uint8> cells,
  ffi.Pointer<ffi.Uint64> hash,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Int,
    ffi.Pointer<ffi.Uint8>,
    ffi.Pointer<ffi.Int>,
    ffi.Pointer<ffi.Uint64>,
  )
>(symbol: 'resqlite_step_rows_hash', isLeaf: true)
external int resqliteStepRowsHash(
  ffi.Pointer<ffi.Void> stmt,
  int colCount,
  int maxRows,
  ffi.Pointer<ffi.Uint8> cells,
  ffi.Pointer<ffi.Int> outRowCount,
  ffi.Pointer<ffi.Uint64> hash,
);

// Hash-only pass ([EXP-075](../../experiments/075-native-hash-selectifchanged.md),
// extended in [EXP-077](../../experiments/077-cheap-check-first-sweep.md)).
//
// Steps the bound stmt to DONE, hashes every cell's raw bytes in C,
// resets at both ends, returns the hash.
//
// `lastRowCount` is -1 on the initial-query path (no prior count
// cached), or the previous emission's row count. When set,
// [EXP-077](../../experiments/077-cheap-check-first-sweep.md)
// short-circuits: if the fresh step count exceeds the cached value,
// stop folding cell bytes — the hashes can't match anyway. The function
// still drains the remaining rows to report the fresh count via
// `outRowCount`.
//
// Safe to call on a freshly-bound stmt (selectIfChanged first pass)
// or on one that decodeQuery just drained (initial-query baseline).
@ffi.Native<
  ffi.Int64 Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<ffi.Int>)
>(symbol: 'resqlite_query_hash', isLeaf: true)
external int resqliteQueryHash(
  ffi.Pointer<ffi.Void> stmt,
  int lastRowCount,
  ffi.Pointer<ffi.Int> outRowCount,
);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_db_handle',
  isLeaf: true,
)
external ffi.Pointer<ffi.Void> sqlite3DbHandle(ffi.Pointer<ffi.Void> stmt);

@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_errmsg',
  isLeaf: true,
)
external ffi.Pointer<Utf8> sqlite3Errmsg(ffi.Pointer<ffi.Void> db);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'strlen',
  isLeaf: true,
)
external int cStrlen(ffi.Pointer<ffi.Void> s);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int sqliteRow = 100;
const int sqliteDone = 101;
const int sqliteInteger = 1;
const int sqliteFloat = 2;
const int sqliteText = 3;
const int sqliteBlob = 4;

const int _fnvOffsetBasis = 0x4bf29ce484222325;
const int _fnvMask = 0x7FFFFFFFFFFFFFFF;
const int _fnvPrime = 0x100000001B3;

// Cell buffer layout: 16 bytes per cell (union-based).
const int cellSize = 16;
const int cellOffType = 0;
const int cellOffLen = 4;
const int cellOffVal = 8;

const int asciiMask = 0x8080808080808080;

// Pre-computed typed-index strides.
const int cellI32s = cellSize ~/ 4; // 4
const int cellI64s = cellSize ~/ 8; // 2
const int typeI32 = cellOffType ~/ 4; // 0
const int lenI32 = cellOffLen ~/ 4; // 1
const int valI64 = cellOffVal ~/ 8; // 1

// ---------------------------------------------------------------------------
// Per-isolate state (each worker gets its own copy)
// ---------------------------------------------------------------------------

/// Per-worker cell buffer. Reused across queries to avoid calloc/free per query.
ffi.Pointer<ffi.Uint8> cellsBuf = ffi.nullptr;
int cellsBufCellCount = 0;
Uint8List cellsTyped = Uint8List(0);
Int32List cellsI32 = Int32List(0);
Int64List cellsI64 = Int64List(0);
Float64List cellsF64 = Float64List(0);

ffi.Pointer<ffi.Uint8> ensureCellBuffer(int cellCount) {
  if (cellCount <= cellsBufCellCount) return cellsBuf;
  if (cellsBuf != ffi.nullptr) calloc.free(cellsBuf);
  cellsBuf = calloc<ffi.Uint8>(cellSize * cellCount);
  cellsBufCellCount = cellCount;
  cellsTyped = cellsBuf.asTypedList(cellSize * cellCount);
  cellsI32 = Int32List.view(
    cellsTyped.buffer,
    cellsTyped.offsetInBytes,
    cellsTyped.length ~/ 4,
  );
  cellsI64 = Int64List.view(
    cellsTyped.buffer,
    cellsTyped.offsetInBytes,
    cellsTyped.length ~/ 8,
  );
  cellsF64 = Float64List.view(
    cellsTyped.buffer,
    cellsTyped.offsetInBytes,
    cellsTyped.length ~/ 8,
  );
  return cellsBuf;
}

/// Per-worker scratch slot for the `outRowCount` out-parameter of
/// [resqliteQueryHash]. Allocated once per isolate, reused across every
/// stream re-query. Stays alive until the isolate dies.
final ffi.Pointer<ffi.Int> rowCountSlot = calloc<ffi.Int>(1);

/// Per-worker scratch slot for the one-pass initial stream decode+hash path.
final ffi.Pointer<ffi.Uint64> initialHashSlot = calloc<ffi.Uint64>(1);

/// Number of rows populated by the most recent batched native step.
final ffi.Pointer<ffi.Int> batchRowCountSlot = calloc<ffi.Int>(1);

/// Keep the persistent per-worker cell buffer bounded while still collapsing
/// the common narrow numeric scan to at most one FFI call per 64 rows.
const int _maxRowsPerStep = 64;
const int _targetCellBufferBytes = 64 * 1024;

int _rowsPerStep(int colCount) {
  if (colCount <= 0) return 1;
  final byBytes = _targetCellBufferBytes ~/ (cellSize * colCount);
  if (byBytes < 1) return 1;
  return byBytes < _maxRowsPerStep ? byBytes : _maxRowsPerStep;
}

/// Invoke [resqliteQueryHash] and return `(hash, rowCount)` as a record.
/// Small wrapper that hides the out-parameter pointer.
(int, int) callQueryHash(ffi.Pointer<ffi.Void> stmt, int lastRowCount) {
  final hash = resqliteQueryHash(stmt, lastRowCount, rowCountSlot);
  return (hash, rowCountSlot.value);
}

int _finishInitialHash(int hash, int rowCount) {
  if (rowCount == 0) return 0;
  return ((hash ^ rowCount) * _fnvPrime) & _fnvMask;
}

Never _throwStepException(ffi.Pointer<ffi.Void> stmt, String sql, int rc) {
  final db = sqlite3DbHandle(stmt);
  final message = db == ffi.nullptr
      ? 'sqlite3_step failed with code $rc'
      : sqlite3Errmsg(db).toDartString();
  throw ResqliteQueryException(message, sql: sql, sqliteCode: rc);
}

/// Per-worker schema cache with LRU eviction. Column names for the same SQL
/// are always identical, so we cache RowSchema keyed by SQL string to avoid
/// N FFI calls + N String allocations per query on cache hit.
///
/// Capped at [_schemaCacheMax] entries (matching the C-level statement cache)
/// to bound memory for apps with dynamic SQL. On eviction, the oldest entry
/// is removed (FIFO via insertion order of [LinkedHashMap]).
const int _schemaCacheMax = 32;
final Map<String, RowSchema> schemaCache = LinkedHashMap<String, RowSchema>();

RowSchema _schemaFor(ffi.Pointer<ffi.Void> stmt, String sql, int colCount) {
  var schema = schemaCache.remove(sql);
  if (schema != null) {
    // LRU promotion: re-insert so this entry moves to the end (most recent).
    schemaCache[sql] = schema;
    return schema;
  }

  schema = RowSchema(
    List<String>.generate(colCount, (i) {
      final namePtr = sqlite3ColumnName(stmt, i);
      final nameLen = cStrlen(namePtr.cast());
      return fastDecodeText(namePtr.cast<ffi.Uint8>(), nameLen);
    }, growable: false),
  );
  schemaCache[sql] = schema;
  if (schemaCache.length > _schemaCacheMax) {
    schemaCache.remove(schemaCache.keys.first);
  }
  return schema;
}

// ---------------------------------------------------------------------------
// Text decode
// ---------------------------------------------------------------------------

/// Fast text decode: ASCII fast-path with word-at-a-time check,
/// falls back to utf8.decode for multi-byte sequences.
@pragma('vm:prefer-inline')
String fastDecodeText(ffi.Pointer<ffi.Uint8> ptr, int len) {
  final list = ptr.asTypedList(len);
  if (len >= 16 && ptr.address & 7 == 0) {
    final words = ptr.cast<ffi.Int64>().asTypedList(len >> 3);
    for (var i = 0; i < words.length; i++) {
      if (words[i] & asciiMask != 0) return utf8.decode(list);
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
// Raw query result
// ---------------------------------------------------------------------------

/// Raw query result before wrapping in ResultSet.
final class RawQueryResult {
  RawQueryResult(this.values, this.schema, this.rowCount, this.estimatedBytes);
  final List<Object?> values;
  final RowSchema schema;
  final int rowCount;

  /// Estimated byte size of the result data, accumulated during the cell loop.
  /// Ints/doubles = 8 bytes, strings/blobs = their byte length, nulls = 0.
  final int estimatedBytes;
}

(int writeIdx, int byteEstimate) _decodeCellRows(
  List<Object?> values,
  int writeIdx,
  int byteEstimate,
  int rowCount,
  int colCount,
) {
  final requiredLength = writeIdx + rowCount * colCount;
  if (requiredLength > values.length) {
    var nextLength = values.length;
    if (nextLength == 0) nextLength = requiredLength;
    while (nextLength < requiredLength) {
      nextLength *= 2;
    }
    values.length = nextLength;
  }

  for (var row = 0; row < rowCount; row++) {
    final rowBase = row * colCount;
    for (var i = 0; i < colCount; i++) {
      final cellIndex = rowBase + i;
      final i32Base = cellIndex * cellI32s;
      final i64Base = cellIndex * cellI64s;
      final type = cellsI32[i32Base + typeI32];

      switch (type) {
        case sqliteInteger:
          values[writeIdx++] = cellsI64[i64Base + valI64];
          byteEstimate += 8;
        case sqliteFloat:
          values[writeIdx++] = cellsF64[i64Base + valI64];
          byteEstimate += 8;
        case sqliteText:
          final textAddr = cellsI64[i64Base + valI64];
          final textLen = cellsI32[i32Base + lenI32];
          byteEstimate += textLen;
          if (textLen == 0) {
            values[writeIdx++] = '';
          } else {
            values[writeIdx++] = fastDecodeText(
              ffi.Pointer<ffi.Uint8>.fromAddress(textAddr),
              textLen,
            );
          }
        case sqliteBlob:
          final blobAddr = cellsI64[i64Base + valI64];
          final blobLen = cellsI32[i32Base + lenI32];
          byteEstimate += blobLen;
          if (blobLen == 0) {
            values[writeIdx++] = Uint8List(0);
          } else {
            values[writeIdx++] = Uint8List.fromList(
              ffi.Pointer<ffi.Uint8>.fromAddress(blobAddr).asTypedList(blobLen),
            );
          }
        default:
          values[writeIdx++] = null;
      }
    }
  }

  return (writeIdx, byteEstimate);
}

// ---------------------------------------------------------------------------
// Query decoder
// ---------------------------------------------------------------------------

/// Decode a bound statement into a [RawQueryResult] using resqlite_step_row.
///
/// The statement must already be acquired and bound (via
/// `resqlite_stmt_acquire_on` or `resqlite_stmt_acquire_writer`).
/// The caller must NOT finalize the statement — it's owned by the C cache.
RawQueryResult decodeQuery(ffi.Pointer<ffi.Void> stmt, String sql) {
  final colCount = sqlite3ColumnCount(stmt);
  final schema = _schemaFor(stmt, sql, colCount);

  final rowsPerStep = _rowsPerStep(colCount);
  final buf = ensureCellBuffer(colCount * rowsPerStep);

  final values = List<Object?>.filled(colCount * 256, null, growable: true);
  var writeIdx = 0;
  var rowCount = 0;
  var byteEstimate = 0;

  while (true) {
    final rc = resqliteStepRows(
      stmt,
      colCount,
      rowsPerStep,
      buf,
      batchRowCountSlot,
    );
    final batchRows = batchRowCountSlot.value;
    if (batchRows > 0) {
      (writeIdx, byteEstimate) = _decodeCellRows(
        values,
        writeIdx,
        byteEstimate,
        batchRows,
        colCount,
      );
      rowCount += batchRows;
    }
    if (rc == sqliteDone) break;
    if (rc != sqliteRow) _throwStepException(stmt, sql, rc);
  }

  values.length = writeIdx;
  return RawQueryResult(values, schema, rowCount, byteEstimate);
}

/// Decode a bound statement and compute the stream result hash in the same
/// SQLite step pass. This is only used for initial stream registration; the
/// unchanged re-query path still uses [resqliteQueryHash] so it can skip Dart
/// decoding entirely.
(RawQueryResult, int) decodeQueryWithInitialHash(
  ffi.Pointer<ffi.Void> stmt,
  String sql,
) {
  final colCount = sqlite3ColumnCount(stmt);
  final schema = _schemaFor(stmt, sql, colCount);

  final rowsPerStep = _rowsPerStep(colCount);
  final buf = ensureCellBuffer(colCount * rowsPerStep);

  final values = List<Object?>.filled(colCount * 256, null, growable: true);
  var writeIdx = 0;
  var rowCount = 0;
  var byteEstimate = 0;
  initialHashSlot.value = _fnvOffsetBasis;

  while (true) {
    final rc = resqliteStepRowsHash(
      stmt,
      colCount,
      rowsPerStep,
      buf,
      batchRowCountSlot,
      initialHashSlot,
    );
    final batchRows = batchRowCountSlot.value;
    if (batchRows > 0) {
      (writeIdx, byteEstimate) = _decodeCellRows(
        values,
        writeIdx,
        byteEstimate,
        batchRows,
        colCount,
      );
      rowCount += batchRows;
    }
    if (rc == sqliteDone) break;
    if (rc != sqliteRow) _throwStepException(stmt, sql, rc);
  }

  values.length = writeIdx;
  final raw = RawQueryResult(values, schema, rowCount, byteEstimate);
  return (raw, _finishInitialHash(initialHashSlot.value, rowCount));
}
