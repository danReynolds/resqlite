import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:resqlite/src/transaction.dart';
import 'package:resqlite/src/writer/writer.dart';

import 'exceptions.dart';
import 'native/resqlite_bindings.dart';
import 'reader/reader_pool.dart';
import 'stream_engine.dart';

/// A high-performance SQLite database with reactive queries.
///
/// All reads, writes, and reactive re-queries run off the main isolate
/// on persistent worker isolates, keeping your UI thread free.
///
/// ```dart
/// final db = await Database.open('app.db');
///
/// final rows = await db.select('SELECT * FROM users WHERE active = ?', [1]);
/// await db.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
///
/// db.stream('SELECT * FROM users').listen((users) {
///   print('${users.length} users');
/// });
///
/// await db.close();
/// ```
///
/// See also:
///
/// - [Transaction], for multi-statement atomic writes with read visibility
/// - [StreamEngine], for the reactive query lifecycle internals
final class Database {
  Database._(this._handle, int readerCount) {
    // Spawn the single writer isolate.
    _writer = Writer.spawn(_streamEngine, _handle);

    // Spawn the reader pool.
    _readerPool = ReaderPool.spawn(handle.address, readerCount);
  }

  late final Future<Writer> _writer;
  late final Future<ReaderPool> _readerPool;

  final ffi.Pointer<ffi.Void> _handle;
  bool _closed = false;

  // Reactive query engine — owns stream lifecycle, uses reader pool for queries.
  late final StreamEngine _streamEngine = StreamEngine(() => _readerPool);

  /// The raw native database handle.
  ///
  /// Exposed for advanced FFI interop only. Most applications should not
  /// need this.
  ffi.Pointer<ffi.Void> get handle => _handle;

  /// The reactive query engine.
  ///
  /// Exposed for testing stream cleanup behavior. Use [stream] for the
  /// public reactive query API.
  StreamEngine get streamEngine => _streamEngine;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  void _ensureOpen() {
    if (_closed) throw ResqliteConnectionException('Database is closed.');
  }

  /// Opens or creates a SQLite database at [path].
  ///
  /// ```dart
  /// final db = await Database.open('app.db');
  /// ```
  ///
  /// If the file at [path] does not exist, a new database is created.
  /// Reader and writer isolates are spawned non-blocking during open —
  /// the first query awaits their readiness automatically.
  ///
  /// If [encryptionKey] is provided, the database is encrypted using
  /// SQLite3 Multiple Ciphers (AES-256). The key must be a hex-encoded
  /// string (64 hex chars for a 256-bit key). All connections (writer +
  /// reader pool) use the same key.
  ///
  /// ```dart
  /// final db = await Database.open(
  ///   'secure.db',
  ///   encryptionKey: '0123456789abcdef0123456789abcdef'
  ///       '0123456789abcdef0123456789abcdef',
  /// );
  /// ```
  ///
  /// Throws a [ResqliteConnectionException] if the file cannot be opened
  /// or the encryption key is incorrect.
  ///
  /// The returned [Database] must be closed with [close] when no longer
  /// needed to release native resources.
  static Future<Database> open(String path, {String? encryptionKey}) async {
    final pathNative = path.toNativeUtf8();
    final keyNative = encryptionKey != null
        ? encryptionKey.toNativeUtf8()
        : ffi.nullptr.cast<Utf8>();
    try {
      // Determine the number of reader isolates to spawn.
      // cores - 1: leave one core for the main isolate (UI thread in Flutter).
      // min 2: so one worker sacrifice doesn't leave zero capacity.
      // max 4: benchmarked 2/4/8 workers — concurrent query throughput plateaus
      //   at 4. Each idle worker costs ~30KB + one C reader connection.
      final readerCount = (Platform.numberOfProcessors - 1).clamp(2, 4);

      final handle = resqliteOpen(pathNative, readerCount, keyNative);
      if (handle == ffi.nullptr) {
        throw ResqliteConnectionException(
          'Failed to open database at "$path"'
          '${encryptionKey != null ? ' (check encryption key)' : ''}',
        );
      }

      return Database._(handle, readerCount);
    } finally {
      calloc.free(pathNative);
      if (encryptionKey != null) calloc.free(keyNative);
    }
  }

