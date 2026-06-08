// ignore_for_file: avoid_print
//
// End-to-end baseline/candidate experiment workflow backed by tracelite.
//
// This script coordinates the existing resqlite Tracelite wrappers instead of
// replacing them: it collects repeated suite-history artifacts for a baseline
// checkout and a candidate checkout, runs the Tracelite decision wrapper over
// those histories, then writes a single manifest and experiment writeup draft.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tracelite_source.dart';
import 'tracelite_workloads.dart';

const _defaultPolicyPeer = 'resqlite';
const _defaultMetric = 'measured_elapsed_ns';
const _defaultRunner = 'script';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _usage(exitCode: 0);
  }

  final paths = _Paths(Directory(options.outDir).absolute.path, options.label);
  final steps = _plannedSteps(options, paths);

  if (options.dryRun) {
    _printPlan(options, paths, steps);
    return;
  }

  _validateInputs(options);
  Directory(paths.outDir).createSync(recursive: true);

  final results = <_StepResult>[];
  final overrideBackup = _TraceliteOverrideBackup.capture(
    options.traceliteRoot,
  );
  try {
    _writeTraceliteResqliteOverride(
      options.traceliteRoot,
      options.baselineRoot,
    );
    results.add(await _runLoggedStep(steps.baseline, paths.baselineLog));
    if (results.every((result) => result.exitCode == 0)) {
      _writeTraceliteResqliteOverride(
        options.traceliteRoot,
        options.candidateRoot,
      );
      results.add(await _runLoggedStep(steps.candidate, paths.candidateLog));
    }
    if (results.every((result) => result.exitCode == 0)) {
      results.add(await _runLoggedStep(steps.decision, paths.decisionLog));
    }
  } finally {
    overrideBackup.restore();
  }

  final decisionArtifact = _readJsonMap(paths.decisionJson);
  if (decisionArtifact != null) {
    await _writeExperimentDraft(options, paths, decisionArtifact);
  }

  await _writeManifest(options, paths, results, decisionArtifact);

  print('');
  print('Artifacts written:');
  print('  manifest: ${paths.manifest}');
  print('  experiment draft: ${paths.experimentMarkdown}');
  print('  baseline history: ${paths.baselineHistory}');
  print('  candidate history: ${paths.candidateHistory}');
  print('  decision JSON: ${paths.decisionJson}');
  print('  decision insights: ${paths.decisionInsightsMarkdown}');

  final collectionFailure = results
      .where((result) => result.name != _Steps.decisionName)
      .where((result) => result.exitCode != 0)
      .toList();
  if (collectionFailure.isNotEmpty) {
    exitCode = collectionFailure.first.exitCode;
    return;
  }

  final decisionResult = _stepResultNamed(results, _Steps.decisionName);
  if (decisionResult != null && decisionArtifact == null) {
    exitCode = decisionResult.exitCode == 0 ? 65 : decisionResult.exitCode;
    return;
  }

  if (options.failOnNonaccepted &&
      (decisionArtifact?['decision'] as String?) != 'accepted') {
    final decisionExitCode = decisionResult?.exitCode ?? 65;
    exitCode = decisionExitCode == 0 ? 65 : decisionExitCode;
  }
}

final class _Options {
  const _Options({
    required this.traceliteRoot,
    required this.baselineRoot,
    required this.candidateRoot,
    required this.dartExecutable,
    required this.label,
    required this.direction,
    required this.outDir,
    required this.preset,
    required this.runner,
    required this.runs,
    required this.interfaces,
    required this.suiteScenarios,
    required this.policyScenarios,
    required this.policyPeers,
    required this.policyMetric,
    required this.minRepetitions,
    required this.maxRepetitions,
    required this.expectation,
    required this.primaryPeer,
    required this.primaryMetric,
    required this.guardrailPeers,
    required this.guardrailMetrics,
    required this.policyPath,
    required this.traceliteSourcePolicy,
    required this.exportGraphData,
    required this.failOnNonaccepted,
    required this.dryRun,
    required this.showHelp,
  });

