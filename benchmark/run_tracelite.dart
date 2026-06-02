// ignore_for_file: avoid_print
//
// Production benchmark workflow backed by tracelite.
//
// This is the resqlite-facing entry point for cross-library benchmark runs.
// It delegates execution, policy calibration, and graph-data export to a local
// tracelite checkout while keeping the stable resqlite release-gate scope
// explicit in this repository. Before running the suite it binds Tracelite's
// resqlite dependency to the checkout under test and records both source
// revisions in the manifest.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tracelite_source.dart';

const _defaultReleaseMetric = 'measured_elapsed_ns';
const _defaultPolicyPeer = 'resqlite';
const _resolveDependenciesStepName = 'resolve tracelite dependencies';
const _validateDependencyStepName = 'validate tracelite resqlite dependency';
const _prepareSqliteShimStepName = 'prepare tracelite sqlite shim';
const _suiteHistoryStepName = 'run tracelite suite history';
const _validateSuiteHistoryStepName = 'validate tracelite suite history';
const _exportGraphDataStepName = 'export tracelite graph data';
const _validateGraphDataStepName = 'validate tracelite graph data';
const _explainArtifactsStepName = 'explain tracelite artifacts';
const _defaultStepTimeout = Duration(minutes: 5);
const _processStartTimeout = Duration(seconds: 30);
const _sqliteShimBuildTimeout = Duration(seconds: 45);
const _sqliteShimSources = [
  'native/tracelite_runtime.c',
  'native/shim_sqlite3.c',
];
const _defaultReleasePolicyScenarios = [
  'high-cardinality-fanout',
  'many-streams-writer-throughput',
  'sqlite-diagnostics',
];
const _defaultDiagnosticScenarios = [
  'point-select',
  'feed-paging',
  'sync-burst',
  'large-working-set',
  'keyed-pk-subscriptions',
];
const _ciSuiteScenarios = [
  'narrow-batch-insert',
  'point-select',
  'keyed-pk-subscriptions',
  'sqlite-diagnostics',
];
const _experimentSuiteScenarios = [
  'feed-paging',
  'chat-sim',
  'keyed-pk-subscriptions',
];

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _usage(exitCode: 0);
  }

  final outDir = Directory(options.outDir).absolute;
  final paths = _Paths(outDir.path, graphDataDir: options.graphDataDir);
  final steps = _plannedSteps(options, paths, forDryRun: true);

  if (options.dryRun) {
    _printPlan(options, paths, steps);
    return;
  }

  _validateTraceliteRoot(options.traceliteRoot);
  _validateResqliteRoot(options.resqliteRoot);
  outDir.createSync(recursive: true);
  final traceliteSource = await traceliteSourceState(
    options.traceliteRoot,
    policy: options.traceliteSourcePolicy,
  );
  validateTraceliteSource(traceliteSource);
  final resqliteSource = await resqliteSourceState(options.resqliteRoot);
  var dependencyBinding = _prepareTraceliteResqliteOverride(options);

  print('# resqlite tracelite benchmark');
  print('');
  print('label: ${options.label}');
  print('preset: ${options.preset}');
  print('out_dir: ${outDir.path}');
  print('tracelite_root: ${options.traceliteRoot}');
  printTraceliteSource(traceliteSource);
  printResqliteSource(resqliteSource);
  _printDependencyBinding(dependencyBinding);
  print('profile: ${options.profile}');
  print('runs: ${options.runs}');
  print(
    'suite_run_timeout_seconds: '
    '${_trimDouble(options.suiteRunTimeoutSeconds)}',
  );
  print('interfaces: ${options.interfaces}');
  print('suite_scenarios: ${options.suiteScenarios}');
  print('policy_metric: ${options.policyMetric}');
  print('policy_peers: ${options.policyPeers}');
  print('policy_scenarios: ${options.policyScenarios}');
  print('min_repetitions: ${options.minRepetitions}');
  print('max_repetitions: ${options.maxRepetitions}');
  print('target_rse_percent: ${_trimDouble(options.targetRsePercent)}');
  print(
    'within_run_noise_percentile: '
    '${_trimDouble(options.withinRunNoisePercentile)}',
  );
  print(
    'threshold_floor_percent: '
    '${_trimDouble(options.thresholdFloorPercent)}',
  );
  print(
    'threshold_ceiling_percent: '
    '${_trimDouble(options.thresholdCeilingPercent)}',
  );
  print(
    'guardrail_floor_percent: '
    '${_trimDouble(options.guardrailFloorPercent)}',
  );
  print(
    'guardrail_ceiling_percent: '
    '${_trimNullableDouble(options.guardrailCeilingPercent)}',
  );
  print(
    'noise_gate_floor_percent: '
    '${_trimDouble(options.noiseGateFloorPercent)}',
  );
  print(
    'noise_gate_ceiling_percent: '
    '${_trimNullableDouble(options.noiseGateCeilingPercent)}',
  );
  print('noise_gate_multiplier: ${_trimDouble(options.noiseGateMultiplier)}');
  print('max_outlier_percent: ${_trimDouble(options.maxOutlierPercent)}');
  print(
    'max_run_outlier_percent: '
    '${_trimDouble(options.maxRunOutlierPercent)}',
  );
  print('');

  final stepResults = <_StepResult>[];

  final resolveResult = await _runStep(_resolveDependenciesStep(options));
  stepResults.add(resolveResult);
  if (resolveResult.exitCode == 0) {
    dependencyBinding = _verifyTraceliteResqliteDependency(
      options,
      dependencyBinding,
    );
    _printDependencyBinding(dependencyBinding);
    if (!dependencyBinding.matchesRequestedRoot) {
      _printDependencyBindingFailure(dependencyBinding);
      stepResults.add(
        _StepResult(
          name: _validateDependencyStepName,
          command: 'read ${dependencyBinding.packageConfigPath}',
          workingDirectory: options.traceliteRoot,
          exitCode: 64,
        ),
      );
    }
  }

  if (stepResults.every((result) => result.exitCode == 0)) {
    stepResults.add(await _buildTraceliteSqliteShim(options));
  }

  if (stepResults.every((result) => result.exitCode == 0)) {
    final suiteResult = await _runStep(_suiteHistoryStep(options, paths));
    stepResults.add(suiteResult);
    if (suiteResult.exitCode == 0) {
      stepResults.add(_validateSuiteHistory(paths));
    }
  }

  if (options.exportGraphData &&
      stepResults.any((result) => result.name == _suiteHistoryStepName)) {
    final graphStep = _graphDataExportStep(options, paths);
    if (graphStep == null) {
      stderr.writeln(
        'no graphable tracelite suite artifacts found; '
        'graph-data export skipped',
      );
      stepResults.add(
        _StepResult(
          name: _exportGraphDataStepName,
          command: 'inspect ${paths.history}',
          workingDirectory: options.traceliteRoot,
          exitCode: 65,
        ),
      );
    } else {
      final graphResult = await _runStep(graphStep);
      stepResults.add(graphResult);
      if (graphResult.exitCode == 0) {
        stepResults.add(await _runStep(_validateGraphDataStep(options, paths)));
      }
    }
  }

  if (File(paths.history).existsSync()) {
    stepResults.add(
      await _runMarkdownStep(
        _explainArtifactsStep(options, paths),
        paths.insightsMarkdown,
      ),
    );
  }

  await _writeManifest(
    options,
    paths,
    stepResults,
    traceliteSource: traceliteSource,
    resqliteSource: resqliteSource,
    dependencyBinding: dependencyBinding,
  );

  print('');
  print('Artifacts written:');
  print('  manifest: ${paths.manifest}');
  print('  suite history: ${paths.history}');
  print('  policy JSON: ${paths.policyJson}');
  print('  policy markdown: ${paths.policyMarkdown}');
  print('  insights JSON: ${paths.insightsJson}');
  print('  insights markdown: ${paths.insightsMarkdown}');
  if (options.exportGraphData) {
    print('  graph data: ${paths.graphDataDir}');
    if (Directory(paths.graphDataInputsDir).existsSync()) {
      print('  graph data inputs: ${paths.graphDataInputsDir}');
    }
  }

  final failedSteps = stepResults
      .where((result) => result.exitCode != 0)
      .toList();
  if (failedSteps.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln(
      'benchmark failed; artifacts were preserved for inspection.',
    );
    exitCode = failedSteps.first.exitCode;
  }
}

