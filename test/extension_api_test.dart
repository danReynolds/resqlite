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

  test('exposes stable debug names without collapsing setup identity', () {
    final first = ResqliteExtension.fromAddress(
      ffi.Pointer.fromAddress(1),
      name: 'first',
    );
    final sameEntrypoint = ResqliteExtension.fromAddress(
      ffi.Pointer.fromAddress(1),
      name: 'same',
      setup: [
        ResqliteConnectionSetup.sql(
          'SELECT ?',
          parameters: ['setup'],
          scope: ResqliteConnectionSetupScope.writer,
        ),
      ],
    );

    expect(
      first.entrypointAddress.address,
      sameEntrypoint.entrypointAddress.address,
    );
    expect(first, isNot(sameEntrypoint));
    expect(sameEntrypoint.setup.single.parameters, ['setup']);
    expect(
      sameEntrypoint.setup.single.scope,
      ResqliteConnectionSetupScope.writer,
    );
    expect(first.debugName, 'first');
    expect(first.toString(), 'ResqliteExtension(first)');
  });

  test('rejects empty setup SQL', () {
    expect(() => ResqliteConnectionSetup.sql(' '), throwsArgumentError);
  });

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
