import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../benchmark/tracelite_source.dart';

void main() {
  test('tracelite source accepts ssh remote for pinned repository', () async {
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_source_pinned_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final revision = await _initGitRepo(
      temp,
      remote: 'git@github.com:danReynolds/tracelite.git',
    );

    final source = await traceliteSourceState(
      temp.path,
      policy: TraceliteSourcePolicy(
        expectedRevision: revision,
        allowUnpinned: false,
        allowDirty: false,
      ),
    );

    expect(
      source['remote_normalized'],
      'https://github.com/danreynolds/tracelite',
    );
    expect(source['repository_matches_pin'], isTrue);
    expect(source['revision_matches_pin'], isTrue);
    expect(source['source_ok'], isTrue);
  });

  test('tracelite source flags mismatched pinned repository', () async {
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_source_mismatch_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final revision = await _initGitRepo(
      temp,
      remote: 'https://github.com/example/tracelite.git',
    );

    final source = await traceliteSourceState(
      temp.path,
      policy: TraceliteSourcePolicy(
        expectedRevision: revision,
        allowUnpinned: false,
        allowDirty: false,
      ),
    );

    expect(source['remote_normalized'], 'https://github.com/example/tracelite');
    expect(source['repository_matches_pin'], isFalse);
    expect(source['revision_matches_pin'], isTrue);
    expect(source['source_ok'], isFalse);
  });
}

Future<String> _initGitRepo(Directory root, {required String remote}) async {
  await _git(root, ['init']);
  await _git(root, ['config', 'user.email', 'test@example.com']);
  await _git(root, ['config', 'user.name', 'Tracelite Source Test']);

  File(p.join(root.path, 'README.md')).writeAsStringSync('# fixture\n');
  await _git(root, ['add', 'README.md']);
  await _git(root, ['commit', '-m', 'initial fixture']);
  await _git(root, ['remote', 'add', 'origin', remote]);

  final result = await _git(root, ['rev-parse', 'HEAD']);
  return result.stdout.toString().trim();
}

Future<ProcessResult> _git(Directory root, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: root.path);
  expect(
    result.exitCode,
    0,
    reason:
        'git ${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
  return result;
}
