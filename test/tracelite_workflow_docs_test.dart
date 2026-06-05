import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('release harness points experiments at tracelite workflows', () {
    final source = File('benchmark/run_release.dart').readAsStringSync();

    expect(source, contains('benchmark/run_tracelite.dart'));
    expect(source, contains('benchmark/profile/run_tracelite_profile.dart'));
    expect(source, isNot(contains('benchmark/run_profile.dart')));
    expect(source, isNot(contains('JSON compatibility/parity checks')));
  });

  test('profile-mode comments keep tracelite as the maintained wrapper', () {
    final profileMode = File('lib/src/profile_mode.dart').readAsStringSync();
    final profileSample = File(
      'benchmark/profile/profile_sample.dart',
    ).readAsStringSync();
    final workloads = File(
      'benchmark/profile/workloads.dart',
    ).readAsStringSync();

    for (final source in [profileMode, profileSample]) {
      expect(source, contains('run_tracelite_profile.dart'));
    }
    expect(profileSample, isNot(contains('run_profile.dart')));
    expect(workloads, contains('tracelite workload driver'));
    expect(workloads, isNot(contains('dispatch_budget.dart')));
  });

  test('legacy profile JSON commands are retired', () {
    for (final path in [
      'benchmark/run_profile.dart',
      'benchmark/profile/diff.dart',
      'benchmark/profile/diff_multirun.dart',
      'benchmark/profile/dispatch_budget.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('experiment docs describe tracelite artifacts only', () {
    final files = [
      'benchmark/README.md',
      'benchmark/METHODOLOGY.md',
      'benchmark/EXPERIMENTS.md',
      'benchmark/experiments/README.md',
      'benchmark/shared/stats.dart',
      'docs/benchmarks/data/tracelite/README.md',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('run_tracelite_profile.dart'), reason: path);
      expect(source, isNot(contains('run_profile.dart')), reason: path);
      expect(source, isNot(contains('parity-diff')), reason: path);
      expect(source, isNot(contains('legacy profile JSON')), reason: path);
    }
  });
}
