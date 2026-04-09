/// Reader pool — manages a fleet of read worker isolates.
///
/// Handles dispatch (round-robin with busy tracking), worker lifecycle
/// (spawn, sacrifice detection, respawn), and backpressure (callers wait
/// when all workers are busy). The actual query execution logic lives in
/// read_worker.dart.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'read_worker.dart';
import 'row.dart';

/// A pool of persistent reader isolates with automatic replacement.
///
/// Each worker handles one query at a time. Small results return via SendPort
/// (fast round-trip). Large results trigger Isolate.exit (zero-copy transfer),
/// killing the worker — the pool detects the death and spawns a replacement.
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
      // Sacrifice path sends raw components for reliable Isolate.exit.
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

    // Retry loop: find an available (alive + not busy) worker.
    // If none are available, wait for a notification and try again.
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
/// Tracks busy state to prevent multiple queries from being dispatched
/// to the same worker simultaneously. When a worker sacrifices via
/// [Isolate.exit] (zero-copy transfer for large results), the slot stays
/// unavailable until the replacement worker finishes spawning.
///
/// The worker signals sacrifice via the reply envelope — see
/// [ReadRequest] in read_worker.dart. The reply is a record
/// `(result, sacrificed, errorMessage)`. If [sacrificed] is true,
/// we don't call [_notifyPool] because the worker is dying — the
/// exitPort handler triggers respawn, which calls [_notifyPool] when
/// the new worker is ready. This prevents a race where callers claim
/// a slot between the replyPort handler (fires first) and the exitPort
/// handler (fires later, marks the slot as dead).
class _WorkerSlot {
  _WorkerSlot(this._notifyPool, this._readerId);

  final void Function() _notifyPool;
  final int _readerId;
  SendPort? _sendPort;
  bool _alive = false;
  bool _busy = false;
  bool _closed = false;
  int _generation = 0; // incremented on each spawn for diagnostics

  /// The in-flight request's completer and replyPort, if any.
  /// Used by the exitPort handler to fail the request if the worker
  /// dies without sending a reply (native crash / segfault).
  Completer<Object?>? _pendingCompleter;
  RawReceivePort? _pendingReplyPort;

  /// Whether the last completed request was a sacrifice.
  /// Used by the exitPort handler to distinguish expected exits
  /// (sacrifice) from unexpected crashes.
  bool _lastRequestSacrificed = false;

  /// A worker is available if it's alive, has a SendPort, and isn't busy.
  bool get isAvailable => _alive && _sendPort != null && !_busy;

  Future<void> spawn(int dbHandleAddr) async {
    if (_closed) return;
    _alive = false;
    _generation++;
    final gen = _generation;

    final readyPort = RawReceivePort();
    final completer = Completer<SendPort>.sync();
    readyPort.handler = (Object? msg) {
      readyPort.close();
      completer.complete(msg as SendPort);
    };

    // Error listener — catches uncaught exceptions in the worker isolate
    // that would otherwise silently kill it.
    final errorPort = RawReceivePort();
    errorPort.handler = (Object? msg) {
      final errors = msg as List;
      stderr.writeln(
        '[resqlite] Worker $_readerId gen$gen UNCAUGHT ERROR: '
        '${errors[0]}\n${errors[1]}',
      );
    };

    final exitPort = RawReceivePort();
    exitPort.handler = (_) {
      exitPort.close();
      errorPort.close();
      _alive = false;
      _sendPort = null;

      // If the worker died with an in-flight request (native crash),
      // fail the pending completer so the caller doesn't hang forever.
      final pending = _pendingCompleter;
      if (pending != null && !pending.isCompleted) {
        _pendingReplyPort?.close();
        _pendingReplyPort = null;
        _pendingCompleter = null;
        _busy = false;
        stderr.writeln(
          '[resqlite] Worker $_readerId gen$gen CRASHED with pending request '
          '(lastSacrificed=$_lastRequestSacrificed, busy=$_busy)',
        );
        pending.completeError(StateError(
          'Worker isolate crashed during query execution '
          '(reader=$_readerId, gen=$gen)',
        ));
        _notifyPool();
      } else {
        // Expected exit: either sacrifice (replyPort already delivered)
        // or graceful close.
        if (_lastRequestSacrificed) {
          stderr.writeln(
            '[resqlite] Worker $_readerId gen$gen exited after sacrifice (expected)',
          );
        }
      }

      _lastRequestSacrificed = false;

      if (!_closed) {
        unawaited(spawn(dbHandleAddr));
      }
    };

    await Isolate.spawn(
      readerEntrypoint,
      [readyPort.sendPort, dbHandleAddr, _readerId],
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
    );

    _sendPort = await completer.future;
    _alive = true;
    _notifyPool(); // Wake up callers waiting for a worker.
  }

  Future<(Object?, bool)> request(
    ReadRequest Function(SendPort replyPort) buildRequest,
  ) {
    final port = _sendPort;
    if (port == null) throw StateError('Worker not alive');

    _busy = true;
    _lastRequestSacrificed = false;
    final replyPort = RawReceivePort();
    final completer = Completer<(Object?, bool)>.sync();

    // Track the pending request so the exitPort handler can fail it
    // if the worker crashes before replying.
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

      // Track sacrifice state so the exitPort handler can distinguish
      // expected exits from crashes.
      _lastRequestSacrificed = sacrificed;

      // If sacrificed, the worker is dying — don't mark as available.
      // The exitPort handler will trigger respawn + _notifyPool.
      _busy = false;
      if (!sacrificed) {
        _notifyPool();
      }
      completer.complete((result, sacrificed));
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