  final String traceliteRoot;
  final String baselineRoot;
  final String candidateRoot;
  final String dartExecutable;
  final String label;
  final String direction;
  final String outDir;
  final String preset;
  final String runner;
  final int runs;
  final String interfaces;
  final String suiteScenarios;
  final String policyScenarios;
  final String policyPeers;
  final String policyMetric;
  final int minRepetitions;
  final int maxRepetitions;
  final String expectation;
  final String primaryPeer;
  final String primaryMetric;
  final String guardrailPeers;
  final String guardrailMetrics;
  final String? policyPath;
  final TraceliteSourcePolicy traceliteSourcePolicy;
  final bool exportGraphData;
  final bool failOnNonaccepted;
  final bool dryRun;
  final bool showHelp;

  static _Options parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      final label = _defaultLabel();
      final preset = _directionPreset('general');
      return _Options(
        traceliteRoot: Platform.environment['TRACELITE_ROOT'] ?? '',
        baselineRoot: '',
        candidateRoot: Directory.current.absolute.path,
        dartExecutable: Platform.resolvedExecutable,
        label: label,
        direction: 'general',
        outDir: p.join('build', 'tracelite-experiments', label),
        preset: 'experiment',
        runner: _defaultRunner,
        runs: 3,
        interfaces: preset.interfaces,
        suiteScenarios: preset.suiteScenarios.join(','),
        policyScenarios: preset.policyScenarios.join(','),
        policyPeers: _defaultPolicyPeer,
        policyMetric: _defaultMetric,
        minRepetitions: 5,
        maxRepetitions: 20,
        expectation: 'improvement',
        primaryPeer: _defaultPolicyPeer,
        primaryMetric: _defaultMetric,
        guardrailPeers: _defaultPolicyPeer,
        guardrailMetrics: _defaultMetric,
        policyPath: null,
        traceliteSourcePolicy: const TraceliteSourcePolicy(
          expectedRevision: pinnedTraceliteRevision,
          allowUnpinned: false,
          allowDirty: false,
        ),
        exportGraphData: true,
        failOnNonaccepted: false,
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
    final direction = values['direction'] ?? 'general';
    final directionPreset = _directionPreset(direction);
    final rawTraceliteRoot =
        values['tracelite-root'] ??
        Platform.environment['TRACELITE_ROOT'] ??
        '';
    final traceliteRoot = rawTraceliteRoot.isEmpty
        ? ''
        : Directory(rawTraceliteRoot).absolute.path;
    final baselineRoot = _absoluteDirectoryOption(values['baseline-root']);
    final candidateRoot = _absoluteDirectoryOption(
      values['candidate-root'] ?? Directory.current.path,
    );

    return _Options(
      traceliteRoot: traceliteRoot,
      baselineRoot: baselineRoot,
      candidateRoot: candidateRoot,
      dartExecutable: values['dart'] ?? Platform.resolvedExecutable,
      label: label,
      direction: direction,
      outDir:
          values['out-dir'] ?? p.join('build', 'tracelite-experiments', label),
      preset: values['preset'] ?? 'experiment',
      runner: values['runner'] ?? _defaultRunner,
      runs: _positiveInt(values['runs'], 3),
      interfaces: values['interfaces'] ?? directionPreset.interfaces,
      suiteScenarios:
          values['suite-scenarios'] ??
          values['scenarios'] ??
          directionPreset.suiteScenarios.join(','),
      policyScenarios:
          values['policy-scenarios'] ??
          directionPreset.policyScenarios.join(','),
      policyPeers: values['policy-peers'] ?? _defaultPolicyPeer,
      policyMetric: values['policy-metric'] ?? _defaultMetric,
      minRepetitions: _positiveInt(values['min-repetitions'], 5),
      maxRepetitions: _positiveInt(values['max-repetitions'], 20),
      expectation: values['expect'] ?? 'improvement',
      primaryPeer: values['primary-peer'] ?? _defaultPolicyPeer,
      primaryMetric: values['primary-metric'] ?? _defaultMetric,
      guardrailPeers:
          values['guardrail-peers'] ?? directionPreset.guardrailPeers,
      guardrailMetrics: values['guardrail-metrics'] ?? _defaultMetric,
      policyPath: _absoluteFileOption(values['policy']),
      traceliteSourcePolicy: traceliteSourcePolicyFromOptions(
        revision: values['tracelite-revision'],
        flags: flags,
      ),
      exportGraphData: !flags.contains('no-graph-data'),
      failOnNonaccepted: flags.contains('fail-on-nonaccepted'),
      dryRun: flags.contains('dry-run'),
      showHelp: false,
    );
  }
}

