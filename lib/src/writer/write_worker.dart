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

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

sealed class WriterRequest {
  WriterRequest(this.replyPort);
  final SendPort replyPort;
}

/// Single parameterized write (INSERT, UPDATE, DELETE, DDL).
final class ExecuteRequest extends WriterRequest {
  ExecuteRequest(this.sql, this.params, super.replyPort);
  final String sql;
  final List<Object?> params;
}

/// Read query within a transaction — runs on the writer connection so it
/// sees uncommitted writes from earlier statements in the same transaction.
final class QueryRequest extends WriterRequest {
  QueryRequest(this.sql, this.params, super.replyPort);
  final String sql;
  final List<Object?> params;
}

/// Batch write — one SQL statement, many parameter sets, single transaction.
final class BatchRequest extends WriterRequest {
  BatchRequest(this.sql, this.paramSets, super.replyPort);
  final String sql;
  final List<List<Object?>> paramSets;
}

/// Begin an interactive transaction (BEGIN IMMEDIATE).
final class BeginRequest extends WriterRequest {
  BeginRequest(super.replyPort);
}

/// Commit the current transaction. Returns dirty tables for stream invalidation.
final class CommitRequest extends WriterRequest {
  CommitRequest(super.replyPort);
}

/// Roll back the current transaction. Clears dirty tables without notifying.
final class RollbackRequest extends WriterRequest {
  RollbackRequest(super.replyPort);
}

/// Shut down the writer isolate.
final class CloseRequest extends WriterRequest {
  CloseRequest(super.replyPort);
}

/// Profile-mode-only request: snapshot the writer's per-isolate counters
/// (`handlerUs`, `sqliteUs`, `handlerCount`). When [reset] is true the
/// writer zeroes them after taking the snapshot, so callers can frame a
/// burst with paired `reset:true` / `reset:false` calls.
///
/// Added by exp 127 to give audit harnesses cross-isolate visibility into
/// the writer's own dispatch wall — the missing counter that was gating
/// `stream-rerun-dispatch` and `measurement-system` direction work in
/// `experiments/signals.json`. The values are populated only when
/// [kProfileMode] is true; in release builds the response carries zeros.
final class WriterCountersSnapshotRequest extends WriterRequest {
  WriterCountersSnapshotRequest(this.reset, super.replyPort);
  final bool reset;
}

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

/// Response to [ExecuteRequest]. Includes the table modifications produced by
/// the write.
final class ExecuteResponse {
  const ExecuteResponse(this.result, this.modifications);

  final WriteResult result;
  final TableDependencies modifications;
}

/// Response to [QueryRequest] (transaction reads).
final class QueryResponse {
  const QueryResponse(this.rows);
  final List<Map<String, Object?>> rows;
}

/// Response to [BatchRequest] and [CommitRequest].
final class BatchResponse {
  const BatchResponse(this.modifications);

  final TableDependencies modifications;
}

/// Response to [WriterCountersSnapshotRequest]. All values are cumulative
/// since the last reset (or since writer spawn). [handlerUs] is total
/// wall the handler dispatch loop spent inside [WriterRequest] subclasses
/// (excluding [WriterCountersSnapshotRequest] itself, which is not
/// counted), [sqliteUs] is the subset of that wall spent specifically
/// inside the FFI write helpers (`executeWrite`, `executeBatchWrite`,
/// `executeNestedBatchWrite`), and [handlerCount] is the number of
/// timed handler invocations.
///
/// In release builds (`kProfileMode == false`) all three fields are
/// always zero — the writer never instruments the hot path.
final class WriterCountersSnapshotResponse {
  const WriterCountersSnapshotResponse({
    required this.handlerUs,
    required this.sqliteUs,
    required this.handlerCount,
  });
  final int handlerUs;
  final int sqliteUs;
  final int handlerCount;
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

  /// Long-running monotonic clock used by the [kProfileMode] handler /
  /// SQLite-call wall accounting. Started once at writer spawn so the
  /// handler hot path only pays for `elapsedMicroseconds` reads, not
  /// per-message Stopwatch construction. Idle in release.
  final Stopwatch ticker = Stopwatch()..start();

  /// Cumulative microseconds the handler dispatch loop spent inside any
  /// [WriterRequest] subclass other than [WriterCountersSnapshotRequest].
  /// Only mutated when [kProfileMode] is true; reset by
  /// [WriterCountersSnapshotRequest] with `reset: true`.
  int handlerUs = 0;