final class _Options {
  const _Options({
    required this.traceliteRoot,
    required this.resqliteRoot,
    required this.dartExecutable,
    required this.label,
    required this.preset,
    required this.outDir,
    required this.profile,
    required this.runs,
    required this.interfaces,
    required this.suiteScenarios,
    required this.policyMetric,
    required this.policyPeers,
    required this.policyScenarios,
    required this.minRepetitions,
    required this.maxRepetitions,
    required this.targetRsePercent,
    required this.withinRunNoisePercentile,
    required this.thresholdFloorPercent,
    required this.thresholdCeilingPercent,
    required this.guardrailFloorPercent,
    required this.guardrailCeilingPercent,
    required this.noiseGateFloorPercent,
    required this.noiseGateCeilingPercent,
    required this.noiseGateMultiplier,
    required this.maxOutlierPercent,
    required this.maxRunOutlierPercent,
    required this.suiteRunTimeoutSeconds,
    required this.traceliteSourcePolicy,
    required this.graphDataDir,
    required this.exportGraphData,
    required this.strict,
    required this.dryRun,
    required this.showHelp,
  });

  final String traceliteRoot;
  final String resqliteRoot;
  final String dartExecutable;
  final String label;
  final String preset;
  final String outDir;
  final String profile;
  final int runs;
  final String interfaces;
  final String suiteScenarios;
  final String policyMetric;
  final String policyPeers;
  final String policyScenarios;
  final int minRepetitions;
  final int maxRepetitions;
  final double targetRsePercent;
  final double withinRunNoisePercentile;
  final double thresholdFloorPercent;
  final double thresholdCeilingPercent;
  final double guardrailFloorPercent;
  final double? guardrailCeilingPercent;
  final double noiseGateFloorPercent;
  final double? noiseGateCeilingPercent;
  final double noiseGateMultiplier;
  final double maxOutlierPercent;
  final double maxRunOutlierPercent;
  final double suiteRunTimeoutSeconds;
  final TraceliteSourcePolicy traceliteSourcePolicy;
  final String? graphDataDir;
  final bool exportGraphData;
  final bool strict;
  final bool dryRun;
  final bool showHelp;

