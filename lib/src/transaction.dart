import 'dart:async';

import 'package:resqlite/resqlite.dart';
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

  bool _active = true;

  Transaction(this._writer);

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
  ]) async {
    _ensureActive();
    final response = await _writer.execute(sql, parameters);
    return response.result;
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
    return _writer.select(sql, parameters);
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
  Future<void> executeBatch(
    String sql,
    List<List<Object?>> paramSets,
  ) async {
    _ensureActive();
    await _writer.executeBatch(sql, paramSets);
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
  Future<T> transaction<T>(Future<T> Function(Transaction tx) body) {
    _ensureActive();
    return _writer.transaction(body);
  }

  void close() {
    _active = false;
  }
}
