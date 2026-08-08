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

  /// Rows this SQL last returned (plus headroom), or 0 when the pool has never
  /// seen it. Stamped by [ReaderPool._dispatch] immediately before the send;
  /// the worker sizes its result buffer from it
  /// ([EXP-260](../../../experiments/260-result-list-presize.md)).
  ///
  /// The hint has to be carried on the request rather than kept in the worker's
  /// own schema cache: a result over [sacrificeSlotThreshold] slots ends the
  /// isolate that produced it, so exactly the results with the most growth to
  /// avoid would always be decoded by a worker that had never seen the SQL.
  int rowHint = 0;

  /// Rows to size the *initial* result buffer for, or 0 for the fixed default
  /// ([EXP-264](../../../experiments/264-initial-alloc-size-memory.md)).
  ///
  /// Also stamped by [ReaderPool._dispatch]. It must come from the main isolate
  /// for the same reason [rowHint] does, plus one of its own: a worker observes
  /// only the executions routed to it, and too low a figure here under-sizes the
  /// buffer.
  int initialRowHint = 0;
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

  /// Row count previously emitted to subscribers, or null when there is no
  /// baseline. Compared with the fresh count alongside the result hash; a null
  /// baseline can never match, so the result is always treated as changed.
  final int? lastRowCount;
}

/// How large a result's *structure* (rows × columns) can grow before handing
/// it to main via `Isolate.exit` — sacrificing this worker — beats sending it.
///
/// Structure is the only thing `send` actually copies; string and number
/// leaves are shared. So the result's shape, never its byte size, picks the
/// cheaper transfer — a byte threshold here once respawned a reader on every
/// big-TEXT read to avoid a copy that was never going to happen.
/// Full mechanism and the measurements behind this value (exp 244/245/246):
/// doc/arch/cross-isolate-data-transfer.md §6a.
const int sacrificeSlotThreshold = int.fromEnvironment(
  'RESQLITE_SLOT_THRESHOLD',
  defaultValue: 32 * 1024,
);

/// The most rows a `select()` may return before the main isolate stops running
/// it itself ([EXP-265](../../../experiments/265-inline-main-isolate-select.md)).
///
/// This is a budget for how long a read is allowed to hold the isolate that
/// paints frames, not a point where inline execution stops being faster — it
/// keeps winning well past this. A 64-row decode of a six-column row is a few
/// microseconds; the reason not to raise it is that the figure bounds the
/// *mispredict*, which is a statement the pool has only ever seen return few
/// rows suddenly returning many.
const int inlineRowMax = int.fromEnvironment(
  'RESQLITE_INLINE_ROW_MAX',
  defaultValue: 64,
);

/// Whether a decoded row result should be sacrificed rather than sent.
bool _shouldSacrifice(RawQueryResult raw) =>
    raw.values.length > sacrificeSlotThreshold;

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
          final raw = executeQuery(
            dbHandleAddr,
            readerId,
            sql,
            parameters,
            request.rowHint,
            request.initialRowHint,
          );
          sacrifice = _shouldSacrifice(raw);
          result = _toRows(raw);

        case SelectWithDepsRequest(:final sql, :final parameters):
          // Initial stream query produces hash + row-count baselines
          // ([EXP-075](../../../experiments/075-native-hash-selectifchanged.md)
          // + [EXP-077](../../../experiments/077-cheap-check-first-sweep.md))
          // so future selectIfChanged calls can short-circuit on unchanged state.
          // [EXP-106](../../../experiments/106-column-level-deps.md)
          // piggybacks table dependencies on the same call so the stream
          // engine can perform writer-side dispatch elision.
          final (
            raw,
            dependencies,
            initialHash,
            initialRowCount,
          ) = executeQueryWithDeps(
            dbHandleAddr,
            readerId,
            sql,
            parameters,
            request.rowHint,
            request.initialRowHint,
          );
          sacrifice = _shouldSacrifice(raw);
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
            request.rowHint,
            request.initialRowHint,
          );
          sacrifice = raw != null && _shouldSacrifice(raw);
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

