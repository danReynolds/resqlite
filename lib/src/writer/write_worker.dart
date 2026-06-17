/// Write worker — isolate entrypoint for all write operations and
/// transaction-scoped reads.
///
/// Transaction reads (tx.select) use the same optimized decode path as
/// readers via query_decode.dart — C statement cache, cell-buffer stepping,
/// ASCII fast-path text decode, and schema caching.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:developer' show Timeline;
import 'dart:ffi' as ffi;
import 'dart:isolate';

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
// Request / Response types
// ---------------------------------------------------------------------------

sealed class WriterRequest {
  WriterRequest(this.replyPort, {this.traceCorrelationId});
  final SendPort replyPort;
  final int? traceCorrelationId;
}

/// Single parameterized write (INSERT, UPDATE, DELETE, DDL).
///
/// [tracksDirty] = `false` lets the writer disable the preupdate hook for
/// this top-level write so the per-row strcmp dedup loops in
/// `dirty_set_add` / `dirty_columns_add_for_active_stmt` never run, and
/// the reply skips the dirty harvest
/// ([EXP-182](../../../experiments/182-skip-dep-tracking-no-streams.md)).
/// Set by [Writer.execute] from `_streamEngine.length > 0` at send time.
/// Inside an open transaction the writer forces tracking on regardless,
/// so callers in that context (`Transaction.execute`) may pass either
/// value; the standard is `true`.
final class ExecuteRequest extends WriterRequest {
  ExecuteRequest(
    this.sql,
    this.params,
    super.replyPort, {
    super.traceCorrelationId,
    this.tracksDirty = true,
  });
  final String sql;
  final List<Object?> params;
  final bool tracksDirty;
}

/// Read query within a transaction — runs on the writer connection so it
/// sees uncommitted writes from earlier statements in the same transaction.
final class QueryRequest extends WriterRequest {
  QueryRequest(
    this.sql,
    this.params,
    super.replyPort, {
    super.traceCorrelationId,
  });
  final String sql;
  final List<Object?> params;
}

/// Batch write — one SQL statement, many parameter sets, single transaction.
///
/// See [ExecuteRequest.tracksDirty] — same semantics, applied across the
/// batch's implicit BEGIN/COMMIT inside the writer.
final class BatchRequest extends WriterRequest {
  BatchRequest(
    this.sql,
    this.paramSets,
    super.replyPort, {
    super.traceCorrelationId,
    this.tracksDirty = true,
  });
  final String sql;
  final List<List<Object?>> paramSets;
  final bool tracksDirty;
}

/// Begin an interactive transaction (BEGIN IMMEDIATE).
///
/// The writer force-enables dependency tracking for the body of the
/// transaction regardless of the request flag, because the commit-time
/// harvest decision depends on stream presence at COMMIT time, not BEGIN.
final class BeginRequest extends WriterRequest {
  BeginRequest(super.replyPort, {super.traceCorrelationId});
}

/// Commit the current transaction. Returns dirty tables for stream invalidation.
///
/// [tracksDirty] = `false` skips the dirty harvest at the outermost
/// commit; the accumulated state (from the forced-on tracking inside the
/// transaction) is discarded instead. Set by [Writer.transaction] from
/// `_streamEngine.length > 0` at commit-send time.
final class CommitRequest extends WriterRequest {
  CommitRequest(super.replyPort, {super.traceCorrelationId, this.tracksDirty = true});
  final bool tracksDirty;
}

/// Roll back the current transaction. Clears dirty tables without notifying.
final class RollbackRequest extends WriterRequest {
  RollbackRequest(super.replyPort, {super.traceCorrelationId});
}

/// No-op barrier; the FIFO reply order guarantees all prior requests
/// have been processed before this one's reply arrives
/// ([EXP-182](../../../experiments/182-skip-dep-tracking-no-streams.md)).
/// Used by [Writer.drainIfUntracked] to fence in-flight non-tracking
/// writes before a newly registered stream dispatches its initial query
/// on the reader pool.
final class DrainRequest extends WriterRequest {
  DrainRequest(super.replyPort);
}

/// Shut down the writer isolate.
final class CloseRequest extends WriterRequest {
  CloseRequest(super.replyPort);
}

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

