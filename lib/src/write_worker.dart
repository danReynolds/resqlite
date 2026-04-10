@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native/resqlite_bindings.dart';
import 'row.dart';

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

/// Base class for messages sent from [Database] to the writer isolate.
///
/// Each subclass maps to a writer operation. The writer pattern-matches
/// on these in [writerEntrypoint] and replies via [replyPort]. On error,
/// the writer sends an [ErrorResponse] instead of the expected type.
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

  /// Tables modified by this write, captured via the preupdate hook.
  /// Empty during transactions (accumulated until commit).
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
// Writer isolate entrypoint
// ---------------------------------------------------------------------------

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'resqlite_writer_handle',
  isLeaf: true,
)
external ffi.Pointer<ffi.Void> _resqliteWriterHandle(ffi.Pointer<ffi.Void> db);

void writerEntrypoint(List<Object> args) {
  final mainPort = args[0] as SendPort;
  final dbHandleAddr = args[1] as int;

  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(dbHandleAddr);
  final writerConn = _resqliteWriterHandle(dbHandle);
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

  // Signal ready.
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
          _handleQuery(writerConn, dbHandle, sql, params, replyPort);

        case BatchRequest(:final sql, :final paramSets, :final replyPort):
          executeBatchWrite(dbHandle, sql, paramSets);
          final dirty = getDirtyTables(dbHandle);
          replyPort.send(BatchResponse(dirty));

        case BeginRequest(:final replyPort):
          if (txDepth == 0) {
            resqliteExec(dbHandle, beginSql);
          } else {
            final sp = 'SAVEPOINT s$txDepth'.toNativeUtf8();
            resqliteExec(dbHandle, sp);
            calloc.free(sp);
          }
          txDepth++;
          replyPort.send(true);

        case CommitRequest(:final replyPort):
          txDepth--;
          if (txDepth == 0) {
            resqliteExec(dbHandle, commitSql);
            final dirty = getDirtyTables(dbHandle);
            replyPort.send(BatchResponse(dirty));
          } else {
            final sp = 'RELEASE s$txDepth'.toNativeUtf8();
            resqliteExec(dbHandle, sp);
            calloc.free(sp);
            // Dirty tables stay accumulated — only the outermost commit
            // collects them.
            replyPort.send(const BatchResponse(<String>[]));
          }

        case RollbackRequest(:final replyPort):
          txDepth--;
          if (txDepth == 0) {
            resqliteExec(dbHandle, rollbackSql);
            // Clear dirty tables — rolled back changes don't count.
            getDirtyTables(dbHandle);
          } else {
            // ROLLBACK TO undoes changes since the savepoint.
            // RELEASE removes the savepoint from SQLite's stack.
            final rollbackSp = 'ROLLBACK TO s$txDepth'.toNativeUtf8();
            final releaseSp = 'RELEASE s$txDepth'.toNativeUtf8();
            resqliteExec(dbHandle, rollbackSp);
            resqliteExec(dbHandle, releaseSp);
            calloc.free(rollbackSp);
            calloc.free(releaseSp);
          }
          replyPort.send(true);

        case CloseRequest(:final replyPort):
          receivePort.close();
          replyPort.send(true);
      }
      }
    } catch (e) {
      // Extract SQL context from the request for better error messages.
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

/// Handle a batch write using a Dart-side loop. Avoids the bulk native param
/// serialization that executeBatchWrite requires — binds params per-row via
/// direct FFI calls instead of pre-flattening all params into native memory.
/// Handle a query within a transaction. Uses the writer connection
/// (sees uncommitted writes). Results are sent as a ResultSet via SendPort.
void _handleQuery(
  ffi.Pointer<ffi.Void> writerConn, // raw sqlite3*
  ffi.Pointer<ffi.Void> dbHandle, // resqlite_db* (for getDirtyTables)
  String sql,
  List<Object?> params,
  SendPort replyPort,
) {
  final sqlNative = sql.toNativeUtf8();
  final ppStmt = calloc<ffi.Pointer<ffi.Void>>();
  try {
    final rc = _sqlite3PrepareV2(
      writerConn,
      sqlNative.cast(),
      -1,
      ppStmt,
      ffi.nullptr,
    );
    if (rc != 0) {
      throw StateError('prepare failed (code $rc)');
    }
  } finally {
    calloc.free(sqlNative);
  }

  final stmt = ppStmt.value;
  calloc.free(ppStmt);

  if (params.isNotEmpty) {
    _bindParamsDart(stmt, params);
  }

  try {
    final colCount = _sqlite3ColumnCount(stmt);
    final schema = RowSchema(
      List<String>.generate(colCount, (i) {
        return _sqlite3ColumnName(stmt, i).toDartString();
      }, growable: false),
    );

    final values = <Object?>[];
    var rowCount = 0;

    while (_sqlite3Step(stmt) == 100) {
      // SQLITE_ROW
      rowCount++;
      for (var i = 0; i < colCount; i++) {
        final type = _sqlite3ColumnType(stmt, i);
        switch (type) {
          case 1: // SQLITE_INTEGER
            values.add(_sqlite3ColumnInt64(stmt, i));
          case 2: // SQLITE_FLOAT
            values.add(_sqlite3ColumnDouble(stmt, i));
          case 3: // SQLITE_TEXT
            final ptr = _sqlite3ColumnText(stmt, i);
            final len = _sqlite3ColumnBytes(stmt, i);
            values.add(utf8.decode(ptr.cast<ffi.Uint8>().asTypedList(len)));
          case 4: // SQLITE_BLOB
            final len = _sqlite3ColumnBytes(stmt, i);
            if (len == 0) {
              values.add(Uint8List(0));
            } else {
              final ptr = _sqlite3ColumnBlob(stmt, i);
              values.add(
                Uint8List.fromList(ptr.cast<ffi.Uint8>().asTypedList(len)),
              );
            }
          default:
            values.add(null);
        }
      }
    }

    // Send ResultSet directly — it implements List<Map<String, Object?>>
    // via ListMixin<Row>/MapMixin and is efficiently copyable (flat values
    // list + shared schema, no per-row Map allocations).
    //
    // No dirty table collection here — _handleQuery only runs during
    // transactions (via tx.select()), and dirty tables must accumulate
    // until commit. Calling getDirtyTables here would clear the buffer
    // and cause stream invalidation to miss updates.
    final resultSet = ResultSet(values, schema, rowCount);
    replyPort.send(QueryResponse(resultSet, const <String>[]));
  } finally {
    _sqlite3Finalize(stmt);
  }
}

// Minimal FFI bindings needed on the writer isolate for transaction queries.
@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Pointer<ffi.Void>>,
    ffi.Pointer<ffi.Void>,
  )