  /// Cumulative microseconds the writer spent inside the FFI write
  /// helpers (`executeWrite`, `executeBatchWrite`,
  /// `executeNestedBatchWrite`). Subset of [handlerUs]; the difference
  /// is the writer-side Dart wall (request decode, dirty-table read,
  /// response build, isolate reply). Only mutated when [kProfileMode]
  /// is true.
  int sqliteUs = 0;

  /// Number of timed handler invocations contributing to [handlerUs].
  int handlerCount = 0;
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

    // Snapshot/reset requests are not part of the timed dispatch wall —
    // they exist precisely to read the wall accounting from the outside,
    // so counting their own handling would inflate the very metric the
    // caller is trying to measure. Handle and return early.
    if (message is WriterCountersSnapshotRequest) {
      message.replyPort.send(
        WriterCountersSnapshotResponse(
          handlerUs: state.handlerUs,
          sqliteUs: state.sqliteUs,
          handlerCount: state.handlerCount,
        ),
      );
      if (message.reset) {
        state.handlerUs = 0;
        state.sqliteUs = 0;
        state.handlerCount = 0;
      }
      return;
    }

    // Timeline markers scope the writer-isolate's per-message work so
    // external profilers (DevTools, `dart --observe`) can show the
    // cross-isolate breakdown without any custom protocol changes.
    // Gated behind `kProfileMode` (compile-time const) so peer-
    // comparison release builds pay zero — the const-false branch
    // tree-shakes away entirely at AOT. Build with
    // `-DRESQLITE_PROFILE=true` to enable (see lib/src/profile_mode.dart
    // and experiments/080-dispatch-budget.md).
    final tHandler0 = kProfileMode ? state.ticker.elapsedMicroseconds : 0;
    if (kProfileMode) {
      Timeline.startSync('writer.handle.${message.runtimeType}');
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
        case CloseRequest():
          receivePort.close();
          message.replyPort.send(true);
        case WriterCountersSnapshotRequest():
          // Already handled by the early return above. Branch is
          // unreachable but the switch is exhaustive over the sealed
          // hierarchy.
          break;
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
        state.handlerUs += state.ticker.elapsedMicroseconds - tHandler0;
        state.handlerCount++;
      }
    }
  };
}

// ---------------------------------------------------------------------------
// Per-request handlers
// ---------------------------------------------------------------------------

void _handleExecute(_WriterState state, ExecuteRequest msg) {
  final tSqlite0 = kProfileMode ? state.ticker.elapsedMicroseconds : 0;
  final result = executeWrite(state.dbHandle, msg.sql, msg.params);
  if (kProfileMode) {
    state.sqliteUs += state.ticker.elapsedMicroseconds - tSqlite0;
  }
  // Dirty tables and columns are only collected outside transactions.
  // Inside a transaction they accumulate in the C-level dirty sets until
  // the outermost transaction completes.
  final modifications = state.txDepth > 0
      ? TableDependencies.none
      : getDirtyTableDependencies(state.dbHandle);
  msg.replyPort.send(ExecuteResponse(result, modifications));
}

void _handleBatch(_WriterState state, BatchRequest msg) {
  final tSqlite0 = kProfileMode ? state.ticker.elapsedMicroseconds : 0;
  if (state.txDepth > 0) {
    // Inside an open transaction: skip the batch's own BEGIN/COMMIT and
    // let the dirty set accumulate until the outermost commit.
    executeNestedBatchWrite(state.dbHandle, msg.sql, msg.paramSets);
    if (kProfileMode) {
      state.sqliteUs += state.ticker.elapsedMicroseconds - tSqlite0;
    }
    msg.replyPort.send(const BatchResponse(TableDependencies.none));
  } else {
    executeBatchWrite(state.dbHandle, msg.sql, msg.paramSets);
    if (kProfileMode) {
      state.sqliteUs += state.ticker.elapsedMicroseconds - tSqlite0;
    }
    msg.replyPort.send(
      BatchResponse(getDirtyTableDependencies(state.dbHandle)),
    );
  }
}

/// Transaction-scoped read. Runs on the writer connection so uncommitted
/// writes from earlier statements in the same transaction are visible.
void _handleTxQuery(_WriterState state, QueryRequest msg) {
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
      QueryResponse(ResultSet(raw.values, raw.schema, raw.rowCount)),
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
    state.txDepth = newDepth;
    msg.replyPort.send(
      BatchResponse(getDirtyTableDependencies(state.dbHandle)),
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
    state.txDepth = newDepth;
    // Dirty tables stay accumulated — only the outermost commit harvests
    // them for stream invalidation.
    msg.replyPort.send(const BatchResponse(TableDependencies.none));
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
