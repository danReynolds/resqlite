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

  // exp 180 — cross-call request batching under backpressure. Standalone
  // execute() calls are buffered here and drained by [_pumpExecGroup]: an idle
  // pump sends the first write immediately (one statement, no added latency),
  // and any writes that arrive while that send's reply is in flight are
  // coalesced into one MultiExecuteRequest on the next pump iteration. So a
  // concurrent burst collapses to ~2 round-trips instead of N, while
  // sequential awaited writes pay exactly the baseline's single lock hop. Each
  // statement still runs as its own autocommit on the worker, so per-call
  // success/failure is unchanged from sending them individually.
  final List<_PendingExecute> _execGroup = <_PendingExecute>[];
  bool _pumping = false;

  Writer(this._streamEngine);

  static Future<Writer> spawn(
    StreamEngine streamEngine,
    Pointer<void> handle,
  ) async {
    final writer = Writer(streamEngine);

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
      throw ResqliteConnectionException('Database is closed.');
    }
    final completer = Completer<T>.sync();
    _pending.addLast(completer);
    sendPort.send(build(_replyPort.sendPort));
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

  /// Runs a standalone write, holding the writer lock only for the send.
  ///
  /// The lock is released as soon as the request is on the worker's port:
  /// the port FIFO guarantees the write is fully processed (at txDepth 0,
  /// including its dirty-set harvest) before any later-sent BEGIN opens a
  /// transaction, so exclusivity across the reply round-trip adds nothing.
  /// Releasing early lets a subsequent write or transaction overlap its
  /// send with this write's worker-side execution and reply scheduling.
  Future<ExecuteResponse> execute(
    String sql, [
    List<Object?> parameters = const [],
    int? traceCorrelationId,
  ]) {
    // Profile mode keeps the per-call send so Tracelite correlation ids and
    // per-write spans stay intact; coalescing (exp 180) is the release shape.
    // Profile mode keeps the per-call send so Tracelite correlation ids and
    // per-write spans stay intact; coalescing (exp 180) is the release shape.
    if (kProfileMode) {
      return _executeSingle(sql, parameters, traceCorrelationId);
    }
    if (_closed) {
      return Future.error(ResqliteConnectionException('Database is closed.'));
    }
    final completer = Completer<ExecuteResponse>.sync();
    _execGroup.add(_PendingExecute(sql, parameters, completer));
    if (!_pumping) {
      _pumping = true;
      _pumpExecGroup();
    }
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
      if (_closed) {
        throw ResqliteConnectionException('Database is closed.');
      }
      reply = executeInTransaction(sql, parameters, traceCorrelationId);
    } finally {
      _mutex.unlock();
    }
    return reply;
  }

  /// Drains [_execGroup] under backpressure, one send per iteration.
  ///
  /// Each iteration sends whatever is currently buffered — a lone write as a
  /// plain [ExecuteRequest] (no added latency vs the pre-exp-180 path), or
  /// several as one [MultiExecuteRequest] — then *awaits the reply before the
  /// next iteration*. That await is the coalescing window: concurrent
  /// `execute()` calls arriving while a send is in flight pile into
  /// [_execGroup] and go out together on the next pass. A tight sequential
  /// `await db.execute()` loop keeps one write in flight at a time, so it pays
  /// exactly the baseline's single lock hop and never batches.
  ///
  /// The lock is held only across each send (ordering the group against any
  /// concurrent transaction/batch via the worker port FIFO) and released
  /// before the reply round-trip, mirroring [_executeSingle].
  Future<void> _pumpExecGroup() async {
    try {
      while (_execGroup.isNotEmpty) {
        final group = List<_PendingExecute>.of(_execGroup);
        _execGroup.clear();

        try {
          Future<ExecuteResponse>? singleReply;
          Future<MultiExecuteResponse>? groupReply;
          await _mutex.lock();
          try {
            if (_closed) {
              throw ResqliteConnectionException('Database is closed.');
            }
            if (group.length == 1) {
              singleReply = executeInTransaction(
                group.first.sql,
                group.first.parameters,
              );
            } else {
              groupReply = _request<MultiExecuteResponse>(
                (replyPort) => MultiExecuteRequest(
                  [for (final p in group) p.sql],
                  [for (final p in group) p.parameters],
                  replyPort,
                ),
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
              final outcome = outcomes[i];
              if (outcome is ExecuteResponse) {
                group[i].completer.complete(outcome);
              } else if (outcome is ResqliteException) {
                group[i].completer.completeError(outcome);
              } else {
                group[i].completer.completeError(
                  ResqliteException('Internal writer error: missing outcome'),
                );
              }
            }
          }
        } on Object catch (error) {
          // Any failure — a closed database, a synchronous send error, or a
          // group-level reply error — fails the group's still-pending callers
          // rather than leaving them hung. Per-statement errors inside a
          // successful group reply are completed individually above and the
          // group never reaches here.
          for (final p in group) {
            if (!p.completer.isCompleted) {
              p.completer.completeError(error);
            }
          }
        }
      }
    } finally {
      _pumping = false;
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
      if (_closed) {
        throw ResqliteConnectionException('Database is closed.');
      }
      reply = executeBatchInTransaction(
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
  Future<ExecuteResponse> executeInTransaction(
    String sql, [
    List<Object?> parameters = const [],
    int? traceCorrelationId,
  ]) {
    assert(
      _mutex.isLocked,
      'executeInTransaction requires the writer lock to be held',
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
  /// See [executeInTransaction].
  Future<BatchResponse?> executeBatchInTransaction(
    String sql,
    List<List<Object?>> paramSets, {
    int? traceCorrelationId,
  }) {
    assert(
      _mutex.isLocked,
      'executeBatchInTransaction requires the writer lock to be held',
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
  Future<QueryResponse> selectInTransaction(
    String sql, [
    List<Object?> parameters = const [],
    int? traceCorrelationId,
  ]) {
    assert(
      _mutex.isLocked,
      'selectInTransaction requires the writer lock to be held',
    );
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

/// A standalone write buffered for cross-call batching (exp 180). Holds the
/// caller's completer so [Writer._flushExecGroup] can resolve it from the
/// coalesced reply with this statement's own [ExecuteResponse] (or error).
final class _PendingExecute {
  _PendingExecute(this.sql, this.parameters, this.completer);
  final String sql;
  final List<Object?> parameters;
  final Completer<ExecuteResponse> completer;
}
