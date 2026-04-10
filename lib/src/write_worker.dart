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
import 'query_decode.dart';
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

void writerEntrypoint(List<Object> args) {
  final mainPort = args[0] as SendPort;
  final dbHandleAddr = args[1] as int;

  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr);
  final receivePort = RawReceivePort();
  var inTransaction = false;

  // Pre-allocate native strings for transaction SQL.
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
          final dirty = inTransaction
              ? const <String>[]
              : getDirtyTables(dbHandle);
          replyPort.send(ExecuteResponse(result, dirty));

        case QueryRequest(:final sql, :final params, :final replyPort):
          _handleQuery(dbHandle, sql, params, replyPort);

        case BatchRequest(:final sql, :final paramSets, :final replyPort):
          executeBatchWrite(dbHandle, sql, paramSets);
          final dirty = getDirtyTables(dbHandle);
          replyPort.send(BatchResponse(dirty));

        case BeginRequest(:final replyPort):
          resqliteExec(dbHandle, beginSql);
          inTransaction = true;
          replyPort.send(true);

        case CommitRequest(:final replyPort):
          resqliteExec(dbHandle, commitSql);
          inTransaction = false;
          final dirty = getDirtyTables(dbHandle);
          replyPort.send(BatchResponse(dirty));

        case RollbackRequest(:final replyPort):
          resqliteExec(dbHandle, rollbackSql);
          inTransaction = false;
          getDirtyTables(dbHandle);
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
    if (stmt == ffi.nullptr) throw StateError('Failed to acquire writer statement');
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
