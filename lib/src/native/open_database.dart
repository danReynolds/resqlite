import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../exceptions.dart';
import '../extensions/extension.dart';
import '../extensions/registration.dart';
import 'resqlite_bindings.dart';

Future<ffi.Pointer<ffi.Void>> openNativeDatabase({
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
    () => _openNativeDatabaseOnWorker(request),
    debugName: 'resqlite.open',
  );

  return ffi.Pointer<ffi.Void>.fromAddress(handleAddress);
}

int _openNativeDatabaseOnWorker(_NativeOpenRequest request) {
  final pathNative = request.path.toNativeUtf8();
  final keyNative = request.encryptionKey != null
      ? request.encryptionKey!.toNativeUtf8()
      : ffi.nullptr.cast<Utf8>();
  final extensionEntrypoints = request.registration.entrypoints.isEmpty
      ? ffi.nullptr
      : calloc<ffi.Pointer<ffi.Void>>(request.registration.entrypoints.length);
  try {
    for (var i = 0; i < request.registration.entrypoints.length; i++) {
      extensionEntrypoints[i] = ffi.Pointer<ffi.Void>.fromAddress(
        request.registration.entrypoints[i].address,
      );
    }

    final handle = request.registration.entrypoints.isEmpty
        ? resqliteOpen(pathNative, request.readerCount, keyNative)
        : resqliteOpenWithExtensions(
            pathNative,
            request.readerCount,
            keyNative,
            extensionEntrypoints,
            request.registration.entrypoints.length,
          );
    if (handle == ffi.nullptr) {
      final extensionNames = request.registration.entrypoints
          .map((entrypoint) => entrypoint.name)
          .join(', ');
      throw ResqliteConnectionException(
        'Failed to open database at "${request.path}"'
        '${request.encryptionKey != null ? ' (check encryption key)' : ''}'
        '${request.registration.entrypoints.isNotEmpty ? ' with extensions: $extensionNames' : ''}',
      );
    }

    try {
      _runExtensionSetup(handle, request.registration.setupSteps);
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
  List<ExtensionSetupStep> setup,
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
    required this.registration,
  });

  factory _NativeOpenRequest.from({
    required String path,
    required String? encryptionKey,
    required int readerCount,
    required Iterable<ResqliteExtension> extensions,
  }) {
    return _NativeOpenRequest._(
      path: path,
      encryptionKey: encryptionKey,
      readerCount: readerCount,
      registration: ExtensionRegistrationPlan.from(extensions),
    );
  }

  final String path;
  final String? encryptionKey;
  final int readerCount;
  // This request crosses an Isolate.run boundary. Keep fields sendable: no
  // FFI pointers, handles, DynamicLibrary instances, or callbacks.
  final ExtensionRegistrationPlan registration;
}
