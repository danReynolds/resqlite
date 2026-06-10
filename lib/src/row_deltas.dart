/// Row delta value types and decoder (exp 160).
///
/// The writer's preupdate hook captures bounded per-row old/new values into
/// a native buffer (see `native/resqlite.h` for the byte layout); the write
/// worker drains it and ships the raw bytes to the main isolate, where the
/// stream engine decodes them lazily — only when at least one stream is
/// admitted for incremental maintenance.
library;

import 'dart:convert' show utf8;
import 'dart:typed_data';

/// SQLite preupdate op codes, as captured by the hook.
const int deltaOpDelete = 9; // SQLITE_DELETE
const int deltaOpInsert = 18; // SQLITE_INSERT
const int deltaOpUpdate = 23; // SQLITE_UPDATE

/// One modified row: full old/new column values indexed by the table's
/// column order (cid order from `PRAGMA table_info`).
final class RowDelta {
  const RowDelta({
    required this.op,
    required this.table,
    required this.oldRowid,
    required this.newRowid,
    required this.oldValues,
    required this.newValues,
  });

  final int op;
  final String table;
  final int oldRowid;
  final int newRowid;

  /// Pre-write values; `null` for INSERT.
  final List<Object?>? oldValues;

  /// Post-write values; `null` for DELETE.
  final List<Object?>? newValues;
}

/// Lazily-decoded view over one write cycle's delta bytes, grouped by
/// table.
///
/// Decodes at most once no matter how many admitted streams consult it;
/// a malformed buffer reports `null` for every table so all consumers
/// fall back to re-query. Construct one per write cycle and discard —
/// it carries no cross-cycle state.
final class RowDeltaBatch {
  RowDeltaBatch(this._bytes);

  final Uint8List _bytes;
  bool _decoded = false;
  Map<String, List<RowDelta>>? _byTable;

  /// Deltas for [table]; `null` when the buffer is malformed or holds no
  /// rows for the table.
  List<RowDelta>? forTable(String table) {
    if (!_decoded) {
      _decoded = true;
      final rows = decodeRowDeltas(_bytes);
      if (rows != null) {
        final byTable = <String, List<RowDelta>>{};
        for (final delta in rows) {
          (byTable[delta.table] ??= []).add(delta);
        }
        _byTable = byTable;
      }
    }
    return _byTable?[table];
  }
}

/// Decode a drained delta buffer.
///
/// Returns `null` on any structural inconsistency — callers treat that
/// exactly like an unreliable capture and fall back to re-query.
List<RowDelta>? decodeRowDeltas(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final deltas = <RowDelta>[];
  var off = 0;

  bool canRead(int n) => off + n <= bytes.length;

  List<Object?>? readCells(int colCount) {
    final values = List<Object?>.filled(colCount, null);
    for (var i = 0; i < colCount; i++) {
      if (!canRead(1)) return null;
      final tag = data.getUint8(off);
      off += 1;
      switch (tag) {
        case 0:
          values[i] = null;
        case 1:
          if (!canRead(8)) return null;
          values[i] = data.getInt64(off, Endian.little);
          off += 8;
        case 2:
          if (!canRead(8)) return null;
          values[i] = data.getFloat64(off, Endian.little);
          off += 8;
        case 3 || 4:
          if (!canRead(4)) return null;
          final len = data.getInt32(off, Endian.little);
          off += 4;
          if (len < 0 || !canRead(len)) return null;
          if (tag == 3) {
            values[i] = utf8.decode(
              Uint8List.sublistView(bytes, off, off + len),
            );
          } else {
            values[i] = Uint8List.fromList(
              Uint8List.sublistView(bytes, off, off + len),
            );
          }
          off += len;
        default:
          return null;
      }
    }
    return values;
  }

  while (off < bytes.length) {
    if (!canRead(1 + 4)) return null;
    final op = data.getUint8(off);
    off += 1;
    final tableLen = data.getInt32(off, Endian.little);
    off += 4;
    if (tableLen < 0 || !canRead(tableLen)) return null;
    final table = utf8.decode(
      Uint8List.sublistView(bytes, off, off + tableLen),
    );
    off += tableLen;
    if (!canRead(8 + 8 + 4 + 1 + 1)) return null;
    final oldRowid = data.getInt64(off, Endian.little);
    off += 8;
    final newRowid = data.getInt64(off, Endian.little);
    off += 8;
    final colCount = data.getInt32(off, Endian.little);
    off += 4;
    final hasOld = data.getUint8(off) != 0;
    off += 1;
    final hasNew = data.getUint8(off) != 0;
    off += 1;
    if (colCount < 0) return null;

    List<Object?>? oldValues;
    List<Object?>? newValues;
    if (hasOld) {
      oldValues = readCells(colCount);
      if (oldValues == null) return null;
    }
    if (hasNew) {
      newValues = readCells(colCount);
      if (newValues == null) return null;
    }
    if (!hasOld && !hasNew) return null;

    deltas.add(
      RowDelta(
        op: op,
        table: table,
        oldRowid: oldRowid,
        newRowid: newRowid,
        oldValues: oldValues,
        newValues: newValues,
      ),
    );
  }

  return deltas;
}