  static _Options parse(List<String> args) {
    if (args.contains('--help') || args.contains('-h')) {
      final label = _defaultLabel();
      final traceliteRoot = Platform.environment['TRACELITE_ROOT'] ?? '';
      return _Options(
        traceliteRoot: traceliteRoot,
        resqliteRoot: Directory(
          Platform.environment['RESQLITE_ROOT'] ?? '.',
        ).absolute.path,
        dartExecutable: Platform.resolvedExecutable,
        label: label,
        preset: 'production',
        outDir: p.join('build', 'tracelite-benchmarks', label),
        profile: 'production',
        runs: 5,
        interfaces: _defaultPolicyPeer,
        suiteScenarios: _defaultReleasePolicyScenarios.join(','),
        policyMetric: _defaultReleaseMetric,
        policyPeers: _defaultPolicyPeer,
        policyScenarios: _defaultReleasePolicyScenarios.join(','),
        minRepetitions: 7,
        maxRepetitions: 30,
        targetRsePercent: 10,
        withinRunNoisePercentile: 0.75,
        thresholdFloorPercent: 5,
        thresholdCeilingPercent: 50,
        guardrailFloorPercent: 3,
        guardrailCeilingPercent: null,
        noiseGateFloorPercent: 5,
        noiseGateCeilingPercent: 50,
        noiseGateMultiplier: 1.5,
        maxOutlierPercent: 10,
        maxRunOutlierPercent: 20,
        suiteRunTimeoutSeconds: 1200,
        traceliteSourcePolicy: const TraceliteSourcePolicy(
          expectedRevision: pinnedTraceliteRevision,
          allowUnpinned: false,
          allowDirty: false,
        ),
        graphDataDir: null,
        exportGraphData: true,
        strict: true,
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

    final preset = _presetDefaults(values['preset'] ?? 'production');
    final label = values['label'] ?? _defaultLabel();
    final rawTraceliteRoot =
        values['tracelite-root'] ??
        Platform.environment['TRACELITE_ROOT'] ??
        '';
    final traceliteRoot = rawTraceliteRoot.isEmpty
        ? ''
        : Directory(rawTraceliteRoot).absolute.path;
    final rawResqliteRoot =
        values['resqlite-root'] ??
        Platform.environment['RESQLITE_ROOT'] ??
        Directory.current.path;
    final resqliteRoot = Directory(rawResqliteRoot).absolute.path;
    final graphDataDir = values['graph-data-dir'] == null
        ? null
        : Directory(values['graph-data-dir']!).absolute.path;
    final minRepetitions = _positiveInt(
      values['min-repetitions'],
      preset.minRepetitions,
    );
    final maxRepetitions = _positiveInt(
      values['max-repetitions'],
      preset.maxRepetitions,
    );
    if (maxRepetitions < minRepetitions) {
      stderr.writeln(
        '--max-repetitions must be greater than or equal to '
        '--min-repetitions',
      );
      exit(64);
    }

    return _Options(
      traceliteRoot: traceliteRoot,
      resqliteRoot: resqliteRoot,
      dartExecutable: values['dart'] ?? Platform.resolvedExecutable,
      label: label,
      preset: preset.name,
      outDir:
          values['out-dir'] ?? p.join('build', 'tracelite-benchmarks', label),
      profile: values['profile'] ?? preset.profile,
      runs: _positiveInt(values['runs'], preset.runs),
      interfaces: values['interfaces'] ?? preset.interfaces,
      suiteScenarios:
          values['suite-scenarios'] ??
          values['scenarios'] ??
          preset.suiteScenarios.join(','),
      policyMetric: values['policy-metric'] ?? _defaultReleaseMetric,
      policyPeers: values['policy-peers'] ?? preset.policyPeers,
      policyScenarios:
          values['policy-scenarios'] ?? preset.policyScenarios.join(','),
      minRepetitions: minRepetitions,
      maxRepetitions: maxRepetitions,
      targetRsePercent: _positiveDouble(
        values['target-rse-percent'],
        preset.targetRsePercent,
      ),
      withinRunNoisePercentile: _positiveDouble(
        values['within-run-noise-percentile'],
        preset.withinRunNoisePercentile,
      ),
      thresholdFloorPercent: _positiveDouble(
        values['threshold-floor-percent'],
        preset.thresholdFloorPercent,
      ),
      thresholdCeilingPercent: _positiveDouble(
        values['threshold-ceiling-percent'],
        preset.thresholdCeilingPercent,
      ),
      guardrailFloorPercent: _positiveDouble(
        values['guardrail-floor-percent'],
        preset.guardrailFloorPercent,
      ),
      guardrailCeilingPercent: _positiveDoubleOrNull(
        values['guardrail-ceiling-percent'],
        fallback: preset.guardrailCeilingPercent,
      ),
      noiseGateFloorPercent: _positiveDouble(
        values['noise-gate-floor-percent'],
        preset.noiseGateFloorPercent,
      ),
      noiseGateCeilingPercent: _positiveDoubleOrNull(
        values['noise-gate-ceiling-percent'],
        fallback: preset.noiseGateCeilingPercent,
      ),
      noiseGateMultiplier: _positiveDouble(
        values['noise-gate-multiplier'],
        preset.noiseGateMultiplier,
      ),
      maxOutlierPercent: _positiveDouble(
        values['max-outlier-percent'],
        preset.maxOutlierPercent,
      ),
      maxRunOutlierPercent: _positiveDouble(
        values['max-run-outlier-percent'],
        preset.maxRunOutlierPercent,
      ),
      suiteRunTimeoutSeconds: _positiveDouble(
        values['suite-run-timeout-seconds'],
        preset.suiteRunTimeoutSeconds,
      ),
      traceliteSourcePolicy: traceliteSourcePolicyFromOptions(
        revision: values['tracelite-revision'],
        flags: flags,
      ),
      graphDataDir: graphDataDir,
      exportGraphData: !flags.contains('no-graph-data'),
      strict: flags.contains('strict')
          ? true
          : flags.contains('no-strict')
          ? false
          : preset.strict,
      dryRun: flags.contains('dry-run'),
      showHelp: false,
    );
  }
}

final class _PresetDefaults {
  const _PresetDefaults({
    required this.name,
    required this.description,
    required this.profile,
    required this.runs,
    required this.interfaces,
    required this.suiteScenarios,
    required this.policyPeers,
    required this.policyScenarios,
    required this.minRepetitions,
    required this.maxRepetitions,
    required this.targetRsePercent,
    required this.withinRunNoisePercentile,
    required this.thresholdFloorPercent,
    required this.thresholdCeilingPercent,
    required this.guardrailFloorPercent,
    required this.guardrailCeilingPercent,
    required this.noiseGateFloorPercent,
    required this.noiseGateCeilingPercent,
    required this.noiseGateMultiplier,
    required this.maxOutlierPercent,
    required this.maxRunOutlierPercent,
    required this.suiteRunTimeoutSeconds,
    required this.strict,
  });

  final String name;
  final String description;
  final String profile;
  final int runs;
  final String interfaces;
  final List<String> suiteScenarios;
  final String policyPeers;
  final List<String> policyScenarios;
  final int minRepetitions;
  final int maxRepetitions;
  final double targetRsePercent;
  final double withinRunNoisePercentile;
  final double thresholdFloorPercent;
  final double thresholdCeilingPercent;
  final double guardrailFloorPercent;
  final double? guardrailCeilingPercent;
  final double noiseGateFloorPercent;
  final double? noiseGateCeilingPercent;
  final double noiseGateMultiplier;
  final double maxOutlierPercent;
  final double maxRunOutlierPercent;
  final double suiteRunTimeoutSeconds;
  final bool strict;
}

_PresetDefaults _presetDefaults(String name) {
  return switch (name) {
    'ci' => const _PresetDefaults(
      name: 'ci',
      description: 'Fast resqlite trace-health smoke for routine CI.',
      profile: 'ci',
      runs: 1,
      interfaces: 'resqlite',
      suiteScenarios: _ciSuiteScenarios,
      policyPeers: _defaultPolicyPeer,
      policyScenarios: _ciSuiteScenarios,
      minRepetitions: 1,
      maxRepetitions: 3,
      targetRsePercent: 25,
      withinRunNoisePercentile: 0.75,
      thresholdFloorPercent: 5,
      thresholdCeilingPercent: 75,
      guardrailFloorPercent: 3,
      guardrailCeilingPercent: null,
      noiseGateFloorPercent: 5,
      noiseGateCeilingPercent: 75,
      noiseGateMultiplier: 1.5,
      maxOutlierPercent: 20,
      maxRunOutlierPercent: 40,
      suiteRunTimeoutSeconds: 180,
      strict: true,
    ),
    'experiment' => const _PresetDefaults(
      name: 'experiment',
      description: 'Focused baseline/candidate collection lane.',
      profile: 'production',
      runs: 3,
      interfaces: 'sqlite_async,resqlite',
      suiteScenarios: _experimentSuiteScenarios,
      policyPeers: _defaultPolicyPeer,
      policyScenarios: _experimentSuiteScenarios,
      minRepetitions: 5,
      maxRepetitions: 20,
      targetRsePercent: 10,
      withinRunNoisePercentile: 0.75,
      thresholdFloorPercent: 5,
      thresholdCeilingPercent: 50,
      guardrailFloorPercent: 3,
      guardrailCeilingPercent: null,
      noiseGateFloorPercent: 5,
      noiseGateCeilingPercent: 50,
      noiseGateMultiplier: 1.5,
      maxOutlierPercent: 10,
      maxRunOutlierPercent: 20,
      suiteRunTimeoutSeconds: 600,
      strict: true,
    ),
    'production' => const _PresetDefaults(
      name: 'production',
      description: 'Repeated pre-publish policy calibration gate.',
      profile: 'production',
      runs: 5,
      interfaces: _defaultPolicyPeer,
      suiteScenarios: _defaultReleasePolicyScenarios,
      policyPeers: _defaultPolicyPeer,
      policyScenarios: _defaultReleasePolicyScenarios,
      minRepetitions: 7,
      maxRepetitions: 30,
      targetRsePercent: 10,
      withinRunNoisePercentile: 0.75,
      thresholdFloorPercent: 5,
      thresholdCeilingPercent: 50,
      guardrailFloorPercent: 3,
      guardrailCeilingPercent: null,
      noiseGateFloorPercent: 5,
      noiseGateCeilingPercent: 50,
      noiseGateMultiplier: 1.5,
      maxOutlierPercent: 10,
      maxRunOutlierPercent: 20,
      suiteRunTimeoutSeconds: 1200,
      strict: true,
    ),
    _ => _invalidPreset(name),
  };
}

Never _invalidPreset(String name) {
  stderr.writeln(
    'unknown --preset=$name; expected ci, experiment, or production',
  );
  exit(64);
}

final class _Paths {
  _Paths(String outDir, {String? graphDataDir})
    : manifest = p.join(outDir, 'resqlite-tracelite-benchmark.json'),
      history = p.join(outDir, 'history.json'),
      policyJson = p.join(outDir, 'policy-calibration.json'),
      policyMarkdown = p.join(outDir, 'policy-calibration.md'),
      insightsJson = p.join(outDir, 'insights.json'),
      insightsMarkdown = p.join(outDir, 'insights.md'),
      graphDataInputsDir = p.join(outDir, 'graph-data-inputs'),
      graphDataDir = graphDataDir ?? p.join(outDir, 'graph-data');

  final String manifest;
  final String history;
  final String policyJson;
  final String policyMarkdown;
  final String insightsJson;
  final String insightsMarkdown;
  final String graphDataInputsDir;
  final String graphDataDir;
}

final class _Step {
  const _Step({
    required this.name,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    this.timeout = _defaultStepTimeout,
  });

  final String name;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Duration timeout;

  String get displayCommand =>
      [executable, for (final arg in arguments) _quoteIfNeeded(arg)].join(' ');
}

final class _TraceliteResqliteDependencyBinding {
  const _TraceliteResqliteDependencyBinding({
    required this.overridePath,
    required this.overrideExisted,
    required this.overrideCreated,
    required this.expectedRoot,
    this.packageConfigPath,
    this.resolvedRoot,
    this.matchesRequestedRoot = false,
    this.error,
  });

  final String overridePath;
  final bool overrideExisted;
  final bool overrideCreated;
  final String expectedRoot;
  final String? packageConfigPath;
  final String? resolvedRoot;
  final bool matchesRequestedRoot;
  final String? error;

  Map<String, Object?> toJson() => {
    'override_path': overridePath,
    'override_existed': overrideExisted,
    'override_created': overrideCreated,
    'expected_resqlite_root': expectedRoot,
    'package_config_path': packageConfigPath,
    'resolved_resqlite_root': resolvedRoot,
    'matches_requested_root': matchesRequestedRoot,
    if (error != null) 'error': error,
  };
}

List<_Step> _plannedSteps(
  _Options options,
  _Paths paths, {
  bool forDryRun = false,
}) {
  final steps = <_Step>[
    _resolveDependenciesStep(options),
    _buildSqliteShimStep(options),
    _suiteHistoryStep(options, paths),
  ];

  if (options.exportGraphData) {
    steps.add(
      forDryRun
          ? _graphDataExportPlanStep(options, paths)
          : _graphDataExportStep(options, paths) ??
                _graphDataExportPlanStep(options, paths),
    );
    steps.add(_validateGraphDataStep(options, paths));
  }
  steps.add(_explainArtifactsStep(options, paths));

  return steps;
}

_Step _resolveDependenciesStep(_Options options) {
  return _Step(
    name: _resolveDependenciesStepName,
    executable: options.dartExecutable,
    arguments: const ['pub', 'get'],
    workingDirectory: options.traceliteRoot,
  );
}

_Step _buildSqliteShimStep(_Options options) {
  final dartArchitecture = _dartExecutableMachOArchitecture(
    options.dartExecutable,
  );
  return _Step(
    name: _prepareSqliteShimStepName,
    executable: 'cc',
    arguments: [
      if (dartArchitecture != null) ...['-arch', dartArchitecture],
      '-dynamiclib',
      '-O2',
      '-Inative',
      'native/tracelite_runtime.c',
      'native/shim_sqlite3.c',
      '-Wl,-reexport-lsqlite3',
      '-o',
      'build/libsqlite_traced.dylib',
    ],
    workingDirectory: options.traceliteRoot,
    timeout: _sqliteShimBuildTimeout,
  );
}

_Step _suiteHistoryStep(_Options options, _Paths paths) {
  return _Step(
    name: _suiteHistoryStepName,
    executable: options.dartExecutable,
    arguments: [
      'bin/tracelite.dart',
      'suite-history',
      '--profile=${options.profile}',
      '--runs=${options.runs}',
      '--interfaces=${options.interfaces}',
      '--scenarios=${options.suiteScenarios}',
      '--metrics=${options.policyMetric}',
      '--policy-peers=${options.policyPeers}',
      '--policy-scenarios=${options.policyScenarios}',
      '--min-repetitions=${options.minRepetitions}',
      '--max-repetitions=${options.maxRepetitions}',
      '--target-rse-percent=${_trimDouble(options.targetRsePercent)}',
      '--within-run-noise-percentile='
          '${_trimDouble(options.withinRunNoisePercentile)}',
      '--threshold-floor-percent=${_trimDouble(options.thresholdFloorPercent)}',
      '--threshold-ceiling-percent='
          '${_trimDouble(options.thresholdCeilingPercent)}',
      '--guardrail-floor-percent=${_trimDouble(options.guardrailFloorPercent)}',
      if (options.guardrailCeilingPercent != null)
        '--guardrail-ceiling-percent='
            '${_trimDouble(options.guardrailCeilingPercent!)}',
      '--noise-gate-floor-percent='
          '${_trimDouble(options.noiseGateFloorPercent)}',
      if (options.noiseGateCeilingPercent != null)
        '--noise-gate-ceiling-percent='
            '${_trimDouble(options.noiseGateCeilingPercent!)}',
      '--noise-gate-multiplier=${_trimDouble(options.noiseGateMultiplier)}',
      '--max-outlier-percent=${_trimDouble(options.maxOutlierPercent)}',
      '--max-run-outlier-percent=${_trimDouble(options.maxRunOutlierPercent)}',
      '--suite-run-timeout-seconds='
          '${_trimDouble(options.suiteRunTimeoutSeconds)}',
      '--strict=${options.strict}',
      '--out-dir=${p.dirname(paths.history)}',
    ],
    workingDirectory: options.traceliteRoot,
    timeout: Duration(
      seconds: (options.suiteRunTimeoutSeconds * options.runs + 600).ceil(),
    ),
  );
}

_Step _graphDataExportPlanStep(_Options options, _Paths paths) {
  return _Step(
    name: _exportGraphDataStepName,
    executable: options.dartExecutable,
    arguments: [
      'bin/tracelite.dart',
      'export-graph-data',
      '--suite-history=${p.absolute(paths.history)}',
      '--run-id=${options.label}',
      '--out=${p.absolute(paths.graphDataDir)}',
    ],
    workingDirectory: options.traceliteRoot,
  );
}

_Step? _graphDataExportStep(_Options options, _Paths paths) {
  final inputs = _graphDataInputArgs(paths);
  if (inputs.isEmpty) return null;
  return _Step(
    name: _exportGraphDataStepName,
    executable: options.dartExecutable,
    arguments: [
      'bin/tracelite.dart',
      'export-graph-data',
      ...inputs,
      '--run-id=${options.label}',
      '--out=${p.absolute(paths.graphDataDir)}',
    ],
    workingDirectory: options.traceliteRoot,
  );
}

_Step _validateGraphDataStep(_Options options, _Paths paths) {
  return _Step(
    name: _validateGraphDataStepName,
    executable: options.dartExecutable,
    arguments: [
      'bin/tracelite.dart',
      'validate-graph-data',
      p.absolute(paths.graphDataDir),
    ],
    workingDirectory: options.traceliteRoot,
  );
}

_Step _explainArtifactsStep(_Options options, _Paths paths) {
  return _Step(
    name: _explainArtifactsStepName,
    executable: options.dartExecutable,
    arguments: [
      'bin/tracelite.dart',
      'explain',
      p.absolute(paths.history),
      '--out-json=${p.absolute(paths.insightsJson)}',
    ],
    workingDirectory: options.traceliteRoot,
  );
}

final class _StepResult {
  const _StepResult({
    required this.name,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    this.timedOut = false,
    this.timeoutSeconds = 0,
    this.elapsedNs = 0,
  });

  final String name;
  final String command;
  final String workingDirectory;
  final int exitCode;
  final bool timedOut;
  final double timeoutSeconds;
  final int elapsedNs;

  String get status => timedOut
      ? 'timed_out'
      : exitCode == 0
      ? 'ok'
      : 'failed';

  Map<String, Object?> toJson() => {
    'name': name,
    'command': command,
    'working_directory': workingDirectory,
    'exit_code': exitCode,
    'status': status,
    'timed_out': timedOut,
    'timeout_seconds': timeoutSeconds,
    'elapsed_ns': elapsedNs,
  };
}

final class _TimedProcessResult {
  const _TimedProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.elapsed,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final Duration elapsed;
}

Future<_TimedProcessResult> _runProcessWithTimeout(_Step step) async {
  final stopwatch = Stopwatch()..start();
  late final Process process;
  try {
    process = await Process.start(
      step.executable,
      step.arguments,
      workingDirectory: step.workingDirectory,
      environment: Platform.environment,
    ).timeout(_processStartTimeout);
  } on TimeoutException {
    stopwatch.stop();
    return _TimedProcessResult(
      exitCode: 124,
      stdout: '',
      stderr:
          'resqlite tracelite wrapper: child process did not start within '
          '${_formatDuration(_processStartTimeout)}.\n',
      timedOut: true,
      elapsed: stopwatch.elapsed,
    );
  } on ProcessException catch (error) {
    stopwatch.stop();
    return _TimedProcessResult(
      exitCode: 127,
      stdout: '',
      stderr: 'resqlite tracelite wrapper: failed to start child: $error\n',
      timedOut: false,
      elapsed: stopwatch.elapsed,
    );
  }
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final stdoutSubscription = process.stdout
      .transform(utf8.decoder)
      .listen(
        stdoutBuffer.write,
        onDone: () => _completeIfPending(stdoutDone),
        onError: (_) => _completeIfPending(stdoutDone),
      );
  final stderrSubscription = process.stderr
      .transform(utf8.decoder)
      .listen(
        stderrBuffer.write,
        onDone: () => _completeIfPending(stderrDone),
        onError: (_) => _completeIfPending(stderrDone),
      );

  var timedOut = false;
  late int exitCode;
  try {
    exitCode = await process.exitCode.timeout(step.timeout);
  } on TimeoutException {
    timedOut = true;
    process.kill(ProcessSignal.sigterm);
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
  } finally {
    stopwatch.stop();
  }

  try {
    await Future.wait([
      stdoutDone.future,
      stderrDone.future,
    ]).timeout(const Duration(seconds: 2));
  } on Object {
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
    stderrBuffer.writeln(
      'resqlite tracelite wrapper: child stdio did not close after exit.',
    );
  }

  return _TimedProcessResult(
    exitCode: exitCode,
    stdout: stdoutBuffer.toString(),
    stderr: stderrBuffer.toString(),
    timedOut: timedOut,
    elapsed: stopwatch.elapsed,
  );
}

void _completeIfPending(Completer<void> completer) {
  if (!completer.isCompleted) completer.complete();
}

double _durationSeconds(Duration duration) {
  return duration.inMicroseconds / Duration.microsecondsPerSecond;
}

String _formatDuration(Duration duration) {
  if (duration.inMicroseconds % Duration.microsecondsPerSecond != 0) {
    return '${_trimDouble(_durationSeconds(duration))}s';
  }
  if (duration.inSeconds % 60 != 0) return '${duration.inSeconds}s';
  if (duration.inMinutes % 60 != 0) return '${duration.inMinutes}m';
  return '${duration.inHours}h';
}

Future<_StepResult> _runStep(_Step step) async {
  print('== ${step.name}');
  print(step.displayCommand);

  final result = await _runProcessWithTimeout(step);

  final stdoutText = _cleanDartToolOutput(result.stdout);
  final stderrText = _cleanDartToolOutput(result.stderr);
  if (stdoutText.trim().isNotEmpty) stdout.write(stdoutText);
  if (stderrText.trim().isNotEmpty) stderr.write(stderrText);
  if (result.timedOut) {
    stderr.writeln(
      'step timed out: ${step.name} (${_formatDuration(step.timeout)})',
    );
  } else if (result.exitCode != 0) {
    stderr.writeln('step failed: ${step.name} (exit ${result.exitCode})');
  }
  print('');
  return _StepResult(
    name: step.name,
    command: step.displayCommand,
    workingDirectory: step.workingDirectory,
    exitCode: result.exitCode,
    timedOut: result.timedOut,
    timeoutSeconds: _durationSeconds(step.timeout),
    elapsedNs: result.elapsed.inMicroseconds * 1000,
  );
}

Future<_StepResult> _runMarkdownStep(_Step step, String stdoutPath) async {
  print('== ${step.name}');
  print(step.displayCommand);

  final result = await _runProcessWithTimeout(step);

  final stdoutText = _cleanDartToolOutput(result.stdout);
  final stderrText = _cleanDartToolOutput(result.stderr);
  File(stdoutPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(stdoutText);
  if (stdoutText.trim().isNotEmpty) stdout.write(stdoutText);
  if (stderrText.trim().isNotEmpty) stderr.write(stderrText);
  if (result.timedOut) {
    stderr.writeln(
      'step timed out: ${step.name} (${_formatDuration(step.timeout)})',
    );
  } else if (result.exitCode != 0) {
    stderr.writeln('step failed: ${step.name} (exit ${result.exitCode})');
  }
  print('');
  return _StepResult(
    name: step.name,
    command: step.displayCommand,
    workingDirectory: step.workingDirectory,
    exitCode: result.exitCode,
    timedOut: result.timedOut,
    timeoutSeconds: _durationSeconds(step.timeout),
    elapsedNs: result.elapsed.inMicroseconds * 1000,
  );
}

Future<_StepResult> _buildTraceliteSqliteShim(_Options options) async {
  if (Platform.operatingSystem != 'macos') {
    print('== $_prepareSqliteShimStepName');
    stderr.writeln(
      'tracelite SQLite shim auto-build is currently configured for macOS; '
      'this wrapper expects build/libsqlite_traced.dylib.',
    );
    print('');
    return _StepResult(
      name: _prepareSqliteShimStepName,
      command: 'build ${_traceliteSqliteShimPath(options)}',
      workingDirectory: options.traceliteRoot,
      exitCode: 64,
    );
  }

  Directory(p.join(options.traceliteRoot, 'build')).createSync(recursive: true);
  final shimPath = _traceliteSqliteShimPath(options);
  if (_sqliteShimIsFresh(options)) {
    print('== $_prepareSqliteShimStepName');
    print('reuse $shimPath');
    print('');
    return _StepResult(
      name: _prepareSqliteShimStepName,
      command: 'reuse $shimPath',
      workingDirectory: options.traceliteRoot,
      exitCode: 0,
    );
  }
  return _runStep(_buildSqliteShimStep(options));
}

bool _sqliteShimIsFresh(_Options options) {
  final output = File(_traceliteSqliteShimPath(options));
  if (!output.existsSync()) return false;
  if (!_sqliteShimMatchesDartArchitecture(output, options.dartExecutable)) {
    return false;
  }

  final outputModified = output.statSync().modified;
  for (final sourcePath in _sqliteShimSources) {
    final source = File(p.join(options.traceliteRoot, sourcePath));
    if (!source.existsSync()) return false;
    if (source.statSync().modified.isAfter(outputModified)) return false;
  }
  return true;
}

bool _sqliteShimMatchesDartArchitecture(File shim, String dartExecutable) {
  final shimArchitectures = _machOArchitectures(shim);
  if (shimArchitectures == null) return true;
  final dartArchitecture = _dartExecutableMachOArchitecture(dartExecutable);
  if (dartArchitecture == null) return true;
  return shimArchitectures.contains(dartArchitecture);
}

List<String>? _machOArchitectures(File file) {
  ProcessResult result;
  try {
    result = Process.runSync('file', [file.path]);
  } on Object {
    return null;
  }
  if (result.exitCode != 0) return null;
  final output = result.stdout.toString();
  if (!output.contains('Mach-O')) return null;
  final architectures = <String>[
    if (output.contains('x86_64')) 'x86_64',
    if (output.contains('arm64')) 'arm64',
  ];
  return architectures;
}

String? _dartExecutableMachOArchitecture(String dartExecutable) {
  ProcessResult result;
  try {
    result = Process.runSync(dartExecutable, ['--version']);
  } on Object {
    return null;
  }
  final output = '${result.stdout}\n${result.stderr}';
  if (output.contains('macos_x64')) return 'x86_64';
  if (output.contains('macos_arm64')) return 'arm64';
  return null;
}

_StepResult _validateSuiteHistory(_Paths paths) {
  const name = _validateSuiteHistoryStepName;
  final historyFile = File(paths.history);
  final command = 'read ${historyFile.path}';
  if (!historyFile.existsSync()) {
    stderr.writeln('missing tracelite suite history: ${historyFile.path}');
    return _StepResult(
      name: name,
      command: command,
      workingDirectory: Directory.current.path,
      exitCode: 65,
    );
  }

  try {
    final decoded =
        jsonDecode(historyFile.readAsStringSync()) as Map<String, Object?>;
    final runs = decoded['runs'];
    if (runs is! List<Object?> || runs.isEmpty) {
      stderr.writeln(
        'tracelite suite history has no runs: ${historyFile.path}',
      );
      return _StepResult(
        name: name,
        command: command,
        workingDirectory: Directory.current.path,
        exitCode: 65,
      );
    }
    final failedRuns = [
      for (final run in runs)
        if (run is Map<String, Object?> && run['status'] != 'ok') run,
    ];
    if (failedRuns.isNotEmpty) {
      stderr.writeln('tracelite suite history contains failed runs:');
      for (final run in failedRuns) {
        stderr.writeln(
          '  ${run['name'] ?? run['run'] ?? '?'}: '
          '${run['status'] ?? '?'} (${run['manifest'] ?? 'no manifest'})',
        );
      }
      return _StepResult(
        name: name,
        command: command,
        workingDirectory: Directory.current.path,
        exitCode: 65,
      );
    }
  } on Object catch (error) {
    stderr.writeln('failed to read tracelite suite history: $error');
    return _StepResult(
      name: name,
      command: command,
      workingDirectory: Directory.current.path,
      exitCode: 65,
    );
  }

  return _StepResult(
    name: name,
    command: command,
    workingDirectory: Directory.current.path,
    exitCode: 0,
  );
}

List<String> _graphDataInputArgs(_Paths paths) {
  final historyPath = paths.history;
  final historyFile = File(historyPath);
  if (!historyFile.existsSync()) return const [];
  try {
    final decoded =
        jsonDecode(historyFile.readAsStringSync()) as Map<String, Object?>;
    final runs = decoded['runs'];
    if (runs is! List<Object?>) return const [];
    final manifests = <String>[];
    final successfulManifests = <String>[];
    for (final run in runs) {
      if (run is! Map<String, Object?>) continue;
      final manifest = run['manifest'];
      if (manifest is! String || manifest.isEmpty) continue;
      final manifestPath = _resolveManifestArtifactPath(historyPath, manifest);
      if (!File(manifestPath).existsSync()) continue;
      manifests.add(manifestPath);
      if (run['status'] == 'ok') successfulManifests.add(manifestPath);
    }
    if (successfulManifests.isNotEmpty) {
      return ['--suite-history=${p.absolute(historyPath)}'];
    }
    final filteredManifests = [
      for (final manifest in manifests)
        if (_writeGraphableSuiteManifest(paths, manifest) case final path?)
          path,
    ];
    return [
      for (final manifest in filteredManifests)
        '--suite=${p.absolute(manifest)}',
    ];
  } on Object {
    return const [];
  }
}

String _resolveManifestArtifactPath(String manifestPath, String artifactPath) {
  final artifact = File(artifactPath);
  if (artifact.isAbsolute || artifact.existsSync()) return artifact.path;
  return File(manifestPath).parent.uri.resolve(artifactPath).toFilePath();
}

String? _writeGraphableSuiteManifest(_Paths paths, String manifestPath) {
  try {
    final file = File(manifestPath);
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (decoded['schema'] != 'tracelite.suite.v1') return null;
    final runs = decoded['runs'];
    if (runs is! List<Object?>) return null;

    final graphableRuns = <Map<String, Object?>>[];
    for (final run in runs) {
      if (run is! Map<String, Object?> || run['status'] != 'ok') continue;
      final artifact = run['artifact'];
      if (artifact is! String || artifact.isEmpty) continue;
      final artifactPath = _resolveManifestArtifactPath(manifestPath, artifact);
      if (!File(artifactPath).existsSync()) continue;
      graphableRuns.add({...run, 'artifact': p.absolute(artifactPath)});
    }
    if (graphableRuns.isEmpty) return null;

    final outDir = Directory(paths.graphDataInputsDir)
      ..createSync(recursive: true);
    final runName = p.basename(p.dirname(manifestPath));
    final outFile = File(p.join(outDir.path, '$runName-manifest.json'));
    outFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({...decoded, 'runs': graphableRuns})}\n',
    );
    return outFile.path;
  } on Object {
    return null;
  }
}

String _traceliteSqliteShimPath(_Options options) {
  return p.join(options.traceliteRoot, 'build', 'libsqlite_traced.dylib');
}

Future<void> _writeManifest(
  _Options options,
  _Paths paths,
  List<_StepResult> stepResults, {
  required Map<String, Object?> traceliteSource,
  required Map<String, Object?> resqliteSource,
  required _TraceliteResqliteDependencyBinding dependencyBinding,
}) async {
  final failedSteps = stepResults
      .where((result) => result.exitCode != 0)
      .toList();
  final manifest = {
    'schema': 'resqlite.tracelite_benchmark_run.v1',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'status': failedSteps.isEmpty ? 'ok' : 'failed',
    'label': options.label,
    'preset': options.preset,
    'tracelite_root': options.traceliteRoot,
    'tracelite_source': traceliteSource,
    'resqlite_root': options.resqliteRoot,
    'resqlite_source': resqliteSource,
    'tracelite_resqlite_dependency': dependencyBinding.toJson(),
    'profile': options.profile,
    'runs': options.runs,
    'suite_run_timeout_seconds': options.suiteRunTimeoutSeconds,
    'suite_scenarios': options.suiteScenarios
        .split(',')
        .map((value) => value.trim())
        .toList(),
    'diagnostic_scenarios': _defaultDiagnosticScenarios,
    'interfaces': options.interfaces
        .split(',')
        .map((value) => value.trim())
        .toList(),
    'policy': {
      'metric': options.policyMetric,
      'peers': options.policyPeers
          .split(',')
          .map((value) => value.trim())
          .toList(),
      'scenarios': options.policyScenarios
          .split(',')
          .map((value) => value.trim())
          .toList(),
      'min_repetitions': options.minRepetitions,
      'max_repetitions': options.maxRepetitions,
      'target_rse_percent': options.targetRsePercent,
      'within_run_noise_percentile': options.withinRunNoisePercentile,
      'threshold_floor_percent': options.thresholdFloorPercent,
      'threshold_ceiling_percent': options.thresholdCeilingPercent,
      'guardrail_floor_percent': options.guardrailFloorPercent,
      'guardrail_ceiling_percent': options.guardrailCeilingPercent,
      'noise_gate_floor_percent': options.noiseGateFloorPercent,
      'noise_gate_ceiling_percent': options.noiseGateCeilingPercent,
      'noise_gate_multiplier': options.noiseGateMultiplier,
      'max_outlier_percent': options.maxOutlierPercent,
      'max_run_outlier_percent': options.maxRunOutlierPercent,
    },
    'artifacts': {
      'suite_history': paths.history,
      'policy_json': paths.policyJson,
      'policy_markdown': paths.policyMarkdown,
      'insights_json': paths.insightsJson,
      'insights_markdown': paths.insightsMarkdown,
      'graph_data_dir': options.exportGraphData ? paths.graphDataDir : null,
      'graph_data_inputs_dir':
          options.exportGraphData &&
              Directory(paths.graphDataInputsDir).existsSync()
          ? paths.graphDataInputsDir
          : null,
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
  print('# resqlite tracelite benchmark plan');
  print('');
  print('label: ${options.label}');
  print('preset: ${options.preset}');
  print('preset_description: ${_presetDefaults(options.preset).description}');
  print('out_dir: ${Directory(options.outDir).path}');
  print('tracelite_root: ${options.traceliteRoot}');
  print('resqlite_root: ${options.resqliteRoot}');
  print(
    'tracelite_resqlite_override: '
    '${p.join(options.traceliteRoot, 'pubspec_overrides.yaml')}',
  );
  print(
    'tracelite_revision_pin: ${options.traceliteSourcePolicy.expectedRevision}',
  );
  print(
    'allow_unpinned_tracelite: ${options.traceliteSourcePolicy.allowUnpinned}',
  );
  print('profile: ${options.profile}');
  print('runs: ${options.runs}');
  print(
    'suite_run_timeout_seconds: '
    '${_trimDouble(options.suiteRunTimeoutSeconds)}',
  );
  print('interfaces: ${options.interfaces}');
  print('suite_scenarios: ${options.suiteScenarios}');
  print('policy_scenarios: ${options.policyScenarios}');
  print('');
  print('artifacts:');
  print('  manifest: ${paths.manifest}');
  print('  suite history: ${paths.history}');
  print('  policy JSON: ${paths.policyJson}');
  print('  policy markdown: ${paths.policyMarkdown}');
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
    print('  timeout ${_formatDuration(step.timeout)}');
    print('  ${step.displayCommand}');
  }
}

_TraceliteResqliteDependencyBinding _prepareTraceliteResqliteOverride(
  _Options options,
) {
  final override = File(
    p.join(options.traceliteRoot, 'pubspec_overrides.yaml'),
  );
  final existed = override.existsSync();
  if (!existed) {
    override.writeAsStringSync(
      'dependency_overrides:\n'
      '  resqlite:\n'
      '    path: ${jsonEncode(options.resqliteRoot)}\n',
    );
  }

  return _TraceliteResqliteDependencyBinding(
    overridePath: override.path,
    overrideExisted: existed,
    overrideCreated: !existed,
    expectedRoot: _canonicalDirectory(options.resqliteRoot),
  );
}

_TraceliteResqliteDependencyBinding _verifyTraceliteResqliteDependency(
  _Options options,
  _TraceliteResqliteDependencyBinding current,
) {
  final packageConfigPath = p.join(
    options.traceliteRoot,
    '.dart_tool',
    'package_config.json',
  );
  final packageConfig = File(packageConfigPath);
  String? resolvedRoot;
  String? error;
  try {
    resolvedRoot = _resolvedPackageRoot(packageConfig, 'resqlite');
  } on Object catch (e) {
    error = e.toString();
  }

  final expectedRoot = _canonicalDirectory(options.resqliteRoot);
  final resolvedCanonical = resolvedRoot == null
      ? null
      : _canonicalDirectory(resolvedRoot);
  return _TraceliteResqliteDependencyBinding(
    overridePath: current.overridePath,
    overrideExisted: current.overrideExisted,
    overrideCreated: current.overrideCreated,
    expectedRoot: expectedRoot,
    packageConfigPath: packageConfigPath,
    resolvedRoot: resolvedCanonical,
    matchesRequestedRoot: resolvedCanonical == expectedRoot,
    error: error,
  );
}

String? _resolvedPackageRoot(File packageConfig, String packageName) {
  if (!packageConfig.existsSync()) {
    return null;
  }
  final decoded =
      jsonDecode(packageConfig.readAsStringSync()) as Map<String, Object?>;
  final packages = decoded['packages'];
  if (packages is! List<Object?>) {
    throw const FormatException('package_config.json has no packages list');
  }

  for (final package in packages) {
    if (package is! Map) continue;
    if (package['name'] != packageName) continue;
    final rootUriText = package['rootUri'];
    if (rootUriText is! String || rootUriText.isEmpty) {
      throw FormatException('$packageName has no rootUri in package_config');
    }
    var rootUri = Uri.parse(rootUriText);
    if (!rootUri.isAbsolute) {
      rootUri = packageConfig.parent.uri.resolveUri(rootUri);
    }
    if (rootUri.scheme != 'file') {
      throw FormatException(
        '$packageName resolved to non-file URI $rootUriText',
      );
    }
    return Directory.fromUri(rootUri).path;
  }
  return null;
}

void _printDependencyBinding(_TraceliteResqliteDependencyBinding binding) {
  print('tracelite_resqlite_override: ${binding.overridePath}');
  print('tracelite_resqlite_override_created: ${binding.overrideCreated}');
  print('tracelite_resqlite_expected_root: ${binding.expectedRoot}');
  if (binding.packageConfigPath != null) {
    print('tracelite_package_config: ${binding.packageConfigPath}');
  }
  if (binding.resolvedRoot != null) {
    print('tracelite_resqlite_resolved_root: ${binding.resolvedRoot}');
  }
  print(
    'tracelite_resqlite_matches_requested_root: '
    '${binding.packageConfigPath == null ? 'pending' : binding.matchesRequestedRoot}',
  );
}

void _printDependencyBindingFailure(
  _TraceliteResqliteDependencyBinding binding,
) {
  stderr.writeln(
    'tracelite does not resolve resqlite to the checkout under test.',
  );
  stderr.writeln('expected: ${binding.expectedRoot}');
  stderr.writeln('actual:   ${binding.resolvedRoot ?? 'not resolved'}');
  if (binding.error != null) {
    stderr.writeln('error:    ${binding.error}');
  }
  stderr.writeln('Update ${binding.overridePath} so it contains:');
  stderr.writeln('dependency_overrides:');
  stderr.writeln('  resqlite:');
  stderr.writeln('    path: ${jsonEncode(binding.expectedRoot)}');
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

void _validateResqliteRoot(String resqliteRoot) {
  if (resqliteRoot.isEmpty || !Directory(resqliteRoot).existsSync()) {
    stderr.writeln(
      'missing resqlite checkout. Pass --resqlite-root=/path/to/resqlite '
      'or set RESQLITE_ROOT.',
    );
    exit(64);
  }
  final pubspec = File(p.join(resqliteRoot, 'pubspec.yaml'));
  final library = File(p.join(resqliteRoot, 'lib', 'resqlite.dart'));
  if (!pubspec.existsSync() || !library.existsSync()) {
    stderr.writeln('not a resqlite checkout: $resqliteRoot');
    stderr.writeln('expected ${pubspec.path} and ${library.path}');
    exit(64);
  }
  final pubspecText = pubspec.readAsStringSync();
  if (!pubspecText.contains(
    RegExp(r'^name:\s*resqlite\s*$', multiLine: true),
  )) {
    stderr.writeln('not a resqlite package: $resqliteRoot');
    stderr.writeln('expected pubspec.yaml to declare "name: resqlite"');
    exit(64);
  }
}

String _canonicalDirectory(String path) {
  final directory = Directory(path);
  try {
    return directory.resolveSymbolicLinksSync();
  } on Object {
    return p.normalize(directory.absolute.path);
  }
}

String _defaultLabel() {
  return DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[:.]'),
    '-',
  );
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

double _positiveDouble(String? value, double fallback) {
  if (value == null) return fallback;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed <= 0) {
    stderr.writeln('expected positive number, got: $value');
    exit(64);
  }
  return parsed;
}

double? _positiveDoubleOrNull(String? value, {double? fallback}) {
  if (value == null) return fallback;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed <= 0) {
    stderr.writeln('expected positive number, got: $value');
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

String _trimDouble(double value) {
  final fixed = value.toStringAsFixed(3);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _trimNullableDouble(double? value) {
  return value == null ? 'none' : _trimDouble(value);
}

Never _usage({int exitCode = 64}) {
  stderr.writeln('usage:');
  stderr.writeln('  dart run benchmark/run_tracelite.dart');
  stderr.writeln('    --tracelite-root=/path/to/tracelite [--label=run-id]');
  stderr.writeln('    [--resqlite-root=/path/to/resqlite]');
  stderr.writeln('    [--preset=ci|experiment|production]');
  stderr.writeln('    [--out-dir=build/tracelite-benchmarks/run-id]');
  stderr.writeln(
    '    [--runs=5] [--interfaces=sqlite3,drift,sqlite_async,resqlite]',
  );
  stderr.writeln('    [--suite-scenarios=chat-sim,...]');
  stderr.writeln(
    '    [--scenarios=chat-sim,...]  # alias for --suite-scenarios',
  );
  stderr.writeln('    [--policy-peers=resqlite]');
  stderr.writeln('    [--policy-scenarios=chat-sim,...]');
  stderr.writeln('    [--policy-metric=measured_elapsed_ns]');
  stderr.writeln('    [--min-repetitions=7] [--max-repetitions=30]');
  stderr.writeln('    [--target-rse-percent=10]');
  stderr.writeln('    [--within-run-noise-percentile=0.75]');
  stderr.writeln('    [--threshold-floor-percent=5]');
  stderr.writeln('    [--threshold-ceiling-percent=50]');
  stderr.writeln('    [--guardrail-floor-percent=3]');
  stderr.writeln('    [--guardrail-ceiling-percent=N]');
  stderr.writeln('    [--noise-gate-floor-percent=5]');
  stderr.writeln('    [--noise-gate-ceiling-percent=50]');
  stderr.writeln('    [--noise-gate-multiplier=1.5]');
  stderr.writeln('    [--max-outlier-percent=10]');
  stderr.writeln('    [--max-run-outlier-percent=20]');
  stderr.writeln('    [--suite-run-timeout-seconds=1200]');
  stderr.writeln('    [--tracelite-revision=$pinnedTraceliteRevision]');
  stderr.writeln(
    '    [--graph-data-dir=docs/benchmarks/data/tracelite/latest]',
  );
  stderr.writeln('    [--allow-unpinned-tracelite] [--allow-dirty-tracelite]');
  stderr.writeln('    [--no-graph-data] [--strict|--no-strict] [--dry-run]');
  stderr.writeln('');
  stderr.writeln('Presets:');
  stderr.writeln('  ci: resqlite-only trace-health smoke, profile=ci, runs=1.');
  stderr.writeln(
    '  experiment: focused sqlite_async/resqlite collection, runs=3.',
  );
  stderr.writeln(
    '  production: policy-scenario pre-publish calibration, runs=5.',
  );
  stderr.writeln('');
  stderr.writeln('TRACELITE_ROOT can be used instead of --tracelite-root.');
  stderr.writeln('RESQLITE_ROOT can be used instead of --resqlite-root.');
  exit(exitCode);
}
