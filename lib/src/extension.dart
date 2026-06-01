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

/// Which native resqlite connections should execute registration SQL.
enum ResqliteConnectionScope {
  /// Execute on the writer and every reader connection.
  all,

  /// Execute only on the writer connection.
  writer,

  /// Execute only on reader connections.
  readers,
}

/// Callback used by extension packages to configure per-connection setup.
///
/// Most SQLite extensions only need their native `sqlite3_xxx_init` function
/// called per connection. Some extensions also expose connection-local setup
/// SQL, such as registering ICU collations or initializing vector metadata.
///
/// The callback is synchronous by design. Calls to
/// [ResqliteExtensionRegistrar.execute] enqueue setup SQL; resqlite executes
/// the queued statements during `Database.open`, after native extension
/// entrypoints have loaded and before the database is returned.
typedef ResqliteExtensionRegister =
    void Function(ResqliteExtensionRegistrar ext);

/// Registrar exposed to [ResqliteExtension.onRegister].
abstract interface class ResqliteExtensionRegistrar {
  /// Enqueues one setup SQL statement.
  ///
  /// Result rows are discarded, so this can be used for side-effecting
  /// `SELECT` calls such as `SELECT vector_init(...)`, PRAGMAs, and DDL. Use
  /// multiple calls when ordering multiple statements matters.
  void execute(
    String sql, {
    List<Object?> parameters = const [],
    ResqliteConnectionScope scope = ResqliteConnectionScope.all,
  });
}

/// A SQLite loadable extension to register on every resqlite connection.
///
/// Extension packages should expose a small factory returning this value and
/// avoid importing `package:sqlite3`. resqlite registers the native entrypoint
/// while it opens the writer and reader pool so each connection sees the same
/// extension functions and virtual tables.
final class ResqliteExtension {
  /// Creates an extension from a typed SQLite extension init pointer.
  ResqliteExtension(this.entrypoint, {this.name, this.onRegister}) {
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
    ResqliteExtensionRegister? onRegister,
  }) {
    return ResqliteExtension(
      entrypoint.cast<ResqliteExtensionEntrypoint>(),
      name: name,
      onRegister: onRegister,
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
    ResqliteExtensionRegister? onRegister,
  }) {
    return ResqliteExtension(
      library.lookup<ResqliteExtensionEntrypoint>(symbol),
      name: name ?? symbol,
      onRegister: onRegister,
    );
  }

  /// Native extension init function.
  final ffi.Pointer<ResqliteExtensionEntrypoint> entrypoint;

  /// Optional debug name used in diagnostics and error messages.
  final String? name;

  /// Open-time registration setup.
  ///
  /// Called by `Database.open` to enqueue per-connection SQL setup for this
  /// extension. The callback itself must not do async work; its
  /// [ResqliteExtensionRegistrar.execute] calls are executed before
  /// `Database.open` completes.
  final ResqliteExtensionRegister? onRegister;

  /// Untyped native entrypoint address passed to SQLite.
  ffi.Pointer<ffi.Void> get entrypointAddress => entrypoint.cast();

  String get debugName =>
      name ?? '0x${entrypointAddress.address.toRadixString(16)}';

  @override
  String toString() => 'ResqliteExtension($debugName)';
}