  /// Closes this database, shutting down all worker isolates and releasing
  /// native resources.
  ///
  /// Semantics:
  ///
  /// 1. Sets the "closed" flag so every new `db.*` call throws
  ///    [ResqliteConnectionException] on entry.
  /// 2. *Drains* the write lock — waits for any in-flight writer
  ///    operation (including a transaction body that is awaiting external
  ///    work) to release. Callers queued on the write lock already re-check
  ///    `_ensureOpen()` on wake and bail out, so only the current holder
  ///    keeps us here. This avoids yanking the writer port out from under
  ///    a live transaction.
  /// 3. Closes the stream engine and reader pool.
  /// 4. Sends `CloseRequest` directly to the writer port (bypassing
  ///    `_writerRequest`, which rejects post-close calls) and awaits the
  ///    writer isolate's acknowledgement.
  /// 5. Frees the native handle.
  ///
  /// Safe and idempotent: concurrent or repeated calls share a single
  /// in-progress close future, so the second caller sees the same
  /// completion as the first instead of racing ahead.
  ///
  /// After `close()` resolves, any further operations on this [Database]
  /// throw a [ResqliteConnectionException].
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;

    final (writer, readerPool) = await (_writer, _readerPool).wait;

    _streamEngine.close();

    await readerPool.close();
    await writer.close();

