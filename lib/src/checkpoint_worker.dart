/// Dedicated isolate for PASSIVE WAL checkpoints.
///
/// The writer WAL hook only marks a coalesced, high-water-gated request. After
/// a successful commit the writer isolate claims that request and sends
/// [CheckpointRun] directly here, keeping checkpoint I/O off the writer's
/// reply path.
@ffi.DefaultAsset('package:resqlite/src/native/resqlite_bindings.dart')
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'native/resqlite_bindings.dart';

/// Internal signal sent by the writer isolate after it claims a checkpoint.
final class CheckpointRun {
  const CheckpointRun();
}

final class _CheckpointClose {
  const _CheckpointClose(this.replyPort);

  final SendPort replyPort;
}

final class _CheckpointFailure {
  const _CheckpointFailure(this.sqliteCode);

  final int sqliteCode;
}

/// Owns the lifecycle of the background checkpoint isolate.
final class CheckpointWorker {
  CheckpointWorker._(this._eventPort);

  final RawReceivePort _eventPort;
  SendPort? _sendPort;
  bool _closed = false;
  int _lastSqliteError = 0;

  /// The port handed directly to the writer isolate for checkpoint signals.
  SendPort get sendPort {
    final port = _sendPort;
    if (port == null) throw StateError('Checkpoint worker is not running.');
    return port;
  }

  /// Last non-BUSY asynchronous checkpoint error, for internal diagnostics.
  ///
  /// A PASSIVE checkpoint can also return SQLITE_OK with partial progress when
  /// a reader pins WAL frames; that is a bounded outcome rather than an error.
  int get lastSqliteError => _lastSqliteError;

  static Future<CheckpointWorker> spawn(ffi.Pointer<ffi.Void> handle) async {
    final handshake = Completer<SendPort>.sync();
    late final CheckpointWorker worker;
    final eventPort = RawReceivePort();
    worker = CheckpointWorker._(eventPort);
    eventPort.handler = (Object? message) {
      switch (message) {
        case SendPort port:
          if (!handshake.isCompleted) handshake.complete(port);
        case _CheckpointFailure(:final sqliteCode):
          worker._lastSqliteError = sqliteCode;
      }
    };

    await Isolate.spawn(checkpointEntrypoint, [
      eventPort.sendPort,
      handle.address,
    ], debugName: 'resqlite.checkpoint');
    worker._sendPort = await handshake.future;

    // Extension setup can commit before runtime workers are spawned. Claim
    // and drain any threshold crossing left behind by that setup work.
    if (resqliteCheckpointTakeRequest(handle) == 1) {
      worker.sendPort.send(const CheckpointRun());
    }

    return worker;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    final port = _sendPort;
    if (port != null) {
      final reply = ReceivePort();
      port.send(_CheckpointClose(reply.sendPort));
      await reply.first;
      reply.close();
      _sendPort = null;
    }
    _eventPort.close();
  }
}

/// Entry point for the isolate that exclusively owns the checkpoint
/// connection embedded in the native database handle.
void checkpointEntrypoint(List<Object> args) {
  final eventPort = args[0] as SendPort;
  final dbHandle = ffi.Pointer<ffi.Void>.fromAddress(args[1] as int);
  final receivePort = RawReceivePort();
  final outLogFrames = calloc<ffi.Int>();
  final outCheckpointedFrames = calloc<ffi.Int>();

  void runClaimedCheckpoints() {
    while (true) {
      final rc = resqliteCheckpointRunPassive(
        dbHandle,
        outLogFrames,
        outCheckpointedFrames,
      );
      // SQLITE_BUSY is an expected best-effort PASSIVE outcome. Any other
      // error is retained for internal diagnostics; a future threshold epoch
      // is still allowed to retry.
      if (rc != 0 && rc != 5) {
        eventPort.send(_CheckpointFailure(rc));
      }
      if (resqliteCheckpointTakeRequest(dbHandle) != 1) break;
    }
  }

  receivePort.handler = (Object? message) {
    switch (message) {
      case CheckpointRun():
        runClaimedCheckpoints();
      case _CheckpointClose(:final replyPort):
        // This close comes from the main isolate while CheckpointRun comes
        // from the writer isolate, so their delivery order is not guaranteed.
        // Atomically adopt an already-claimed request when close overtakes its
        // wakeup, or claim a pending request. Skip work when truly idle.
        if (resqliteCheckpointClaimForClose(dbHandle) == 1) {
          runClaimedCheckpoints();
        }
        receivePort.close();
        calloc.free(outLogFrames);
        calloc.free(outCheckpointedFrames);
        replyPort.send(true);
    }
  };

  eventPort.send(receivePort.sendPort);
}
