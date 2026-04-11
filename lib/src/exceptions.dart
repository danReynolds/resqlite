/// Base exception for all resqlite errors.
///
/// See also:
///
/// - [ResqliteQueryException], for SQL and constraint errors
/// - [ResqliteTransactionException], for BEGIN/COMMIT/ROLLBACK failures
/// - [ResqliteConnectionException], for lifecycle errors
class ResqliteException implements Exception {
  ResqliteException(this.message);

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => 'ResqliteException: $message';
}

/// An error caused by a SQL query — malformed SQL, constraint violations,
/// or runtime execution failures.
///
/// ```dart
/// try {
///   await db.execute('INSERT INTO users(id) VALUES (?)', [1]);
/// } on ResqliteQueryException catch (e) {
///   print(e.message);    // "UNIQUE constraint failed: users.id"
///   print(e.sql);        // "INSERT INTO users(id) VALUES (?)"
///   print(e.sqliteCode); // 19 (SQLITE_CONSTRAINT)
/// }
/// ```
///
/// The [sqliteCode] is the raw SQLite [result code](https://www.sqlite.org/rescode.html).
/// Common values:
///
/// - `1` `SQLITE_ERROR` — generic
/// - `5` `SQLITE_BUSY` — another writer holds the lock
/// - `19` `SQLITE_CONSTRAINT` — a CHECK, UNIQUE, NOT NULL, or FOREIGN KEY
///   constraint failed. Extended codes narrow it: `787` FK, `1555` PK,
///   `2067` UNIQUE, etc.
class ResqliteQueryException extends ResqliteException {
  ResqliteQueryException(
    super.message, {
    required this.sql,
    this.parameters,
    this.sqliteCode,
  });

  /// The SQL statement that caused the error.
  final String sql;

  /// The bound parameters, if any.
  final List<Object?>? parameters;

  /// The SQLite result code (e.g., 19 for SQLITE_CONSTRAINT).
  ///
  /// See [SQLite result codes](https://www.sqlite.org/rescode.html) for
  /// the full list. `null` if the error did not originate from SQLite
  /// itself (e.g., parameter marshalling failures).
  final int? sqliteCode;

  @override
  String toString() =>
      'ResqliteQueryException: $message\n  SQL: $sql'
      '${parameters != null ? '\n  Params: $parameters' : ''}'
      '${sqliteCode != null ? '\n  SQLite code: $sqliteCode' : ''}';
}

/// An error raised by the library's own transaction control (BEGIN,
/// COMMIT, ROLLBACK, SAVEPOINT, RELEASE). These statements are issued by
/// resqlite, not by the caller, so there is no user-written SQL to
/// surface — the [operation] field identifies which control statement
/// failed and [sqliteCode] carries SQLite's reason.
///
/// The most common cause is a deferred foreign-key violation surfacing at
/// COMMIT time:
///
/// ```dart
/// try {
///   await db.transaction((tx) async {
///     await tx.execute('INSERT INTO child(pid) VALUES (?)', [999]);
///   });
/// } on ResqliteTransactionException catch (e) {
///   print(e.operation);  // 'commit'
///   print(e.sqliteCode); // 787 (SQLITE_CONSTRAINT_FOREIGNKEY)
/// }
/// ```
class ResqliteTransactionException extends ResqliteException {
  ResqliteTransactionException(
    super.message, {
    required this.operation,
    this.sqliteCode,
  });

  /// The transaction control operation that failed:
  /// `'begin'`, `'commit'`, `'rollback'`, `'savepoint'`, `'release'`,
  /// or `'rollback_to'`.
  final String operation;

  /// The SQLite result code, if the failure came from SQLite.
  final int? sqliteCode;

  @override
  String toString() =>
      'ResqliteTransactionException: $message\n  Operation: $operation'
      '${sqliteCode != null ? '\n  SQLite code: $sqliteCode' : ''}';
}

/// An error related to database lifecycle — opening, closing, or using
/// a database that is no longer available.
///
/// Thrown when:
/// - [Database.open] fails (file not writable, bad encryption key)
/// - Any operation is attempted after [Database.close]
class ResqliteConnectionException extends ResqliteException {
  ResqliteConnectionException(super.message);

  @override
  String toString() => 'ResqliteConnectionException: $message';
}
