import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'native dependency tracking fault injection',
    () async {
      final root = Directory.current.path;
      final temp = await Directory.systemTemp.createTemp('resqlite_deps_test_');
      addTearDown(() => temp.delete(recursive: true));

      final exe = p.join(temp.path, 'resqlite_deps_fault_test');
      final cc = Platform.environment['CC'] ?? 'cc';
      final compile = await Process.run(cc, [
        '-DRESQLITE_DEPS_TEST',
        '-I',
        p.join(root, 'native'),
        '-I',
        p.join(root, 'third_party', 'sqlite3mc'),
        p.join(root, 'test', 'native', 'resqlite_deps_fault_test.c'),
        p.join(root, 'native', 'resqlite_deps.c'),
        '-o',
        exe,
      ]);

      expect(
        compile.exitCode,
        0,
        reason: 'stdout:\n${compile.stdout}\nstderr:\n${compile.stderr}',
      );

      final run = await Process.run(exe, const []);
      expect(
        run.exitCode,
        0,
        reason: 'stdout:\n${run.stdout}\nstderr:\n${run.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: Platform.isWindows
        ? 'native dependency test expects a POSIX C compiler'
        : false,
  );
}