/// Response to [ExecuteRequest]. Includes the table modifications produced by
/// the write.
final class ExecuteResponse {
  const ExecuteResponse(
    this.result,
    this.modifications, {
    this.writerSqliteUs = 0,
  });

  final WriteResult result;
  final TableDependencies modifications;
  final int writerSqliteUs;
}

/// Response to [QueryRequest] (transaction reads).
final class QueryResponse {
  const QueryResponse(this.rows, {this.writerSqliteUs = 0});
  final List<Map<String, Object?>> rows;
  final int writerSqliteUs;
}

/// Response to [BatchRequest] and [CommitRequest].
final class BatchResponse {
  const BatchResponse(this.modifications, {this.writerSqliteUs = 0});

  final TableDependencies modifications;
  final int writerSqliteUs;
}

// ---------------------------------------------------------------------------
// Writer-specific FFI binding
// ---------------------------------------------------------------------------

@ffi.Native<
  ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint8>,
    ffi.Int,
  )
>(symbol: 'resqlite_stmt_acquire_writer', isLeaf: true)
external ffi.Pointer<ffi.Void> _resqliteStmtAcquireWriter(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.Void> sql,
  ffi.Pointer<ffi.Uint8> params,
  int paramCount,
);

// ---------------------------------------------------------------------------
// Writer isolate entrypoint
// ---------------------------------------------------------------------------

/// Mutable state owned by the writer isolate for the duration of its life.
/// Passed to per-request handlers so each handler is a small, self-contained
/// function that can be reasoned about in isolation.
final class _WriterState {
  _WriterState({required this.dbHandle});

  /// Native SQLite connection handle. Shared with the main isolate via
  /// `dbHandle.address` — the writer isolate owns all access.
  final ffi.Pointer<ffi.Void> dbHandle;

  /// Transaction nesting depth.
  ///
  /// - `0` = no active transaction.
  /// - `1` = top-level transaction (BEGIN IMMEDIATE / COMMIT / ROLLBACK).
  /// - `2+` = nested savepoints (SAVEPOINT sN / RELEASE sN / ROLLBACK TO sN).
  ///
  /// Contract: after handling a `CommitRequest` or `RollbackRequest` this
  /// value is always reduced by exactly one, regardless of whether the
  /// underlying SQLite call succeeded — the writer is responsible for
  /// leaving both Dart's view and SQLite's savepoint stack in a consistent
  /// state so subsequent requests see predictable depth.
  int txDepth = 0;

  /// Mirror of the native `track_dirty` flag, so we only call the FFI
  /// setter when the desired value differs from the current one
  /// ([EXP-182](../../../experiments/182-skip-dep-tracking-no-streams.md)).
  /// Native default after `resqlite_open` is enabled.
  bool nativeTrackEnabled = true;
}

void _ensureTrackDirty(_WriterState state, bool enabled) {
  if (state.nativeTrackEnabled == enabled) return;
  resqliteSetTrackDirty(state.dbHandle, enabled ? 1 : 0);
  state.nativeTrackEnabled = enabled;
}