    resqliteClose(_handle);
  }

  // -------------------------------------------------------------------------
  // Read operations
  // -------------------------------------------------------------------------

  /// Executes a query and returns all matching rows.
  ///
  /// ```dart
  /// final users = await db.select(
  ///   'SELECT id, name FROM users WHERE active = ?',
  ///   [1],
  /// );
  /// for (final user in users) {
  ///   print('${user['id']}: ${user['name']}');
  /// }
  /// ```
  ///
  /// The [parameters] list is bound positionally to `?` placeholders in
  /// [sql]. Returns an empty list if no rows match.
  ///
  /// The returned rows are lightweight [Row] views over a shared result
  /// buffer — accessing `row['column']` is a hash lookup, not a map copy.
  /// Use `Map<String, Object?>.from(row)` if you need a mutable copy.
  ///
  /// Runs on a background worker isolate. The main isolate only receives
  /// the finished result.
  ///
  /// Throws a [ResqliteQueryException] if the SQL is malformed.
  ///
  /// See also:
  ///
  /// - [selectBytes], for JSON-encoded results without Dart object allocation
  /// - [stream], for reactive queries that re-emit on writes
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _ensureOpen();

    final transaction = Transaction.current;
    if (transaction != null) {
      return transaction.select(sql, parameters);
    }

    final pool = await _readerPool;
    // No post-await _ensureOpen re-check: if close() has run while we
    // were parked, the pool itself now rejects dispatch with
    // ResqliteConnectionException (see ReaderPool._dispatch). That lets
    // *in-flight* reads that had already dispatched to a worker finish
    // via the pool's drain semantics, while reads still parked on the
    // pool future bail out cleanly.
    return pool.select(sql, parameters);
  }

  /// Executes a query and returns the result as JSON-encoded bytes.
  ///
  /// ```dart
  /// final bytes = await db.selectBytes(
  ///   'SELECT id, name FROM users WHERE active = ?',
  ///   [1],
  /// );
  /// // bytes is a Uint8List containing a JSON array, e.g.:
  /// // [{"id":1,"name":"Ada"},{"id":2,"name":"Grace"}]
  /// ```
  ///
  /// JSON serialization happens entirely in C — no Dart [Map] or [String]
  /// objects are created for the result data. The result crosses to Dart as
  /// a single [Uint8List].
  ///
  /// This is ideal for HTTP responses, file export, or any path where the
  /// end consumer wants JSON bytes rather than Dart objects.
  ///
  /// Throws a [ResqliteQueryException] if the SQL is malformed.
  Future<Uint8List> selectBytes(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _ensureOpen();

    final pool = await _readerPool;
    return pool.selectBytes(sql, parameters);
  }

  // -------------------------------------------------------------------------
  // Reactive queries
  // -------------------------------------------------------------------------

  /// Creates a reactive query that re-emits results when underlying tables
  /// change.
  ///
  /// ```dart
  /// db.stream('SELECT * FROM tasks WHERE done = ?', [0]).listen((tasks) {
  ///   print('${tasks.length} open tasks');
  /// });
  /// ```
  ///
  /// The first emission contains the current results. Subsequent emissions
  /// occur after any write that modifies tables this query depends on.
  ///
  /// Table dependencies are detected automatically via SQLite's authorizer
  /// hook — works with JOINs, subqueries, views, and CTEs without requiring
  /// a manual table list.
  ///
  /// Streams are deduplicated: multiple calls with the same [sql] and
  /// [parameters] share a single underlying query. New listeners on an
  /// existing stream receive the cached result immediately.
  ///
  /// Unchanged results are suppressed — if a write touches a watched table
  /// but doesn't change this query's output, no emission occurs.
  ///
  /// Create streams once and reuse them (e.g., as `late final` fields in
  /// a `State` class), rather than creating new streams on every build.
  Stream<List<Map<String, Object?>>> stream(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    _ensureOpen();
    return _streamEngine.stream(sql, parameters);
  }

  // -------------------------------------------------------------------------
  // Write operations
  // -------------------------------------------------------------------------

  /// Executes a write statement and returns the result.
  ///
  /// ```dart
  /// final result = await db.execute(
  ///   'INSERT INTO users(name, email) VALUES (?, ?)',
  ///   ['Ada', 'ada@example.com'],
  /// );
  /// print('Inserted row ${result.lastInsertId}');
  /// print('${result.affectedRows} row(s) affected');
  /// ```
  ///
  /// The [parameters] list is bound positionally to `?` placeholders in
  /// [sql]. Each element must be a [String], [int], [double], [Uint8List]
  /// (for blobs), or `null`.
  ///
  /// Suitable for INSERT, UPDATE, DELETE, and DDL statements. For queries
  /// that return rows, use [select] instead.
  ///
  /// Any active [stream] queries watching the affected tables are
  /// automatically re-queried after this write commits.
  ///
  /// Throws a [ResqliteQueryException] if the SQL is malformed or
  /// violates a constraint.
  Future<WriteResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    _ensureOpen();

    final transaction = Transaction.current;
    if (transaction != null) {
      return transaction.execute(sql, parameters);
    }

    final writer = await _writer;
    return writer.locked(() => execute(sql, parameters));
  }

  /// Executes one SQL statement across many parameter sets in a single
  /// transaction.
  ///
  /// ```dart
  /// await db.executeBatch(
  ///   'INSERT INTO users(name) VALUES (?)',
  ///   [['Ada'], ['Grace'], ['Sonja']],
  /// );
  /// ```
  ///
  /// The statement is prepared once and reused across all [paramSets],
  /// wrapped in a single BEGIN/COMMIT transaction. This is significantly
  /// faster than calling [execute] in a loop.
  ///
  /// All-or-nothing: if any row fails, the entire batch rolls back.
  ///
  /// Streams watching the affected table fire once on commit, not per row.
  ///
  /// Throws a [ResqliteQueryException] if any statement fails.
  Future<void> executeBatch(String sql, List<List<Object?>> paramSets) async {
    _ensureOpen();

    final transaction = Transaction.current;
    if (transaction != null) {
      return transaction.executeBatch(sql, paramSets);
    }

    final writer = await _writer;
    return writer.locked(() => writer.executeBatch(sql, paramSets));
  }

  /// Runs [body] inside a database transaction.
  ///
  /// ```dart
  /// final count = await db.transaction((tx) async {
  ///   await tx.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);
  ///   final rows = await tx.select('SELECT COUNT(*) as c FROM users');
  ///   return rows.first['c'] as int;
  /// });
  /// ```
  ///
  /// All operations within [body] are applied atomically. If [body]
  /// completes normally, the transaction commits. If [body] throws,
  /// the transaction rolls back and the exception is rethrown.
  ///
  /// The [Transaction] passed to [body] supports both [Transaction.execute]
  /// and [Transaction.select]. Reads inside the transaction see uncommitted
  /// writes from earlier statements in the same transaction.
  ///
  /// Stream invalidation happens once on commit, not per statement.
  /// Rolled-back transactions do not trigger stream re-queries.
  ///
  /// Returns the value returned by [body].
  Future<T> transaction<T>(Future<T> Function(Transaction tx) body) async {
    _ensureOpen();

    final transaction = Transaction.current;
    if (transaction != null) {
      return transaction.transaction(body);
    }

    final writer = await _writer;
    return writer.locked(() => writer.transaction(body));
  }
}
