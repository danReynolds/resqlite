import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'native/resqlite_bindings.dart';
import 'reader_pool.dart';
import 'stream_engine.dart';
import 'write_worker.dart';

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
  Database._(this._handle);

  final ffi.Pointer<ffi.Void> _handle;
  bool _closed = false;

  // Writer isolate — spawned non-blocking on open, awaited on first write.
  SendPort? _writerPort;
  Future<SendPort>? _writerReady;

  // Write lock — ensures concurrent db.execute() / db.transaction() calls
  // don't interleave on the writer isolate. Callers wait for the lock;
  // the lock holder has exclusive write access until released.
  //
  // FIFO fairness: Dart fires Future `.then` callbacks in registration order,
  // and the single-threaded event loop guarantees that when a waiter wakes it
  // re-registers on the new completer before any later-arriving caller can
  // enter `_withWriteLock`. So waiters are served in arrival order and no
  // starvation is possible.
  Completer<void>? _writeLock;

  /// Zone key storing the active [Transaction] when inside a transaction body.
  /// Database methods check this to transparently route through the transaction
  /// instead of deadlocking on the write lock.
  static const _activeTransactionZone = #_activeTransaction;

  /// Returns the active [Transaction] if called from within a transaction
  /// body for *this* database, or `null` otherwise.
  ///
  /// The Zone key is process-global, so a transaction on a different
  /// [Database] instance can leak into our Zone if the caller nests
  /// `dbB.execute(...)` inside `dbA.transaction(...)`. We filter on
  /// `identical(tx._db, this)` so those cross-database calls run against
  /// their own database normally, instead of silently routing through
  /// the wrong connection.
  Transaction? get _activeTx {
    final tx = Zone.current[_activeTransactionZone] as Transaction?;
    return (tx != null && identical(tx._db, this)) ? tx : null;
  }

  /// Acquires exclusive write access, runs [body], then releases the lock.
  Future<T> _withWriteLock<T>(Future<T> Function() body) async {
    _ensureOpen();
    while (true) {
      final lock = _writeLock;
      if (lock == null) break;
      await lock.future;
      // After waking, re-check _closed so callers queued before close()
      // don't proceed to run against a torn-down writer.
      _ensureOpen();
    }
    _writeLock = Completer<void>();
    try {
      return await body();
    } finally {
      final lock = _writeLock;
      _writeLock = null;
      lock?.complete();
    }
  }

  // Persistent reader pool.
  ReaderPool? _readerPool;
  Future<ReaderPool>? _readerPoolReady;

  // Reactive query engine — owns stream lifecycle, uses reader pool for queries.
  late final StreamEngine _streamEngine = StreamEngine(() => _readers);

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
      final readerCount = _defaultReaderCount();
      final handle = resqliteOpen(pathNative, readerCount, keyNative);
      if (handle == ffi.nullptr) {
        throw ResqliteConnectionException(
          'Failed to open database at "$path"'
          '${encryptionKey != null ? ' (check encryption key)' : ''}',
        );
      }
      final db = Database._(handle);
      db._spawnWriter(); // non-blocking
      db._spawnReaderPool(size: readerCount); // non-blocking
      return db;
    } finally {
      calloc.free(pathNative);
      if (encryptionKey != null) calloc.free(keyNative);
    }
  }

  // -------------------------------------------------------------------------
  // Subsystem initialization
  // -------------------------------------------------------------------------

  void _spawnWriter() {
    final completer = Completer<SendPort>();
    _writerReady = completer.future;

    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is SendPort) {
        _writerPort = message;
        completer.complete(message);
      }
    });

    Isolate.spawn(writerEntrypoint, [receivePort.sendPort, _handle.address]);
  }

  // cores - 1: leave one core for the main isolate (UI thread in Flutter).
  // min 2: so one worker sacrifice doesn't leave zero capacity.
  // max 4: benchmarked 2/4/8 workers — concurrent query throughput plateaus
  //   at 4. Each idle worker costs ~30KB + one C reader connection.
  static int _defaultReaderCount() =>
      (Platform.numberOfProcessors - 1).clamp(2, 4);

  void _spawnReaderPool({required int size}) {
    _readerPoolReady = ReaderPool.spawn(_handle.address, size).then((pool) {
      _readerPool = pool;
      return pool;
    });
  }

  Future<ReaderPool> get _readers async {
    if (_readerPool != null) return _readerPool!;
    return _readerPoolReady!;
  }

  Future<SendPort> get _writer async {
    if (_writerPort != null) return _writerPort!;
    return _writerReady!;
  }

  Future<T> _writerRequest<T>(
    WriterRequest Function(SendPort replyPort) build,
  ) async {
    final writer = await _writer;
    final port = RawReceivePort();
    final completer = Completer<T>();
    port.handler = (Object? response) {
      port.close();
      if (response is ErrorResponse) {
        completer.completeError(
          ResqliteQueryException(
            response.message,
            sql: response.sql ?? '<unknown>',
            parameters: response.parameters,
          ),
        );
      } else {
        completer.complete(response as T);
      }
    };
    writer.send(build(port.sendPort));
    return completer.future;
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
  ]) {
    final tx = _activeTx;
    if (tx != null) return tx.execute(sql, parameters);
    return _withWriteLock(() async {
      final response = await _writerRequest<ExecuteResponse>(
        (replyPort) => ExecuteRequest(sql, parameters, replyPort),
      );
      _streamEngine.handleDirtyTables(response.dirtyTables);
      return response.result;
    });
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
  Future<void> executeBatch(String sql, List<List<Object?>> paramSets) {
    final tx = _activeTx;
    if (tx != null) return tx.executeBatch(sql, paramSets);
    return _withWriteLock(() async {
      final response = await _writerRequest<BatchResponse>(
        (replyPort) => BatchRequest(sql, paramSets, replyPort),
      );
      _streamEngine.handleDirtyTables(response.dirtyTables);
    });
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
  Future<T> transaction<T>(Future<T> Function(Transaction tx) body) {
    final tx = _activeTx;
    if (tx != null) return tx.transaction(body);
    return _withWriteLock(() => _runTransaction(body));
  }

  /// Runs a transaction without acquiring the write lock. Used by both
  /// [transaction] (which acquires the lock first) and [Transaction.transaction]
  /// (which already holds the lock from the outer transaction).
  ///
  /// Error handling is structured so that:
  ///
  /// 1. If [body] throws, we issue a rollback and rethrow the *body* error,
  ///    even if the rollback itself also fails (rollback errors are
  ///    suppressed — the user's error is more informative).
  /// 2. If commit throws, we do *not* issue a second rollback. The writer
  ///    isolate already cleaned up its own transaction state when commit
  ///    failed (best-effort rollback + `txDepth` reset), so re-sending
  ///    `RollbackRequest` would either no-op against a non-existent
  ///    transaction or, worse, roll back some *other* enclosing scope.
  Future<T> _runTransaction<T>(Future<T> Function(Transaction tx) body) async {
    await _writerRequest<bool>((replyPort) => BeginRequest(replyPort));

    final T result;
    try {
      final tx = Transaction._(this);
      result = await runZoned(
        () => body(tx),
        zoneValues: {_activeTransactionZone: tx},
      );
    } catch (_) {
      try {
        await _writerRequest<bool>((replyPort) => RollbackRequest(replyPort));
      } catch (_) {
        // Swallow rollback errors — propagating them would mask the
        // original body error, which is what the caller actually needs
        // to see. The writer isolate always leaves `txDepth` consistent
        // after a rollback attempt, so state is already reset for the
        // next caller.
      }
      rethrow;
    }

    // Commit is deliberately outside the try/catch: on commit failure the
    // writer isolate has already rolled back and reset `txDepth`, so we
    // must not issue a second rollback. The error propagates directly.
    final response = await _writerRequest<BatchResponse>(
      (replyPort) => CommitRequest(replyPort),
    );
    _streamEngine.handleDirtyTables(response.dirtyTables);
    return result;
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
    final tx = _activeTx;
    if (tx != null) return tx.select(sql, parameters);
    _ensureOpen();
    final pool = await _readers;
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
    final pool = await _readers;
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
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Closes this database, shutting down all worker isolates and releasing
  /// native resources.
  ///
  /// All active streams are closed. Safe to call multiple times.
  ///
  /// After calling [close], any further operations on this [Database]
  /// throw a [ResqliteConnectionException].
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _streamEngine.closeAll();
    _readerPool?.close();
    if (_writerPort != null) {
      await _writerRequest<bool>((replyPort) => CloseRequest(replyPort));
    }
    resqliteClose(_handle);
  }

  void _ensureOpen() {
    if (_closed) throw ResqliteConnectionException('Database is closed.');
  }
}

/// A transaction proxy for executing writes and reads atomically.
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
///
/// See also:
///
/// - [Database.transaction], which creates and manages this object
final class Transaction {
  Transaction._(this._db);
  final Database _db;

  /// Executes a write statement within this transaction.
  ///
  /// Same as [Database.execute], but the write is part of the enclosing
  /// transaction and only commits when the transaction completes.
  Future<WriteResult> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final response = await _db._writerRequest<ExecuteResponse>(
      (replyPort) => ExecuteRequest(sql, parameters, replyPort),
    );
    return response.result;
  }

  /// Executes a query within this transaction, seeing uncommitted writes.
  ///
  /// This runs on the writer connection (not the reader pool) so it can
  /// see rows inserted or updated earlier in the same transaction.
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final response = await _db._writerRequest<QueryResponse>(
      (replyPort) => QueryRequest(sql, parameters, replyPort),
    );
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
  Future<void> executeBatch(
    String sql,
    List<List<Object?>> paramSets,
  ) async {
    if (paramSets.isEmpty) return;
    await _db._writerRequest<BatchResponse>(
      (replyPort) => BatchRequest(sql, paramSets, replyPort),
    );
    // Dirty tables accumulate in C until the outer commit collects them.
  }

  /// Runs [body] inside a nested transaction (SAVEPOINT).
  ///
  /// If [body] completes normally, the savepoint is released (changes
  /// become part of the enclosing transaction). If [body] throws, the
  /// savepoint is rolled back (only this nested transaction's changes
  /// are undone) and the exception is rethrown.
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
    // Already holds the write lock from the outer transaction.
    // _runTransaction sends Begin (→ SAVEPOINT) / Commit (→ RELEASE)
    // / Rollback (→ ROLLBACK TO) to the writer isolate.
    return _db._runTransaction(body);
  }
}
