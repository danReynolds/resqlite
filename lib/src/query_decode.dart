/// Shared query result decoding — used by both reader and writer workers.
///
/// Contains the cell buffer, schema cache, fast text decode, and the
/// stepped-query decode loop. Each isolate gets its own copy of the
/// file-level globals (Dart isolates don't share top-level state).
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

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
external ffi.Pointer<Utf8> sqlite3ColumnName(
  ffi.Pointer<ffi.Void> stmt,
  int n,
);

@ffi.Native<
  ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Pointer<ffi.Uint8>)
>(symbol: 'resqlite_step_row', isLeaf: true)
external int resqliteStepRow(
  ffi.Pointer<ffi.Void> stmt,
  int colCount,
  ffi.Pointer<ffi.Uint8> cells,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'strlen',
  isLeaf: true,
)
external int cStrlen(ffi.Pointer<ffi.Void> s);

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int sqliteRow = 100;
const int sqliteInteger = 1;
const int sqliteFloat = 2;
const int sqliteText = 3;
const int sqliteBlob = 4;

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
int cellsBufColCount = 0;

ffi.Pointer<ffi.Uint8> ensureCellBuffer(int colCount) {
  if (colCount <= cellsBufColCount) return cellsBuf;
  if (cellsBuf != ffi.nullptr) calloc.free(cellsBuf);
  cellsBuf = calloc<ffi.Uint8>(cellSize * colCount);
  cellsBufColCount = colCount;
  return cellsBuf;
}

/// Per-worker schema cache. Column names for the same SQL are always identical,
/// so we cache RowSchema keyed by SQL string to avoid N FFI calls + N String
/// allocations per query on cache hit.
final Map<String, RowSchema> schemaCache = {};

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

// ---------------------------------------------------------------------------
// Stepped query decode
// ---------------------------------------------------------------------------

/// Decode a bound statement into a [RawQueryResult] using resqlite_step_row.
///
/// The statement must already be acquired and bound (via
/// `resqlite_stmt_acquire_on` or `resqlite_stmt_acquire_writer`).
/// The caller must NOT finalize the statement — it's owned by the C cache.
RawQueryResult decodeSteppedQuery(ffi.Pointer<ffi.Void> stmt, String sql) {
  final colCount = sqlite3ColumnCount(stmt);
  final schema = schemaCache[sql] ?? () {
    final s = RowSchema(List<String>.generate(colCount, (i) {
      final namePtr = sqlite3ColumnName(stmt, i);
      final nameLen = cStrlen(namePtr.cast());
      return fastDecodeText(namePtr.cast<ffi.Uint8>(), nameLen);
    }, growable: false));
    schemaCache[sql] = s;
    return s;
  }();

  final buf = ensureCellBuffer(colCount);
  final cellsTyped = buf.asTypedList(cellSize * colCount);
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

  while (resqliteStepRow(stmt, colCount, buf) == sqliteRow) {
    rowCount++;
    if (writeIdx + colCount > values.length) {
      values.length = values.length * 2;
    }
    for (var i = 0; i < colCount; i++) {
      final i32Base = i * cellI32s;
      final i64Base = i * cellI64s;
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

  values.length = writeIdx;
  return RawQueryResult(values, schema, rowCount, byteEstimate);
}
