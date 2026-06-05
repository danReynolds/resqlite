import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('tracelite profile workflow dry-run prints artifact plan', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_workflow_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/profile/run_tracelite_profile.dart',
      '--tracelite-root=${p.join(root, 'test', 'fixtures', 'tracelite_root')}',
      '--runtime=${p.join(temp.path, 'libtracelite_runtime.test')}',
      '--label=unit-run',
      '--out-dir=${p.join(temp.path, 'profile')}',
      '--graph-data-dir=${p.join(temp.path, 'pages', 'tracelite')}',
      '--dry-run',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final stdoutText = result.stdout.toString();
    expect(stdoutText, contains('resqlite tracelite profile plan'));
    expect(stdoutText, contains('primary tracelite artifacts'));
    expect(stdoutText, contains('profile.tlt-region'));
    expect(stdoutText, contains('workload-summary.json'));
    expect(stdoutText, contains('insights.json'));
    expect(stdoutText, contains('insights.md'));
    expect(stdoutText, contains(p.join('pages', 'tracelite', 'index.json')));
    expect(stdoutText, contains('explain'));
    expect(stdoutText, contains('validate-graph-data'));
    expect(
      stdoutText,
      contains('benchmark/profile/run_tracelite_workloads.dart'),
    );
    expect(stdoutText, contains('RESQLITE_TRACELITE=true'));
    expect(stdoutText, contains('TRACELITE_REGION='));
    expect(stdoutText, contains('TRACELITE_RUNTIME='));
    expect(stdoutText, isNot(contains('profile.json')));
    expect(stdoutText, isNot(contains('parity-diff.txt')));
  });
}
