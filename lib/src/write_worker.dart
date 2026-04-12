/// Write worker — isolate entrypoint for all write operations and
/// transaction-scoped reads.
///
/// Transaction reads (tx.select) use the same optimized decode path as
/// readers via query_decode.dart — C statement cache, cell-buffer stepping,
/// ASCII fast-path text decode, and schema caching.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native/resqlite_bindings.dart';
import 'query_decoder.dart';
import 'row.dart';

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

// ---------------------------------------------------------------------------
// Response types
// ---------------------------------------------------------------------------

/// Response to [ExecuteRequest]. Includes dirty tables for stream invalidation.
final class ExecuteResponse {
  const ExecuteResponse(this.result, this.dirtyTables);
  final WriteResult result;
  final List<String> dirtyTables;
}

/// Response to [QueryRequest] (transaction reads).
final class QueryResponse {
  const QueryResponse(this.rows, this.dirtyTables);
  final List<Map<String, Object?>> rows;
  final List<String> dirtyTables;
}

/// Response to [BatchRequest] and [CommitRequest].
final class BatchResponse {
  const BatchResponse(this.dirtyTables);
  final List<String> dirtyTables;
}

/// Structured error marshalled from the writer isolate back to the main
/// isolate. The main isolate uses [kind] to reconstruct the correct
/// [ResqliteException] subtype with its structured fields intact rather
/// than collapsing everything into a stringified message.
///
/// Kinds:
/// - `query` — an error from an `ExecuteRequest`, `QueryRequest`, or
///   `BatchRequest`. Reconstructed as [ResqliteQueryException] with
///   [sql], [parameters], and [sqliteCode].
/// - `transaction` — a BEGIN / COMMIT / ROLLBACK / SAVEPOINT / RELEASE /
///   ROLLBACK TO failure. Reconstructed as [ResqliteTransactionException]
///   with [operation] and [sqliteCode].
/// - `internal` — a non-SQLite error that slipped through (should be
///   rare). Reconstructed as a bare [ResqliteException].
final class ErrorResponse {
  const ErrorResponse(
    this.kind,
    this.message, {
    this.sql,
    this.parameters,
    this.sqliteCode,
    this.operation,
  });

  final String kind;
  final String message;
  final String? sql;
  final List<Object?>? parameters;
  final int? sqliteCode;
  final String? operation;
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
    )>(symbol: 'resqlite_stmt_acquire_writer', isLeaf: true)
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
  _WriterState({
    required this.dbHandle,
    required this.beginSql,
    required this.commitSql,
    required this.rollbackSql,
  });

  /// Native SQLite connection handle. Shared with the main isolate via
  /// `dbHandle.address` — the writer isolate owns all access.
  final ffi.Pointer<ffi.Void> dbHandle;

  /// Pre-allocated native strings reused across every transaction so we
  /// don't pay a `toNativeUtf8` + free per `BEGIN`/`COMMIT`/`ROLLBACK`.
  final ffi.Pointer<Utf8> beginSql;
  final ffi.Pointer<Utf8> commitSql;
  final ffi.Pointer<Utf8> rollbackSql;

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
    beginSql: 'BEGIN IMMEDIATE'.toNativeUtf8(),
    commitSql: 'COMMIT'.toNativeUtf8(),
    rollbackSql: 'ROLLBACK'.toNativeUtf8(),
  );
  final receivePort = RawReceivePort();

  mainPort.send(receivePort.sendPort);

  receivePort.handler = (Object? message) {
    if (message is! WriterRequest) return;

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
      }
    } on ResqliteException catch (e) {
      // Typed resqlite exceptions are marshalled with their structured
      // fields intact so the main isolate can reconstruct the exact
      // subtype (ResqliteQueryException / ResqliteTransactionException)
      // with sqliteCode, sql, and operation preserved for user inspection.
      message.replyPort.send(_marshalException(e));
    } on Error catch (e, st) {
      // Errors (StackOverflowError, OutOfMemoryError, assertion failures,
      // etc.) indicate bugs or unrecoverable VM state — not query errors.
      // We cannot rethrow from an isolate event handler without crashing
      // the isolate and leaving the main side hanging on a reply, so we
      // surface a distinct "internal" error kind and continue. The main
      // isolate will rewrap this as a plain ResqliteException so users
      // can see the stack rather than silently swallowing it.
      message.replyPort.send(ErrorResponse(
        'internal',
        'Internal error in writer isolate: $e\n$st',
      ));
    }
  };
}

