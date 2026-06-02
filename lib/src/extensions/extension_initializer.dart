import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../exceptions.dart';
import 'extension.dart';
import '../native/resqlite_bindings.dart';

Future<ffi.Pointer<ffi.Void>> openNativeDatabaseForResqlite({
  required String path,
  required String? encryptionKey,
  required int readerCount,
  required Iterable<ResqliteExtension> extensions,
}) async {
  final request = _NativeOpenRequest.from(
    path: path,
    encryptionKey: encryptionKey,
    readerCount: readerCount,
    extensions: extensions,
  );
  final handleAddress = await Isolate.run(
    () => _openNativeDatabase(request),
    debugName: 'resqlite.open',
  );

  return ffi.Pointer<ffi.Void>.fromAddress(handleAddress);
}

int _openNativeDatabase(_NativeOpenRequest request) {
  final pathNative = request.path.toNativeUtf8();
  final keyNative = request.encryptionKey != null
      ? request.encryptionKey!.toNativeUtf8()
      : ffi.nullptr.cast<Utf8>();
  final extensionEntrypoints = request.extensionEntrypoints.isEmpty
      ? ffi.nullptr
      : calloc<ffi.Pointer<ffi.Void>>(request.extensionEntrypoints.length);
  try {
    for (var i = 0; i < request.extensionEntrypoints.length; i++) {
      extensionEntrypoints[i] = ffi.Pointer<ffi.Void>.fromAddress(
        request.extensionEntrypoints[i].address,
      );
    }

    final handle = request.extensionEntrypoints.isEmpty
        ? resqliteOpen(pathNative, request.readerCount, keyNative)
        : resqliteOpenWithExtensions(
            pathNative,
            request.readerCount,
            keyNative,
            extensionEntrypoints,
            request.extensionEntrypoints.length,
          );
    if (handle == ffi.nullptr) {
      final extensionNames = request.extensionEntrypoints
          .map((entrypoint) => entrypoint.name)
          .join(', ');
      throw ResqliteConnectionException(
        'Failed to open database at "${request.path}"'
        '${request.encryptionKey != null ? ' (check encryption key)' : ''}'
        '${request.extensionEntrypoints.isNotEmpty ? ' with extensions: $extensionNames' : ''}',
      );
    }

    try {
      _runExtensionSetup(handle, request.setup);
      return handle.address;
    } catch (_) {
      resqliteClose(handle);
      rethrow;
    }
  } finally {
    calloc.free(pathNative);
    if (request.encryptionKey != null) calloc.free(keyNative);
    if (extensionEntrypoints != ffi.nullptr) {
      calloc.free(extensionEntrypoints);
    }
  }
}

void _runExtensionSetup(
  ffi.Pointer<ffi.Void> handle,
  List<_ExtensionConnectionSetup> setup,
) {
  for (final step in setup) {
    final setupSql = step.sql;
    final params = step.parameters;
    final sqlNative = setupSql.toNativeUtf8();
    try {
      final paramsNative = allocateParams(params);
      try {
        final rc = resqliteRunConnectionSetup(
          handle,
          sqlNative,
          paramsNative,
          params.length,
          _setupScopeCode(step.scope),
        );
        if (rc != 0) {
          final message = resqliteErrmsg(handle).toDartString();
          throw ResqliteConnectionException(
            'Failed to run setup for extension ${step.extensionName}: $message'
            '\n  SQL: $setupSql'
            '${params.isNotEmpty ? '\n  Params: $params' : ''}'
            '\n  SQLite code: $rc',
          );
        }
      } finally {
        freeParams(paramsNative, params);
      }
    } finally {
      calloc.free(sqlNative);
    }
  }
}

int _setupScopeCode(ResqliteConnectionScope scope) {
  return switch (scope) {
    ResqliteConnectionScope.all => 0,
    ResqliteConnectionScope.writer => 1,
    ResqliteConnectionScope.readers => 2,
  };
}

final class _NativeOpenRequest {
  _NativeOpenRequest._({
    required this.path,
    required this.encryptionKey,
    required this.readerCount,
    required this.extensionEntrypoints,
    required this.setup,
  });

  factory _NativeOpenRequest.from({
    required String path,
    required String? encryptionKey,
    required int readerCount,
    required Iterable<ResqliteExtension> extensions,
  }) {
    final extensionList = extensions.toList(growable: false);
    return _NativeOpenRequest._(
      path: path,
      encryptionKey: encryptionKey,
      readerCount: readerCount,
      extensionEntrypoints: _collectExtensionEntrypoints(extensionList),
      setup: _collectExtensionSetup(extensionList),
    );
  }

  final String path;
  final String? encryptionKey;
  final int readerCount;
  // This request crosses an Isolate.run boundary. Keep fields sendable: no
  // FFI pointers, handles, DynamicLibrary instances, or callbacks.
  final List<_ExtensionEntrypoint> extensionEntrypoints;
  final List<_ExtensionConnectionSetup> setup;
}

List<_ExtensionEntrypoint> _collectExtensionEntrypoints(
  Iterable<ResqliteExtension> extensions,
) {
  final entrypoints = <_ExtensionEntrypoint>[];
  final seenEntrypoints = <int, String>{};
  for (final extension in extensions) {
    final address = extension.entrypointAddress.address;
    final existingName = seenEntrypoints[address];
    if (existingName != null) {
      throw ArgumentError(
        'Duplicate resqlite extension entrypoint: '
        '${extension.debugName} reuses the native entrypoint from '
        '$existingName. Combine setup in one extension value instead.',
      );
    }
    seenEntrypoints[address] = extension.debugName;
    entrypoints.add(
      _ExtensionEntrypoint(address: address, name: extension.debugName),
    );
  }
  return List.unmodifiable(entrypoints);
}

List<_ExtensionConnectionSetup> _collectExtensionSetup(
  Iterable<ResqliteExtension> extensions,
) {
  final setup = <_ExtensionConnectionSetup>[];
  for (final extension in extensions) {
    final onRegister = extension.onRegister;
    if (onRegister == null) continue;

    final registrar = _ExtensionRegistrar(
      extensionName: extension.debugName,
      setup: setup,
    );
    try {
      onRegister(registrar);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ResqliteConnectionException(
          'Failed to register extension ${extension.debugName}: $error',
        ),
        stackTrace,
      );
    }
  }
  return List.unmodifiable(setup);
}

final class _ExtensionConnectionSetup {
  const _ExtensionConnectionSetup({
    required this.extensionName,
    required this.sql,
    required this.parameters,
    required this.scope,
  });

  final String extensionName;
  final String sql;
  final List<Object?> parameters;
  final ResqliteConnectionScope scope;
}

final class _ExtensionEntrypoint {
  const _ExtensionEntrypoint({required this.address, required this.name});

  final int address;
  final String name;
}

final class _ExtensionRegistrar implements ResqliteExtensionRegistrar {
  _ExtensionRegistrar({
    required this.extensionName,
    required List<_ExtensionConnectionSetup> setup,
  }) : _setup = setup;

  final String extensionName;
  final List<_ExtensionConnectionSetup> _setup;

  @override
  void execute(
    String sql, {
    List<Object?> parameters = const [],
    ResqliteConnectionScope scope = ResqliteConnectionScope.all,
  }) {
    if (sql.trim().isEmpty) {
      throw ArgumentError.value(sql, 'sql', 'must not be empty');
    }
    _setup.add(
      _ExtensionConnectionSetup(
        extensionName: extensionName,
        sql: sql,
        parameters: List.unmodifiable(parameters),
        scope: scope,
      ),
    );
  }
}
