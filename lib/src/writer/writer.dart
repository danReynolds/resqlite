import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/mutex.dart';
import 'package:resqlite/src/native/resqlite_bindings.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';
import 'package:resqlite/src/writer/write_worker.dart';

final class Writer {
  final StreamEngine _streamEngine;

  /// Worker SendPort, cached once [spawn]'s handshake completes so the
  /// request path never awaits an already-resolved future. `null` only
  /// before spawn finishes and after [close].
  SendPort? _sendPort;
  bool _closed = false;

  /// Persistent reply port shared by every request.
  ///
  /// The writer isolate processes its port in FIFO order and sends exactly
  /// one reply per request (handlers either reply or throw, and the
  /// entrypoint converts throws into a reply), so replies arrive in request
  /// order and a FIFO queue of completers is sufficient to match them to
  /// callers. This replaces the previous per-request `RawReceivePort`,
  /// removing a port allocate/register/close cycle from every write.
  late final RawReceivePort _replyPort = RawReceivePort(_onReply);

  /// Completers for in-flight requests, in send order.
  final ListQueue<Completer<Object?>> _pending =
      ListQueue<Completer<Object?>>();

  // Writer mutex — ensures concurrent db.execute() / db.transaction() calls
  // don't interleave on the writer isolate. Callers wait for the lock;
  // the lock holder has exclusive write access until released.
  //
  // FIFO fairness: Dart fires Future `.then` callbacks in registration order,
  // and the single-threaded event loop guarantees that when a waiter wakes it
  // re-registers on the new completer before any later-arriving caller can
  // enter `_withWriteLock`. So waiters are served in arrival order and no
  // starvation is possible.
  //
  // Transactions hold the lock from BEGIN through COMMIT/ROLLBACK — an
  // execute sent mid-transaction would silently join the open transaction
  // on the worker (txDepth > 0 defers its dirty-set harvest). Standalone
  // writes only need the lock around the *send* (see [execute]): the
  // worker's port FIFO already orders them against any later BEGIN.
  final _mutex = Mutex();

  // Standalone writes buffered for cross-call batching (exp 180); drained by
  // [_drainPendingWrites], which owns the coalescing logic.
  final List<_PendingWrite> _pendingWrites = <_PendingWrite>[];
  bool _draining = false;

  Writer._(this._streamEngine);

