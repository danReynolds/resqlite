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

  test('compares extensions by native entrypoint address', () {
    final first = ResqliteExtension.fromAddress(
      ffi.Pointer.fromAddress(1),
      name: 'first',
    );
    final sameEntrypoint = ResqliteExtension.fromAddress(
      ffi.Pointer.fromAddress(1),
      name: 'same',
    );
    final differentEntrypoint = ResqliteExtension.fromAddress(
      ffi.Pointer.fromAddress(2),
      name: 'different',
    );

    expect(first, sameEntrypoint);
    expect(first.hashCode, sameEntrypoint.hashCode);
    expect(first, isNot(differentEntrypoint));
    expect(first.debugName, 'first');
    expect(first.toString(), 'ResqliteExtension(first)');
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
