// ignore_for_file: avoid_print
//
// Baseline/candidate decision workflow backed by tracelite.
//
// This is the resqlite-facing entry point for deciding whether a benchmark
// candidate is acceptable using the same release-lane policy as
// benchmark/run_tracelite.dart.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tracelite_source.dart';
import 'tracelite_workloads.dart';

const _defaultReleaseMetric = 'measured_elapsed_ns';
const _defaultPolicyPeer = 'resqlite';
Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _usage(exitCode: 0);
  }

  final outDir = Directory(options.outDir).absolute;
  final paths = _Paths(outDir.path, graphDataDir: options.graphDataDir);
  final decisionStep = _decisionStep(options, paths);
  final graphStep = _graphDataStep(options, paths);
  final explainStep = _explainStep(options, paths);

  if (options.dryRun) {
    _printPlan(options, paths, [
      decisionStep,
      if (graphStep != null) graphStep,
      explainStep,
    ]);
    return;
  }

  _validateInputs(options);
  outDir.createSync(recursive: true);
  final traceliteSource = await traceliteSourceState(
    options.traceliteRoot,
    policy: options.traceliteSourcePolicy,
  );
  validateTraceliteSource(traceliteSource);

  print('# resqlite tracelite decision');
  print('');
  print('label: ${options.label}');
  print('out_dir: ${outDir.path}');
  print('tracelite_root: ${options.traceliteRoot}');
  printTraceliteSource(traceliteSource);
  print('baseline: ${options.baseline}');
  print('candidate: ${options.candidate}');
  print('policy: ${options.policy}');
  print('expect: ${options.expectation}');
  print('primary_peer: ${options.primaryPeer}');
  print('primary_metric: ${options.primaryMetric}');
  print('primary_scenarios: ${options.primaryScenarios}');
  print('guardrail_peers: ${options.guardrailPeers}');
  print('guardrail_scenarios: ${options.guardrailScenarios}');
  print('guardrail_metrics: ${options.guardrailMetrics}');
  print('');

  final stepResults = <_StepResult>[];
  stepResults.add(await _runDecisionStep(decisionStep, paths));
  if (graphStep != null && File(paths.decisionJson).existsSync()) {
    stepResults.add(await _runStep(graphStep));
  }
  if (File(paths.decisionJson).existsSync()) {
    stepResults.add(
      await _runMarkdownStep(explainStep, paths.insightsMarkdown),
    );
  }

  await _writeManifest(
    options,
    paths,
    stepResults,
    traceliteSource: traceliteSource,
  );

  print('');
  print('Artifacts written:');
  print('  manifest: ${paths.manifest}');
  print('  decision JSON: ${paths.decisionJson}');
  print('  decision markdown: ${paths.decisionMarkdown}');
  print('  insights JSON: ${paths.insightsJson}');
  print('  insights markdown: ${paths.insightsMarkdown}');
  if (options.exportGraphData) {
    print('  graph data: ${paths.graphDataDir}');
  }

  final failedSteps = stepResults
      .where((result) => result.exitCode != 0)
      .toList();
  if (failedSteps.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln('decision failed; artifacts were preserved for inspection.');
    exitCode = failedSteps.first.exitCode;
  }
}

final class _Options {
  const _Options({
    required this.traceliteRoot,
    required this.dartExecutable,
    required this.label,
    required this.outDir,
    required this.baseline,
    required this.candidate,
    required this.policy,
    required this.expectation,
    required this.primaryPeer,
    required this.primaryMetric,
    required this.primaryScenarios,
    required this.guardrailPeers,
    required this.guardrailScenarios,
    required this.guardrailMetrics,
    required this.traceliteSourcePolicy,
    required this.graphDataDir,
    required this.exportGraphData,
    required this.dryRun,
    required this.showHelp,
  });

  final String traceliteRoot;
  final String dartExecutable;
  final String label;
  final String outDir;
  final String baseline;
  final String candidate;
  final String policy;
  final String expectation;
  final String primaryPeer;
  final String primaryMetric;
  final String primaryScenarios;
  final String guardrailPeers;
  final String guardrailScenarios;
  final String guardrailMetrics;
  final TraceliteSourcePolicy traceliteSourcePolicy;
  final String? graphDataDir;
  final bool exportGraphData;
  final bool dryRun;
  final bool showHelp;