>(symbol: 'sqlite3_prepare_v2', isLeaf: true)
external int _sqlite3PrepareV2(
  ffi.Pointer<ffi.Void> db,
  ffi.Pointer<ffi.Void> sql,
  int nByte,
  ffi.Pointer<ffi.Pointer<ffi.Void>> ppStmt,
  ffi.Pointer<ffi.Void> pzTail,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_step',
  isLeaf: true,
)
external int _sqlite3Step(ffi.Pointer<ffi.Void> stmt);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_finalize',
  isLeaf: true,
)
external int _sqlite3Finalize(ffi.Pointer<ffi.Void> stmt);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_column_count',
  isLeaf: true,
)
external int _sqlite3ColumnCount(ffi.Pointer<ffi.Void> stmt);

@ffi.Native<ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_name',
  isLeaf: true,
)
external ffi.Pointer<Utf8> _sqlite3ColumnName(
  ffi.Pointer<ffi.Void> stmt,
  int n,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_type',
  isLeaf: true,
)
external int _sqlite3ColumnType(ffi.Pointer<ffi.Void> stmt, int iCol);

@ffi.Native<ffi.Int64 Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_int64',
  isLeaf: true,
)
external int _sqlite3ColumnInt64(ffi.Pointer<ffi.Void> stmt, int iCol);

@ffi.Native<ffi.Double Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_double',
  isLeaf: true,
)
external double _sqlite3ColumnDouble(ffi.Pointer<ffi.Void> stmt, int iCol);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_text',
  isLeaf: true,
)
external ffi.Pointer<ffi.Void> _sqlite3ColumnText(
  ffi.Pointer<ffi.Void> stmt,
  int iCol,
);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_bytes',
  isLeaf: true,
)
external int _sqlite3ColumnBytes(ffi.Pointer<ffi.Void> stmt, int iCol);

@ffi.Native<ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_column_blob',
  isLeaf: true,
)
external ffi.Pointer<ffi.Void> _sqlite3ColumnBlob(
  ffi.Pointer<ffi.Void> stmt,
  int iCol,
);

void _bindParamsDart(ffi.Pointer<ffi.Void> stmt, List<Object?> params) {
  for (var i = 0; i < params.length; i++) {
    final value = params[i];
    final idx = i + 1;
    if (value == null) {
      _sqlite3BindNull(stmt, idx);
    } else if (value is int) {
      _sqlite3BindInt64(stmt, idx, value);
    } else if (value is double) {
      _sqlite3BindDouble(stmt, idx, value);
    } else if (value is String) {
      final encoded = value.toNativeUtf8();
      _sqlite3BindText(
        stmt,
        idx,
        encoded,
        -1,
        ffi.Pointer<ffi.Void>.fromAddress(-1), // SQLITE_TRANSIENT
      );
      calloc.free(encoded);
    } else if (value is Uint8List) {
      final blob = calloc<ffi.Uint8>(value.length);
      blob.asTypedList(value.length).setAll(0, value);
      _sqlite3BindBlob(
        stmt,
        idx,
        blob.cast(),
        value.length,
        ffi.Pointer<ffi.Void>.fromAddress(-1), // SQLITE_TRANSIENT
      );
      calloc.free(blob);
    }
  }
}

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int)>(
  symbol: 'sqlite3_bind_null',
  isLeaf: true,
)
external int _sqlite3BindNull(ffi.Pointer<ffi.Void> stmt, int idx);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Int64)>(
  symbol: 'sqlite3_bind_int64',
  isLeaf: true,
)
external int _sqlite3BindInt64(ffi.Pointer<ffi.Void> stmt, int idx, int val);

@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Int, ffi.Double)>(
  symbol: 'sqlite3_bind_double',
  isLeaf: true,
)
external int _sqlite3BindDouble(
  ffi.Pointer<ffi.Void> stmt,
  int idx,
  double val,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<Utf8>,
    ffi.Int,
    ffi.Pointer<ffi.Void>,
  )
>(symbol: 'sqlite3_bind_text', isLeaf: true)
external int _sqlite3BindText(
  ffi.Pointer<ffi.Void> stmt,
  int idx,
  ffi.Pointer<Utf8> val,
  int n,
  ffi.Pointer<ffi.Void> destructor,
);

@ffi.Native<
  ffi.Int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Void>,
    ffi.Int,
    ffi.Pointer<ffi.Void>,
  )
>(symbol: 'sqlite3_bind_blob', isLeaf: true)
external int _sqlite3BindBlob(
  ffi.Pointer<ffi.Void> stmt,
  int idx,
  ffi.Pointer<ffi.Void> val,
  int n,
  ffi.Pointer<ffi.Void> destructor,
);