void writerEntrypoint(List<Object> args) {
  final mainPort = args[0] as SendPort;
  final dbHandleAddr = args[1] as int;

  final state = _WriterState(
    dbHandle: ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr),
  );
  final receivePort = RawReceivePort();

  mainPort.send(receivePort.sendPort);

  receivePort.handler = (Object? message) {
    if (message is! WriterRequest) return;

    // Timeline markers scope the writer-isolate's per-message work so
    // external profilers (DevTools, `dart --observe`) can show the
    // cross-isolate breakdown without any custom protocol changes.
    // Gated behind `kProfileMode` (compile-time const) so peer-
    // comparison release builds pay zero — the const-false branch
    // tree-shakes away entirely at AOT. Build with
    // `-DRESQLITE_PROFILE=true` to enable (see lib/src/profile_mode.dart
    // and experiments/080-dispatch-budget.md).
    if (kProfileMode) {
      Timeline.startSync('writer.handle.${message.runtimeType}');
      final typeId = TraceliteProfile.internString(
        message.runtimeType.toString(),
      );
      TraceliteProfile.begin(
        TraceliteResqliteSpans.writerHandle,
        args: [typeId],
        correlationId: message.traceCorrelationId,
      );
    }
    try {
      switch (message) {
        case ExecuteRequest():
          _handleExecute(state, message);
        case QueryRequest():
          _handleTxQuery(state, message);
        case BatchRequest():
          _handleBatch(state, message);
        case BeginRequest():
          _handleBegin(state, message);
        case CommitRequest():
          _handleCommit(state, message);
        case RollbackRequest():
          _handleRollback(state, message);
        case DrainRequest():
          // FIFO barrier — the reply order alone guarantees that every
          // earlier request has been processed before this one's reply
          // arrives, so the body is intentionally empty.
          message.replyPort.send(true);
        case CloseRequest():
          receivePort.close();
          message.replyPort.send(true);
      }
    } on ResqliteException catch (e) {
      // Same-group isolates (Isolate.spawn) deep-copy objects across
      // SendPort, so we send the typed exception directly. The main
      // isolate receives the exact subtype (ResqliteQueryException,
      // ResqliteTransactionException) with all structured fields intact.
      message.replyPort.send(e);
    } on Error catch (e, st) {
      // Errors (StackOverflowError, OutOfMemoryError, assertion failures,
      // etc.) indicate bugs or unrecoverable VM state — not query errors.
      // We cannot rethrow from an isolate event handler without crashing
      // the isolate and leaving the main side hanging on a reply, so we
      // wrap as a ResqliteException and continue.
      message.replyPort.send(
        ResqliteException('Internal error in writer isolate: $e\n$st'),
      );
    } finally {
      if (kProfileMode) {
        Timeline.finishSync();
        TraceliteProfile.end(
          TraceliteResqliteSpans.writerHandle,
          correlationId: message.traceCorrelationId,
        );
      }
    }
  };
}

// ---------------------------------------------------------------------------
// Per-request handlers
// ---------------------------------------------------------------------------

void _handleExecute(_WriterState state, ExecuteRequest msg) {
  // [EXP-182] At top-level (txDepth == 0) the request flag chooses whether
  // the preupdate hook accumulates and whether the reply harvests. Inside
  // an open transaction tracking stays forced on (set by BeginRequest)
  // because the COMMIT decides the harvest, and we cannot predict stream
  // arrivals between BEGIN and COMMIT.
  if (state.txDepth == 0) {
    _ensureTrackDirty(state, msg.tracksDirty);
  }
  final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
  final result = executeWrite(state.dbHandle, msg.sql, msg.params);
  final writerSqliteUs = _stopSqliteTimer(sqliteSw);
  // Dirty tables and columns are only collected outside transactions.
  // Inside a transaction they accumulate in the C-level dirty sets until
  // the outermost transaction completes.
  final TableDependencies modifications;
  if (state.txDepth > 0) {
    modifications = TableDependencies.none;
  } else if (msg.tracksDirty) {
    modifications = getDirtyTableDependencies(state.dbHandle);
  } else {
    // Tracking was off: the dirty set is already empty, no FFI needed.
    modifications = TableDependencies.none;
  }
  msg.replyPort.send(
    ExecuteResponse(result, modifications, writerSqliteUs: writerSqliteUs),
  );
}

void _handleBatch(_WriterState state, BatchRequest msg) {
  if (state.txDepth > 0) {
    // Inside an open transaction: skip the batch's own BEGIN/COMMIT and
    // let the dirty set accumulate until the outermost commit.
    final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
    executeNestedBatchWrite(state.dbHandle, msg.sql, msg.paramSets);
    msg.replyPort.send(
      BatchResponse(
        TableDependencies.none,
        writerSqliteUs: _stopSqliteTimer(sqliteSw),
      ),
    );
  } else {
    // [EXP-182] same gate as `_handleExecute`: at top level the request
    // flag controls both preupdate accumulation and harvest. The C-side
    // BEGIN/COMMIT inside `executeBatchWrite` still runs; only the
    // preupdate work and reply harvest are skipped when off.
    _ensureTrackDirty(state, msg.tracksDirty);
    final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
    executeBatchWrite(state.dbHandle, msg.sql, msg.paramSets);
    final writerSqliteUs = _stopSqliteTimer(sqliteSw);
    final modifications = msg.tracksDirty
        ? getDirtyTableDependencies(state.dbHandle)
        : TableDependencies.none;
    msg.replyPort.send(
      BatchResponse(modifications, writerSqliteUs: writerSqliteUs),
    );
  }
}

