/// Base exception for all resqlite errors.
///
/// See also:
///
/// - [ResqliteQueryException], for SQL and constraint errors
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
  /// the full list.
  final int? sqliteCode;

  @override
  String toString() =>
      'ResqliteQueryException: $message\n  SQL: $sql'
      '${parameters != null ? '\n  Params: $parameters' : ''}'
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
