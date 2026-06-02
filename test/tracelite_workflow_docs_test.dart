import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('release harness points experiments at tracelite workflows', () {
    final source = File('benchmark/run_release.dart').readAsStringSync();

    expect(source, contains('benchmark/run_tracelite.dart'));
    expect(source, contains('benchmark/profile/run_tracelite_profile.dart'));
    expect(source, contains('legacy'));
    expect(source, contains('JSON compatibility/parity checks'));
    expect(
      source,
      isNot(contains('use `benchmark/run_profile.dart`\ninstead')),
    );
  });

  test('profile-mode comments keep tracelite as the preferred wrapper', () {
    final profileMode = File('lib/src/profile_mode.dart').readAsStringSync();
    final profileSample = File(
      'benchmark/profile/profile_sample.dart',
    ).readAsStringSync();
    final dispatchBudget = File(
      'benchmark/profile/dispatch_budget.dart',
    ).readAsStringSync();

    for (final source in [profileMode, profileSample, dispatchBudget]) {
      expect(source, contains('run_tracelite_profile.dart'));
    }
    expect(profileSample, contains('legacy `run_profile.dart` JSON shape'));
    expect(dispatchBudget, contains('legacy\n/// JSON parity artifact'));
  });

  test('legacy profile command points new experiments at tracelite', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'benchmark/run_profile.dart',
      '--help',
    ]);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final stdoutText = result.stdout.toString();
    expect(stdoutText, contains('Legacy compatibility harness'));
    expect(stdoutText, contains('old profile JSON A/B diffs'));
    expect(
      stdoutText,
      contains('benchmark/profile/run_tracelite_profile.dart'),
    );
    expect(stdoutText, contains('Write legacy profile JSON'));
  });

  test('experiment docs keep legacy profile JSON demoted', () {
    final methodology = File('benchmark/METHODOLOGY.md').readAsStringSync();
    final experimentGuide = File('benchmark/EXPERIMENTS.md').readAsStringSync();
    final experiments = File(
      'benchmark/experiments/README.md',
    ).readAsStringSync();
    final singleRunDiff = File('benchmark/profile/diff.dart').readAsStringSync();
    final multirunDiff = File(
      'benchmark/profile/diff_multirun.dart',
    ).readAsStringSync();
    final sharedStats = File('benchmark/shared/stats.dart').readAsStringSync();

    for (final source in [
      methodology,
      experimentGuide,
      experiments,
      singleRunDiff,
      multirunDiff,
      sharedStats,
    ]) {
      expect(source, contains('run_tracelite_profile.dart'));
      expect(source, contains('legacy'));
    }
  });
}
