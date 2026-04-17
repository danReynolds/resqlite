/// Read worker — isolate entrypoint and query execution for the reader pool.
///
/// The actual cell decode loop, schema cache, and text decode live in
/// query_decode.dart (shared with the writer). This file owns the reader-
/// specific FFI bindings, the sacrifice decision, and the isolate protocol.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../exceptions.dart';
import '../native/resqlite_bindings.dart';
import '../query_decoder.dart';
import '../row.dart';

// ---------------------------------------------------------------------------
// Request types — sent from pool to worker via SendPort
// ---------------------------------------------------------------------------

/// Base class for read requests sent from the pool to a worker isolate.
sealed class ReadRequest {
  ReadRequest(this.sql, this.parameters);
  final String sql;
  final List<Object?> parameters;
}

/// Standard row query — returns a [ResultSet].
final class SelectRequest extends ReadRequest {
  SelectRequest(super.sql, super.parameters);
}

/// Row query that also captures read table dependencies via the SQLite
/// authorizer hook. Used for initial stream registration in [StreamEngine].
final class SelectWithDepsRequest extends ReadRequest {
  SelectWithDepsRequest(super.sql, super.parameters);
}

/// JSON bytes query — serialized entirely in C, no Dart objects for result data.
final class SelectBytesRequest extends ReadRequest {
  SelectBytesRequest(super.sql, super.parameters);
}

/// Stream re-query with worker-side hash comparison.
final class SelectIfChangedRequest extends ReadRequest {
  SelectIfChangedRequest(
    super.sql,
    super.parameters,
    this.lastResultHash,
    this.lastRowCount,
  );
  final int lastResultHash;

  /// Previously-emitted row count, or `-1` if unknown. Passed into
  /// `resqlite_query_hash` to enable the exp 077 short-circuit when
  /// the fresh row count already diverges.
  final int lastRowCount;
}

/// Byte-size threshold for sacrifice. If the estimated transfer size of
/// a result exceeds this, the worker uses Isolate.exit (zero-copy) instead
/// of SendPort.send (memcpy). Below this threshold the copy is sub-millisecond;
/// above it the zero-copy transfer outweighs the ~2-5ms respawn cost.
///
/// Applies to both row results (estimated during the cell loop) and
/// selectBytes results (exact byte length of the JSON buffer).
const int sacrificeByteThreshold = 256 * 1024; // 256 KB

// ---------------------------------------------------------------------------
// Read worker isolate entrypoint
// ---------------------------------------------------------------------------

/// Worker entrypoint args:
///   [int dbHandleAddr, int readerId, SendPort eventPort]
void readerEntrypoint(List<Object> args) {
  final dbHandleAddr = args[0] as int;
  final readerId = args[1] as int;
  final eventPort = args[2] as SendPort;

  final receivePort = RawReceivePort();
  eventPort.send(receivePort.sendPort);

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
          result = _toRows(raw);

        case SelectWithDepsRequest(:final sql, :final parameters):
          // Initial stream query produces hash + row-count baselines
          // (exp 075 + 077) so future selectIfChanged calls can
          // short-circuit on unchanged state.
          final (raw, readTables, initialHash, initialRowCount) =
              executeQueryWithDeps(
            dbHandleAddr, readerId, sql, parameters,
          );
          sacrifice = raw.estimatedBytes > sacrificeByteThreshold;
          result = (_toRows(raw), readTables, initialHash, initialRowCount);

        case SelectBytesRequest(:final sql, :final parameters):
          final bytes =
              executeQueryBytes(dbHandleAddr, readerId, sql, parameters);
          sacrifice = bytes.length > sacrificeByteThreshold;
          result = bytes;

        case SelectIfChangedRequest(
          :final sql,
          :final parameters,
          :final lastResultHash,
          :final lastRowCount,
        ):
          // Two-pass selectIfChanged (exp 075). Row-count short-circuit
          // (exp 077) stops the hash walk early if count-differ is already
          // evident, so the changed case pays less pass-1 work.
          final (newHash, newRowCount, raw) = executeQueryIfChanged(
            dbHandleAddr,
            readerId,
            sql,
            parameters,
            lastResultHash,
            lastRowCount,
          );
          sacrifice =
              raw != null && raw.estimatedBytes > sacrificeByteThreshold;
          result = (
            raw == null ? null : _toRows(raw),
            newHash,
            newRowCount,
          );
      }

      if (sacrifice) {
        receivePort.close();
        Isolate.exit(eventPort, (result, true, null));
      }
      eventPort.send((result, false, null));
    } catch (e) {
      // Same-group isolates (Isolate.spawn) can send arbitrary objects
      // via SendPort — the VM deep-copies them. Wrap non-resqlite errors
      // with the request's SQL context so callers always get a typed
      // exception with sql/parameters intact.
      final error = e is ResqliteException
          ? e
          : ResqliteQueryException(
              e.toString(),
              sql: request.sql,
              parameters: request.parameters,
            );
      eventPort.send((null, false, error));
    }
  };
}

