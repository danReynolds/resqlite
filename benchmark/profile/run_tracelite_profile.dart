// ignore_for_file: avoid_print
//
// End-to-end tracelite profile workflow for resqlite.
//
// This script keeps tracelite integration out of resqlite's package graph. It
// shells out to a local tracelite checkout to create a region, runs the existing
// resqlite profile harness with tracelite enabled, then exports tracelite
// workload-summary and graph-data artifacts.
//
// Usage:
//   dart run benchmark/profile/run_tracelite_profile.dart \
//     --tracelite-root=/path/to/tracelite \
//     --label=exp-N

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../tracelite_source.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _usage(exitCode: 0);
  }

  final outDir = Directory(options.outDir).absolute;
  final paths = _ArtifactPaths(outDir.path, graphDataDir: options.graphDataDir);
  final steps = _plannedSteps(options, paths);

  if (options.dryRun) {
    _printPlan(options, paths, steps);
    return;
  }

  _validateTraceliteRoot(options.traceliteRoot);
  _validateRuntime(options.runtimePath);
  final traceliteSource = await traceliteSourceState(
    options.traceliteRoot,
    policy: options.traceliteSourcePolicy,
  );
  validateTraceliteSource(traceliteSource);

  outDir.createSync(recursive: true);

  print('# resqlite tracelite profile');
  print('');
  print('label: ${options.label}');
  print('out_dir: ${outDir.path}');
  print('tracelite_root: ${options.traceliteRoot}');
  printTraceliteSource(traceliteSource);
  print('runtime: ${options.runtimePath}');
  print('');

  for (final step in steps) {
    await _runStep(step);
  }

  await _writeManifest(options, paths, traceliteSource: traceliteSource);

  print('');
  print('Artifacts written:');
  print('  manifest: ${paths.manifest}');
  print('  legacy profile JSON: ${paths.legacyProfileJson}');
  print('  tracelite region: ${paths.region}');
  print('  workload summary JSON: ${paths.workloadSummaryJson}');
  print('  workload summary markdown: ${paths.workloadSummaryMarkdown}');
  if (options.exportGraphData) {
    print('  graph data: ${paths.graphDataDir}');
  }
  if (options.writeParityDiff) {
    print('  parity diff: ${paths.parityDiff}');
  }
}

class _Options {
  _Options({
    required this.traceliteRoot,
    required this.runtimePath,
    required this.dartExecutable,
    required this.label,
    required this.outDir,
    required this.ringDataWords,
    required this.maxProducers,
    required this.traceliteSourcePolicy,
    required this.graphDataDir,
    required this.exportGraphData,
    required this.writeParityDiff,
    required this.dryRun,
    required this.showHelp,
  });

  final String traceliteRoot;
  final String runtimePath;
  final String dartExecutable;
  final String label;
  final String outDir;
  final int ringDataWords;
  final int maxProducers;
  final TraceliteSourcePolicy traceliteSourcePolicy;
  final String? graphDataDir;
  final bool exportGraphData;
  final bool writeParityDiff;
  final bool dryRun;
  final bool showHelp;