final class _DirectionPreset {
  const _DirectionPreset({
    required this.interfaces,
    required this.suiteScenarios,
    required this.policyScenarios,
    required this.guardrailPeers,
  });

  final String interfaces;
  final List<String> suiteScenarios;
  final List<String> policyScenarios;
  final String guardrailPeers;
}

_DirectionPreset _directionPreset(String direction) {
  return switch (direction) {
    'parameter-encoding-and-binding' => const _DirectionPreset(
      interfaces: 'sqlite_async,resqlite',
      suiteScenarios: ['narrow-batch-insert'],
      policyScenarios: ['narrow-batch-insert'],
      guardrailPeers: 'sqlite_async',
    ),
    'stream-rerun-dispatch' => const _DirectionPreset(
      interfaces: _defaultPolicyPeer,
      suiteScenarios: [
        'high-cardinality-fanout',
        'many-streams-writer-throughput',
        'keyed-pk-subscriptions',
      ],
      policyScenarios: [
        'high-cardinality-fanout',
        'many-streams-writer-throughput',
        'keyed-pk-subscriptions',
      ],
      guardrailPeers: _defaultPolicyPeer,
    ),
    'memory' => const _DirectionPreset(
      interfaces: _defaultPolicyPeer,
      suiteScenarios: ['large-working-set', 'sqlite-diagnostics'],
      policyScenarios: ['large-working-set'],
      guardrailPeers: _defaultPolicyPeer,
    ),
    'production-release' => const _DirectionPreset(
      interfaces: _defaultPolicyPeer,
      suiteScenarios: traceliteProductionSuiteScenarios,
      policyScenarios: traceliteReleasePolicyScenarios,
      guardrailPeers: _defaultPolicyPeer,
    ),
    _ => const _DirectionPreset(
      interfaces: 'sqlite_async,resqlite',
      suiteScenarios: traceliteExperimentSuiteScenarios,
      policyScenarios: traceliteExperimentSuiteScenarios,
      guardrailPeers: _defaultPolicyPeer,
    ),
  };
}

final class _Paths {
  _Paths(this.outDir, String label)
    : baselineDir = p.join(outDir, 'baseline'),
      candidateDir = p.join(outDir, 'candidate'),
      decisionDir = p.join(outDir, 'decision'),
      manifest = p.join(outDir, 'resqlite-tracelite-experiment.json'),
      experimentMarkdown = p.join(outDir, '$label-experiment.md'),
      baselineLog = p.join(outDir, 'baseline.log'),
      candidateLog = p.join(outDir, 'candidate.log'),
      decisionLog = p.join(outDir, 'decision.log');

  final String outDir;
  final String baselineDir;
  final String candidateDir;
  final String decisionDir;
  final String manifest;
  final String experimentMarkdown;
  final String baselineLog;
  final String candidateLog;
  final String decisionLog;