// Only [executeQueryInline] needs this. Every other decode runs its statement
// to SQLITE_DONE, which releases the implicit read transaction on its own; an
// abandoned statement would hold that connection's WAL snapshot open until its
// next acquire, which may never come.
@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_reset',
  isLeaf: true,
)
external int _sqlite3Reset(ffi.Pointer<ffi.Void> stmt);

// ---------------------------------------------------------------------------
// Query execution
// ---------------------------------------------------------------------------

/// Wrap a decoded result in a lazy `ResultSet` view and up-cast to the
/// `List<Map<String, Object?>>` shape the pool / stream engine consumes.
/// The cast is a type-system formality — `ResultSet implements List<Row>`
/// and `Row implements Map<String, Object?>`, so it's always safe.
List<Map<String, Object?>> _toRows(RawQueryResult raw) => raw.toResultSet();

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
  List<Object?> parameters, [
  int rowHint = 0,
  int initialRowHint = 0,
]) => _withAcquiredStmt(
  handleAddr,
  readerId,
  sql,
  parameters,
  (_, stmt) =>
      decodeQuery(stmt, sql, rowHint: rowHint, initialRowHint: initialRowHint),
);

/// Run a SELECT on [readerId] from the calling isolate and decode it there,
/// with no isolate hop at either end
/// ([EXP-265](../../../experiments/265-inline-main-isolate-select.md)).
///
/// This is the same execution as [executeQuery]; what differs is who runs it
/// and what happens when it turns out to be the wrong choice. The caller is the
/// main isolate, which cannot afford an unbounded decode, so:
///
///  * more than [rowCap] rows aborts the decode and returns null, and
///  * **any** failure returns null rather than throwing.
///
/// Null means "run this on a worker instead". A null from a genuine SQL error
/// costs one duplicate execution and then surfaces the identical exception from
/// the pool, which is why this path reports none of its own: reader connections
/// are `SQLITE_OPEN_READONLY`, so re-running a statement that failed here
/// cannot have done anything the second attempt would repeat.
///
/// [readerId] must be a connection no worker isolate can touch. The connections
/// are `SQLITE_OPEN_NOMUTEX`.
RawQueryResult? executeQueryInline(
  int handleAddr,
  int readerId,
  String sql,
  List<Object?> parameters,
  int rowHint,
  int initialRowHint,
  int rowCap,
) {
  try {
    return _withAcquiredStmt(handleAddr, readerId, sql, parameters, (_, stmt) {
      try {
        return decodeQuery(
          stmt,
          sql,
          rowHint: rowHint,
          initialRowHint: initialRowHint,
          inlineRowCap: rowCap,
        );
      } catch (_) {
        // Reached with the statement mid-iteration, holding a read
        // transaction this isolate has no other reason to come back for.
        _sqlite3Reset(stmt);
        rethrow;
      }
    });
  } catch (_) {
    return null;
  }
}

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
  List<Object?> parameters, [
  int rowHint = 0,
  int initialRowHint = 0,
]) => _withAcquiredStmt(handleAddr, readerId, sql, parameters, (
  dbHandle,
  stmt,
) {
  final (raw, hash) = decodeQueryWithInitialHash(
    stmt,
    sql,
    rowHint: rowHint,
    initialRowHint: initialRowHint,
  );
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
  int? lastRowCount, [
  int rowHint = 0,
  int initialRowHint = 0,
]) => _withAcquiredStmt(handleAddr, readerId, sql, parameters, (_, stmt) {
  final (newHash, newRowCount) = callQueryHash(stmt);
  if (newHash == lastResultHash && newRowCount == lastRowCount) {
    return (newHash, newRowCount, null);
  }
  return (
    newHash,
    newRowCount,
    decodeQuery(stmt, sql, rowHint: rowHint, initialRowHint: initialRowHint),
  );
});
