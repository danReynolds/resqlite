/// Reader pool — manages a fleet of read worker isolates.
///
/// Handles dispatch (round-robin with busy tracking), worker lifecycle
/// (spawn, sacrifice detection, respawn), and backpressure (callers wait
/// when all workers are busy). The actual query execution logic lives in
/// read_worker.dart.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../exceptions.dart';
import 'read_worker.dart';

/// A pool of persistent reader isolates with automatic replacement.
///
/// Each worker handles one query at a time. All worker events flow through a
/// single event port per worker lifetime: the initial command SendPort,
/// normal replies, sacrifice payloads sent via Isolate.exit, and onExit
/// notifications.
///
/// Large results trigger sacrifice — the worker sends the result via
/// Isolate.exit (zero-copy) and the isolate terminates. Because the
/// sacrifice payload and onExit notification arrive on the same port, the
/// VM's same-port FIFO ordering guarantees the payload is processed before
/// the exit notification, eliminating the race condition between the two.
///
/// Dispatch never sends two queries to the same worker. If all workers are
/// busy, callers wait until one becomes available (finishes its query or
/// respawns after sacrifice).
final class ReaderPool {
  ReaderPool._(this._workers);

  final List<_WorkerSlot> _workers;
  int _next = 0;
  bool _closed = false;

  /// Completed whenever any worker becomes available (finishes a query
  /// or finishes respawning). Callers waiting in _dispatch are woken up.
  Completer<void>? _workerAvailable;

  static Future<ReaderPool> spawn(int dbHandleAddr, int count) async {
    final pool = ReaderPool._([]);
    final slots = List.generate(
      count,
      (i) => _WorkerSlot(pool._notifyAvailable, i),
    );
    await Future.wait(slots.map((s) => s.spawn(dbHandleAddr)));
    pool._workers.addAll(slots);

    return pool;
  }

  /// Wake up any callers waiting for an available worker.
  void _notifyAvailable() {
    if (_workerAvailable case Completer<void> c) {
      _workerAvailable = null;
      c.complete();
    }
  }

  /// Execute a query on the next available worker.
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await _dispatch(SelectRequest(sql, parameters));
    return result as List<Map<String, Object?>>;
  }

  /// Execute a query and capture read dependencies (table names).
  ///
  /// Also returns the C-computed hash of the initial result (exp 075) so
  /// later [selectIfChanged] calls have a baseline in the same hash
  /// domain to compare against.
  Future<(List<Map<String, Object?>>, List<String>, int)> selectWithDeps(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await _dispatch(
      SelectWithDepsRequest(sql, parameters),
    );
    return result as (List<Map<String, Object?>>, List<String>, int);
  }

  /// Execute a query returning JSON-encoded bytes.
  Future<Uint8List> selectBytes(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await _dispatch(SelectBytesRequest(sql, parameters));
    return result as Uint8List;
  }

  /// Execute a re-query with worker-side hash comparison.
  /// Returns `(rows, newHash)` if changed, or `(null, newHash)` if unchanged.
  Future<(List<Map<String, Object?>>?, int)> selectIfChanged(
    String sql,
    List<Object?> parameters,
    int lastResultHash,
  ) async {
    final result = await _dispatch(
      SelectIfChangedRequest(sql, parameters, lastResultHash),
    );
    return result as (List<Map<String, Object?>>?, int);
  }

  Future<Object?> _dispatch(ReadRequest request) async {
    // Fail fast on a closed pool so a caller who slipped past the
    // Database-level open check (e.g. a subscription whose reQuery
    // fires during close) doesn't park forever on `_workerAvailable`
    // waiting for a worker that will never come back.
    if (_closed) {
      throw ResqliteConnectionException('Reader pool is closed.');
    }

    final count = _workers.length;

    while (true) {
      for (var attempt = 0; attempt < count; attempt++) {
        final slot = _workers[_next % count];
        _next++;
        if (slot.isAvailable) {
          return slot.request(request);
        }
      }

      // All workers busy or dead. Wait for any to become available.
      _workerAvailable ??= Completer<void>.sync();
      await _workerAvailable!.future;

      // Re-check after waking: close() may have run while we were
      // parked and we must not loop forever over dead slots.
      if (_closed) {
        throw ResqliteConnectionException('Reader pool is closed.');
      }
    }
  }

  /// Drains any in-flight read and then shuts every worker down.
  ///
  /// Returns a Future that completes when all worker isolates have
  /// finished their current request and released their SQLite
  /// connections. This matches the writer-side drain in
  /// `Database.close()` so `resqliteClose(handle)` never runs while a
  /// reader worker is still stepping over the handle.
  ///
  /// Any caller that had parked on `_workerAvailable` waiting for a
  /// free worker is woken up so `_dispatch` can observe `_closed` and
  /// bail out with StateError rather than looping over dead slots.
  Future<void> close() async {
    _closed = true;
    // Wake any parked dispatch waiters so they can re-check _closed.
    if (_workerAvailable case Completer<void> c) {
      _workerAvailable = null;
      c.complete();
    }
    await Future.wait(_workers.map((slot) => slot.close()));
  }
}

