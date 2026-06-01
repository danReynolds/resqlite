import 'dart:ffi' as ffi;

import 'package:resqlite/resqlite.dart';
import 'package:test/test.dart';

void main() {
  test('rejects null extension entrypoints', () {
    expect(
      () => ResqliteExtension(ffi.nullptr.cast<ResqliteExtensionEntrypoint>()),
      throwsArgumentError,
    );
    expect(
      () => ResqliteExtension.fromAddress(ffi.nullptr),
      throwsArgumentError,
    );
  });

  test(
    'exposes stable debug names without collapsing registration identity',
    () {
      final first = ResqliteExtension.fromAddress(
        ffi.Pointer.fromAddress(1),
        name: 'first',
      );
      var registered = false;
      final sameEntrypoint = ResqliteExtension.fromAddress(
        ffi.Pointer.fromAddress(1),
        name: 'same',
        onRegister: (_) {
          registered = true;
        },
      );

      expect(
        first.entrypointAddress.address,
        sameEntrypoint.entrypointAddress.address,
      );
      expect(first, isNot(sameEntrypoint));
      sameEntrypoint.onRegister?.call(_NoopRegistrar());
      expect(registered, isTrue);
      expect(first.debugName, 'first');
      expect(first.toString(), 'ResqliteExtension(first)');
    },
  );

  test('reports a missing entrypoint from an existing dynamic library', () {
    expect(
      () => ResqliteExtension.inLibrary(
        ffi.DynamicLibrary.process(),
        '__missing_resqlite_extension_symbol__',
      ),
      throwsArgumentError,
    );
  });
}

final class _NoopRegistrar implements ResqliteExtensionRegistrar {
  @override
  void execute(
    String sql, {
    List<Object?> parameters = const [],
    ResqliteConnectionScope scope = ResqliteConnectionScope.all,
  }) {}
}
