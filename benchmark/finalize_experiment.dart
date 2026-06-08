// ignore_for_file: avoid_print
import 'dart:io';

import 'package:path/path.dart' as p;

const _usage = '''
Usage:
  dart run benchmark/finalize_experiment.dart --experiment=experiments/NNN-short-slug.md

Regenerates docs/experiments/history.json and runs the experiment postflight
checks that should pass before committing an experiment record.
''';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options.help) {
    print(_usage.trim());
    return;
  }

  final experiment = options.experiment;
  if (experiment == null) {
    stderr.writeln(_usage.trim());
    exitCode = 64;
    return;
  }

  final experimentFile = File(experiment);
  final validationError = _validateExperimentFile(experimentFile);
  if (validationError != null) {
    stderr.writeln(validationError);
    exitCode = 64;
    return;
  }

  final commands = [
    _Command(
      label: 'generate experiment history',
      executable: Platform.resolvedExecutable,
      args: const ['run', 'benchmark/generate_history.dart'],
    ),
    _Command(
      label: 'check generated docs data',
      executable: Platform.resolvedExecutable,
      args: const ['run', 'benchmark/check_generated_data.dart'],
    ),
    _Command(
      label: 'check experiment signals',
      executable: Platform.resolvedExecutable,
      args: const ['run', 'benchmark/check_experiment_signals.dart'],
    ),
  ];

  print('Finalizing ${p.relative(experimentFile.absolute.path)}');
  for (final command in commands) {
    if (options.dryRun) {
      print('[dry-run] ${command.shellLine}');
      continue;
    }

    final exitCode = await command.run();
    if (exitCode != 0) {
      stderr.writeln(
        'Experiment finalization failed during "${command.label}" '
        '(exit $exitCode).',
      );
      exit(exitCode);
    }
  }

  if (options.dryRun) {
    print('Dry run complete.');
  } else {
    print('Experiment finalization checks passed.');
  }
}

_Options _parseArgs(List<String> args) {
  String? experiment;
  var help = false;
  var dryRun = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      help = true;
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg.startsWith('--experiment=')) {
      experiment = arg.substring('--experiment='.length);
    } else if (arg == '--experiment' && i + 1 < args.length) {
      experiment = args[++i];
    } else {
      stderr.writeln('Unknown argument: $arg');
      help = true;
    }
  }

  return _Options(experiment: experiment, help: help, dryRun: dryRun);
}

String? _validateExperimentFile(File experimentFile) {
  final root = p.normalize(p.absolute('.'));
  final experimentsDir = p.normalize(p.join(root, 'experiments'));
  final experimentPath = p.normalize(p.absolute(experimentFile.path));
  if (!p.isWithin(experimentsDir, experimentPath)) {
    return 'Experiment file must live under experiments/: '
        '${p.relative(experimentPath)}';
  }
  if (!experimentFile.existsSync()) {
    return 'Missing experiment file: ${p.relative(experimentPath)}';
  }

  final filename = p.basename(experimentPath);
  final idMatch = RegExp(r'^(\d+\w?)-.+\.md$').firstMatch(filename);
  if (idMatch == null) {
    return 'Experiment filename must start with an id, for example '
        'experiments/147-short-slug.md: ${p.relative(experimentPath)}';
  }

  final readme = File(p.join(experimentsDir, 'README.md'));
  if (!readme.existsSync()) {
    return 'Missing experiments/README.md.';
  }
  final readmeText = readme.readAsStringSync();
  if (!RegExp(r'\]\(' + RegExp.escape(filename) + r'\)').hasMatch(readmeText)) {
    return 'Experiment ${idMatch.group(1)} is not linked from '
        'experiments/README.md.';
  }

  final content = experimentFile.readAsStringSync();
  const placeholderTokens = [
    '<title>',
    '<state the proposed change',
    '<interpret whether',
    '<state the outcome',
    '<what you expected',
    '<what the code change was',
    '<accept / reject',
  ];
  for (final token in placeholderTokens) {
    if (content.toLowerCase().contains(token)) {
      return 'Experiment ${idMatch.group(1)} still contains draft '
          'placeholder text: $token';
    }
  }

  return null;
}

class _Options {
  const _Options({
    required this.experiment,
    required this.help,
    required this.dryRun,
  });

  final String? experiment;
  final bool help;
  final bool dryRun;
}

class _Command {
  const _Command({
    required this.label,
    required this.executable,
    required this.args,
  });

  final String label;
  final String executable;
  final List<String> args;

  String get shellLine => _quote([executable, ...args]);

  Future<int> run() async {
    print('');
    print('==> $label');
    print(shellLine);
    final process = await Process.start(
      executable,
      args,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }
}

String _quote(List<String> command) {
  return command.map(_quotePart).join(' ');
}

String _quotePart(String part) {
  if (RegExp(r'^[A-Za-z0-9_./:=+-]+$').hasMatch(part)) return part;
  return "'${part.replaceAll("'", "'\\''")}'";
}