/// Transaction-scoped read. Runs on the writer connection so uncommitted
/// writes from earlier statements in the same transaction are visible.
void _handleTxQuery(_WriterState state, QueryRequest msg) {
  final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
  final sqlNative = cachedSqlUtf8(msg.sql);
  final paramsNative = allocateParams(msg.params);
  try {
    final stmt = _resqliteStmtAcquireWriter(
      state.dbHandle,
      sqlNative.cast(),
      paramsNative,
      msg.params.length,
    );
    if (stmt == ffi.nullptr) {
      throw ResqliteQueryException(
        resqliteErrmsg(state.dbHandle).toDartString(),
        sql: msg.sql,
        parameters: msg.params,
      );
    }
    final raw = decodeQuery(stmt, msg.sql);
    msg.replyPort.send(
      QueryResponse(
        ResultSet(raw.values, raw.schema, raw.rowCount),
        writerSqliteUs: _stopSqliteTimer(sqliteSw),
      ),
    );
  } finally {
    // Both resources are freed in one finally regardless of which line
    // threw — an earlier version of this function had a paired try/finally
    // that leaked `paramsNative` when stmt acquisition failed.
    freeParams(paramsNative, msg.params);
  }
}

void _handleBegin(_WriterState state, BeginRequest msg) {
  // BEGIN at depth 0, SAVEPOINT at depth > 0.
  //
  // On failure, txDepth stays at its current value and the error
  // propagates — _runTransaction on the main isolate will never have
  // entered its body, so there is nothing to roll back.
  // [EXP-182] Inside a transaction we cannot predict whether a stream
  // will register between BEGIN and COMMIT, so force tracking on for
  // the whole body. The COMMIT decides whether to harvest based on
  // stream presence at COMMIT-send time.
  _ensureTrackDirty(state, true);
  if (state.txDepth == 0) {
    final rc = resqliteTxBeginImmediate(state.dbHandle);
    if (rc != 0) {
      throw ResqliteTransactionException(
        resqliteErrmsg(state.dbHandle).toDartString(),
        operation: 'begin',
        sqliteCode: rc,
      );
    }
  } else {
    final sp = 'SAVEPOINT s${state.txDepth}'.toNativeUtf8();
    try {
      final rc = resqliteExec(state.dbHandle, sp);
      if (rc != 0) {
        throw ResqliteTransactionException(
          resqliteErrmsg(state.dbHandle).toDartString(),
          operation: 'savepoint',
          sqliteCode: rc,
        );
      }
    } finally {
      calloc.free(sp);
    }
  }
  state.txDepth++;
  msg.replyPort.send(true);
}

