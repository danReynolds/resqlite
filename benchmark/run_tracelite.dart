// ignore_for_file: avoid_print
//
// Production benchmark workflow backed by tracelite.
//
// This is the resqlite-facing entry point for cross-library benchmark runs.
// It delegates execution, policy calibration, and graph-data export to a local
// tracelite checkout while keeping the stable resqlite release-gate scope
// explicit in this repository.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const _defaultReleaseMetric = 'measured_elapsed_ns';
const _defaultPolicyPeer = 'resqlite';
const _defaultReleasePolicyScenarios = [
  'chat-sim',
  'high-cardinality-fanout',
  'many-streams-writer-throughput',
  'narrow-batch-insert',
  'sqlite-diagnostics',
];
const _defaultDiagnosticScenarios = [
  'point-select',
  'feed-paging',
  'sync-burst',
  'large-working-set',
  'keyed-pk-subscriptions',
];
const _defaultSuiteScenarios = [
  'narrow-batch-insert',
  'point-select',
  'feed-paging',
  'sync-burst',
  'chat-sim',
  'large-working-set',
  'keyed-pk-subscriptions',
  'high-cardinality-fanout',
  'many-streams-writer-throughput',
  'sqlite-diagnostics',
];

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    _usage(exitCode: 0);
  }

  final outDir = Directory(options.outDir).absolute;
  final paths = _Paths(outDir.path, graphDataDir: options.graphDataDir);
  final steps = _plannedSteps(options, paths);

  if (options.dryRun) {
    _printPlan(options, paths, steps);
    return;
  }

  _validateTraceliteRoot(options.traceliteRoot);
  outDir.createSync(recursive: true);
  final traceliteSource = await _traceliteSourceState(options.traceliteRoot);

  print('# resqlite tracelite benchmark');
  print('');
  print('label: ${options.label}');
  print('out_dir: ${outDir.path}');
  print('tracelite_root: ${options.traceliteRoot}');
  _printTraceliteSource(traceliteSource);
  print('profile: ${options.profile}');
  print('runs: ${options.runs}');
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
  for (final step in steps) {
    stepResults.add(await _runStep(step));
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
  print('  suite history: ${paths.history}');
  print('  policy JSON: ${paths.policyJson}');
  print('  policy markdown: ${paths.policyMarkdown}');
  if (options.exportGraphData) {
    print('  graph data: ${paths.graphDataDir}');
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
    required this.dartExecutable,
    required this.label,
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
    required this.graphDataDir,
    required this.exportGraphData,
    required this.strict,
    required this.dryRun,
    required this.showHelp,
  });

  final String traceliteRoot;
  final String dartExecutable;
  final String label;
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
        dartExecutable: Platform.resolvedExecutable,
        label: label,
        outDir: p.join('build', 'tracelite-benchmarks', label),
        profile: 'production',
        runs: 5,
        interfaces: 'sqlite3,drift,sqlite_async,resqlite',
        suiteScenarios: _defaultSuiteScenarios.join(','),
        policyMetric: _defaultReleaseMetric,
        policyPeers: _defaultPolicyPeer,
        policyScenarios: _defaultReleasePolicyScenarios.join(','),
        minRepetitions: 5,
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
    final minRepetitions = _positiveInt(values['min-repetitions'], 5);
    final maxRepetitions = _positiveInt(values['max-repetitions'], 30);
    if (maxRepetitions < minRepetitions) {
      stderr.writeln(
        '--max-repetitions must be greater than or equal to '
        '--min-repetitions',
      );
      exit(64);
    }

    return _Options(
      traceliteRoot: traceliteRoot,
      dartExecutable: values['dart'] ?? Platform.resolvedExecutable,
      label: label,
      outDir:
          values['out-dir'] ?? p.join('build', 'tracelite-benchmarks', label),
      profile: values['profile'] ?? 'production',
      runs: _positiveInt(values['runs'], 5),
      interfaces: values['interfaces'] ?? 'sqlite3,drift,sqlite_async,resqlite',
      suiteScenarios:
          values['suite-scenarios'] ??
          values['scenarios'] ??
          _defaultSuiteScenarios.join(','),
      policyMetric: values['policy-metric'] ?? _defaultReleaseMetric,
      policyPeers: values['policy-peers'] ?? _defaultPolicyPeer,
      policyScenarios:
          values['policy-scenarios'] ??
          _defaultReleasePolicyScenarios.join(','),
      minRepetitions: minRepetitions,
      maxRepetitions: maxRepetitions,
      targetRsePercent: _positiveDouble(values['target-rse-percent'], 10),
      withinRunNoisePercentile: _positiveDouble(
        values['within-run-noise-percentile'],
        0.75,
      ),
      thresholdFloorPercent: _positiveDouble(
        values['threshold-floor-percent'],
        5,
      ),
      thresholdCeilingPercent: _positiveDouble(
        values['threshold-ceiling-percent'],
        50,
      ),
      guardrailFloorPercent: _positiveDouble(
        values['guardrail-floor-percent'],
        3,
      ),
      guardrailCeilingPercent: _positiveDoubleOrNull(
        values['guardrail-ceiling-percent'],
      ),
      noiseGateFloorPercent: _positiveDouble(
        values['noise-gate-floor-percent'],
        5,
      ),
      noiseGateCeilingPercent: _positiveDoubleOrNull(
        values['noise-gate-ceiling-percent'],
        fallback: 50,
      ),
      noiseGateMultiplier: _positiveDouble(
        values['noise-gate-multiplier'],
        1.5,
      ),
      maxOutlierPercent: _positiveDouble(values['max-outlier-percent'], 10),
      maxRunOutlierPercent: _positiveDouble(
        values['max-run-outlier-percent'],
        20,
      ),
      graphDataDir: graphDataDir,
      exportGraphData: !flags.contains('no-graph-data'),
      strict: !flags.contains('no-strict'),
      dryRun: flags.contains('dry-run'),
      showHelp: false,
    );
  }
}

