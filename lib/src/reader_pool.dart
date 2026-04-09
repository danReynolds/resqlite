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
/// reply via SendPort, then exits by closing its receive port. The pool
/// detects the sacrifice via the reply flag and initiates respawn immediately,
/// without waiting for the exitPort.
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
/// When a worker sacrifices (large result), the reply arrives via SendPort
/// with sacrifice=true. The replyPort handler marks the slot as dead and
/// initiates respawn immediately — it does NOT wait for the exitPort.
///
/// The exitPort is a safety net for genuine crashes (native segfault, OOM)
/// where the worker dies without sending any reply. In the sacrifice flow,
/// the exitPort fires later but is a no-op (pending completer already resolved).
class _WorkerSlot {
  _WorkerSlot(this._notifyPool, this._readerId);

  final void Function() _notifyPool;
  final int _readerId;
  int _dbHandleAddr = 0;
  SendPort? _sendPort;
  bool _alive = false;
  bool _busy = false;
  bool _closed = false;

  /// The in-flight request's completer and replyPort, if any.
  /// Used by the exitPort handler to fail the request if the worker
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

    final exitPort = RawReceivePort();
    exitPort.handler = (_) {
      exitPort.close();

      // Safety net: if the worker died with a pending request that was
      // never replied to (genuine native crash), fail the completer.
      // In the sacrifice flow, the replyPort handler already resolved
      // the completer and initiated respawn, so this is a no-op.
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
    };

    await Isolate.spawn(
      readerEntrypoint,
      [readyPort.sendPort, dbHandleAddr, _readerId],
      onExit: exitPort.sendPort,
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

      // Worker replies with (result, sacrificed, errorMessage) record.
      final (result, sacrificed, error) = msg as (Object?, bool, String?);

      if (error != null) {
        _busy = false;
        _notifyPool();
        completer.completeError(StateError(error));
        return;
      }

      if (sacrificed) {
        // Worker is exiting after sending this reply. Mark the slot as
        // dead and start respawning immediately. The exitPort will fire
        // later but is a no-op (completer already resolved).
        _alive = false;
        _sendPort = null;
        _busy = false;
        completer.complete((result, true));
        if (!_closed) unawaited(spawn(_dbHandleAddr));
        // Don't _notifyPool here — wait for spawn to complete.
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
  }
}
