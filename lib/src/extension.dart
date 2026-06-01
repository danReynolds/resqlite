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

/// A SQLite loadable extension to register on every resqlite connection.
///
/// Extension packages should expose a small factory returning this value and
/// avoid importing `package:sqlite3`. resqlite registers the native entrypoint
/// while it opens the writer and reader pool so each connection sees the same
/// extension functions and virtual tables.
final class ResqliteExtension {
  ResqliteExtension(this.entrypoint, {this.name}) {
    if (entrypoint == ffi.nullptr) {
      throw ArgumentError.value(entrypoint, 'entrypoint', 'must not be null');
    }
  }

  /// Native extension init function.
  final ffi.Pointer<ffi.NativeFunction<ResqliteExtensionInitNative>> entrypoint;

  /// Optional debug name used in diagnostics and error messages.
  final String? name;

  ffi.Pointer<ffi.Void> get opaqueEntrypoint => entrypoint.cast();

  @override
  String toString() => name == null
      ? 'ResqliteExtension(0x${entrypoint.address.toRadixString(16)})'
      : 'ResqliteExtension($name)';
}
