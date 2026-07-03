import 'dart:async';
import 'dart:collection';

import 'package:resqlite/resqlite.dart';
import 'package:resqlite/src/profile_counters.dart';
import 'package:resqlite/src/profile_mode.dart';
import 'package:resqlite/src/tracelite_profile.dart';
import 'package:resqlite/src/writer/write_worker.dart';
import 'package:resqlite/src/writer/writer.dart';

/// A transaction proxy object for executing writes and reads atomically.
///
/// Obtained via [Database.transaction]. All operations use the writer
/// connection, so reads see uncommitted writes from earlier statements
/// in the same transaction.
///
/// Supports nested transactions via [transaction], which uses SQLite
/// SAVEPOINTs under the hood:
///
/// ```dart
/// await db.transaction((tx) async {
///   await tx.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
///
///   // Nested transaction — uses SAVEPOINT internally.
///   await tx.transaction((inner) async {
///     await inner.execute('INSERT INTO users(name) VALUES (?)', ['Bob']);
///     // Throw here to roll back only Bob's insert.
///   });
///
///   final rows = await tx.select('SELECT COUNT(*) as c FROM users');
///   print(rows.first['c']); // includes Ada (and Bob if inner didn't throw)
/// });
/// ```
final class Transaction {
  final Writer _writer;
  final int? _traceCorrelationId;

  bool _active = true;

  // Exp 213: buffered execute() calls waiting for the next microtask flush.
  // A Future.wait-style burst inside the transaction body accumulates in
  // this queue and goes out as a single MultiExecuteRequest against the
  // still-open transaction.
  final ListQueue<_PendingTxWrite> _pendingWrites =
      ListQueue<_PendingTxWrite>();
  bool _flushScheduled = false;

  // Number of write requests we've handed to the writer that haven't
  // replied yet. Distinguishes the sequential-await pattern
  // (`await tx.execute(...); await tx.execute(...)`) from the burst
  // pattern (`Future.wait([tx.execute(...), tx.execute(...)])`): when a
  // caller reaches [execute] with `_inFlightWrites == 0` and the buffer
  // empty, no other execute() in the tx is racing, so the fast path
  // sends synchronously and skips the microtask hop.
  int _inFlightWrites = 0;

  Transaction(this._writer, {int? traceCorrelationId})
    : _traceCorrelationId = traceCorrelationId;

  /// Zone key storing the active [Transaction] when inside a transaction body.
  /// Database methods check this to transparently route through the transaction
  /// instead of deadlocking on the write lock.
  static const currentZoneKey = #_activeTransaction;

  /// Returns the current [Transaction] if any.
  static Transaction? get current {
    return Zone.current[currentZoneKey] as Transaction?;
  }

  void _ensureActive() {
    if (!_active) {
      throw StateError(
        'Transaction is no longer active. A Transaction may only be '
        'used inside the body passed to Database.transaction() or '
        'Transaction.transaction(). Do not hold references past the end '
        'of the body.',
      );
    }
  }

