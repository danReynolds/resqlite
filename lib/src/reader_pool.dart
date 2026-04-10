/// Reader pool — manages a fleet of read worker isolates.
///
/// Handles dispatch (round-robin with busy tracking), worker lifecycle
/// (spawn, sacrifice detection, respawn), and backpressure (callers wait
/// when all workers are busy). The actual query execution logic lives in
/// read_worker.dart.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'read_worker.dart';
import 'row.dart';

/// A pool of persistent reader isolates with automatic replacement.
///
/// Each worker handles one query at a time. Small results return via SendPort
/// (fast round-trip). Large results trigger sacrifice — the worker sends the
/// result via Isolate.exit (zero-copy) and the isolate terminates. The pool
/// detects the sacrifice and initiates respawn immediately.
///
/// Sacrifice and crash detection share a single control port per worker,
/// which receives both the Isolate.exit data and the onExit notification.
/// Because these arrive on the same port, the VM's same-port FIFO ordering
/// guarantees the data message is processed before the exit notification,
/// eliminating the race condition between the two.
///
/// Dispatch never sends two queries to the same worker. If all workers are
/// busy, callers wait until one becomes available (finishes its query or
/// respawns after sacrifice).
final class ReaderPool {
  ReaderPool._(this._workers);

  final List<_WorkerSlot> _workers;
  int _next = 0;

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
    final (result, sacrificed) = await _dispatch(
      (replyPort) => SelectRequest(replyPort, sql, parameters),
    );
    if (sacrificed) {
      // Sacrifice path sends raw components (primitives only) to avoid
      // Isolate.exit serialization issues. Reconstruct ResultSet here.
      final (values, columns, rowCount) =
          result as (List<Object?>, List<String>, int);
      return ResultSet(values, RowSchema(columns), rowCount);
    }
    return result as List<Map<String, Object?>>;
  }

  /// Execute a query and capture read dependencies (table names).
  Future<(List<Map<String, Object?>>, List<String>)> selectWithDeps(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final (result, sacrificed) = await _dispatch(
      (replyPort) => SelectWithDepsRequest(replyPort, sql, parameters),
    );
    if (sacrificed) {
      final (values, columns, rowCount, readTables) =
          result as (List<Object?>, List<String>, int, List<String>);
      return (
        ResultSet(values, RowSchema(columns), rowCount)
            as List<Map<String, Object?>>,
        readTables,
      );
    }
    return result as (List<Map<String, Object?>>, List<String>);
  }

  /// Execute a query returning JSON-encoded bytes.
  Future<Uint8List> selectBytes(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final (result, _) = await _dispatch(
      (replyPort) => SelectBytesRequest(replyPort, sql, parameters),
    );
    return result as Uint8List;
  }

  /// Execute a re-query with worker-side hash comparison.
  /// Returns `(rows, newHash)` if changed, or `(null, lastHash)` if unchanged.
  Future<(List<Map<String, Object?>>?, int)> selectIfChanged(
    String sql,
    List<Object?> parameters,
    int lastResultHash,
  ) async {
    final (result, sacrificed) = await _dispatch(
      (replyPort) => SelectIfChangedRequest(
        replyPort, sql, parameters, lastResultHash,
      ),
    );
    if (sacrificed) {
      final (hash, values, columns, rowCount) =
          result as (int, List<Object?>, List<String>, int);
      return (
        ResultSet(values, RowSchema(columns), rowCount)
            as List<Map<String, Object?>>?,
        hash,
      );
    }
    final (hash, rows) = result as (int, List<Map<String, Object?>>?);
    return (rows, hash);
  }

  /// Returns (result, sacrificed) — callers reconstruct typed results.
  Future<(Object?, bool)> _dispatch(
    ReadRequest Function(SendPort replyPort) buildRequest,
  ) async {
    final count = _workers.length;

    while (true) {
      for (var attempt = 0; attempt < count; attempt++) {
        final slot = _workers[_next % count];
        _next++;
        if (slot.isAvailable) {
          return slot.request(buildRequest);
        }
      }

      // All workers busy or dead. Wait for any to become available.
      _workerAvailable ??= Completer<void>.sync();
      await _workerAvailable!.future;
    }
  }

  void close() {
    for (final slot in _workers) {
      slot.close();
    }
  }
}

