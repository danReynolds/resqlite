import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/mutex.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/transaction.dart';
import 'package:resqlite/src/writer/write_worker.dart';

class Writer {
  final StreamEngine _streamEngine;

  final _workerPort = Completer<SendPort>();
  bool _closed = false;

  // Writer mutex — ensures concurrent db.execute() / db.transaction() calls
  // don't interleave on the writer isolate. Callers wait for the lock;
  // the lock holder has exclusive write access until released.
  //
  // FIFO fairness: Dart fires Future `.then` callbacks in registration order,
  // and the single-threaded event loop guarantees that when a waiter wakes it
  // re-registers on the new completer before any later-arriving caller can
  // enter `_withWriteLock`. So waiters are served in arrival order and no
  // starvation is possible.
  final _mutex = Mutex();

  Writer(this._streamEngine);

  static Future<Writer> spawn(
      StreamEngine streamEngine, Pointer<void> handle) async {
    final writer = Writer(streamEngine);

    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is SendPort) {
        writer._workerPort.complete(message);
      }
    });

    Isolate.spawn(writerEntrypoint, [receivePort.sendPort, handle.address]);

    await writer._workerPort.future;

    return writer;
  }

  void _ensureOpen() {
    if (_closed) throw ResqliteConnectionException('Writer is closed.');
  }

  /// Reconstruct the exact [ResqliteException] subtype from the structured
  /// fields the writer isolate marshalled over. Preserves `sqliteCode`,
  /// `sql`, `parameters`, and `operation` so the caller sees the same
  /// information they would have if the error had originated in-process.
  static ResqliteException _exceptionFromResponse(ErrorResponse response) {
    switch (response.kind) {
      case 'query':
        return ResqliteQueryException(
          response.message,
          sql: response.sql ?? '<unknown>',
          parameters: response.parameters,
          sqliteCode: response.sqliteCode,
        );
      case 'transaction':
        return ResqliteTransactionException(
          response.message,
          operation: response.operation ?? 'unknown',
          sqliteCode: response.sqliteCode,
        );
      default:
        return ResqliteException(response.message);
    }
  }

  Future<T> _request<T>(
    WriterRequest Function(SendPort replyPort) build,
  ) async {
    final sendPort = await _workerPort.future;
    final port = RawReceivePort();
    final completer = Completer<T>();
    port.handler = (Object? response) {
      port.close();
      if (response is ErrorResponse) {
        completer.completeError(_exceptionFromResponse(response));
      } else {
        completer.complete(response as T);
      }
    };
    sendPort.send(build(port.sendPort));
    return completer.future;
  }

  Future<T> locked<T>(Future<T> Function() body) async {
    try {
      await _mutex.lock();
      if (_closed) {
        throw ResqliteConnectionException('Database is closed.');
      }
      return await body();
    } finally {
      _mutex.unlock();
    }
  }

  Future<WriteResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final response = await _request<ExecuteResponse>(
      (replyPort) => ExecuteRequest(sql, parameters, replyPort),
    );

    if (Transaction.current == null) {
      _streamEngine.handleDirtyTables(response.dirtyTables);
    }

    return response.result;
  }

  Future<void> executeBatch(String sql, List<List<Object?>> paramSets) async {
    // Empty batch is a no-op — short-circuit before acquiring the write
    // lock so we don't pay for an isolate round-trip on empty input.
    if (paramSets.isEmpty) {
      _ensureOpen();
      return Future.value();
    }
    // Validate on the main isolate so ArgumentError reaches the caller
    // directly instead of round-tripping through the writer as a generic
    // "internal error" response.
    assertUniformParamSets(sql, paramSets);

    final response = await _request<BatchResponse>(
      (replyPort) => BatchRequest(sql, paramSets, replyPort),
    );

    if (Transaction.current == null) {
      _streamEngine.handleDirtyTables(response.dirtyTables);
    }
  }

  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final response = await _request<QueryResponse>(
      (replyPort) => QueryRequest(sql, parameters, replyPort),
    );
    return response.rows;
  }

  /// Runs a transaction. Used by both [Database.transaction] and [Transaction.transaction].
  ///
  /// Error handling is structured so that:
  ///
  /// 1. If [body] throws, we issue a rollback and rethrow the *body* error,
  ///    even if the rollback itself also fails (rollback errors are
  ///    suppressed — the user's error is more informative).
  /// 2. If commit throws, we do *not* issue a second rollback. The writer
  ///    isolate already cleaned up its own transaction state when commit
  ///    failed (best-effort rollback + `txDepth` reset), so re-sending
  ///    `RollbackRequest` would either no-op against a non-existent
  ///    transaction or, worse, roll back some *other* enclosing scope.
  Future<T> transaction<T>(Future<T> Function(Transaction tx) body) async {
    await _request<bool>((replyPort) => BeginRequest(replyPort));

    final tx = Transaction(this);
    final T result;
    try {
      try {
        result = await runZoned(
          () => body(tx),
          zoneValues: {Transaction.currentZoneKey: tx},
        );
      } finally {
        tx.close();
      }
    } catch (_) {
      try {
        await _request<bool>((replyPort) => RollbackRequest(replyPort));
      } catch (_) {
        // Swallow rollback errors — propagating them would mask the
        // original body error, which is what the caller actually needs
        // to see. The writer isolate always leaves `txDepth` consistent
        // after a rollback attempt, so state is already reset for the
        // next caller.
      }
      rethrow;
    }

    // Commit is deliberately outside the try/catch: on commit failure the
    // writer isolate has already rolled back and reset `txDepth`, so we
    // must not issue a second rollback. The error propagates directly.
    final response = await _request<BatchResponse>(
      (replyPort) => CommitRequest(replyPort),
    );

    if (Transaction.current == null) {
      _streamEngine.handleDirtyTables(response.dirtyTables);
    }

    return result;
  }

  Future<void> close() async {
    _closed = true;

    await _mutex.run(() async {
      // Send CloseRequest directly, not via `_writerRequest` which now
      // rejects post-close calls. This is the one place that needs to
      // reach the writer after `_closed == true`.
      if (await _workerPort case SendPort workerPort) {
        final port = RawReceivePort();
        final done = Completer<void>();
        port.handler = (_) {
          port.close();
          if (!done.isCompleted) done.complete();
        };
        workerPort.send(CloseRequest(port.sendPort));
        await done.future;
      }
    });
  }
}
