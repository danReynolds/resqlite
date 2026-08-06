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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'blob_transfer.dart' show BlobTransfer;
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

// Hash-only pass ([EXP-075](../../experiments/075-native-hash-selectifchanged.md)).
//
// Steps the bound stmt to DONE, hashes every cell's raw bytes in C,
// resets at both ends, returns the hash.
//
// Safe to call on a freshly-bound stmt (selectIfChanged first pass)
// or on one that decodeQuery just drained (initial-query baseline).
@ffi.Native<ffi.Int64 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int>)>(
  symbol: 'resqlite_query_hash',
  isLeaf: true,
)
external int resqliteQueryHash(
  ffi.Pointer<ffi.Void> stmt,
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

/// Cell type the native step loop reports for a TEXT value whose bytes are all
/// below 0x80 (`RESQLITE_TEXT_ASCII` in `resqlite.h`). Such a value decodes
/// with a plain [String.fromCharCodes] widen; plain [sqliteText] means the
/// native scan found a multi-byte sequence and the cell needs [utf8.decode].
const int sqliteTextAscii = 6;

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
int cellsBufColCount = 0;
Uint8List cellsTyped = Uint8List(0);
Int32List cellsI32 = Int32List(0);
Int64List cellsI64 = Int64List(0);
Float64List cellsF64 = Float64List(0);

ffi.Pointer<ffi.Uint8> ensureCellBuffer(int colCount) {
  if (colCount <= cellsBufColCount) return cellsBuf;
  if (cellsBuf != ffi.nullptr) calloc.free(cellsBuf);
  cellsBuf = calloc<ffi.Uint8>(cellSize * colCount);
  cellsBufColCount = colCount;
  cellsTyped = cellsBuf.asTypedList(cellSize * colCount);
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

/// Invoke [resqliteQueryHash] and return `(hash, rowCount)` as a record.
/// Small wrapper that hides the out-parameter pointer.
(int, int) callQueryHash(ffi.Pointer<ffi.Void> stmt) {
  final hash = resqliteQueryHash(stmt, rowCountSlot);
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

/// What one SQL string's result size has looked like over its last two
/// executions ([EXP-260](../../experiments/260-result-list-presize.md)).
///
/// Both figures stay 0 until two executions have been observed, because a
/// single observation is not enough to size against: a statement whose row
/// count swings with its parameters (`SELECT ... LIMIT ?`) would be sized from
/// whichever leg happened to run first.
///
/// The two ends of the buffer's life want opposite statistics, and each takes
/// the one whose mistakes are cheap:
///
///  * [hint] steers *growth*, so it takes the **smaller** of the two row counts
///    plus headroom. Over-sizing a growth is the expensive mistake there —
///    zero-filling slots a small result throws away costs more than the
///    doubling it avoided — and a result that never overflows the initial
///    buffer never reads this field at all.
///  * [initialRows] sizes the *initial* allocation, so it takes the **larger**
///    of the two plus headroom, capped at [initialResultRows]. Under-sizing is
///    the expensive mistake here, because a result that outgrows its first
///    buffer pays doublings to catch up. The cap is what keeps the field from
///    reintroducing the failure exp 260 measured: it can only ever make the
///    initial allocation *smaller* than the fixed default, never larger, so a
///    statement whose row count swings upward is bounded by today's behaviour.
final class RowSizeMemory {
  /// Rows the most recent execution returned, or -1 before the first.
  int previous = -1;

  /// Rows to size the next execution's buffer growth for, or 0 for "no
  /// opinion".
  int hint = 0;

  /// Rows to size the next execution's *initial* buffer for, or 0 for "no
  /// opinion" (meaning [initialResultRows]). Never exceeds
  /// [initialResultRows].
  int initialRows = 0;

  void record(int rowCount) {
    if (previous < 0) {
      previous = rowCount;
      return;
    }
    final low = rowCount < previous ? rowCount : previous;
    final high = rowCount < previous ? previous : rowCount;
    hint = nextRowHint(low);
    initialRows = initialRowsFor(high);
    previous = rowCount;
  }
}

/// Rows to size an initial result buffer for, given that the largest of this
/// SQL's last two executions returned [rowCount] rows.
///
/// Clamped into `1 ..= initialResultRows`: at least one row so the decode loop
/// always has somewhere to write its first cell, and never more than the fixed
/// default so this can only shrink an allocation.
@pragma('vm:prefer-inline')
int initialRowsFor(int rowCount) {
  final hinted = nextRowHint(rowCount);
  if (hinted >= initialResultRows) return initialResultRows;
  return hinted < 1 ? 1 : hinted;
}

/// Per-worker schema cache entry: the column names for a SQL string, plus what
/// that SQL's results have measured on this isolate.
final class CachedSchema {
  CachedSchema(this.schema);

  final RowSchema schema;

  /// Fallback size hint for callers that bring none of their own. The reader
  /// pool supplies a hint that survives worker sacrifice; the writer isolate,
  /// which is long-lived and never sacrificed, has only this.
  final RowSizeMemory size = RowSizeMemory();
}

/// Rows the initial result buffer is sized for while nothing is known about
/// the result — the first two executions of a SQL string, and every execution
/// of one whose column names have been evicted from [schemaCache].
///
/// [EXP-067](../../experiments/067-shrink-initial-allocation.md) shrank this
/// constant for *every* query and regressed the small-query workloads, because
/// a result larger than the new size then had to double its way up from four
/// rows. [EXP-264](../../experiments/264-initial-alloc-size-memory.md) shrinks
/// it only for a statement that has twice returned few enough rows to fit,
/// through [RowSizeMemory.initialRows], and leaves this constant as the
/// no-knowledge default.
const int initialResultRows = 256;

/// Slots to grow a [colCount]-column result buffer to, from [current] slots,
/// when the SQL is expected to return [rowHint] rows (0 = no expectation).
///
/// A hint is deliberately applied here rather than to the initial allocation.
/// By the time the buffer overflows, the result has already proven it is larger
/// than [initialResultRows], so acting on the hint cannot make a small result
/// allocate a large buffer — a query that returns fewer rows than the initial
/// allocation holds never reaches this code and is byte-identical to a build
/// with no hint at all. That matters because the hint is keyed by SQL, and a
/// statement whose row count swings with its parameters (`SELECT ... LIMIT ?`)
/// would otherwise pay a large zero-fill on every small execution — a cost that
/// measured well above the doubling it was meant to avoid.
@pragma('vm:prefer-inline')
int grownSlots(int colCount, int current, int rowHint) {
  final doubled = current * 2;
  final hinted = colCount * rowHint;
  return hinted > doubled ? hinted : doubled;
}

/// Rows to size this execution's initial result buffer for.
///
/// Reads the *worker-local* [RowSizeMemory] rather than the hint the reader pool
/// stamps on the request, and the asymmetry is deliberate
/// ([EXP-264](../../experiments/264-initial-alloc-size-memory.md)). Exp 260 had
/// to keep its growth hint on the main isolate because a result above
/// `sacrificeSlotThreshold` returns via `Isolate.exit` and ends the worker that
/// produced it, discarding anything that worker learned. This hint only ever
/// describes a result small enough to fit in the initial buffer, and such a
/// result never triggers a sacrifice — so the worker that measured it is still
/// alive to use it, and reading it costs the main isolate nothing.
///
/// The pool's hint is also structurally unable to help here: it exists only for
/// statements that have returned more rows than [initialResultRows], and those
/// clamp straight back to [initialResultRows].
@pragma('vm:prefer-inline')
int initialSlotRows(RowSizeMemory size) {
  final rows = size.initialRows;
  return rows == 0 ? initialResultRows : rows;
}

/// Row hint to carry into the next execution of a SQL that just returned
/// [rowCount] rows. The 25% headroom absorbs a result that grows slightly
/// between executions without paying a doubling.
@pragma('vm:prefer-inline')
int nextRowHint(int rowCount) => rowCount + (rowCount >> 2);

/// Per-worker schema cache with LRU eviction. Column names for the same SQL
/// are always identical, so we cache RowSchema keyed by SQL string to avoid
/// N FFI calls + N String allocations per query on cache hit.
///
/// Capped at [_schemaCacheMax] entries (matching the C-level statement cache)
/// to bound memory for apps with dynamic SQL. On eviction, the oldest entry
/// is removed (FIFO via insertion order of [LinkedHashMap]).
const int _schemaCacheMax = 32;
final Map<String, CachedSchema> schemaCache =
    LinkedHashMap<String, CachedSchema>();

CachedSchema _schemaFor(ffi.Pointer<ffi.Void> stmt, String sql, int colCount) {
  var entry = schemaCache.remove(sql);
  if (entry != null) {
    // LRU promotion: re-insert so this entry moves to the end (most recent).
    schemaCache[sql] = entry;
    return entry;
  }

  entry = CachedSchema(
    RowSchema(
      List<String>.generate(colCount, (i) {
        final namePtr = sqlite3ColumnName(stmt, i);
        final nameLen = cStrlen(namePtr.cast());
        return fastDecodeText(namePtr.cast<ffi.Uint8>(), nameLen);
      }, growable: false),
    ),
  );
  schemaCache[sql] = entry;
  if (schemaCache.length > _schemaCacheMax) {
    schemaCache.remove(schemaCache.keys.first);
  }
  return entry;
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
  RawQueryResult(
    this.values,
    this.schema,
    this.rowCount, {
    required this.hasWrappedCells,
  });
  final List<Object?> values;
  final RowSchema schema;
  final int rowCount;

  /// Whether any cell was wrapped in [TransferableTypedData]. Lets the receive
  /// boundary skip its scan entirely when nothing needs materializing.
  final bool hasWrappedCells;

  /// The one conversion from decoded result to caller-facing [ResultSet].
  ///
  /// Threads [hasWrappedCells] across the isolate hop so the main-isolate
  /// receive boundary knows whether [materializeTransferableBlobCells] has any
  /// work; build decode-derived [ResultSet]s through this, not by hand.
  ResultSet toResultSet() =>
      ResultSet(values, schema, rowCount, hasWrappedCells: hasWrappedCells);
}

// ---------------------------------------------------------------------------
// Query decoder
// ---------------------------------------------------------------------------

/// Decode a bound statement into a [RawQueryResult] using resqlite_step_row.
///
/// The statement must already be acquired and bound (via
/// `resqlite_stmt_acquire_on` or `resqlite_stmt_acquire_writer`).
/// The caller must NOT finalize the statement — it's owned by the C cache.
RawQueryResult decodeQuery(
  ffi.Pointer<ffi.Void> stmt,
  String sql, {
  int rowHint = 0,
}) {
  final colCount = sqlite3ColumnCount(stmt);
  final entry = _schemaFor(stmt, sql, colCount);
  final schema = entry.schema;

  final buf = ensureCellBuffer(colCount);

  final hint = rowHint == 0 ? entry.size.hint : rowHint;
  final values = List<Object?>.filled(
    colCount * initialSlotRows(entry.size),
    null,
    growable: true,
  );
  var writeIdx = 0;
  var rowCount = 0;
  var hasWrappedCells = false;

  var rc = resqliteStepRow(stmt, colCount, buf);
  while (rc == sqliteRow) {
    rowCount++;
    if (writeIdx + colCount > values.length) {
      values.length = grownSlots(colCount, values.length, hint);
    }
    for (var i = 0; i < colCount; i++) {
      final i32Base = i * cellI32s;
      final i64Base = i * cellI64s;
      final type = cellsI32[i32Base + typeI32];

      switch (type) {
        case sqliteInteger:
          values[writeIdx++] = cellsI64[i64Base + valI64];
        case sqliteFloat:
          values[writeIdx++] = cellsF64[i64Base + valI64];
        case sqliteTextAscii:
          final textLen = cellsI32[i32Base + lenI32];
          if (textLen == 0) {
            values[writeIdx++] = '';
          } else {
            values[writeIdx++] = String.fromCharCodes(
              ffi.Pointer<ffi.Uint8>.fromAddress(
                cellsI64[i64Base + valI64],
              ).asTypedList(textLen),
            );
          }
        case sqliteText:
          // Reported only when the native scan found a byte >= 0x80, so this
          // arm goes straight to UTF-8. Empty text always classifies as ASCII.
          values[writeIdx++] = utf8.decode(
            ffi.Pointer<ffi.Uint8>.fromAddress(
              cellsI64[i64Base + valI64],
            ).asTypedList(cellsI32[i32Base + lenI32]),
          );
        case sqliteBlob:
          final blobAddr = cellsI64[i64Base + valI64];
          final blobLen = cellsI32[i32Base + lenI32];
          if (blobLen == 0) {
            values[writeIdx++] = Uint8List(0);
          } else if (blobLen >= BlobTransfer.cellThreshold) {
            hasWrappedCells = true;
            // Copies native -> external instead of native -> heap; see
            // [BlobTransfer.cellThreshold].
            values[writeIdx++] = TransferableTypedData.fromList([
              ffi.Pointer<ffi.Uint8>.fromAddress(blobAddr).asTypedList(blobLen),
            ]);
          } else {
            values[writeIdx++] = Uint8List.fromList(
              ffi.Pointer<ffi.Uint8>.fromAddress(blobAddr).asTypedList(blobLen),
            );
          }
        default:
          values[writeIdx++] = null;
      }
    }
    rc = resqliteStepRow(stmt, colCount, buf);
  }
  if (rc != sqliteDone) _throwStepException(stmt, sql, rc);

  entry.size.record(rowCount);
  values.length = writeIdx;
  return RawQueryResult(
    values,
    schema,
    rowCount,
    hasWrappedCells: hasWrappedCells,
  );
}

/// Decode a bound statement and compute the stream result hash in the same
/// SQLite step pass. This is only used for initial stream registration; the
/// unchanged re-query path still uses [resqliteQueryHash] so it can skip Dart
/// decoding entirely.
(RawQueryResult, int) decodeQueryWithInitialHash(
  ffi.Pointer<ffi.Void> stmt,
  String sql, {
  int rowHint = 0,
}) {
  final colCount = sqlite3ColumnCount(stmt);
  final entry = _schemaFor(stmt, sql, colCount);
  final schema = entry.schema;

  final buf = ensureCellBuffer(colCount);

  final hint = rowHint == 0 ? entry.size.hint : rowHint;
  final values = List<Object?>.filled(
    colCount * initialSlotRows(entry.size),
    null,
    growable: true,
  );
  var writeIdx = 0;
  var rowCount = 0;
  var hasWrappedCells = false;
  initialHashSlot.value = _fnvOffsetBasis;

  var rc = resqliteStepRowHash(stmt, colCount, buf, initialHashSlot);
  while (rc == sqliteRow) {
    rowCount++;
    if (writeIdx + colCount > values.length) {
      values.length = grownSlots(colCount, values.length, hint);
    }
    for (var i = 0; i < colCount; i++) {
      final i32Base = i * cellI32s;
      final i64Base = i * cellI64s;
      final type = cellsI32[i32Base + typeI32];

      switch (type) {
        case sqliteInteger:
          values[writeIdx++] = cellsI64[i64Base + valI64];
        case sqliteFloat:
          values[writeIdx++] = cellsF64[i64Base + valI64];
        case sqliteTextAscii:
          final textLen = cellsI32[i32Base + lenI32];
          if (textLen == 0) {
            values[writeIdx++] = '';
          } else {
            values[writeIdx++] = String.fromCharCodes(
              ffi.Pointer<ffi.Uint8>.fromAddress(
                cellsI64[i64Base + valI64],
              ).asTypedList(textLen),
            );
          }
        case sqliteText:
          // Reported only when the native scan found a byte >= 0x80, so this
          // arm goes straight to UTF-8. Empty text always classifies as ASCII.
          values[writeIdx++] = utf8.decode(
            ffi.Pointer<ffi.Uint8>.fromAddress(
              cellsI64[i64Base + valI64],
            ).asTypedList(cellsI32[i32Base + lenI32]),
          );
        case sqliteBlob:
          final blobAddr = cellsI64[i64Base + valI64];
          final blobLen = cellsI32[i32Base + lenI32];
          if (blobLen == 0) {
            values[writeIdx++] = Uint8List(0);
          } else if (blobLen >= BlobTransfer.cellThreshold) {
            hasWrappedCells = true;
            // Copies native -> external instead of native -> heap; see
            // [BlobTransfer.cellThreshold].
            values[writeIdx++] = TransferableTypedData.fromList([
              ffi.Pointer<ffi.Uint8>.fromAddress(blobAddr).asTypedList(blobLen),
            ]);
          } else {
            values[writeIdx++] = Uint8List.fromList(
              ffi.Pointer<ffi.Uint8>.fromAddress(blobAddr).asTypedList(blobLen),
            );
          }
        default:
          values[writeIdx++] = null;
      }
    }
    rc = resqliteStepRowHash(stmt, colCount, buf, initialHashSlot);
  }
  if (rc != sqliteDone) _throwStepException(stmt, sql, rc);

  entry.size.record(rowCount);
  values.length = writeIdx;
  final raw = RawQueryResult(
    values,
    schema,
    rowCount,
    hasWrappedCells: hasWrappedCells,
  );
  return (raw, _finishInitialHash(initialHashSlot.value, rowCount));
}