/// Manages a single worker isolate's lifecycle.
///
/// Uses a persistent control port per worker that receives both sacrifice
/// data (via Isolate.exit) and onExit notifications. Because both arrive
/// on the same port, the VM's same-port FIFO ordering guarantees the
/// Isolate.exit data is processed before the onExit null — eliminating
/// the race condition that previously caused false crash detection.
///
/// This is the same pattern the Dart SDK uses in Isolate.run.
class _WorkerSlot {
  _WorkerSlot(this._notifyPool, this._readerId);

  final void Function() _notifyPool;
  final int _readerId;
  int _dbHandleAddr = 0;
  SendPort? _sendPort;
  bool _alive = false;
  bool _busy = false;
  bool _closed = false;

  /// Persistent control port — receives sacrifice data (via Isolate.exit)
  /// and onExit notifications on the same port for ordering guarantees.
  RawReceivePort? _controlPort;

  /// The in-flight request's completer and replyPort, if any.
  /// Used by the control port handler to fail the request if the worker
  /// dies without sending a reply (genuine native crash).
  Completer<Object?>? _pendingCompleter;
  RawReceivePort? _pendingReplyPort;

  /// A worker is available if it's alive, has a SendPort, and isn't busy.
  bool get isAvailable => _alive && _sendPort != null && !_busy;

  Future<void> spawn(int dbHandleAddr) async {
    if (_closed) return;
    _alive = false;
    _dbHandleAddr = dbHandleAddr;

    final readyPort = RawReceivePort();
    final completer = Completer<SendPort>.sync();
    readyPort.handler = (Object? msg) {
      readyPort.close();
      completer.complete(msg as SendPort);
    };

    // Create a fresh control port for this worker's lifetime.
    // Both Isolate.exit data and onExit notifications arrive here.
    _controlPort?.close();
    _controlPort = RawReceivePort();
    _controlPort!.handler = (Object? msg) {
      if (msg == null) {
        // onExit notification — the isolate has terminated.
        // If there's a pending completer, the worker crashed without
        // sending data (genuine native crash). If the completer was
        // already resolved by a sacrifice data message, this is a no-op.
        final pending = _pendingCompleter;
        if (pending != null && !pending.isCompleted) {
          _pendingReplyPort?.close();
          _pendingReplyPort = null;
          _pendingCompleter = null;
          _alive = false;
          _sendPort = null;
          _busy = false;
          pending.completeError(StateError(
            'Worker isolate crashed during query execution',
          ));
          if (!_closed) unawaited(spawn(dbHandleAddr));
          _notifyPool();
        }
        return;
      }

      // Sacrifice data arrived via Isolate.exit (zero-copy).
      // The onExit null will follow on this same port but the completer
      // will already be resolved, making it a no-op.
      _pendingReplyPort?.close();
      _pendingReplyPort = null;
      final pending = _pendingCompleter;
      _pendingCompleter = null;

      final (result, _, error) = msg as (Object?, bool, String?);

      _alive = false;
      _sendPort = null;
      _busy = false;

      if (error != null) {
        pending?.completeError(StateError(error));
      } else {
        pending?.complete((result, true));
      }
      if (!_closed) unawaited(spawn(_dbHandleAddr));
      // Don't _notifyPool here — wait for spawn to complete.
    };

    await Isolate.spawn(
      readerEntrypoint,
      [readyPort.sendPort, dbHandleAddr, _readerId, _controlPort!.sendPort],
      onExit: _controlPort!.sendPort,
    );

    _sendPort = await completer.future;
    _alive = true;
    _notifyPool();
  }

  Future<(Object?, bool)> request(
    ReadRequest Function(SendPort replyPort) buildRequest,
  ) {
    final port = _sendPort;
    if (port == null) throw StateError('Worker not alive');

    _busy = true;
    final replyPort = RawReceivePort();
    final completer = Completer<(Object?, bool)>.sync();

    _pendingCompleter = completer;
    _pendingReplyPort = replyPort;

    replyPort.handler = (Object? msg) {
      replyPort.close();
      _pendingCompleter = null;
      _pendingReplyPort = null;

      // Normal (non-sacrifice) reply via SendPort.send.
      final (result, _, error) = msg as (Object?, bool, String?);

      if (error != null) {
        _busy = false;
        _notifyPool();
        completer.completeError(StateError(error));
        return;
      }

      _busy = false;
      _notifyPool();
      completer.complete((result, false));
    };

    port.send(buildRequest(replyPort.sendPort));
    return completer.future;
  }

  void close() {
    _closed = true;
    _sendPort?.send(null);
    _alive = false;
    _sendPort = null;
    _controlPort?.close();
    _controlPort = null;
  }
}
