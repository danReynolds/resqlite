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

/// A SQLite loadable extension to register on every resqlite connection.
///
/// Extension packages should expose a small factory returning this value and
/// avoid importing `package:sqlite3`. resqlite registers the native entrypoint
/// while it opens the writer and reader pool so each connection sees the same
/// extension functions and virtual tables.
final class ResqliteExtension {
  /// Creates an extension from a typed SQLite extension init pointer.
  ResqliteExtension(this.entrypoint, {this.name}) {
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
  }) {
    return ResqliteExtension(
      entrypoint.cast<ResqliteExtensionEntrypoint>(),
      name: name,
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
  }) {
    return ResqliteExtension(
      library.lookup<ResqliteExtensionEntrypoint>(symbol),
      name: name ?? symbol,
    );
  }

  /// Native extension init function.
  final ffi.Pointer<ResqliteExtensionEntrypoint> entrypoint;

  /// Optional debug name used in diagnostics and error messages.
  final String? name;

  /// Untyped native entrypoint address passed to SQLite.
  ffi.Pointer<ffi.Void> get entrypointAddress => entrypoint.cast();

  String get debugName =>
      name ?? '0x${entrypointAddress.address.toRadixString(16)}';

  @override
  bool operator ==(Object other) {
    return other is ResqliteExtension &&
        other.entrypointAddress.address == entrypointAddress.address;
  }

  @override
  int get hashCode => entrypointAddress.address.hashCode;

  @override
  String toString() => 'ResqliteExtension($debugName)';
}