  static _Options parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      final label = _defaultLabel();
      return _Options(
        traceliteRoot: Platform.environment['TRACELITE_ROOT'] ?? '',
        dartExecutable: Platform.resolvedExecutable,
        label: label,
        outDir: p.join('build', 'tracelite-decisions', label),
        baseline: '',
        candidate: '',
        policy: '',
        expectation: 'no_regression',
        primaryPeer: _defaultPolicyPeer,
        primaryMetric: _defaultReleaseMetric,
        primaryScenarios: traceliteReleasePolicyScenarios.join(','),
        guardrailPeers: _defaultPolicyPeer,
        guardrailScenarios: traceliteReleasePolicyScenarios.join(','),
        guardrailMetrics: _defaultReleaseMetric,
        traceliteSourcePolicy: const TraceliteSourcePolicy(
          expectedRevision: pinnedTraceliteRevision,
          allowUnpinned: false,
          allowDirty: false,
        ),
        graphDataDir: null,
        exportGraphData: true,
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
    final graphDataDir = values['graph-data-dir'] == null
        ? null
        : Directory(values['graph-data-dir']!).absolute.path;
    final expectation = values['expect'] ?? 'no_regression';
    if (expectation != 'improvement' && expectation != 'no_regression') {
      stderr.writeln('--expect must be improvement or no_regression');
      exit(64);
    }

    return _Options(
      traceliteRoot: traceliteRoot,
      dartExecutable: values['dart'] ?? Platform.resolvedExecutable,
      label: label,
      outDir:
          values['out-dir'] ?? p.join('build', 'tracelite-decisions', label),
      baseline: _absolutePathOption(values['baseline']),
      candidate: _absolutePathOption(values['candidate']),
      policy: _absolutePathOption(values['policy']),
      expectation: expectation,
      primaryPeer: values['primary-peer'] ?? _defaultPolicyPeer,
      primaryMetric: values['primary-metric'] ?? _defaultReleaseMetric,
      primaryScenarios:
          values['primary-scenarios'] ??
          traceliteReleasePolicyScenarios.join(','),
      guardrailPeers: values['guardrail-peers'] ?? _defaultPolicyPeer,
      guardrailScenarios:
          values['guardrail-scenarios'] ??
          values['primary-scenarios'] ??
          traceliteReleasePolicyScenarios.join(','),
      guardrailMetrics: values['guardrail-metrics'] ?? _defaultReleaseMetric,
      traceliteSourcePolicy: traceliteSourcePolicyFromOptions(
        revision: values['tracelite-revision'],
        flags: flags,
      ),
      graphDataDir: graphDataDir,
      exportGraphData: !flags.contains('no-graph-data'),
      dryRun: flags.contains('dry-run'),
      showHelp: false,
    );
  }
}

final class _Paths {
  _Paths(String outDir, {String? graphDataDir})
    : manifest = p.join(outDir, 'resqlite-tracelite-decision.json'),
      decisionJson = p.join(outDir, 'decision.json'),
      decisionMarkdown = p.join(outDir, 'decision.md'),
      insightsJson = p.join(outDir, 'insights.json'),
      insightsMarkdown = p.join(outDir, 'insights.md'),
      graphDataDir = graphDataDir ?? p.join(outDir, 'graph-data');

  final String manifest;
  final String decisionJson;
  final String decisionMarkdown;
  final String insightsJson;
  final String insightsMarkdown;
  final String graphDataDir;
}