/// Convert a typed resqlite exception into a marshalable `ErrorResponse`
/// that the main isolate can reconstruct back into the exact subtype.
ErrorResponse _marshalException(ResqliteException e) {
  if (e is ResqliteQueryException) {
    return ErrorResponse(
      'query',
      e.message,
      sql: e.sql,
      parameters: e.parameters,
      sqliteCode: e.sqliteCode,
    );
  }
  if (e is ResqliteTransactionException) {
    return ErrorResponse(
      'transaction',
      e.message,
      sqliteCode: e.sqliteCode,
      operation: e.operation,
    );
  }
  return ErrorResponse('internal', e.message);
}

// ---------------------------------------------------------------------------
// Per-request handlers
// ---------------------------------------------------------------------------

void _handleExecute(_WriterState state, ExecuteRequest msg) {
  // All writes go through executeWrite → resqlite_execute, which uses the
  // prepared-statement cache for single-statement SQL and automatically
  // falls back to sqlite3_exec for multi-statement SQL (detected via
  // pzTail from sqlite3_prepare_v3).
  final result = executeWrite(state.dbHandle, msg.sql, msg.params);
  // Dirty tables are only collected outside transactions. Inside a
  // transaction they accumulate in the C-level dirty set until the
  // outermost commit harvests them.
  final dirty = state.txDepth > 0
      ? const <String>[]
      : getDirtyTables(state.dbHandle);
  msg.replyPort.send(ExecuteResponse(result, dirty));
}

void _handleBatch(_WriterState state, BatchRequest msg) {
  if (state.txDepth > 0) {
    // Inside an open transaction: skip the batch's own BEGIN/COMMIT and
    // let the dirty set accumulate until the outermost commit.
    executeBatchWriteNested(state.dbHandle, msg.sql, msg.paramSets);
    msg.replyPort.send(const BatchResponse(<String>[]));
  } else {
    executeBatchWrite(state.dbHandle, msg.sql, msg.paramSets);
    msg.replyPort.send(BatchResponse(getDirtyTables(state.dbHandle)));
  }
}

/// Transaction-scoped read. Runs on the writer connection so uncommitted
/// writes from earlier statements in the same transaction are visible.
void _handleTxQuery(_WriterState state, QueryRequest msg) {
  final sqlNative = msg.sql.toNativeUtf8();
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
    // No dirty table collection — this path only runs during transactions
    // and the dirty set must accumulate until commit.
    msg.replyPort.send(QueryResponse(
      ResultSet(raw.values, raw.schema, raw.rowCount),
      const <String>[],
    ));
  } finally {
    // Both resources are freed in one finally regardless of which line
    // threw — an earlier version of this function had a paired try/finally
    // that leaked `paramsNative` when stmt acquisition failed.
    freeParams(paramsNative, msg.params);
    calloc.free(sqlNative);
  }
}

void _handleBegin(_WriterState state, BeginRequest msg) {
  // BEGIN at depth 0, SAVEPOINT at depth > 0.
  //
  // On failure, txDepth stays at its current value and the error
  // propagates — _runTransaction on the main isolate will never have
  // entered its body, so there is nothing to roll back.
  if (state.txDepth == 0) {
    final rc = resqliteExec(state.dbHandle, state.beginSql);
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
    final rc = resqliteExec(state.dbHandle, state.commitSql);
    if (rc != 0) {
      // Capture the error message BEFORE any further sqlite calls — the
      // errmsg pointer is only stable until the next call.
      final errMsg = resqliteErrmsg(state.dbHandle).toDartString();
      // On commit failure SQLite typically auto-rolls the transaction
      // back, but behavior depends on the error (deferred FK, I/O, etc.).
      // Issue a best-effort ROLLBACK and ignore its return — it may
      // legitimately fail with "no transaction active".
      resqliteExec(state.dbHandle, state.rollbackSql);
      // Drop any tables dirtied by the aborted transaction.
      getDirtyTables(state.dbHandle);
      state.txDepth = newDepth;
      throw ResqliteTransactionException(
        errMsg,
        operation: 'commit',
        sqliteCode: rc,
      );
    }
    state.txDepth = newDepth;
    msg.replyPort.send(BatchResponse(getDirtyTables(state.dbHandle)));
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
    msg.replyPort.send(const BatchResponse(<String>[]));
  }
}

void _handleRollback(_WriterState state, RollbackRequest msg) {
  // Contract: same as _handleCommit — txDepth is always reduced by one
  // after this returns, regardless of whether the underlying ROLLBACK
  // succeeded. That keeps the writer usable for the next caller even if
  // SQLite reports a rollback failure.
  final newDepth = state.txDepth - 1;
  if (newDepth == 0) {
    final rc = resqliteExec(state.dbHandle, state.rollbackSql);
    // Clear the dirty set — rolled-back changes don't count for stream
    // invalidation, even if SQLite reported a rollback error.
    getDirtyTables(state.dbHandle);
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