  static _Options parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      final label = _defaultLabel();
      final traceliteRoot = Platform.environment['TRACELITE_ROOT'] ?? '';
      return _Options(
        traceliteRoot: traceliteRoot,
        runtimePath: _defaultRuntimePath(traceliteRoot),
        dartExecutable: Platform.resolvedExecutable,
        label: label,
        outDir: p.join('build', 'tracelite-profile', label),
        ringDataWords: 4194304,
        maxProducers: 8,
        traceliteSourcePolicy: const TraceliteSourcePolicy(
          expectedRevision: pinnedTraceliteRevision,
          allowUnpinned: false,
          allowDirty: false,
        ),
        graphDataDir: null,
        exportGraphData: true,
        writeParityDiff: true,
        dryRun: false,
        showHelp: true,
      );
    }

    final values = <String, String>{};
    final flags = <String>{};
    for (final arg in args) {
      if (!arg.startsWith('--')) {
        stderr.writeln('unexpected argument: $arg');
        _usage();
      }
      final eq = arg.indexOf('=');
      if (eq == -1) {
        flags.add(arg.substring(2));
      } else {
        values[arg.substring(2, eq)] = arg.substring(eq + 1);
      }
    }

    final label = values['label'] ?? _defaultLabel();
    final rawTraceliteRoot =
        values['tracelite-root'] ??
        Platform.environment['TRACELITE_ROOT'] ??
        '';
    final traceliteRoot = rawTraceliteRoot.isEmpty
        ? ''
        : Directory(rawTraceliteRoot).absolute.path;
    final runtimePath = File(
      values['runtime'] ?? _defaultRuntimePath(traceliteRoot),
    ).absolute.path;
    final graphDataDir = values['graph-data-dir'] == null
        ? null
        : Directory(values['graph-data-dir']!).absolute.path;
    return _Options(
      traceliteRoot: traceliteRoot,
      runtimePath: runtimePath,
      dartExecutable: values['dart'] ?? Platform.resolvedExecutable,
      label: label,
      outDir: values['out-dir'] ?? p.join('build', 'tracelite-profile', label),
      ringDataWords: _positiveInt(values['ring-data-words'], 4194304),
      maxProducers: _positiveInt(values['max-producers'], 8),
      traceliteSourcePolicy: traceliteSourcePolicyFromOptions(
        revision: values['tracelite-revision'],
        flags: flags,
      ),
      graphDataDir: graphDataDir,
      exportGraphData: !flags.contains('no-graph-data'),
      writeParityDiff: !flags.contains('no-parity-diff'),
      dryRun: flags.contains('dry-run'),
      showHelp: false,
    );
  }
}

class _ArtifactPaths {
  _ArtifactPaths(String outDir, {String? graphDataDir})
    : manifest = p.join(outDir, 'manifest.json'),
      region = p.join(outDir, 'profile.tlt-region'),
      legacyProfileJson = p.join(outDir, 'profile.json'),
      workloadSummaryJson = p.join(outDir, 'workload-summary.json'),
      workloadSummaryMarkdown = p.join(outDir, 'workload-summary.md'),
      graphDataDir = graphDataDir ?? p.join(outDir, 'graph-data'),
      parityDiff = p.join(outDir, 'parity-diff.txt');

  final String manifest;
  final String region;
  final String legacyProfileJson;
  final String workloadSummaryJson;
  final String workloadSummaryMarkdown;
  final String graphDataDir;
  final String parityDiff;
}

class _Step {
  _Step({
    required this.name,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    this.environment = const {},
    this.stdoutPath,
  });

  final String name;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final String? stdoutPath;

  String get displayCommand =>
      [executable, for (final arg in arguments) _quoteIfNeeded(arg)].join(' ');
}