final class _Step {
  const _Step({
    required this.name,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String name;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  String get displayCommand =>
      [executable, for (final arg in arguments) _quoteIfNeeded(arg)].join(' ');
}

final class _StepResult {
  const _StepResult({
    required this.name,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
  });

  final String name;
  final String command;
  final String workingDirectory;
  final int exitCode;

  String get status => exitCode == 0 ? 'ok' : 'failed';

  Map<String, Object?> toJson() => {
    'name': name,
    'command': command,
    'working_directory': workingDirectory,
    'exit_code': exitCode,
    'status': status,
  };
}

_Step _decisionStep(_Options options, _Paths paths) {
  return _Step(
    name: 'run tracelite decision',
    executable: options.dartExecutable,
    arguments: [
      'run',
      'bin/tracelite.dart',
      'decision',
      '--baseline=${options.baseline}',
      '--candidate=${options.candidate}',
      '--policy=${options.policy}',
      '--expect=${options.expectation}',
      '--primary-peer=${options.primaryPeer}',
      '--primary-metric=${options.primaryMetric}',
      '--primary-scenarios=${options.primaryScenarios}',
      '--guardrail-peers=${options.guardrailPeers}',
      '--guardrail-scenarios=${options.guardrailScenarios}',
      '--guardrail-metrics=${options.guardrailMetrics}',
      '--out-json=${paths.decisionJson}',
    ],
    workingDirectory: options.traceliteRoot,
  );
}

_Step? _graphDataStep(_Options options, _Paths paths) {
  if (!options.exportGraphData) return null;
  final baselineArgs = _graphDataInputArgs(options.baseline);
  final candidateArgs = _graphDataInputArgs(options.candidate);
  return _Step(
    name: 'export tracelite decision graph data',
    executable: options.dartExecutable,
    arguments: [
      'run',
      'bin/tracelite.dart',
      'export-graph-data',
      ...baselineArgs,
      ...candidateArgs,
      '--decision=${p.absolute(paths.decisionJson)}',
      '--run-id=${options.label}',
      '--out=${p.absolute(paths.graphDataDir)}',
    ],
    workingDirectory: options.traceliteRoot,
  );
}

List<String> _graphDataInputArgs(String path) {
  final file = File(path);
  if (!file.existsSync()) return ['--suite=$path'];

  try {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    return switch (decoded['schema']) {
      'tracelite.suite_history.v1' => ['--suite-history=${p.absolute(path)}'],
      'tracelite.compare.v1' => ['--compare=${p.absolute(path)}'],
      _ => ['--suite=${p.absolute(path)}'],
    };
  } on Object {
    return ['--suite=${p.absolute(path)}'];
  }
}

_Step _explainStep(_Options options, _Paths paths) {
  return _Step(
    name: 'explain tracelite decision',
    executable: options.dartExecutable,
    arguments: [
      'run',
      'bin/tracelite.dart',
      'explain',
      p.absolute(paths.decisionJson),
      '--out-json=${p.absolute(paths.insightsJson)}',
    ],
    workingDirectory: options.traceliteRoot,
  );
}

Future<_StepResult> _runDecisionStep(_Step step, _Paths paths) async {
  print('== ${step.name}');
  print(step.displayCommand);

  final result = await Process.run(
    step.executable,
    step.arguments,
    workingDirectory: step.workingDirectory,
    environment: Platform.environment,
  );

  final stdoutText = _cleanDartToolOutput(result.stdout.toString());
  final stderrText = _cleanDartToolOutput(result.stderr.toString());
  File(paths.decisionMarkdown)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(stdoutText);
  if (stdoutText.trim().isNotEmpty) stdout.write(stdoutText);
  if (stderrText.trim().isNotEmpty) stderr.write(stderrText);
  if (result.exitCode != 0) {
    stderr.writeln('step failed: ${step.name} (exit ${result.exitCode})');
  }
  print('');
  return _StepResult(
    name: step.name,
    command: step.displayCommand,
    workingDirectory: step.workingDirectory,
    exitCode: result.exitCode,
  );
}

Future<_StepResult> _runMarkdownStep(_Step step, String stdoutPath) async {
  print('== ${step.name}');
  print(step.displayCommand);

  final result = await Process.run(
    step.executable,
    step.arguments,
    workingDirectory: step.workingDirectory,
    environment: Platform.environment,
  );

  final stdoutText = _cleanDartToolOutput(result.stdout.toString());
  final stderrText = _cleanDartToolOutput(result.stderr.toString());
  File(stdoutPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(stdoutText);
  if (stdoutText.trim().isNotEmpty) stdout.write(stdoutText);
  if (stderrText.trim().isNotEmpty) stderr.write(stderrText);
  if (result.exitCode != 0) {
    stderr.writeln('step failed: ${step.name} (exit ${result.exitCode})');
  }
  print('');
  return _StepResult(
    name: step.name,
    command: step.displayCommand,
    workingDirectory: step.workingDirectory,
    exitCode: result.exitCode,
  );
}

Future<_StepResult> _runStep(_Step step) async {
  print('== ${step.name}');
  print(step.displayCommand);

  final result = await Process.run(
    step.executable,
    step.arguments,
    workingDirectory: step.workingDirectory,
    environment: Platform.environment,
  );

  final stdoutText = _cleanDartToolOutput(result.stdout.toString());
  final stderrText = _cleanDartToolOutput(result.stderr.toString());
  if (stdoutText.trim().isNotEmpty) stdout.write(stdoutText);
  if (stderrText.trim().isNotEmpty) stderr.write(stderrText);
  if (result.exitCode != 0) {
    stderr.writeln('step failed: ${step.name} (exit ${result.exitCode})');
  }
  print('');
  return _StepResult(
    name: step.name,
    command: step.displayCommand,
    workingDirectory: step.workingDirectory,
    exitCode: result.exitCode,
  );
}

Future<void> _writeManifest(
  _Options options,
  _Paths paths,
  List<_StepResult> stepResults, {
  required Map<String, Object?> traceliteSource,
}) async {
  final failedSteps = stepResults
      .where((result) => result.exitCode != 0)
      .toList();
  final manifest = {
    'schema': 'resqlite.tracelite_decision_run.v1',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'status': failedSteps.isEmpty ? 'ok' : 'failed',
    'label': options.label,
    'tracelite_root': options.traceliteRoot,
    'tracelite_source': traceliteSource,
    'baseline': options.baseline,
    'candidate': options.candidate,
    'policy': options.policy,
    'decision': {
      'expectation': options.expectation,
      'primary_peer': options.primaryPeer,
      'primary_metric': options.primaryMetric,
      'primary_scenarios': options.primaryScenarios
          .split(',')
          .map((value) => value.trim())
          .toList(),
      'guardrail_peers': options.guardrailPeers
          .split(',')
          .map((value) => value.trim())
          .toList(),
      'guardrail_scenarios': options.guardrailScenarios
          .split(',')
          .map((value) => value.trim())
          .toList(),
      'guardrail_metrics': options.guardrailMetrics
          .split(',')
          .map((value) => value.trim())
          .toList(),
    },
    'artifacts': {
      'decision_json': paths.decisionJson,
      'decision_markdown': paths.decisionMarkdown,
      'insights_json': paths.insightsJson,
      'insights_markdown': paths.insightsMarkdown,
      'graph_data_dir': options.exportGraphData ? paths.graphDataDir : null,
    },
    'steps': stepResults.map((result) => result.toJson()).toList(),
  };
  final file = File(paths.manifest);
  file.parent.createSync(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}

void _printPlan(_Options options, _Paths paths, List<_Step> steps) {
  print('# resqlite tracelite decision plan');
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
  print('baseline: ${options.baseline}');
  print('candidate: ${options.candidate}');
  print('policy: ${options.policy}');
  print('primary_scenarios: ${options.primaryScenarios}');
  print('guardrail_metrics: ${options.guardrailMetrics}');
  print('');
  print('artifacts:');
  print('  manifest: ${paths.manifest}');
  print('  decision JSON: ${paths.decisionJson}');
  print('  decision markdown: ${paths.decisionMarkdown}');
  print('  insights JSON: ${paths.insightsJson}');
  print('  insights markdown: ${paths.insightsMarkdown}');
  if (options.exportGraphData) {
    print('  graph data index: ${p.join(paths.graphDataDir, 'index.json')}');
  }
  print('');
  print('steps:');
  for (final step in steps) {
    print('- ${step.name}');
    print('  cwd ${step.workingDirectory}');
    print('  ${step.displayCommand}');
  }
}

void _validateInputs(_Options options) {
  _validateTraceliteRoot(options.traceliteRoot);
  _requireFile('--baseline', options.baseline);
  _requireFile('--candidate', options.candidate);
  _requireFile('--policy', options.policy);
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

void _requireFile(String option, String path) {
  if (path.isEmpty) {
    stderr.writeln('missing required $option=path');
    exit(64);
  }
  if (!File(path).existsSync()) {
    stderr.writeln('$option does not exist: $path');
    exit(64);
  }
}

String _absolutePathOption(String? value) {
  if (value == null || value.isEmpty) return '';
  return File(value).absolute.path;
}

String _defaultLabel() {
  return DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
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
  stderr.writeln('  dart run benchmark/decide_tracelite.dart');
  stderr.writeln('    --tracelite-root=/path/to/tracelite');
  stderr.writeln('    --baseline=build/baseline/manifest.json');
  stderr.writeln('    --candidate=build/candidate/manifest.json');
  stderr.writeln(
    '    --policy=build/tracelite-benchmarks/latest/policy-calibration.json',
  );
  stderr.writeln('    [--label=decision-id]');
  stderr.writeln('    [--out-dir=build/tracelite-decisions/decision-id]');
  stderr.writeln('    [--expect=no_regression|improvement]');
  stderr.writeln('    [--primary-peer=resqlite]');
  stderr.writeln('    [--primary-metric=measured_elapsed_ns]');
  stderr.writeln('    [--primary-scenarios=high-cardinality-fanout,...]');
  stderr.writeln('    [--guardrail-peers=resqlite]');
  stderr.writeln('    [--guardrail-scenarios=high-cardinality-fanout,...]');
  stderr.writeln('    [--guardrail-metrics=measured_elapsed_ns]');
  stderr.writeln('    [--tracelite-revision=$pinnedTraceliteRevision]');
  stderr.writeln(
    '    [--graph-data-dir=docs/benchmarks/data/tracelite/latest-decision]',
  );
  stderr.writeln('    [--allow-unpinned-tracelite] [--allow-dirty-tracelite]');
  stderr.writeln('    [--no-graph-data] [--dry-run]');
  stderr.writeln('');
  stderr.writeln('TRACELITE_ROOT can be used instead of --tracelite-root.');
  exit(exitCode);
}