  /// Executes a write statement within this transaction.
  ///
  /// Same as [Database.execute], but the write is part of the enclosing
  /// transaction and only commits when the transaction completes.
  ///
  /// Throws [StateError] if called after the enclosing transaction body
  /// has returned.
  Future<WriteResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    _ensureActive();
    final correlationId = _traceCorrelationId;
    // Fast path (exp 213): no other write is in flight or buffered, so
    // the caller is in a sequential-await pattern (the common case).
    // The dedicated async helper preserves the pre-213 single-await
    // microtask cost — using `.then().whenComplete()` on the caller
    // side adds two extra chained-callback hops per call, which showed
    // up as measurable regressions on the tx-interleaved-select lane.
    if (_pendingWrites.isEmpty && _inFlightWrites == 0) {
      return _fastPathExecute(sql, parameters, correlationId);
    }
    // Slow path: another write is in flight (Future.wait burst pattern)
    // or already-buffered writes are waiting for the current microtask
    // to end. Buffer and let the scheduled flush turn the group into
    // one MultiExecuteRequest.
    //
    // Snapshot the caller's parameters (`List.of(...)`) at buffer time —
    // the send is deferred to the next microtask, and a caller who
    // reuses/mutates the same list instance between `tx.execute` calls
    // would otherwise bind whatever the list held at flush time. The
    // pre-213 immediate-send path bound at call time, so this preserves
    // that semantic.
    final completer = Completer<WriteResult>.sync();
    _pendingWrites.add(
      _PendingTxWrite(sql, List<Object?>.of(parameters), correlationId, completer),
    );
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flushPending);
    }
    return completer.future;
  }

  Future<WriteResult> _fastPathExecute(
    String sql,
    List<Object?> parameters,
    int? correlationId,
  ) async {
    _inFlightWrites++;
    try {
      final ExecuteResponse response;
      if (correlationId == null || !(kProfileMode && kTraceliteProfileMode)) {
        response = await _writer.executeLocked(sql, parameters, correlationId);
      } else {
        // Preserve pre-213 Dart-side `databaseExecute` tracelite span on
        // the fast path so profile builds see the same span shape they
        // did before this experiment. The slow path traces the batch
        // send via [_flushPending] instead.
        final sqlId = TraceliteProfile.internString(sql);
        response = await TraceliteProfile.traceAsync(
          TraceliteResqliteSpans.databaseExecute,
          () => _writer.executeLocked(sql, parameters, correlationId),
          correlationId: correlationId,
          beginArgs: [sqlId, parameters.length],
          endArgs: (r) => [r.result.affectedRows],
        );
      }
      ProfileCounters.recordWriterSqlite(response.writerSqliteUs);
      return response.result;
    } finally {
      _inFlightWrites--;
    }
  }

  /// Flushes any buffered writes so subsequent reads / nested tx / batch
  /// / close see the effects of prior [execute] calls. Guarantees FIFO
  /// order against later `await`-linked work.
  Future<void> _drainBuffer() async {
    while (_pendingWrites.isNotEmpty) {
      await _flushPending();
    }
  }

  Future<void> _flushPending() async {
    if (_pendingWrites.isEmpty) {
      _flushScheduled = false;
      return;
    }
    final group = List<_PendingTxWrite>.of(_pendingWrites);
    _pendingWrites.clear();
    _flushScheduled = false;

    try {
      if (group.length == 1) {
        // Singleton: use the existing single-execute path so the
        // sequential-await pattern pays only the microtask-hop overhead
        // (no MultiExecuteRequest packing).
        final p = group.first;
        try {
          final response = await _writer.executeLocked(
            p.sql,
            p.parameters,
            p.traceCorrelationId,
          );
          ProfileCounters.recordWriterSqlite(response.writerSqliteUs);
          p.completer.complete(response.result);
        } on ResqliteException catch (e) {
          p.completer.completeError(e);
        }
      } else {
        // Burst: send as one MultiExecuteRequest. The writer's handler
        // runs each statement inside the still-open transaction
        // (`txDepth > 0` returns `TableDependencies.none` per outcome —
        // dirty sets accumulate through the outermost commit) and
        // returns one outcome per statement. The tx-level correlation
        // id covers the whole batch — pre-213 each `ExecuteRequest`
        // carried its own, but a coalesced group all belongs to the
        // same enclosing transaction so one id is the right shape.
        try {
          final response = await _writer.multiExecuteLocked(
            [for (final p in group) (sql: p.sql, params: p.parameters)],
            traceCorrelationId: _traceCorrelationId,
          );
          final outcomes = response.outcomes;
          for (var i = 0; i < group.length; i++) {
            final p = group[i];
            switch (outcomes[i]) {
              case final ExecuteResponse r:
                ProfileCounters.recordWriterSqlite(r.writerSqliteUs);
                p.completer.complete(r.result);
              case final ResqliteException error:
                p.completer.completeError(error);
              default:
                p.completer.completeError(
                  ResqliteException(
                    'Internal writer error: missing outcome in tx multi-execute',
                  ),
                );
            }
          }
        } on ResqliteException catch (e) {
          // Whole-group failure (e.g. isolate closed mid-send) — fail
          // every still-pending completer rather than hang them.
          for (final p in group) {
            if (!p.completer.isCompleted) p.completer.completeError(e);
          }
        }
      }
    } catch (e) {
      // Belt-and-braces for anything that slipped past the ResqliteException
      // catches above — don't leave a caller's future hanging.
      for (final p in group) {
        if (!p.completer.isCompleted) p.completer.completeError(e);
      }
    }
  }

  /// Executes a query within this transaction, seeing uncommitted writes.
  ///
  /// This runs on the writer connection (not the reader pool) so it can
  /// see rows inserted or updated earlier in the same transaction.
  ///
  /// Throws [StateError] if called after the enclosing transaction body
  /// has returned.
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _ensureActive();
    // Reads must see the effects of buffered writes.
    if (_pendingWrites.isNotEmpty) await _drainBuffer();
    final correlationId = _traceCorrelationId;
    if (correlationId == null || !(kProfileMode && kTraceliteProfileMode)) {
      final response = await _writer.selectLocked(
        sql,
        parameters,
        correlationId,
      );
      ProfileCounters.recordWriterSqlite(response.writerSqliteUs);
      return response.rows;
    }
    final sqlId = TraceliteProfile.internString(sql);
    final response = await TraceliteProfile.traceAsync(
      TraceliteResqliteSpans.databaseSelect,
      () => _writer.selectLocked(sql, parameters, correlationId),
      correlationId: correlationId,
      beginArgs: [sqlId, parameters.length],
      endArgs: (response) => [response.rows.length],
    );
    ProfileCounters.recordWriterSqlite(response.writerSqliteUs);
    return response.rows;
  }

  /// Executes one SQL statement across many parameter sets within this
  /// transaction.
  ///
  /// ```dart
  /// await db.transaction((tx) async {
  ///   await tx.executeBatch(
  ///     'INSERT INTO users(name) VALUES (?)',
  ///     [['Ada'], ['Grace'], ['Sonja']],
  ///   );
  /// });
  /// ```
  ///
  /// Runs as a single isolate round-trip: the flattened param array crosses
  /// once, the statement is prepared (or fetched from the writer cache) once,
  /// and bind+step is looped entirely in C. The enclosing transaction provides
  /// atomicity — no inner BEGIN/COMMIT is issued. On error this throws, and
  /// the enclosing scope (top-level transaction or savepoint) rolls back.
  ///
  /// Throws [StateError] if called after the enclosing transaction body
  /// has returned.
  Future<void> executeBatch(String sql, List<List<Object?>> paramSets) async {
    _ensureActive();
    // Batch runs on the same writer connection but through a different
    // request type — buffered execute() calls must land first to preserve
    // FIFO order against the batch.
    if (_pendingWrites.isNotEmpty) await _drainBuffer();
    final correlationId = _traceCorrelationId;
    if (correlationId == null || !(kProfileMode && kTraceliteProfileMode)) {
      final response = await _writer.executeBatchLocked(
        sql,
        paramSets,
        traceCorrelationId: correlationId,
      );
      if (response != null) {
        ProfileCounters.recordWriterSqlite(response.writerSqliteUs);
      }
      return;
    }
    final sqlId = TraceliteProfile.internString(sql);
    final paramCount = paramSets.isEmpty ? 0 : paramSets.first.length;
    final response = await TraceliteProfile.traceAsync(
      TraceliteResqliteSpans.databaseExecuteBatch,
      () => _writer.executeBatchLocked(
        sql,
        paramSets,
        traceCorrelationId: correlationId,
      ),
      correlationId: correlationId,
      beginArgs: [sqlId, paramCount, paramSets.length],
    );
    if (response != null) {
      ProfileCounters.recordWriterSqlite(response.writerSqliteUs);
    }
  }

  /// Initiates a nested transaction as a new savepoint. If [body] completes normally,
  /// the savepoint is released (changes become part of the enclosing transaction).
  /// If [body] throws, the savepoint is rolled back (only this nested transaction's changes are undone)
  /// and the exception is rethrown.
  ///
  /// ```dart
  /// await db.transaction((tx) async {
  ///   await tx.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
  ///   try {
  ///     await tx.transaction((inner) async {
  ///       await inner.execute('INSERT INTO users(name) VALUES (?)', ['Bob']);
  ///       throw StateError('oops');
  ///     });
  ///   } on StateError {
  ///     // Bob's insert is rolled back; Ada's remains.
  ///   }
  /// });
  /// ```
  Future<T> transaction<T>(Future<T> Function(Transaction tx) body) async {
    _ensureActive();
    // Buffered writes must be committed to the outer scope before the
    // savepoint begins — otherwise a rollback of the inner would also
    // undo them.
    if (_pendingWrites.isNotEmpty) await _drainBuffer();
    return _writer.transaction(body, traceCorrelationId: _traceCorrelationId);
  }

  /// Non-empty when the tx body is holding buffered fire-and-forget
  /// `tx.execute()` calls that haven't been flushed. Read by
  /// [Writer.transaction] to skip the [drainForClose] microtask hop for
  /// the common case where every execute was sequentially awaited
  /// (buffer was drained inline).
  bool get hasPendingWrites => _pendingWrites.isNotEmpty;

  /// Called by [Writer.transaction] after `body` returns (or throws). Flushes
  /// any un-awaited buffered writes so their effects reach SQLite before the
  /// enclosing COMMIT / ROLLBACK — matches the pre-exp-213 behavior where
  /// fire-and-forget `tx.execute()` calls still landed in the tx.
  Future<void> drainForClose() async {
    if (_pendingWrites.isNotEmpty) await _drainBuffer();
  }

  void close() {
    _active = false;
  }
}

/// A buffered `Transaction.execute` call plus the caller's completer.
final class _PendingTxWrite {
  _PendingTxWrite(this.sql, this.parameters, this.traceCorrelationId, this.completer);
  final String sql;
  final List<Object?> parameters;
  final int? traceCorrelationId;
  final Completer<WriteResult> completer;
}
