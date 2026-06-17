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
final class ExecuteRequest extends WriterRequest {
  ExecuteRequest(
    this.sql,
    this.params,
    super.replyPort, {
    super.traceCorrelationId,
  });
  final String sql;
  final List<Object?> params;
}

/// A coalesced group of standalone writes (exp 180 cross-call request
/// batching). The main isolate buffers `execute()` calls issued in the same
/// event-loop turn and sends them as one request, collapsing N round-trips
/// into one. Each statement runs as its own autocommit on the worker — exactly
/// as if sent individually — so per-call success/failure stays independent.
final class MultiExecuteRequest extends WriterRequest {
  MultiExecuteRequest(this.sqls, this.paramsList, super.replyPort);
  final List<String> sqls;
  final List<List<Object?>> paramsList;
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
final class BatchRequest extends WriterRequest {
  BatchRequest(
    this.sql,
    this.paramSets,
    super.replyPort, {
    super.traceCorrelationId,
  });
  final String sql;
  final List<List<Object?>> paramSets;
}

/// Begin an interactive transaction (BEGIN IMMEDIATE).
final class BeginRequest extends WriterRequest {
  BeginRequest(super.replyPort, {super.traceCorrelationId});
}

/// Commit the current transaction. Returns dirty tables for stream invalidation.
final class CommitRequest extends WriterRequest {
  CommitRequest(super.replyPort, {super.traceCorrelationId});
}

/// Roll back the current transaction. Clears dirty tables without notifying.
final class RollbackRequest extends WriterRequest {
  RollbackRequest(super.replyPort, {super.traceCorrelationId});
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

/// Response to [MultiExecuteRequest]. One outcome per input statement, in
/// order: either an [ExecuteResponse] (success) or a [ResqliteException]
/// (that statement's error). Failures are isolated to their own statement —
/// the rest still ran and committed.
final class MultiExecuteResponse {
  const MultiExecuteResponse(this.outcomes);
  final List<Object> outcomes;
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
        case MultiExecuteRequest():
          _handleMultiExecute(state, message);
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
  final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
  final result = executeWrite(state.dbHandle, msg.sql, msg.params);
  final writerSqliteUs = _stopSqliteTimer(sqliteSw);
  // Dirty tables and columns are only collected outside transactions.
  // Inside a transaction they accumulate in the C-level dirty sets until
  // the outermost transaction completes.
  final modifications = state.txDepth > 0
      ? TableDependencies.none
      : getDirtyTableDependencies(state.dbHandle);
  msg.replyPort.send(
    ExecuteResponse(result, modifications, writerSqliteUs: writerSqliteUs),
  );
}

void _handleMultiExecute(_WriterState state, MultiExecuteRequest msg) {
  // Each statement runs independently as its own autocommit (the mutex on
  // the main isolate guarantees a coalesced group is only ever sent at
  // txDepth 0, never mid-transaction). Per-statement dirty tables are
  // harvested right after each write — resqlite_get_dirty_tables resets the
  // set on read, so outcome[i] carries exactly statement i's modifications,
  // identical to sending it as a standalone ExecuteRequest. A statement
  // error is captured as that statement's outcome and the loop continues, so
  // one caller's failure never affects another's.
  final outcomes = List<Object>.filled(msg.sqls.length, _noOutcome);
  for (var i = 0; i < msg.sqls.length; i++) {
    try {
      final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
      final result = executeWrite(state.dbHandle, msg.sqls[i], msg.paramsList[i]);
      final writerSqliteUs = _stopSqliteTimer(sqliteSw);
      final modifications = state.txDepth > 0
          ? TableDependencies.none
          : getDirtyTableDependencies(state.dbHandle);
      outcomes[i] = ExecuteResponse(
        result,
        modifications,
        writerSqliteUs: writerSqliteUs,
      );
    } on ResqliteException catch (e) {
      outcomes[i] = e;
    }
  }
  msg.replyPort.send(MultiExecuteResponse(outcomes));
}

/// Placeholder so a slot is never left null if an `Error` (not a
/// `ResqliteException`) escapes mid-loop — the entrypoint's `on Error` catch
/// then replies with a single exception and the main isolate fails the whole
/// group, so these placeholders are never delivered.
const Object _noOutcome = 'unfilled';

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
    final sqliteSw = kProfileMode ? (Stopwatch()..start()) : null;
    executeBatchWrite(state.dbHandle, msg.sql, msg.paramSets);
    final writerSqliteUs = _stopSqliteTimer(sqliteSw);
    msg.replyPort.send(
      BatchResponse(
        getDirtyTableDependencies(state.dbHandle),
        writerSqliteUs: writerSqliteUs,
      ),
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
    msg.replyPort.send(
      BatchResponse(
        getDirtyTableDependencies(state.dbHandle),
        writerSqliteUs: writerSqliteUs,
      ),
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