// ---------------------------------------------------------------------------
// Reader-specific FFI bindings
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Query execution
// ---------------------------------------------------------------------------

/// Wrap a decoded result in a lazy `ResultSet` view and up-cast to the
/// `List<Map<String, Object?>>` shape the pool / stream engine consumes.
/// The cast is a type-system formality — `ResultSet implements List<Row>`
/// and `Row implements Map<String, Object?>`, so it's always safe.
List<Map<String, Object?>> _toRows(RawQueryResult raw) =>
    ResultSet(raw.values, raw.schema, raw.rowCount)
        as List<Map<String, Object?>>;

/// Acquire the stmt on the dedicated reader, run `body`, and release
/// native params + SQL buffer. All `executeQuery*` helpers below share
/// this setup/cleanup — the only piece that differs between them is
/// what they do with the bound stmt.
T _withAcquiredStmt<T>(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
  T Function(ffi.Pointer<ffi.Void> dbHandle, ffi.Pointer<ffi.Void> stmt) body,
) {
  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
  final sqlNative = sql.toNativeUtf8();
  final paramsNative = allocateParams(parameters);
  try {
    final stmt = _resqliteStmtAcquireOn(
      dbHandle,
      readerId,
      sqlNative.cast(),
      paramsNative,
      parameters.length,
    );
    if (stmt == ffi.nullptr) {
      throw ResqliteQueryException(
        resqliteErrmsg(dbHandle).toDartString(),
        sql: sql,
        parameters: parameters,
      );
    }
    return body(dbHandle, stmt);
  } finally {
    freeParams(paramsNative, parameters);
    calloc.free(sqlNative);
  }
}

/// Execute a SELECT query on a dedicated reader (no pool mutex).
RawQueryResult executeQuery(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) =>
    _withAcquiredStmt(
      handleAddr,
      readerId,
      sql,
      parameters,
      (_, stmt) => decodeQuery(stmt, sql),
    );

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

/// Execute a stream's initial query.
///
/// Returns the rows, the authorizer-captured read tables, the C-computed
/// baseline hash (exp 075), and the row count (exp 077 — cached so
/// subsequent selectIfChanged calls can short-circuit on count mismatch).
(RawQueryResult, List<String>, int, int) executeQueryWithDeps(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) =>
    _withAcquiredStmt(handleAddr, readerId, sql, parameters, (dbHandle, stmt) {
      final raw = decodeQuery(stmt, sql);
      // Pass -1 to opt out of the row-count short-circuit: on the
      // initial query we don't have a baseline count to compare against.
      final (hash, rowCount) = callQueryHash(stmt, -1);
      final readTables = getReadTables(dbHandle, readerId);
      return (raw, readTables, hash, rowCount);
    });

/// Two-pass selectIfChanged (experiment 075 + row-count short-circuit 077).
///
/// Pass 1: `resqliteQueryHash` steps + hashes the bound stmt in C. If
/// the fresh hash matches the stream's last-emitted value AND the row
/// count matches the cached one, return `(hash, rowCount, null)` — the
/// subscriber is up to date, no Dart decode needed.
///
/// Pass 2 (on mismatch): re-step the same stmt through `decodeQuery`.
/// `resqliteQueryHash` resets the stmt on exit, and bindings survive
/// reset, so no re-acquire is required. The pass-1 hash is reused as
/// the new baseline.
(int, int, RawQueryResult?) executeQueryIfChanged(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
  int lastResultHash,
  int lastRowCount,
) =>
    _withAcquiredStmt(handleAddr, readerId, sql, parameters, (_, stmt) {
      final (newHash, newRowCount) = callQueryHash(stmt, lastRowCount);
      if (newHash == lastResultHash && newRowCount == lastRowCount) {
        return (newHash, newRowCount, null);
      }
      return (newHash, newRowCount, decodeQuery(stmt, sql));
    });
