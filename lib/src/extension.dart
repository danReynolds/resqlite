import 'dart:ffi' as ffi;

/// Native signature for SQLite loadable extension entrypoints.
///
/// SQLite calls these functions with `(sqlite3* db, char** pzErrMsg,
/// const sqlite3_api_routines* pApi)`. Extension packages expose one of these
/// symbols through `@Native`, then hand the resulting function pointer to
/// [ResqliteExtension].
typedef ResqliteExtensionInitNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
    );

/// Native function pointer type for a SQLite extension entrypoint.
typedef ResqliteExtensionEntrypoint =
    ffi.NativeFunction<ResqliteExtensionInitNative>;

/// Which native resqlite connections should run an extension setup statement.
enum ResqliteConnectionSetupScope {
  /// Run setup on the writer and every reader connection.
  all,

  /// Run setup only on the writer connection.
  writer,

  /// Run setup only on reader connections.
  readers,
}

/// SQL to run on native connections after an extension is loaded.
///
/// Most SQLite extensions only need their native `sqlite3_xxx_init` function
/// called per connection. Some extensions also expose connection-local setup
/// SQL, such as registering ICU collations or initializing vector metadata.
/// Extension packages should hide these generic setup objects behind
/// domain-specific options where possible.
///
/// Setup is run by `Database.open` after native extension entrypoints have been
/// loaded on the writer/reader pool and before Dart workers are spawned. Each
/// setup entry must contain exactly one SQL statement. Use multiple entries
/// when ordering multiple statements matters.
final class ResqliteConnectionSetup {
  factory ResqliteConnectionSetup.sql(
    String sql, {
    List<Object?> parameters = const [],
    ResqliteConnectionSetupScope scope = ResqliteConnectionSetupScope.all,
  }) {
    if (sql.trim().isEmpty) {
      throw ArgumentError.value(sql, 'sql', 'must not be empty');
    }
    return ResqliteConnectionSetup._(sql, List.unmodifiable(parameters), scope);
  }

  const ResqliteConnectionSetup._(this.sql, this.parameters, this.scope);

  /// Single SQL statement to execute.
  final String sql;

  /// Bound parameters for [sql].
  final List<Object?> parameters;

  /// Native connections that should execute [sql].
  final ResqliteConnectionSetupScope scope;
}

/// A SQLite loadable extension to register on every resqlite connection.
///
/// Extension packages should expose a small factory returning this value and
/// avoid importing `package:sqlite3`. resqlite registers the native entrypoint
/// while it opens the writer and reader pool so each connection sees the same
/// extension functions and virtual tables.
final class ResqliteExtension {
  /// Creates an extension from a typed SQLite extension init pointer.
  ResqliteExtension(
    this.entrypoint, {
    this.name,
    Iterable<ResqliteConnectionSetup> setup = const [],
  }) : setup = List.unmodifiable(setup) {
    if (entrypoint == ffi.nullptr) {
      throw ArgumentError.value(entrypoint, 'entrypoint', 'must not be null');
    }
  }

  /// Creates an extension from an untyped native entrypoint address.
  ///
  /// Use this when another package or platform integration has already
  /// resolved the native SQLite extension init symbol.
  factory ResqliteExtension.fromAddress(
    ffi.Pointer<ffi.Void> entrypoint, {
    String? name,
    Iterable<ResqliteConnectionSetup> setup = const [],
  }) {
    return ResqliteExtension(
      entrypoint.cast<ResqliteExtensionEntrypoint>(),
      name: name,
      setup: setup,
    );
  }

  /// Looks up an extension init symbol in an already-open dynamic library.
  ///
  /// This mirrors `package:sqlite3`'s `SqliteExtension.inLibrary` escape hatch,
  /// while keeping the resulting extension tied to resqlite's open-scoped
  /// connection-pool loading.
  factory ResqliteExtension.inLibrary(
    ffi.DynamicLibrary library,
    String symbol, {
    String? name,
    Iterable<ResqliteConnectionSetup> setup = const [],
  }) {
    return ResqliteExtension(
      library.lookup<ResqliteExtensionEntrypoint>(symbol),
      name: name ?? symbol,
      setup: setup,
    );
  }

  /// Native extension init function.
  final ffi.Pointer<ResqliteExtensionEntrypoint> entrypoint;

  /// Optional debug name used in diagnostics and error messages.
  final String? name;

  /// Open-time SQL setup to run after the extension is loaded.
  final List<ResqliteConnectionSetup> setup;

  /// Untyped native entrypoint address passed to SQLite.
  ffi.Pointer<ffi.Void> get entrypointAddress => entrypoint.cast();

  String get debugName =>
      name ?? '0x${entrypointAddress.address.toRadixString(16)}';

  @override
  String toString() => 'ResqliteExtension($debugName)';
}