  String get baselineHistory => p.join(baselineDir, 'history.json');
  String get candidateHistory => p.join(candidateDir, 'history.json');
  String get baselinePolicy => p.join(baselineDir, 'policy-calibration.json');
  String get decisionJson => p.join(decisionDir, 'decision.json');
  String get decisionInsightsMarkdown => p.join(decisionDir, 'insights.md');
}

final class _Steps {
  const _Steps({
    required this.baseline,
    required this.candidate,
    required this.decision,
  });

  static const decisionName = 'decide experiment';

  final _Step baseline;
  final _Step candidate;
  final _Step decision;
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

_StepResult? _stepResultNamed(List<_StepResult> results, String name) {
  for (final result in results) {
    if (result.name == name) return result;
  }
  return null;
}

final class _TraceliteOverrideBackup {
  const _TraceliteOverrideBackup(this.path, this.originalContent);

  final String path;
  final String? originalContent;

  static _TraceliteOverrideBackup capture(String traceliteRoot) {
    final path = p.join(traceliteRoot, 'pubspec_overrides.yaml');
    final file = File(path);
    return _TraceliteOverrideBackup(
      path,
      file.existsSync() ? file.readAsStringSync() : null,
    );
  }

  void restore() {
    final file = File(path);
    if (originalContent == null) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    file.writeAsStringSync(originalContent!);
  }
}

void _writeTraceliteResqliteOverride(
  String traceliteRoot,
  String resqliteRoot,
) {
  final file = File(p.join(traceliteRoot, 'pubspec_overrides.yaml'));
  file.writeAsStringSync(
    'dependency_overrides:\n'
    '  resqlite:\n'
    '    path: ${jsonEncode(resqliteRoot)}\n',
  );
}

_Steps _plannedSteps(_Options options, _Paths paths) {
  return _Steps(
    baseline: _benchmarkStep(
      options,
      name: 'collect baseline history',
      root: options.baselineRoot,
      role: 'baseline',
      outDir: paths.baselineDir,
    ),
    candidate: _benchmarkStep(
      options,
      name: 'collect candidate history',
      root: options.candidateRoot,
      role: 'candidate',
      outDir: paths.candidateDir,
    ),
    decision: _decisionStep(options, paths),
  );
}

_Step _benchmarkStep(
  _Options options, {
  required String name,
  required String root,
  required String role,
  required String outDir,
}) {
  return _Step(
    name: name,
    executable: options.dartExecutable,
    arguments: [
      'run',
      'benchmark/run_tracelite.dart',
      '--preset=${options.preset}',
      '--tracelite-root=${options.traceliteRoot}',
      '--resqlite-root=$root',
      '--label=${options.label}-$role',
      '--out-dir=$outDir',
      '--runner=${options.runner}',
      '--runs=${options.runs}',
      '--interfaces=${options.interfaces}',
      '--suite-scenarios=${options.suiteScenarios}',
      '--policy-peers=${options.policyPeers}',
      '--policy-scenarios=${options.policyScenarios}',
      '--policy-metric=${options.policyMetric}',
      '--min-repetitions=${options.minRepetitions}',
      '--max-repetitions=${options.maxRepetitions}',
      '--no-strict',
      '--tracelite-revision=${options.traceliteSourcePolicy.expectedRevision}',
      if (options.traceliteSourcePolicy.allowUnpinned)
        '--allow-unpinned-tracelite',
      if (options.traceliteSourcePolicy.allowDirty) '--allow-dirty-tracelite',
      if (!options.exportGraphData) '--no-graph-data',
    ],
    workingDirectory: root,
  );
}

_Step _decisionStep(_Options options, _Paths paths) {
  final policy = options.policyPath ?? paths.baselinePolicy;
  return _Step(
    name: _Steps.decisionName,
    executable: options.dartExecutable,
    arguments: [
      'run',
      'benchmark/decide_tracelite.dart',
      '--tracelite-root=${options.traceliteRoot}',
      '--baseline=${paths.baselineHistory}',
      '--candidate=${paths.candidateHistory}',
      '--policy=$policy',
      '--expect=${options.expectation}',
      '--primary-peer=${options.primaryPeer}',
      '--primary-metric=${options.primaryMetric}',
      '--primary-scenarios=${options.policyScenarios}',
      '--guardrail-peers=${options.guardrailPeers}',
      '--guardrail-scenarios=${options.policyScenarios}',
      '--guardrail-metrics=${options.guardrailMetrics}',
      '--label=${options.label}-decision',
      '--out-dir=${paths.decisionDir}',
      '--tracelite-revision=${options.traceliteSourcePolicy.expectedRevision}',
      if (options.traceliteSourcePolicy.allowUnpinned)
        '--allow-unpinned-tracelite',
      if (options.traceliteSourcePolicy.allowDirty) '--allow-dirty-tracelite',
      if (!options.exportGraphData) '--no-graph-data',
    ],
    workingDirectory: Directory.current.absolute.path,
  );
}

Future<_StepResult> _runLoggedStep(_Step step, String logPath) async {
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
  final logFile = File(logPath)..parent.createSync(recursive: true);
  logFile.writeAsStringSync(
    [
      r'$ ',
      step.displayCommand,
      '',
      '## stdout',
      stdoutText,
      '',
      '## stderr',
      stderrText,
    ].join('\n'),
  );
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

Future<void> _writeExperimentDraft(
  _Options options,
  _Paths paths,
  Map<String, Object?> decision,
) async {
  final buffer = StringBuffer()
    ..writeln('# Experiment ${options.label}: <title>')
    ..writeln()
    ..writeln('**Date:** ${DateTime.now().toUtc().toIso8601String()}')
    ..writeln('**Status:** ${decision['decision'] ?? 'unknown'}')
    ..writeln('**Direction:** `${options.direction}`')
    ..writeln()
    ..writeln('## Hypothesis')
    ..writeln()
    ..writeln('<state the proposed change and why it should work>')
    ..writeln()
    ..writeln('## Approach')
    ..writeln()
    ..writeln('- Baseline root: `${options.baselineRoot}`')
    ..writeln('- Candidate root: `${options.candidateRoot}`')
    ..writeln('- Tracelite root: `${options.traceliteRoot}`')
    ..writeln('- Suite scenarios: `${options.suiteScenarios}`')
    ..writeln('- Policy scenarios: `${options.policyScenarios}`')
    ..writeln()
    ..writeln('## Results')
    ..writeln()
    ..writeln('Decision: `${decision['decision'] ?? 'unknown'}`')
    ..writeln()
    ..writeln(
      '| role | scenario | peer | metric | status | change | max CV | p | CI |',
    )
    ..writeln('|---|---|---|---|---|---:|---:|---:|---|');

  for (final comparison in _decisionComparisons(decision)) {
    buffer.writeln(
      '| `${comparison['role'] ?? ''}` '
      '| `${comparison['scenario'] ?? ''}` '
      '| `${comparison['peer'] ?? ''}` '
      '| `${comparison['metric'] ?? ''}` '
      '| `${comparison['status'] ?? ''}` '
      '| ${_formatPercent(comparison['change_percent'])} '
      '| ${_formatPercent(comparison['max_cv_percent'])} '
      '| ${_formatNumber(comparison['nonparametric_p_value'])} '
      '| ${_formatInterval(comparison)} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('Artifacts:')
    ..writeln()
    ..writeln('- Baseline history: `${paths.baselineHistory}`')
    ..writeln('- Candidate history: `${paths.candidateHistory}`')
    ..writeln('- Decision JSON: `${paths.decisionJson}`')
    ..writeln('- Decision insights: `${paths.decisionInsightsMarkdown}`')
    ..writeln()
    ..writeln('## Analysis')
    ..writeln()
    ..writeln(
      '<interpret whether the result is accepted, rejected, or deferred>',
    )
    ..writeln()
    ..writeln('## Conclusion')
    ..writeln()
    ..writeln('<state the outcome and what future experimenters should learn>');

  await File(paths.experimentMarkdown).writeAsString(buffer.toString());
}

Future<void> _writeManifest(
  _Options options,
  _Paths paths,
  List<_StepResult> stepResults,
  Map<String, Object?>? decision,
) async {
  final failedCollection = stepResults
      .where((result) => result.name != _Steps.decisionName)
      .any((result) => result.exitCode != 0);
  final missingDecisionArtifact =
      _stepResultNamed(stepResults, _Steps.decisionName) != null &&
      decision == null;
  final manifest = {
    'schema': 'resqlite.tracelite_experiment_run.v1',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'status': failedCollection || missingDecisionArtifact ? 'failed' : 'ok',
    'label': options.label,
    'direction': options.direction,
    'baseline_root': options.baselineRoot,
    'candidate_root': options.candidateRoot,
    'tracelite_root': options.traceliteRoot,
    'tracelite_revision': options.traceliteSourcePolicy.expectedRevision,
    'preset': options.preset,
    'runner': options.runner,
    'runs': options.runs,
    'interfaces': options.interfaces.split(','),
    'suite_scenarios': options.suiteScenarios.split(','),
    'policy_scenarios': options.policyScenarios.split(','),
    'decision': decision == null
        ? null
        : {
            'decision': decision['decision'],
            'primary': (decision['gates'] as Map<String, Object?>?)?['primary'],
            'guardrails':
                (decision['gates'] as Map<String, Object?>?)?['guardrails'],
          },
    'artifacts': {
      'baseline_history': paths.baselineHistory,
      'candidate_history': paths.candidateHistory,
      'baseline_policy': paths.baselinePolicy,
      'decision_json': paths.decisionJson,
      'decision_insights_markdown': paths.decisionInsightsMarkdown,
      'experiment_markdown': paths.experimentMarkdown,
      'baseline_log': paths.baselineLog,
      'candidate_log': paths.candidateLog,
      'decision_log': paths.decisionLog,
    },
    'steps': stepResults.map((result) => result.toJson()).toList(),
  };

  await File(
    paths.manifest,
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
}

List<Map<String, Object?>> _decisionComparisons(Map<String, Object?> decision) {
  final gates = decision['gates'];
  if (gates is! Map<String, Object?>) return const [];
  final comparisons = <Map<String, Object?>>[];
  for (final gateName in ['primary', 'guardrails']) {
    final gate = gates[gateName];
    if (gate is! Map<String, Object?>) continue;
    final rows = gate['comparisons'];
    if (rows is! List<Object?>) continue;
    for (final row in rows) {
      if (row is Map<String, Object?>) comparisons.add(row);
    }
  }
  return comparisons;
}

Map<String, Object?>? _readJsonMap(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } on Object {
    return null;
  }
}

void _printPlan(_Options options, _Paths paths, _Steps steps) {
  print('# resqlite tracelite experiment plan');
  print('');
  print('label: ${options.label}');
  print('direction: ${options.direction}');
  print('out_dir: ${paths.outDir}');
  print('baseline_root: ${options.baselineRoot}');
  print('candidate_root: ${options.candidateRoot}');
  print('tracelite_root: ${options.traceliteRoot}');
  print(
    'tracelite_revision: ${options.traceliteSourcePolicy.expectedRevision}',
  );
  print('suite_scenarios: ${options.suiteScenarios}');
  print('policy_scenarios: ${options.policyScenarios}');
  print('');
  print('artifacts:');
  print('  manifest: ${paths.manifest}');
  print('  experiment draft: ${paths.experimentMarkdown}');
  print('  baseline history: ${paths.baselineHistory}');
  print('  candidate history: ${paths.candidateHistory}');
  print('  decision JSON: ${paths.decisionJson}');
  print('');
  print('steps:');
  for (final step in [steps.baseline, steps.candidate, steps.decision]) {
    print('- ${step.name}');
    print('  cwd ${step.workingDirectory}');
    print('  ${step.displayCommand}');
  }
}

void _validateInputs(_Options options) {
  _requireDirectory('--tracelite-root', options.traceliteRoot);
  _requireDirectory('--baseline-root', options.baselineRoot);
  _requireDirectory('--candidate-root', options.candidateRoot);
  _requireFile(
    'baseline benchmark/run_tracelite.dart',
    p.join(options.baselineRoot, 'benchmark', 'run_tracelite.dart'),
  );
  _requireFile(
    'candidate benchmark/run_tracelite.dart',
    p.join(options.candidateRoot, 'benchmark', 'run_tracelite.dart'),
  );
  if (options.policyPath != null) _requireFile('--policy', options.policyPath!);
}

void _requireDirectory(String label, String path) {
  if (path.isEmpty || !Directory(path).existsSync()) {
    stderr.writeln('missing $label: $path');
    exit(64);
  }
}

void _requireFile(String label, String path) {
  if (path.isEmpty || !File(path).existsSync()) {
    stderr.writeln('missing $label: $path');
    exit(64);
  }
}

String _defaultLabel() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}T'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}Z';
}

String _absoluteDirectoryOption(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  return Directory(value).absolute.path;
}

String? _absoluteFileOption(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return File(value).absolute.path;
}

int _positiveInt(String? value, int fallback) {
  if (value == null || value.trim().isEmpty) return fallback;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    stderr.writeln('expected positive integer, got `$value`');
    exit(64);
  }
  return parsed;
}

String _formatPercent(Object? value) {
  if (value is! num) return '';
  return '${value.toStringAsFixed(1)}%';
}

String _formatNumber(Object? value) {
  if (value is! num) return '';
  return value.toStringAsPrecision(3);
}

String _formatInterval(Map<String, Object?> comparison) {
  final low = comparison['delta_ci95_low'];
  final high = comparison['delta_ci95_high'];
  if (low is! num || high is! num) return '';
  String ms(num value) => '${(value / 1000000).toStringAsFixed(2)}ms';
  return '${ms(low)}..${ms(high)}';
}

String _quoteIfNeeded(String value) {
  if (value.isEmpty) return "''";
  if (!RegExp(r'''[\s'"$`\\]''').hasMatch(value)) return value;
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _cleanDartToolOutput(String value) {
  return value.replaceAll('Running build hooks...', '');
}

Never _usage({int exitCode = 64}) {
  stderr.writeln('usage:');
  stderr.writeln('  dart run benchmark/run_tracelite_experiment.dart');
  stderr.writeln('    --tracelite-root=/path/to/tracelite');
  stderr.writeln('    --baseline-root=/path/to/baseline-resqlite');
  stderr.writeln('    --candidate-root=/path/to/candidate-resqlite');
  stderr.writeln(
    '    [--label=exp-N] [--direction=parameter-encoding-and-binding]',
  );
  stderr.writeln('    [--preset=experiment] [--runs=3] [--runner=script]');
  stderr.writeln('    [--suite-scenarios=narrow-batch-insert]');
  stderr.writeln('    [--policy-scenarios=narrow-batch-insert]');
  stderr.writeln('    [--interfaces=sqlite_async,resqlite]');
  stderr.writeln('    [--expect=improvement|no_regression]');
  stderr.writeln('    [--policy=/path/to/policy-calibration.json]');
  stderr.writeln('    [--tracelite-revision=$pinnedTraceliteRevision]');
  stderr.writeln('    [--allow-unpinned-tracelite] [--allow-dirty-tracelite]');
  stderr.writeln('    [--no-graph-data] [--fail-on-nonaccepted] [--dry-run]');
  stderr.writeln('');
  stderr.writeln('Directions: general, parameter-encoding-and-binding,');
  stderr.writeln('  stream-rerun-dispatch, memory, production-release.');
  exit(exitCode);
}