/// Manages a single worker isolate's lifecycle.
///
/// Uses a persistent event port per worker that receives the initial command
/// SendPort, normal replies, sacrifice data (via Isolate.exit), and onExit
/// notifications. Because sacrifice data and onExit arrive on the same port,
/// the VM's same-port FIFO ordering guarantees the Isolate.exit data is
/// processed before the onExit null — eliminating the race condition that
/// previously caused false crash detection.
///
/// This is the same pattern the Dart SDK uses in Isolate.run.
class _WorkerSlot {
  _WorkerSlot(this._notifyPool, this._readerId);

  final void Function() _notifyPool;
  final int _readerId;
  int _dbHandleAddr = 0;
  SendPort? _sendPort;
  bool _closed = false;

  /// Persistent worker event port for this isolate lifetime.
  /// First message is the worker's command SendPort, then runtime events:
  /// normal replies, sacrifice payloads, and onExit notifications.
  /// Recreated on respawn so stale events die with the old isolate.
  RawReceivePort? _workerPort;

  /// The in-flight request's completer, if any.
  /// Used by the event port handler to fail the request if the worker
  /// dies without sending a reply (genuine native crash). This is also the
  /// authoritative "busy" bit for the slot: if it's non-null, dispatch must
  /// not send another request to this worker.
  Completer<Object?>? _pendingCompleter;

  /// A worker is available if it has a command port and no in-flight request.
  bool get isAvailable => _sendPort != null && _pendingCompleter == null;

  Future<void> spawn(int dbHandleAddr) async {
    if (_closed) return;
    _dbHandleAddr = dbHandleAddr;

    final completer = Completer<SendPort>.sync();

    final workerPort = _workerPort = RawReceivePort();
    workerPort.handler = (Object? msg) {
      if (msg case SendPort sendPort) {
        // Startup handshake: the worker publishes its send port.
        completer.complete(sendPort);
        return;
      }

      // onExit notification — the isolate has terminated.
      // If there's a pending completer, the worker crashed without
      // sending any reply (genuine native crash). If the completer
      // was already resolved by a prior event, this is a normal
      // post-sacrifice/post-close exit and we ignore it.
      if (msg == null) {
        // If the worker has been respawned by the preceding [Isolate.exit] message, then this exit message is a no-op.
        if (_workerPort != workerPort) {
          return;
        }

        _workerPort?.close();
        _workerPort = null;

        // An exit on startup indicates some crash most have occurred.
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Worker isolate crashed during startup'),
          );
          return;
        }

        // An exit with a pending completer indicates a crash during query execution.
        if (_pendingCompleter case Completer completer) {
          _pendingCompleter = null;
          _sendPort = null;
          completer.completeError(
            StateError('Worker isolate crashed during query execution'),
          );
          if (!_closed) unawaited(spawn(dbHandleAddr));
          _notifyPool();
        }
        return;
      }

      final pending = _pendingCompleter;
      _pendingCompleter = null;
      if (pending == null) {
        // Late event for a worker lifecycle we've already resolved.
        return;
      }

      final (result, sacrificed, error) =
          msg as (Object?, bool, ResqliteException?);

      // If the isolate has sacrified itself in order to return a large response,
      // then the pending request is resolved with the response and the worker
      // spawns a new isolate to replace it.
      if (sacrificed) {
        _sendPort = null;
        _workerPort?.close();
        _workerPort = null;

        if (error != null) {
          pending.completeError(error);
        } else {
          pending.complete(result);
        }
        if (!_closed) unawaited(spawn(_dbHandleAddr));

        // Otherwise, deliver the result and notify the pool that this worker is available
        // for its next request.
      } else {
        // Notify the pool that this worker is available again. This should be done *before* returning
        // the result, so that a worker is already available *before* the caller that the result will be returned
        // to can attempt to request more work.
        _notifyPool();

        if (error == null) {
          pending.complete(result);
        } else {
          pending.completeError(error);
        }
      }
    };

    await Isolate.spawn(
        readerEntrypoint,
        [
          dbHandleAddr,
          _readerId,
          workerPort.sendPort,
        ],
        onExit: workerPort.sendPort);

    _sendPort = await completer.future;
    _notifyPool();
  }

  Future<Object?> request(ReadRequest request) {
    final port = _sendPort;
    if (port == null) throw StateError('Worker not alive');
    if (_pendingCompleter != null) {
      throw StateError('Worker already has an in-flight request');
    }

    final completer = _pendingCompleter = Completer<Object?>.sync();
    port.send(request);
    return completer.future;
  }

  /// Drain-then-shutdown. If a query is in flight, we wait for it to
  /// complete before signalling the worker to exit — otherwise the
  /// worker could still be stepping over the shared SQLite handle when
  /// `Database.close()` frees it a few lines later.
  Future<void> close() async {
    _closed = true;
    final pending = _pendingCompleter;
    if (pending != null) {
      try {
        await pending.future;
      } catch (_) {
        // We only need the completion signal; the caller handles errors.
      }
    }
    _sendPort?.send(null);
    _sendPort = null;
    _workerPort?.close();
    _workerPort = null;
  }
}