List<_Step> _plannedSteps(_Options options, _ArtifactPaths paths) {
  final resqliteRoot = Directory.current.absolute.path;
  final steps = <_Step>[
    _Step(
      name: 'create tracelite region',
      executable: options.dartExecutable,
      arguments: [
        'run',
        'bin/tracelite.dart',
        'create-region',
        '--out=${paths.region}',
        '--ring-data-words=${options.ringDataWords}',
        '--max-producers=${options.maxProducers}',
      ],
      workingDirectory: options.traceliteRoot,
    ),
    _Step(
      name: 'run resqlite profile harness',
      executable: options.dartExecutable,
      arguments: [
        'run',
        '-DRESQLITE_PROFILE=true',
        '-DRESQLITE_TRACELITE=true',
        'benchmark/run_profile.dart',
        '--out=${paths.legacyProfileJson}',
      ],
      workingDirectory: resqliteRoot,
      environment: {
        'TRACELITE_REGION': p.absolute(paths.region),
        'TRACELITE_RUNTIME': options.runtimePath,
      },
    ),
    _Step(
      name: 'export tracelite workload summary',
      executable: options.dartExecutable,
      arguments: [
        'run',
        'bin/tracelite.dart',
        'workload-summary',
        p.absolute(paths.region),
        '--out-json=${p.absolute(paths.workloadSummaryJson)}',
      ],
      workingDirectory: options.traceliteRoot,
      stdoutPath: paths.workloadSummaryMarkdown,
    ),
  ];

  if (options.exportGraphData) {
    steps.add(
      _Step(
        name: 'export graph data',
        executable: options.dartExecutable,
        arguments: [
          'run',
          'bin/tracelite.dart',
          'export-graph-data',
          '--workload-summary=${p.absolute(paths.workloadSummaryJson)}',
          '--run-id=${options.label}',
          '--out=${p.absolute(paths.graphDataDir)}',
        ],
        workingDirectory: options.traceliteRoot,
      ),
    );
    steps.add(
      _Step(
        name: 'validate graph data',
        executable: options.dartExecutable,
        arguments: [
          'run',
          'bin/tracelite.dart',
          'validate-graph-data',
          p.absolute(paths.graphDataDir),
        ],
        workingDirectory: options.traceliteRoot,
      ),
    );
  }

  if (options.writeParityDiff) {
    steps.add(
      _Step(
        name: 'compare legacy JSON with tracelite workload summary',
        executable: options.dartExecutable,
        arguments: [
          'run',
          'benchmark/profile/diff.dart',
          paths.legacyProfileJson,
          paths.workloadSummaryJson,
        ],
        workingDirectory: resqliteRoot,
        stdoutPath: paths.parityDiff,
      ),
    );
  }

  return steps;
}

Future<void> _runStep(_Step step) async {
  print('== ${step.name}');
  print(step.displayCommand);

  final result = await Process.run(
    step.executable,
    step.arguments,
    workingDirectory: step.workingDirectory,
    environment: {...Platform.environment, ...step.environment},
  );

  final stdoutText = _cleanDartToolOutput(result.stdout.toString());
  final stderrText = _cleanDartToolOutput(result.stderr.toString());

  if (step.stdoutPath != null) {
    final file = File(step.stdoutPath!);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(stdoutText);
  } else if (stdoutText.trim().isNotEmpty) {
    stdout.write(stdoutText);
  }

  if (stderrText.trim().isNotEmpty) {
    stderr.write(stderrText);
  }

  if (result.exitCode != 0) {
    stderr.writeln('step failed: ${step.name} (exit ${result.exitCode})');
    exit(result.exitCode);
  }
  print('');
}

