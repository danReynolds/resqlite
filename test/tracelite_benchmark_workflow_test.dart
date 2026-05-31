import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('tracelite decision workflow dry-run prints release lane plan', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_decision_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final baseline = File(p.join(temp.path, 'baseline-manifest.json'))
      ..writeAsStringSync('{}');
    final candidate = File(p.join(temp.path, 'candidate-manifest.json'))
      ..writeAsStringSync('{}');
    final policy = File(p.join(temp.path, 'policy-calibration.json'))
      ..writeAsStringSync('{}');

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/decide_tracelite.dart',
      '--tracelite-root=${p.join(root, 'test', 'fixtures', 'tracelite_root')}',
      '--baseline=${baseline.path}',
      '--candidate=${candidate.path}',
      '--policy=${policy.path}',
      '--label=unit-decision',
      '--out-dir=${p.join(temp.path, 'decision')}',
      '--graph-data-dir=${p.join(temp.path, 'pages', 'tracelite-decision')}',
      '--dry-run',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final stdoutText = result.stdout.toString();
    expect(stdoutText, contains('resqlite tracelite decision plan'));
    expect(stdoutText, contains('decision'));
    expect(stdoutText, contains('--policy=${policy.absolute.path}'));
    expect(stdoutText, contains('--expect=no_regression'));
    expect(stdoutText, contains('--primary-peer=resqlite'));
    expect(stdoutText, contains('--primary-metric=measured_elapsed_ns'));
    expect(stdoutText, contains('--primary-scenarios=chat-sim,'));
    expect(stdoutText, contains('--guardrail-peers=resqlite'));
    expect(stdoutText, contains('--guardrail-scenarios=chat-sim,'));
    expect(stdoutText, contains('--guardrail-metrics=measured_elapsed_ns'));
    expect(stdoutText, contains('export-graph-data'));
    expect(stdoutText, contains('--suite=${baseline.absolute.path}'));
    expect(stdoutText, contains('--suite=${candidate.absolute.path}'));
    expect(stdoutText, contains('--decision='));
    expect(
      stdoutText,
      contains(p.join('pages', 'tracelite-decision', 'index.json')),
    );
  });

  test('tracelite decision workflow preserves manifest on failure', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_decision_failure_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');
    final fakeDart = File(p.join(temp.path, 'fake-dart'));
    fakeDart.writeAsStringSync('#!/bin/sh\nexit 65\n');
    await Process.run('chmod', ['+x', fakeDart.path]);

    final baseline = File(p.join(temp.path, 'baseline-manifest.json'))
      ..writeAsStringSync('{}');
    final candidate = File(p.join(temp.path, 'candidate-manifest.json'))
      ..writeAsStringSync('{}');
    final policy = File(p.join(temp.path, 'policy-calibration.json'))
      ..writeAsStringSync('{}');
    final outDir = p.join(temp.path, 'decision');

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/decide_tracelite.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--dart=${fakeDart.path}',
      '--baseline=${baseline.path}',
      '--candidate=${candidate.path}',
      '--policy=${policy.path}',
      '--label=failing-decision',
      '--out-dir=$outDir',
      '--allow-unpinned-tracelite',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      65,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final manifestFile = File(
      p.join(outDir, 'resqlite-tracelite-decision.json'),
    );
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(manifest['status'], 'failed');
    expect(
      manifest['tracelite_source'],
      containsPair('path', fakeRoot.absolute.path),
    );
    expect(
      manifest['tracelite_source'],
      containsPair('git_available', isFalse),
    );
    final steps = manifest['steps']! as List<Object?>;
    expect(steps, hasLength(1));
    expect(steps.single as Map<String, Object?>, containsPair('exit_code', 65));
  });

  test(
    'tracelite benchmark workflow dry-run prints release gate plan',
    () async {
      final root = Directory.current.path;
      final temp = await Directory.systemTemp.createTemp(
        'resqlite_tracelite_benchmark_test_',
      );
      addTearDown(() => temp.delete(recursive: true));

      final result = await Process.run(Platform.resolvedExecutable, [
        'benchmark/run_tracelite.dart',
        '--tracelite-root=${p.join(root, 'test', 'fixtures', 'tracelite_root')}',
        '--label=unit-benchmark',
        '--out-dir=${p.join(temp.path, 'benchmark')}',
        '--graph-data-dir=${p.join(temp.path, 'pages', 'tracelite')}',
        '--runs=2',
        '--dry-run',
      ], workingDirectory: root);

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      final stdoutText = result.stdout.toString();
      expect(stdoutText, contains('resqlite tracelite benchmark plan'));
      expect(stdoutText, contains('suite-history'));
      expect(
        stdoutText,
        contains('--scenarios=narrow-batch-insert,point-select,feed-paging,'),
      );
      expect(stdoutText, contains('--policy-scenarios=chat-sim,'));
      expect(stdoutText, contains('--metrics=measured_elapsed_ns'));
      expect(stdoutText, contains('--policy-peers=resqlite'));
      expect(stdoutText, contains('--min-repetitions=5'));
      expect(stdoutText, contains('--max-repetitions=30'));
      expect(stdoutText, contains('--target-rse-percent=10'));
      expect(stdoutText, contains('--within-run-noise-percentile=0.75'));
      expect(stdoutText, contains('--threshold-floor-percent=5'));
      expect(stdoutText, contains('--threshold-ceiling-percent=50'));
      expect(stdoutText, contains('--guardrail-floor-percent=3'));
      expect(stdoutText, contains('--noise-gate-floor-percent=5'));
      expect(stdoutText, contains('--noise-gate-ceiling-percent=50'));
      expect(stdoutText, contains('--noise-gate-multiplier=1.5'));
      expect(stdoutText, contains('--max-outlier-percent=10'));
      expect(stdoutText, contains('--max-run-outlier-percent=20'));
      expect(stdoutText, contains('export-graph-data'));
      expect(stdoutText, contains('--suite-history='));
      expect(stdoutText, contains(p.join('pages', 'tracelite', 'index.json')));
    },
  );

  test('tracelite benchmark workflow preserves manifest on failure', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_benchmark_failure_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');
    final fakeDart = File(p.join(temp.path, 'fake-dart'));
    fakeDart.writeAsStringSync('#!/bin/sh\nexit 65\n');
    await Process.run('chmod', ['+x', fakeDart.path]);

    final outDir = p.join(temp.path, 'benchmark');
    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/run_tracelite.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--dart=${fakeDart.path}',
      '--label=failing-benchmark',
      '--out-dir=$outDir',
      '--no-graph-data',
      '--allow-unpinned-tracelite',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      65,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final manifestFile = File(
      p.join(outDir, 'resqlite-tracelite-benchmark.json'),
    );
    expect(manifestFile.existsSync(), isTrue);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    expect(manifest['status'], 'failed');
    expect(
      manifest['tracelite_source'],
      containsPair('path', fakeRoot.absolute.path),
    );
    expect(
      manifest['tracelite_source'],
      containsPair('git_available', isFalse),
    );
    final steps = manifest['steps']! as List<Object?>;
    expect(steps, hasLength(1));
    expect(steps.single as Map<String, Object?>, containsPair('exit_code', 65));
  });

  test('tracelite benchmark workflow rejects unpinned checkout', () async {
    final root = Directory.current.path;
    final temp = await Directory.systemTemp.createTemp(
      'resqlite_tracelite_unpinned_test_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final fakeRoot = Directory(p.join(temp.path, 'tracelite_root'));
    Directory(p.join(fakeRoot.path, 'bin')).createSync(recursive: true);
    File(p.join(fakeRoot.path, 'bin', 'tracelite.dart')).writeAsStringSync('');

    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/run_tracelite.dart',
      '--tracelite-root=${fakeRoot.path}',
      '--label=unpinned-benchmark',
      '--out-dir=${p.join(temp.path, 'benchmark')}',
      '--no-graph-data',
    ], workingDirectory: root);

    expect(
      result.exitCode,
      64,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    expect(
      result.stderr.toString(),
      contains('tracelite source pin cannot be verified'),
    );
  });
}