void _handleCommit(_WriterState state, CommitRequest msg) {
  // Contract: after handling this request (success or failure), txDepth
  // is reduced by exactly one and the corresponding SQLite scope is no
  // longer active. The next request sees a predictable state.
  final newDepth = state.txDepth - 1;
  final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
  if (newDepth == 0) {
    final rc = resqliteTxCommit(state.dbHandle);
    if (rc != 0) {
      // Capture the error message BEFORE any further sqlite calls — the
      // errmsg pointer is only stable until the next call.
      final errMsg = resqliteErrmsg(state.dbHandle).toDartString();
      // On commit failure SQLite typically auto-rolls the transaction
      // back, but behavior depends on the error (deferred FK, I/O, etc.).
      // Issue a best-effort ROLLBACK and ignore its return — it may
      // legitimately fail with "no transaction active".
      resqliteTxRollback(state.dbHandle);
      // Drop any tables/columns dirtied by the aborted transaction.
      discardDirtyTableDependencies(state.dbHandle);
      state.txDepth = newDepth;
      throw ResqliteTransactionException(
        errMsg,
        operation: 'commit',
        sqliteCode: rc,
      );
    }
    final writerSqliteUs = _stopSqliteTimer(sqliteSw);
    state.txDepth = newDepth;
    // [EXP-182] When the COMMIT-send-time check found no streams, the
    // accumulated dirty state (from the forced-on tracking inside the
    // transaction) is discarded rather than marshalled to Dart.
    final TableDependencies modifications;
    if (msg.tracksDirty) {
      modifications = getDirtyTableDependencies(state.dbHandle);
    } else {
      discardDirtyTableDependencies(state.dbHandle);
      modifications = TableDependencies.none;
    }
    msg.replyPort.send(
      BatchResponse(modifications, writerSqliteUs: writerSqliteUs),
    );
  } else {
    final sp = 'RELEASE s$newDepth'.toNativeUtf8();
    final rc = resqliteExec(state.dbHandle, sp);
    calloc.free(sp);
    if (rc != 0) {
      final errMsg = resqliteErrmsg(state.dbHandle).toDartString();
      // RELEASE failed — the savepoint is still live in SQLite.
      //
      // Policy trade-off: we force-clean the savepoint via
      // ROLLBACK TO + RELEASE, which *discards* the writes the caller
      // was trying to commit. The alternative would be to leave the
      // savepoint alive and propagate "still-active" state back to Dart
      // so `_runTransaction` could issue rollbacks up the stack — a
      // bigger refactor for a rare error path.
      //
      // SQLite does not fire deferred FK checks on RELEASE (only on the
      // outermost COMMIT), so in practice this path fires only on I/O
      // errors or corruption, at which point the writes are not
      // recoverable anyway. The caller still sees the original RELEASE
      // error and can make its recovery decision at the enclosing scope.
      // Errors from the cleanup itself are swallowed — we are already
      // returning an error and cannot surface two.
      final rollbackSp = 'ROLLBACK TO s$newDepth'.toNativeUtf8();
      final releaseSp = 'RELEASE s$newDepth'.toNativeUtf8();
      resqliteExec(state.dbHandle, rollbackSp);
      resqliteExec(state.dbHandle, releaseSp);
      calloc.free(rollbackSp);
      calloc.free(releaseSp);
      state.txDepth = newDepth;
      throw ResqliteTransactionException(
        errMsg,
        operation: 'release',
        sqliteCode: rc,
      );
    }
    final writerSqliteUs = _stopSqliteTimer(sqliteSw);
    state.txDepth = newDepth;
    // Dirty tables stay accumulated — only the outermost commit harvests
    // them for stream invalidation.
    msg.replyPort.send(
      BatchResponse(TableDependencies.none, writerSqliteUs: writerSqliteUs),
    );
  }
}

void _handleRollback(_WriterState state, RollbackRequest msg) {
  // Contract: same as _handleCommit — txDepth is always reduced by one
  // after this returns, regardless of whether the underlying ROLLBACK
  // succeeded. That keeps the writer usable for the next caller even if
  // SQLite reports a rollback failure.
  final newDepth = state.txDepth - 1;
  if (newDepth == 0) {
    final rc = resqliteTxRollback(state.dbHandle);
    // Clear the dirty sets — rolled-back changes don't count for stream
    // invalidation, even if SQLite reported a rollback error.
    discardDirtyTableDependencies(state.dbHandle);
    state.txDepth = newDepth;
    if (rc != 0) {
      throw ResqliteTransactionException(
        resqliteErrmsg(state.dbHandle).toDartString(),
        operation: 'rollback',
        sqliteCode: rc,
      );
    }
  } else {
    // ROLLBACK TO undoes changes since the savepoint; RELEASE then
    // removes the savepoint from SQLite's stack.
    final rollbackSp = 'ROLLBACK TO s$newDepth'.toNativeUtf8();
    final releaseSp = 'RELEASE s$newDepth'.toNativeUtf8();
    final rc1 = resqliteExec(state.dbHandle, rollbackSp);
    final rc2 = resqliteExec(state.dbHandle, releaseSp);
    calloc.free(rollbackSp);
    calloc.free(releaseSp);
    state.txDepth = newDepth;
    if (rc1 != 0) {
      throw ResqliteTransactionException(
        resqliteErrmsg(state.dbHandle).toDartString(),
        operation: 'rollback_to',
        sqliteCode: rc1,
      );
    }
    if (rc2 != 0) {
      throw ResqliteTransactionException(
        resqliteErrmsg(state.dbHandle).toDartString(),
        operation: 'release',
        sqliteCode: rc2,
      );
    }
  }
  msg.replyPort.send(true);
}

int _stopSqliteTimer(Stopwatch? sw) {
  if (sw == null) return 0;
  sw.stop();
  return sw.elapsedMicroseconds;
}
