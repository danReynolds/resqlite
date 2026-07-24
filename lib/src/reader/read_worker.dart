/// Read worker — isolate entrypoint and query execution for the reader pool.
///
/// The actual cell decode loop, schema cache, and text decode live in
/// query_decode.dart (shared with the writer). This file owns the reader-
/// specific FFI bindings, the sacrifice decision, and the isolate protocol.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:developer' show Timeline;
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../dependency_tracking.dart';
import '../exceptions.dart';
import '../native/request_cache.dart';
import '../native/resqlite_bindings.dart';
import '../profile_mode.dart';
import '../query_decoder.dart';
import '../row.dart';
import '../tracelite_profile.dart';

// ---------------------------------------------------------------------------
// Request types — sent from pool to worker via SendPort
// ---------------------------------------------------------------------------

/// Base class for read requests sent from the pool to a worker isolate.
sealed class ReadRequest {
  ReadRequest(this.sql, this.parameters, {this.traceCorrelationId});
  final String sql;
  final List<Object?> parameters;
  final int? traceCorrelationId;
}

/// Standard row query — returns a [ResultSet].
final class SelectRequest extends ReadRequest {
  SelectRequest(super.sql, super.parameters, {super.traceCorrelationId});
}

/// Row query that also captures read table dependencies via the SQLite
/// authorizer hook. Used for initial stream registration in [StreamEngine].
final class SelectWithDepsRequest extends ReadRequest {
  SelectWithDepsRequest(
    super.sql,
    super.parameters, {
    super.traceCorrelationId,
  });
}

/// JSON bytes query — serialized entirely in C, no Dart objects for result data.
final class SelectBytesRequest extends ReadRequest {
  SelectBytesRequest(super.sql, super.parameters, {super.traceCorrelationId});
}

/// Stream re-query with worker-side hash comparison.
final class SelectIfChangedRequest extends ReadRequest {
  SelectIfChangedRequest(
    super.sql,
    super.parameters,
    this.lastResultHash,
    this.lastRowCount, {
    super.traceCorrelationId,
  });
  final int lastResultHash;

  /// Previously-emitted row count, or `-1` if unknown. Compared with the
  /// fresh count alongside the canonical result hash.
  final int lastRowCount;
}

/// Byte-size threshold for sacrifice. If the estimated transfer size of
/// a result exceeds this, the worker uses Isolate.exit (zero-copy) instead
/// of SendPort.send (memcpy). Below this threshold the copy is sub-millisecond;
/// above it the zero-copy transfer outweighs the ~2-5ms respawn cost.
///
/// Applies to both row results (estimated during the cell loop) and
/// selectBytes results (exact byte length of the JSON buffer).
///
/// [EXP-244] Compile-time define (benchmark scaffolding — reverted before
/// merge) so the burst harness can force the no-sacrifice "send" lane by
/// setting the threshold above every tested result. Default unchanged.
const int sacrificeByteThreshold = int.fromEnvironment(
  'RESQLITE_SACRIFICE_THRESHOLD',
  defaultValue: 256 * 1024, // 256 KB
);

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

    // Mark this worker's dedicated reader connection busy so
    // Database.diagnostics() (sqlite3_db_status from the main isolate)
    // skips it while we're stepping over it — the connections are
    // NOMUTEX, so a concurrent status read is a data race. Cleared in
    // `finally` below, and explicitly before Isolate.exit on the
    // sacrifice path (exit skips finally).
    resqliteReaderSetBusy(
      ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr),
      readerId,
      1,
    );

    // Timeline marker scopes the reader-isolate's per-message work so
    // external profilers can see the cross-isolate breakdown. Gated
    // behind `kProfileMode` (compile-time const) so release builds pay
    // zero — the const-false branch tree-shakes away at AOT. Build with
    // `-DRESQLITE_PROFILE=true` to enable. See lib/src/profile_mode.dart.
    if (kProfileMode) {
      Timeline.startSync('reader.handle.${request.runtimeType}');
      final typeId = TraceliteProfile.internString(
        request.runtimeType.toString(),
      );
      TraceliteProfile.begin(
        TraceliteResqliteSpans.readerHandle,
        args: [typeId, readerId],
        correlationId: request.traceCorrelationId,
      );
    }
    try {
      final Object? result;
      final bool sacrifice;

      switch (request) {
        case SelectRequest(:final sql, :final parameters):
          final raw = executeQuery(dbHandleAddr, readerId, sql, parameters);
          // [EXP-236] TransferableTypedData-wrapped blob cells cross the hop
          // by ownership move, so only the residual heap payload argues for
          // sacrificing the worker.
          sacrifice = raw.estimatedBytes - raw.transferableBytes >
              sacrificeByteThreshold;
          result = _toRows(raw);

        case SelectWithDepsRequest(:final sql, :final parameters):
          // Initial stream query produces hash + row-count baselines
          // ([EXP-075](../../../experiments/075-native-hash-selectifchanged.md)
          // + [EXP-077](../../../experiments/077-cheap-check-first-sweep.md))
          // so future selectIfChanged calls can short-circuit on unchanged state.
          // [EXP-106](../../../experiments/106-column-level-deps.md)
          // piggybacks table dependencies on the same call so the stream
          // engine can perform writer-side dispatch elision.
          final (raw, dependencies, initialHash, initialRowCount) =
              executeQueryWithDeps(dbHandleAddr, readerId, sql, parameters);
          sacrifice = raw.estimatedBytes - raw.transferableBytes >
              sacrificeByteThreshold;
          result = (_toRows(raw), dependencies, initialHash, initialRowCount);

        case SelectBytesRequest(:final sql, :final parameters):
          // Unlike select() (rows), selectBytes never sacrifices: the result
          // is native bytes, so Isolate.exit would need a fromList copy first
          // — saving no copy and only adding a reader respawn. Sending the
          // (bytes view, rowCount) record is the one mandatory SendPort copy,
          // at any size; the rowCount rides along for free.
          result = executeQueryBytes(dbHandleAddr, readerId, sql, parameters);
          sacrifice = false;

        case SelectIfChangedRequest(
          :final sql,
          :final parameters,
          :final lastResultHash,
          :final lastRowCount,
        ):
          // Two-pass selectIfChanged
          // ([EXP-075](../../../experiments/075-native-hash-selectifchanged.md)).
          // The hash and row count are both canonical baselines, so a changed
          // result can be reused safely by the next rerun.
          final (newHash, newRowCount, raw) = executeQueryIfChanged(
            dbHandleAddr,
            readerId,
            sql,
            parameters,
            lastResultHash,
            lastRowCount,
          );
          sacrifice = raw != null &&
              raw.estimatedBytes - raw.transferableBytes >
                  sacrificeByteThreshold;
          result = (raw == null ? null : _toRows(raw), newHash, newRowCount);
      }

      if (sacrifice) {
        receivePort.close();
        // Isolate.exit skips `finally`; release the busy bracket and
        // close the timeline span manually. The result is fully
        // materialized at this point — no further native reads occur.
        resqliteReaderSetBusy(
          ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr),
          readerId,
          0,
        );
        if (kProfileMode) {
          Timeline.finishSync();
          TraceliteProfile.end(
            TraceliteResqliteSpans.readerHandle,
            correlationId: request.traceCorrelationId,
          );
        }
        Isolate.exit(eventPort, (result, true, null));
      }
      eventPort.send((result, false, null));
      // [EXP-183] After `SendPort.send` returns the bytes have been
      // snapshotted into the receiver, so the native `json_buf` is safe
      // to realloc. Shrink it back down when the buffer has grown past
      // 1 MB but the just-sent result fit comfortably below 256 KB —
      // a one-off oversized `selectBytes` no longer pins the reader's
      // capacity for the remainder of the connection's life. The C
      // function is a no-op for warm small buffers (< 1 MB) and for
      // back-to-back large reads (last_used_len >= 256 KB), so the
      // common case has no extra work.
      if (request is SelectBytesRequest &&
          result is ({Uint8List bytes, int rowCount})) {
        resqliteReaderMaybeShrinkJsonBuf(
          ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr),
          readerId,
          result.bytes.length,
        );
      }
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
    } finally {
      resqliteReaderSetBusy(
        ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr),
        readerId,
        0,
      );
      if (kProfileMode) {
        Timeline.finishSync();
        TraceliteProfile.end(
          TraceliteResqliteSpans.readerHandle,
          correlationId: request.traceCorrelationId,
        );
      }
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
  final sqlNative = cachedSqlUtf8(sql);
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
  }
}