final class _Paths {
  _Paths(String outDir, {String? graphDataDir})
    : manifest = p.join(outDir, 'resqlite-tracelite-benchmark.json'),
      history = p.join(outDir, 'history.json'),
      policyJson = p.join(outDir, 'policy-calibration.json'),
      policyMarkdown = p.join(outDir, 'policy-calibration.md'),
      graphDataDir = graphDataDir ?? p.join(outDir, 'graph-data');

  final String manifest;
  final String history;
  final String policyJson;
  final String policyMarkdown;
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

List<_Step> _plannedSteps(_Options options, _Paths paths) {
  final steps = <_Step>[
    _Step(
      name: 'run tracelite suite history',
      executable: options.dartExecutable,
      arguments: [
        'run',
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
        '--threshold-floor-percent='
            '${_trimDouble(options.thresholdFloorPercent)}',
        '--threshold-ceiling-percent='
            '${_trimDouble(options.thresholdCeilingPercent)}',
        '--guardrail-floor-percent='
            '${_trimDouble(options.guardrailFloorPercent)}',
        if (options.guardrailCeilingPercent != null)
          '--guardrail-ceiling-percent='
              '${_trimDouble(options.guardrailCeilingPercent!)}',
        '--noise-gate-floor-percent='
            '${_trimDouble(options.noiseGateFloorPercent)}',
        if (options.noiseGateCeilingPercent != null)
          '--noise-gate-ceiling-percent='
              '${_trimDouble(options.noiseGateCeilingPercent!)}',
        '--noise-gate-multiplier='
            '${_trimDouble(options.noiseGateMultiplier)}',
        '--max-outlier-percent=${_trimDouble(options.maxOutlierPercent)}',
        '--max-run-outlier-percent='
            '${_trimDouble(options.maxRunOutlierPercent)}',
        '--strict=${options.strict}',
        '--out-dir=${p.dirname(paths.history)}',
      ],
      workingDirectory: options.traceliteRoot,
    ),
  ];

  if (options.exportGraphData) {
    steps.add(
      _Step(
        name: 'export tracelite graph data',
        executable: options.dartExecutable,
        arguments: [
          'run',
          'bin/tracelite.dart',
          'export-graph-data',
          '--suite-history=${p.absolute(paths.history)}',
          '--run-id=${options.label}',
          '--out=${p.absolute(paths.graphDataDir)}',
        ],
        workingDirectory: options.traceliteRoot,
      ),
    );
  }

  return steps;
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
    'schema': 'resqlite.tracelite_benchmark_run.v1',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'status': failedSteps.isEmpty ? 'ok' : 'failed',
    'label': options.label,
    'tracelite_root': options.traceliteRoot,
    'tracelite_source': traceliteSource,
    'profile': options.profile,
    'runs': options.runs,
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

Future<Map<String, Object?>> _traceliteSourceState(String traceliteRoot) async {
  Future<String?> git(List<String> args) async {
    final result = await Process.run('git', ['-C', traceliteRoot, ...args]);
    if (result.exitCode != 0) return null;
    return result.stdout.toString().trim();
  }

  final revision = await git(['rev-parse', 'HEAD']);
  final branch = await git(['rev-parse', '--abbrev-ref', 'HEAD']);
  final status = await git(['status', '--porcelain']);
  return {
    'path': traceliteRoot,
    'git_available': revision != null,
    if (revision != null) 'revision': revision,
    if (branch != null) 'branch': branch,
    if (status != null) 'dirty': status.isNotEmpty,
  };
}

void _printTraceliteSource(Map<String, Object?> source) {
  if (source['git_available'] != true) {
    print('tracelite_git: unavailable');
    return;
  }
  print('tracelite_revision: ${source['revision']}');
  print('tracelite_branch: ${source['branch']}');
  print('tracelite_dirty: ${source['dirty']}');
}

void _printPlan(_Options options, _Paths paths, List<_Step> steps) {
  print('# resqlite tracelite benchmark plan');
  print('');
  print('label: ${options.label}');
  print('out_dir: ${Directory(options.outDir).path}');
  print('tracelite_root: ${options.traceliteRoot}');
  print('suite_scenarios: ${options.suiteScenarios}');
  print('policy_scenarios: ${options.policyScenarios}');
  print('');
  print('artifacts:');
  print('  manifest: ${paths.manifest}');
  print('  suite history: ${paths.history}');
  print('  policy JSON: ${paths.policyJson}');
  print('  policy markdown: ${paths.policyMarkdown}');
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
  stderr.writeln('    [--min-repetitions=5] [--max-repetitions=30]');
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
  stderr.writeln(
    '    [--graph-data-dir=docs/benchmarks/data/tracelite/latest]',
  );
  stderr.writeln('    [--no-graph-data] [--no-strict] [--dry-run]');
  stderr.writeln('');
  stderr.writeln('TRACELITE_ROOT can be used instead of --tracelite-root.');
  exit(exitCode);
}
