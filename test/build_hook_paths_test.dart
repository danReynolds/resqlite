import 'dart:io';

import 'package:test/test.dart';

import 'package:resqlite/src/native/build_paths.dart';

void main() {
  test('output paths use native Windows drive syntax', () {
    final outputDirectory = Uri.parse(
      'file:///D:/a/tracelite/tracelite/.dart_tool/hooks_runner/'
      'shared/resqlite/build/8e04c28b44/',
    );

    final path = outputFilePath(
      outputDirectory,
      'sqlite3mc_tracelite.c',
      windows: true,
    );

    expect(path, startsWith(r'D:\a\tracelite\tracelite'));
    expect(path, isNot(startsWith('/D:/')));
  });

  test('package file paths use native Windows drive syntax', () {
    final packageRoot = Uri.parse('file:///D:/a/resqlite/resqlite/');

    final path = packageFilePath(
      packageRoot,
      'third_party/sqlite3mc/sqlite3mc_amalgamation.c',
      windows: true,
    );

    expect(
      path,
      r'D:\a\resqlite\resqlite\third_party\sqlite3mc\sqlite3mc_amalgamation.c',
    );
  });

  test('native hook requests platform C11-compatible modes', () {
    final source = File('hook/build.dart').readAsStringSync();

    expect(source, contains("std: targetOS == OS.windows ? 'c11' : 'gnu11'"));
    expect(source, contains("'/experimental:c11atomics'"));
  });
}