/// Execute a SELECT query on a dedicated reader (no pool mutex).
RawQueryResult executeQuery(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) => _withAcquiredStmt(
  handleAddr,
  readerId,
  sql,
  parameters,
  (_, stmt) => decodeQuery(stmt, sql),
);

/// Execute a query returning JSON bytes as a view over the reader
/// connection's persistent `json_buf`, plus the number of rows serialized
/// into them (counted in C during the same pass — no extra walk).
///
/// The returned [Uint8List] aliases native memory that is reused on the next
/// query, so hand it straight to `SendPort.send` (which copies it) — never
/// retain it. The send copy is mandatory anyway, so sending the view avoids a
/// redundant `Uint8List.fromList`.
({Uint8List bytes, int rowCount}) executeQueryBytes(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) {
  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(handleAddr);
  final result = queryBytes(dbHandle, readerId, sql, parameters);
  return (
    bytes: result.ptr.asTypedList(result.length),
    rowCount: result.rowCount,
  );
}

/// Execute a stream's initial query.
///
/// Returns the rows, the authorizer-captured read dependencies
/// ([TableDependencies.unknown] when the C-side reliability flag was tripped
/// during prepare), the C-computed baseline hash
/// ([EXP-075](../../../experiments/075-native-hash-selectifchanged.md)), and
/// the row count ([EXP-077](../../../experiments/077-cheap-check-first-sweep.md)
/// — cached as an additional equality guard for subsequent reruns).
(RawQueryResult, TableDependencies, int, int) executeQueryWithDeps(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
) => _withAcquiredStmt(handleAddr, readerId, sql, parameters, (dbHandle, stmt) {
  final (raw, hash) = decodeQueryWithInitialHash(stmt, sql);
  // Collect dependency metadata from the reader's most recent cached stmt entry.
  return (
    raw,
    getReadTableDependencies(dbHandle, readerId),
    hash,
    raw.rowCount,
  );
});

/// Two-pass selectIfChanged
/// ([EXP-075](../../../experiments/075-native-hash-selectifchanged.md)).
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
) => _withAcquiredStmt(handleAddr, readerId, sql, parameters, (_, stmt) {
  final (newHash, newRowCount) = callQueryHash(stmt);
  if (newHash == lastResultHash && newRowCount == lastRowCount) {
    return (newHash, newRowCount, null);
  }
  return (newHash, newRowCount, decodeQuery(stmt, sql));
});
