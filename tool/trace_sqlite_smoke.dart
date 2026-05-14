import 'dart:io';

Future<void> main() async {
  final packageRoot = Directory.current.absolute.path;
  final tempDir = await Directory.systemTemp.createTemp(
    'resqlite_trace_sqlite_smoke_',
  );

  try {
    await Directory('${tempDir.path}/bin').create(recursive: true);
    await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: resqlite_trace_sqlite_smoke
publish_to: none

environment:
  sdk: ^3.10.4

dependencies:
  resqlite:
    path: $packageRoot

hooks:
  user_defines:
    resqlite:
      trace_sqlite: true
      tracelite_root: $packageRoot/test/fixtures/tracelite_root
''');
    await File('${tempDir.path}/bin/main.dart').writeAsString('''
import 'dart:io';

import 'package:resqlite/resqlite.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('resqlite_trace_sqlite_');
  try {
    final db = await Database.open('\${dir.path}/test.db');
    await db.execute('CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute('INSERT INTO t(name) VALUES (?)', ['trace']);
    final rows = await db.select('SELECT name FROM t');
    if (rows.single['name'] != 'trace') {
      throw StateError('unexpected rows: \$rows');
    }
    await db.close();
  } finally {
    await dir.delete(recursive: true);
  }
}
''');

    await _run('pub get', tempDir.path, ['pub', 'get']);
    await _run('run smoke', tempDir.path, ['run', 'bin/main.dart']);
  } finally {
    await tempDir.delete(recursive: true);
  }
}

Future<void> _run(
  String label,
  String workingDirectory,
  List<String> args,
) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    args,
    workingDirectory: workingDirectory,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      args,
      '$label failed with exit code ${result.exitCode}',
      result.exitCode,
    );
  }
}
