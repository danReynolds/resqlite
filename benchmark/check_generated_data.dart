import 'dart:io';

import 'generate_devices.dart' as generate_devices;
import 'generate_history.dart' as generate_history;
import 'generate_readme.dart' as generate_readme;
import 'generate_signals.dart' as generate_signals;

/// Verifies that the generated-docs sources are well-formed enough that the
/// generators run to completion.
///
/// This does **not** compare against the committed `docs/.../*.json` or
/// `experiments/signals.json`. Those are generated artifacts owned by the
/// post-merge "Update Docs Data" bot, not by experiment branches — see
/// experiments/RUNNER_INSTRUCTIONS.md ("Generated files are bot-owned"). A
/// branch never has to carry a fresh copy, which is what used to force every
/// open experiment PR to re-resolve the same mechanical conflict on those
/// files. The job here is to fail fast on a *source* that can't be generated
/// (a malformed signals fragment, a missing run declaration, a broken
/// experiment <-> benchmark-run mapping) — every one of those checks lives
/// inside the build functions below and throws on violation.
Future<void> main() async {
  final builders = <String, void Function()>{
    'devices.json': () => generate_devices.buildDevicesData(
      hardwareResultsMarkdown: File(
        'benchmark/HARDWARE_RESULTS.md',
      ).readAsStringSync(),
      resultsDir: Directory('benchmark/results'),
      generatedAt: null,
    ),
    'history.json': () => generate_history.buildHistoryData(
      resultsDir: Directory('benchmark/results'),
      experimentsDir: Directory('experiments'),
      generatedAt: null,
    ),
    'signals.json': () => generate_signals.buildSignalsData(
      signalsSourceDir: Directory('experiments/signals'),
      generatedAt: null,
    ),
    'README.md': () =>
        generate_readme.buildReadme(experimentsDir: Directory('experiments')),
  };

  final failures = <String>[];
  for (final entry in builders.entries) {
    try {
      entry.value();
      print('${entry.key}: generators build cleanly.');
    } catch (error, stack) {
      failures.add(entry.key);
      stderr.writeln('::error::${entry.key} failed to generate: $error');
      stderr.writeln(stack);
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln(
      'Generated-docs sources do not build: ${failures.join(', ')}. '
      'Fix the offending source (experiment doc, benchmark result, or '
      'signals fragment) — you do NOT need to commit the regenerated '
      'docs/*.json or signals.json; the bot owns those on main.',
    );
    exitCode = 1;
    return;
  }

  print('All generated-docs sources build cleanly.');
}
