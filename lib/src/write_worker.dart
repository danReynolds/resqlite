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

/// Error response sent when the writer catches an exception.
/// Converted to [ResqliteQueryException] on the main isolate.
final class ErrorResponse {
  const ErrorResponse(this.message, {this.sql, this.parameters});
  final String message;
  final String? sql;
  final List<Object?>? parameters;
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

void writerEntrypoint(List<Object> args) {
  final mainPort = args[0] as SendPort;
  final dbHandleAddr = args[1] as int;

  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr);
  final receivePort = RawReceivePort();

  /// Transaction nesting depth.
  /// 0 = no active transaction.
  /// 1 = top-level transaction (BEGIN IMMEDIATE / COMMIT / ROLLBACK).
  /// 2+ = nested savepoints (SAVEPOINT s1 / RELEASE s1 / ROLLBACK TO s1).
  var txDepth = 0;

  // Pre-allocate native strings for top-level transaction SQL.
  final beginSql = 'BEGIN IMMEDIATE'.toNativeUtf8();
  final commitSql = 'COMMIT'.toNativeUtf8();
  final rollbackSql = 'ROLLBACK'.toNativeUtf8();

  mainPort.send(receivePort.sendPort);

  receivePort.handler = (Object? message) {
    if (message is! WriterRequest) return;

    try {
      switch (message) {
        case ExecuteRequest(:final sql, :final params, :final replyPort):
          WriteResult result;
          if (params.isEmpty) {
            final sqlNative = sql.toNativeUtf8();
            final rc = resqliteExec(dbHandle, sqlNative);
            calloc.free(sqlNative);
            if (rc != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              throw StateError('exec failed: $errMsg (code $rc)');
            }
            result = const WriteResult(0, 0);
          } else {
            result = executeWrite(dbHandle, sql, params);
          }
          // Only send dirty tables if not in a transaction —
          // during transactions, dirty tables accumulate until commit.
          final dirty = txDepth > 0
              ? const <String>[]
              : getDirtyTables(dbHandle);
          replyPort.send(ExecuteResponse(result, dirty));

        case QueryRequest(:final sql, :final params, :final replyPort):
          _handleQuery(dbHandle, sql, params, replyPort);

        case BatchRequest(:final sql, :final paramSets, :final replyPort):
          // Inside an open transaction (either from db.transaction or
          // tx.transaction savepoint), skip the batch's own BEGIN/COMMIT and
          // let dirty tables accumulate until the outer commit.
          if (txDepth > 0) {
            executeBatchWriteNested(dbHandle, sql, paramSets);
            replyPort.send(const BatchResponse(<String>[]));
          } else {
            executeBatchWrite(dbHandle, sql, paramSets);
            replyPort.send(BatchResponse(getDirtyTables(dbHandle)));
          }

        case BeginRequest(:final replyPort):
          // BEGIN at depth 0, SAVEPOINT at depth > 0.
          // On failure, `txDepth` stays at its current value and the error
          // propagates — the caller's `_runTransaction` never entered its
          // body so there is nothing to roll back.
          if (txDepth == 0) {
            final rc = resqliteExec(dbHandle, beginSql);
            if (rc != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              throw StateError('begin failed: $errMsg (code $rc)');
            }
          } else {
            final sp = 'SAVEPOINT s$txDepth'.toNativeUtf8();
            final rc = resqliteExec(dbHandle, sp);
            calloc.free(sp);
            if (rc != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              throw StateError('savepoint failed: $errMsg (code $rc)');
            }
          }
          txDepth++;
          replyPort.send(true);

        case CommitRequest(:final replyPort):
          // Contract: after handling this request (success or failure),
          // `txDepth` is reduced by one and the corresponding SQLite
          // transaction scope is no longer active. This lets the writer
          // stay consistent even if commit or release fails — the next
          // request sees a predictable state.
          final newDepth = txDepth - 1;
          if (newDepth == 0) {
            final rc = resqliteExec(dbHandle, commitSql);
            if (rc != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              // On commit failure SQLite typically auto-rolls the txn back,
              // but behavior depends on the error (deferred FK, etc.). Run
              // a best-effort ROLLBACK; ignore its return code since it
              // may legitimately fail with "no transaction active".
              resqliteExec(dbHandle, rollbackSql);
              // Drop any tables dirtied by the aborted transaction.
              getDirtyTables(dbHandle);
              txDepth = newDepth;
              throw StateError('commit failed: $errMsg (code $rc)');
            }
            txDepth = newDepth;
            final dirty = getDirtyTables(dbHandle);
            replyPort.send(BatchResponse(dirty));
          } else {
            final sp = 'RELEASE s$newDepth'.toNativeUtf8();
            final rc = resqliteExec(dbHandle, sp);
            calloc.free(sp);
            if (rc != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              // RELEASE failed — the savepoint is still live in SQLite.
              //
              // Policy trade-off: we force-clean the savepoint via
              // ROLLBACK TO + RELEASE, which *discards* the writes the
              // caller was trying to commit. The alternative would be to
              // leave the savepoint alive and let the outer scope decide,
              // but that would require the writer to hold per-depth
              // "still-active" state and propagate it back to Dart so
              // `_runTransaction` could issue additional RollbackRequests
              // up the savepoint stack — a bigger refactor for a rare
              // error path. (SQLite doesn't fire deferred FK checks on
              // RELEASE, only on the outermost COMMIT, so in practice
              // this fires only on I/O errors or corruption, at which
              // point the writes are not recoverable anyway.)
              //
              // The caller still sees the original RELEASE error and can
              // make their own recovery decision at the enclosing scope.
              // Errors from the cleanup path itself are swallowed — we
              // are already returning an error and cannot surface two.
              final rollbackSp = 'ROLLBACK TO s$newDepth'.toNativeUtf8();
              final releaseSp = 'RELEASE s$newDepth'.toNativeUtf8();
              resqliteExec(dbHandle, rollbackSp);
              resqliteExec(dbHandle, releaseSp);
              calloc.free(rollbackSp);
              calloc.free(releaseSp);
              txDepth = newDepth;
              throw StateError(
                'release savepoint failed: $errMsg (code $rc)',
              );
            }
            txDepth = newDepth;
            // Dirty tables stay accumulated — only the outermost commit
            // collects them.
            replyPort.send(const BatchResponse(<String>[]));
          }

        case RollbackRequest(:final replyPort):
          // Contract: same as CommitRequest — `txDepth` is always reduced
          // by one after this returns, regardless of whether the underlying
          // ROLLBACK succeeds. That keeps the writer usable for the next
          // caller even if SQLite reports a rollback failure.
          final newDepth = txDepth - 1;
          if (newDepth == 0) {
            final rc = resqliteExec(dbHandle, rollbackSql);
            // Clear dirty tables regardless — rolled-back changes don't count.
            getDirtyTables(dbHandle);
            txDepth = newDepth;
            if (rc != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              throw StateError('rollback failed: $errMsg (code $rc)');
            }
          } else {
            // ROLLBACK TO undoes changes since the savepoint.
            // RELEASE removes the savepoint from SQLite's stack.
            final rollbackSp = 'ROLLBACK TO s$newDepth'.toNativeUtf8();
            final releaseSp = 'RELEASE s$newDepth'.toNativeUtf8();
            final rc1 = resqliteExec(dbHandle, rollbackSp);
            final rc2 = resqliteExec(dbHandle, releaseSp);
            calloc.free(rollbackSp);
            calloc.free(releaseSp);
            txDepth = newDepth;
            if (rc1 != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              throw StateError(
                'rollback to savepoint failed: $errMsg (code $rc1)',
              );
            }
            if (rc2 != 0) {
              final errMsg = resqliteErrmsg(dbHandle).toDartString();
              throw StateError(
                'release savepoint failed: $errMsg (code $rc2)',
              );
            }
          }
          replyPort.send(true);

        case CloseRequest(:final replyPort):
          receivePort.close();
          replyPort.send(true);
      }
    } catch (e) {
      String? sql;
      List<Object?>? params;
      if (message is ExecuteRequest) {
        sql = message.sql;
        params = message.params;
      } else if (message is QueryRequest) {
        sql = message.sql;
        params = message.params;
      } else if (message is BatchRequest) {
        sql = message.sql;
      }
      message.replyPort.send(
        ErrorResponse(e.toString(), sql: sql, parameters: params),
      );
    }
  };
}

/// Handle a read query within a transaction. Uses the writer connection
/// (sees uncommitted writes) via the C statement cache and shared decode path.
void _handleQuery(
  ffi.Pointer<ffi.Void> dbHandle,
  String sql,
  List<Object?> params,
  SendPort replyPort,
) {
  final sqlNative = sql.toNativeUtf8();
  final paramsNative = allocateParams(params);
  ffi.Pointer<ffi.Void> stmt;
  try {
    stmt = _resqliteStmtAcquireWriter(
      dbHandle,
      sqlNative.cast(),
      paramsNative,
      params.length,
    );
    if (stmt == ffi.nullptr)
      throw StateError('Failed to acquire writer statement');
  } finally {
    calloc.free(sqlNative);
  }

  try {
    final raw = decodeQuery(stmt, sql);
    // No dirty table collection — _handleQuery only runs during transactions,
    // and dirty tables must accumulate until commit.
    replyPort.send(QueryResponse(
      ResultSet(raw.values, raw.schema, raw.rowCount),
      const <String>[],
    ));
  } finally {
    freeParams(paramsNative, params);
  }
}