Future<void> _writeManifest(
  _Options options,
  _ArtifactPaths paths, {
  required Map<String, Object?> traceliteSource,
}) async {
  final manifest = {
    'schema': 'resqlite.tracelite_profile_run.v1',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'label': options.label,
    'tracelite_root': options.traceliteRoot,
    'tracelite_source': traceliteSource,
    'runtime': options.runtimePath,
    'profile_flags': {'RESQLITE_PROFILE': true, 'RESQLITE_TRACELITE': true},
    'artifacts': {
      'region': paths.region,
      'legacy_profile_json': paths.legacyProfileJson,
      'workload_summary_json': paths.workloadSummaryJson,
      'workload_summary_markdown': paths.workloadSummaryMarkdown,
      'graph_data_dir': options.exportGraphData ? paths.graphDataDir : null,
      'parity_diff': options.writeParityDiff ? paths.parityDiff : null,
    },
  };
  final file = File(paths.manifest);
  file.parent.createSync(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}

void _printPlan(_Options options, _ArtifactPaths paths, List<_Step> steps) {
  print('# resqlite tracelite profile plan');
  print('');
  print('label: ${options.label}');
  print('out_dir: ${Directory(options.outDir).path}');
  print('tracelite_root: ${options.traceliteRoot}');
  print(
    'tracelite_revision_pin: ${options.traceliteSourcePolicy.expectedRevision}',
  );
  print(
    'allow_unpinned_tracelite: ${options.traceliteSourcePolicy.allowUnpinned}',
  );
  print('runtime: ${options.runtimePath}');
  print('');
  print('artifacts:');
  print('  manifest: ${paths.manifest}');
  print('  legacy profile JSON: ${paths.legacyProfileJson}');
  print('  tracelite region: ${paths.region}');
  print('  workload summary JSON: ${paths.workloadSummaryJson}');
  print('  workload summary markdown: ${paths.workloadSummaryMarkdown}');
  if (options.exportGraphData) {
    print('  graph data index: ${p.join(paths.graphDataDir, 'index.json')}');
  }
  if (options.writeParityDiff) {
    print('  parity diff: ${paths.parityDiff}');
  }
  print('');
  print('steps:');
  for (final step in steps) {
    print('- ${step.name}');
    if (step.environment.isNotEmpty) {
      for (final entry in step.environment.entries) {
        print('  env ${entry.key}=${entry.value}');
      }
    }
    print('  cwd ${step.workingDirectory}');
    print('  ${step.displayCommand}');
  }
}

void _validateTraceliteRoot(String traceliteRoot) {
  if (traceliteRoot.isEmpty || !Directory(traceliteRoot).existsSync()) {
    stderr.writeln(
      'missing tracelite checkout. Pass --tracelite-root=/path/to/tracelite '
      'or set TRACELITE_ROOT.',
    );
    exit(64);
  }
  final cli = File(p.join(traceliteRoot, 'bin', 'tracelite.dart'));
  if (!cli.existsSync()) {
    stderr.writeln('not a tracelite checkout: $traceliteRoot');
    stderr.writeln('expected ${cli.path}');
    exit(64);
  }
}

void _validateRuntime(String runtimePath) {
  if (File(runtimePath).existsSync()) {
    return;
  }
  stderr.writeln('missing tracelite runtime: $runtimePath');
  stderr.writeln('build it from the tracelite checkout, for example:');
  final basename = p.basename(runtimePath);
  final sharedFlag = Platform.isMacOS ? '-dynamiclib' : '-shared -fPIC';
  stderr.writeln(
    '  cc $sharedFlag -O2 -Inative native/tracelite_runtime.c '
    '-o build/$basename',
  );
  exit(66);
}

String _defaultLabel() {
  return DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
}

String _defaultRuntimePath(String traceliteRoot) {
  final ext = switch (Platform.operatingSystem) {
    'macos' => 'dylib',
    'windows' => 'dll',
    _ => 'so',
  };
  return traceliteRoot.isEmpty
      ? p.join('build', 'libtracelite_runtime.$ext')
      : p.join(traceliteRoot, 'build', 'libtracelite_runtime.$ext');
}

int _positiveInt(String? value, int fallback) {
  if (value == null) return fallback;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    stderr.writeln('expected positive integer, got: $value');
    exit(64);
  }
  return parsed;
}

String _quoteIfNeeded(String value) {
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }
  return value;
}

String _cleanDartToolOutput(String text) {
  return text.replaceAll('Running build hooks...', '');
}

Never _usage({int exitCode = 64}) {
  stderr.writeln('usage:');
  stderr.writeln('  dart run benchmark/profile/run_tracelite_profile.dart');
  stderr.writeln('    --tracelite-root=/path/to/tracelite [--label=run-id]');
  stderr.writeln('    [--out-dir=build/tracelite-profile/run-id]');
  stderr.writeln(
    '    [--graph-data-dir=docs/benchmarks/data/tracelite/latest]',
  );
  stderr.writeln('    [--runtime=/path/to/libtracelite_runtime.dylib]');
  stderr.writeln('    [--dart=/path/to/dart]');
  stderr.writeln('    [--ring-data-words=4194304] [--max-producers=8]');
  stderr.writeln('    [--tracelite-revision=$pinnedTraceliteRevision]');
  stderr.writeln('    [--allow-unpinned-tracelite] [--allow-dirty-tracelite]');
  stderr.writeln('    [--no-graph-data] [--no-parity-diff] [--dry-run]');
  stderr.writeln('');
  stderr.writeln('TRACELITE_ROOT can be used instead of --tracelite-root.');
  exit(exitCode);
}
