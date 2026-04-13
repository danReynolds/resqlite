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
import '../result_hash.dart';
import '../row.dart';

// ---------------------------------------------------------------------------
// Request types — sent from pool to worker via SendPort
// ---------------------------------------------------------------------------

/// Base class for read requests sent from the pool to a worker isolate.
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
final class SelectIfChangedRequest extends ReadRequest {
  SelectIfChangedRequest(
    super.replyPort,
    super.sql,
    super.parameters,
    this.lastResultHash,
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

// ---------------------------------------------------------------------------
// Read worker isolate entrypoint
// ---------------------------------------------------------------------------

/// Worker entrypoint args:
///   [SendPort mainPort, int dbHandleAddr, int readerId, SendPort controlPort]
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
          result = ResultSet(raw.values, raw.schema, raw.rowCount);

        case SelectWithDepsRequest(:final sql, :final parameters):
          final (raw, readTables) = executeQueryWithDeps(
            dbHandleAddr,
            readerId,
            sql,
            parameters,
          );
          sacrifice = raw.estimatedBytes > sacrificeByteThreshold;
          result = (
            ResultSet(raw.values, raw.schema, raw.rowCount)
                as List<Map<String, Object?>>,
            readTables,
          );

        case SelectBytesRequest(:final sql, :final parameters):
          final bytes =
              executeQueryBytes(dbHandleAddr, readerId, sql, parameters);
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
            result = (
              newHash,
              ResultSet(raw.values, raw.schema, raw.rowCount)
                  as List<Map<String, Object?>>
            );
          }
      }

      if (sacrifice) {
        receivePort.close();
        Isolate.exit(controlPort, (result, true, null));
      }
      request.replyPort.send((result, false, null));
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
      request.replyPort.send((null, false, error));
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
    )>(symbol: 'resqlite_stmt_acquire_on', isLeaf: true)
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
int hashRawResult(RawQueryResult raw) => hashValues(raw.rowCount, raw.values);

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
    handleAddr,
    readerId,
    sql,
    parameters,
    captureReadTables: true,
  );
  return (raw, tables!);
}

/// Shared implementation for [executeQuery] and [executeQueryWithDeps].
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
    calloc.free(sqlNative);
  }

  try {
    final raw = decodeQuery(stmt, sql);

    final readTables =
        captureReadTables ? getReadTables(dbHandle, readerId) : null;

    return (raw, readTables);
  } finally {
    freeParams(paramsNative, parameters);
  }
}
