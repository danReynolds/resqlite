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
}
