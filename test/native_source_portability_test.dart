import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('native source keeps compiler-specific helpers behind wrappers', () {
    final source = File('native/resqlite.c').readAsStringSync();
    final directHotAttributes = source.split('\n').where((line) {
      return line.contains('__attribute__((hot))') &&
          !line.trimLeft().startsWith('#define RESQLITE_HOT');
    });
    final directBuiltinHints = source.split('\n').where((line) {
      return line.contains('__builtin_expect') &&
          !line.trimLeft().startsWith('#define RESQLITE_');
    });

    expect(source, contains('RESQLITE_HOT'));
    expect(directHotAttributes, isEmpty);
    expect(source, contains('RESQLITE_LIKELY'));
    expect(directBuiltinHints, isEmpty);
    expect(source, contains('resqlite_strdup'));
    expect(RegExp(r'(^|[^A-Za-z0-9_])strdup\s*\(').hasMatch(source), isFalse);
  });
}