  static Future<Writer> spawn(
    StreamEngine streamEngine,
    Pointer<void> handle,
  ) async {
    final writer = Writer._(streamEngine);

    final handshake = Completer<SendPort>();
    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is SendPort) {
        handshake.complete(message);
        receivePort.close();
      }
    });

    Isolate.spawn(writerEntrypoint, [receivePort.sendPort, handle.address]);

    writer._sendPort = await handshake.future;

    return writer;
  }

  void _onReply(Object? response) {
    // Defensive: a reply with no pending completer (e.g. a stray message
    // after close) is dropped rather than crashing the port handler.
    if (_pending.isEmpty) return;
    final completer = _pending.removeFirst();
    if (response is ResqliteException) {
      completer.completeError(response);
    } else {
      completer.complete(response);
    }
  }

  /// Sends [build]'s request and returns a future for its reply.
  ///
  /// The send happens synchronously — no awaits before `sendPort.send` —
  /// which [execute] relies on to keep its lock window covering the
  /// send. Completers are `sync` so the reply handler resumes the
  /// awaiting caller (response bookkeeping + stream invalidation) directly
  /// inside the port event, the same pattern the reader pool uses for its
  /// per-worker completers.
  Future<T> _request<T>(WriterRequest Function(SendPort replyPort) build) {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw ResqliteConnectionException.databaseClosed();
    }
    final completer = Completer<T>.sync();
    _pending.addLast(completer);
    sendPort.send(build(_replyPort.sendPort));
    return completer.future;
  }

  void _ensureOpen() {
    if (_closed) throw ResqliteConnectionException.databaseClosed();
  }

  Future<T> locked<T>(Future<T> Function() body) async {
    try {
      await _mutex.lock();
      _ensureOpen();
      return await body();
    } finally {
      _mutex.unlock();
    }
  }

  /// Runs a standalone write. Buffers into the coalescing pump
  /// ([_drainPendingWrites]) so a concurrent burst collapses to ~2 isolate
  /// round-trips instead of N (exp 180); profile mode sends per-call so
  /// Tracelite correlation ids stay intact.
  Future<ExecuteResponse> execute(
    String sql, [
    List<Object?> parameters = const [],
    int? traceCorrelationId,
  ]) {
    if (kProfileMode) {
      return _executeSingle(sql, parameters, traceCorrelationId);
    }
    if (_closed) {
      return Future.error(ResqliteConnectionException.databaseClosed());
    }
    final completer = Completer<ExecuteResponse>.sync();
    _pendingWrites.add(_PendingWrite(sql, parameters, completer));
    if (!_draining) _drainPendingWrites();
    return completer.future;
  }

  /// Pre-exp-180 single-send path: takes the lock around the send and returns
  /// the reply future directly. Used only in profile mode.
  Future<ExecuteResponse> _executeSingle(
    String sql,
    List<Object?> parameters,
    int? traceCorrelationId,
  ) async {
    await _mutex.lock();
    final Future<ExecuteResponse> reply;
    try {
      _ensureOpen();
      reply = executeLocked(sql, parameters, traceCorrelationId);
    } finally {
      _mutex.unlock();
    }
    return reply;
  }

  /// Drains [_pendingWrites] under backpressure, one send per iteration.
  ///
  /// Each iteration sends whatever is currently buffered — a lone write as a
  /// plain [ExecuteRequest] (no added latency vs the pre-exp-180 path), or
  /// several as one [MultiExecuteRequest] — then *awaits the reply before the
  /// next iteration*. That await is the coalescing window: concurrent
  /// `execute()` calls arriving while a send is in flight pile into
  /// [_pendingWrites] and go out together on the next pass. A tight sequential
  /// `await db.execute()` loop keeps one write in flight at a time, so it pays
  /// exactly the baseline's single lock hop and never batches.
  ///
  /// The lock is held only across each send (ordering the group against any
  /// concurrent transaction/batch via the worker port FIFO) and released
  /// before the reply round-trip, mirroring [_executeSingle].
  Future<void> _drainPendingWrites() async {
    _draining = true;
    try {
      while (_pendingWrites.isNotEmpty) {
        final group = List<_PendingWrite>.of(_pendingWrites);
        _pendingWrites.clear();

        try {
          Future<ExecuteResponse>? singleReply;
          Future<MultiExecuteResponse>? groupReply;
          await _mutex.lock();
          try {
            _ensureOpen();
            // A lone write goes as a plain ExecuteRequest — same lean path as
            // a non-batched send; only a genuine pile-up pays the multi wrapper.
            if (group.length == 1) {
              final p = group.first;
              singleReply = _request<ExecuteResponse>(
                (replyPort) => ExecuteRequest(p.sql, p.parameters, replyPort),
              );
            } else {
              groupReply = _request<MultiExecuteResponse>(
                (replyPort) => MultiExecuteRequest([
                  for (final p in group) (sql: p.sql, params: p.parameters),
                ], replyPort),
              );
            }
          } finally {
            _mutex.unlock();
          }

          // Distribute outside the lock — the reply round-trip pipelines.
          if (singleReply != null) {
            group.first.completer.complete(await singleReply);
          } else {
            final outcomes = (await groupReply!).outcomes;
            for (var i = 0; i < group.length; i++) {
              final completer = group[i].completer;
              switch (outcomes[i]) {
                case final ExecuteResponse response:
                  completer.complete(response);
                case final ResqliteException error:
                  completer.completeError(error);
                default:
                  completer.completeError(
                    ResqliteException('Internal writer error: missing outcome'),
                  );
              }
            }
          }
        } catch (error) {
          // A closed db, a synchronous send error, or a group-level reply
          // failure fails the group's still-pending callers rather than
          // hanging them. (Per-statement errors complete individually above.)
          for (final p in group) {
            if (!p.completer.isCompleted) {
              p.completer.completeError(error);
            }
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Batch variant of [execute]. Parameter validation throws to the
  /// caller before anything is sent; the empty-batch short-circuit
  /// never touches the worker.
  Future<BatchResponse?> executeBatch(
    String sql,
    List<List<Object?>> paramSets, {
    int? traceCorrelationId,
  }) async {
    await _mutex.lock();
    final Future<BatchResponse?> reply;
    try {
      _ensureOpen();
      reply = executeBatchLocked(
        sql,
        paramSets,
        traceCorrelationId: traceCorrelationId,
      );
    } finally {
      _mutex.unlock();
    }
    return reply;
  }

  /// Sends a write while the writer lock is already held.
  ///
  /// Used by [Transaction.execute] (the enclosing transaction holds the
  /// lock from BEGIN through COMMIT) and by [execute], which takes the
  /// lock around this send.
  Future<ExecuteResponse> executeLocked(
    String sql, [
    List<Object?> parameters = const [],
    int? traceCorrelationId,
  ]) {
    assert(
      _mutex.isLocked,
      'executeLocked requires the writer lock to be held',
    );
    return _request<ExecuteResponse>(
      (replyPort) => ExecuteRequest(
        sql,
        parameters,
        replyPort,
        traceCorrelationId: traceCorrelationId,
      ),
    );
  }

  /// Sends a batch write while the writer lock is already held.
  /// See [executeLocked].
  Future<BatchResponse?> executeBatchLocked(
    String sql,
    List<List<Object?>> paramSets, {
    int? traceCorrelationId,
  }) {
    assert(
      _mutex.isLocked,
      'executeBatchLocked requires the writer lock to be held',
    );
    // Empty batch is a no-op — short-circuit so we don't pay for an
    // isolate round-trip on empty input.
    if (paramSets.isEmpty) {
      return Future.value();
    }
    // Validate on the main isolate so ArgumentError reaches the caller
    // directly instead of round-tripping through the writer as a generic
    // "internal error" response.
    assertUniformParamSets(sql, paramSets);

    return _request<BatchResponse>(
      (replyPort) => BatchRequest(
        sql,
        paramSets,
        replyPort,
        traceCorrelationId: traceCorrelationId,
      ),
    );
  }

  /// Transaction-scoped read on the writer connection, so it sees
  /// uncommitted writes from earlier statements in the same transaction.
  /// The enclosing transaction holds the writer lock.
  Future<QueryResponse> selectLocked(
    String sql, [
    List<Object?> parameters = const [],
    int? traceCorrelationId,
  ]) {
    assert(_mutex.isLocked, 'selectLocked requires the writer lock to be held');
    return _request<QueryResponse>(
      (replyPort) => QueryRequest(
        sql,
        parameters,
        replyPort,
        traceCorrelationId: traceCorrelationId,
      ),
    );
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
  Future<T> transaction<T>(
    Future<T> Function(Transaction tx) body, {
    int? traceCorrelationId,
  }) async {
    await _request<bool>(
      (replyPort) =>
          BeginRequest(replyPort, traceCorrelationId: traceCorrelationId),
    );

    final tx = Transaction(this, traceCorrelationId: traceCorrelationId);
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
        await _request<bool>(
          (replyPort) => RollbackRequest(
            replyPort,
            traceCorrelationId: traceCorrelationId,
          ),
        );
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
      (replyPort) =>
          CommitRequest(replyPort, traceCorrelationId: traceCorrelationId),
    );
    ProfileCounters.recordWriterSqlite(response.writerSqliteUs);

    if (Transaction.current == null) {
      _streamEngine.onDependencyChanges(
        response.modifications,
        traceCorrelationId: traceCorrelationId,
      );
    }

    return result;
  }

  Future<void> close() async {
    _closed = true;

    await _mutex.run(() async {
      final sendPort = _sendPort;
      if (sendPort == null) return;
      final done = Completer<Object?>.sync();
      _pending.addLast(done);
      sendPort.send(CloseRequest(_replyPort.sendPort));
      _sendPort = null;
      await done.future;
    });
    _replyPort.close();
  }
}

/// A buffered standalone write: its SQL/params plus the caller's completer,
/// which [Writer._drainPendingWrites] resolves from the coalesced reply.
final class _PendingWrite {
  _PendingWrite(this.sql, this.parameters, this.completer);
  final String sql;
  final List<Object?> parameters;
  final Completer<ExecuteResponse> completer;
}
