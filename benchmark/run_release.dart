// ignore_for_file: avoid_print
//
// Release-mode benchmark entry point.
//
// This is the pristine peer-comparison harness. Runs resqlite against
// drift / sqlite_async / sqlite3 with NO diagnostic instrumentation —
// what ships here is exactly what downstream users run. Results feed
// the public dashboard and HARDWARE_RESULTS.md.
//
// **If you are running an experiment** on a branch and want to know
// whether your change helped or hurt, use the tracelite wrappers instead:
// `benchmark/run_tracelite.dart` for suite-level baseline/candidate artifacts
// and `benchmark/profile/run_tracelite_profile.dart` for profile-mode
// diagnostics.
//
// See benchmark/EXPERIMENTS.md for the experiment-mode workflow.
import 'dart:convert';
import 'dart:io' show Directory, File, Process, exit, stderr;

import 'shared/baseline_compatibility.dart';
import 'shared/benchmark_environment.dart';
import 'shared/parse_results.dart';
import 'shared/release_artifact.dart';
import 'shared/release_reporting.dart';
import 'shared/stats.dart' show AggregateStats;
import 'suites/chat_sim.dart';
import 'suites/concurrent_reads.dart';
import 'suites/disjoint_columns.dart';
import 'suites/feed_paging.dart';
import 'suites/high_cardinality_fanout.dart';
import 'suites/keyed_pk_subscriptions.dart';
import 'suites/large_working_set.dart';
import 'suites/many_streams_writer_throughput.dart';
import 'suites/memory.dart';
import 'suites/parameterized.dart';
import 'suites/point_query.dart';
import 'suites/scaling.dart';
import 'suites/schema_shapes.dart';
import 'suites/select_bytes.dart';
import 'suites/select_maps.dart';
import 'suites/sqlite_diagnostics.dart';
import 'suites/streaming.dart';
import 'suites/sync_burst.dart';
import 'suites/writes.dart';

Future<void> main(List<String> args) async {
  final options = _parseOptions(args);
  await _ensureDriftCodegenFresh();
  final resultsDir = Directory('benchmark/results');
  final environment = await collectBenchmarkEnvironment(
    extra: {'benchmarkMode': 'release', 'includeSlow': options.includeSlow},
  );
  final baseline = _resolveComparisonBaseline(resultsDir, options, environment);
  final compareFile = baseline.file;

  final runMarkdowns = <String>[];
  final runMetrics = <Map<String, double>>[];

  print('resqlite Comprehensive Benchmark Suite');
  print('=====================================');
  print('');
  print('Label: ${options.label}');
  print('Repeats: ${options.repeatCount}');
  if (compareFile != null) {
    print('Compare to: ${compareFile.path} (${baseline.mode})');
    if (!baseline.isCompatible) {
      print('Baseline compatibility: incompatible');
      for (final reason in baseline.reasons) {
        print('  - $reason');
      }
    }
  } else {
    print(
      options.autoCompare
          ? 'Compare to: none'
          : 'Compare to: none (automatic comparison disabled)',
    );
  }
  print('');

  for (var i = 0; i < options.repeatCount; i++) {
    if (options.repeatCount > 1) {
      print('--- Repeat ${i + 1}/${options.repeatCount} ---');
    }
    final markdown = await _runSuiteOnce(includeSlow: options.includeSlow);
    runMarkdowns.add(markdown);
    runMetrics.add(extractResqliteMedians(markdown));
  }

  final representativeMarkdown = runMarkdowns.last;
  final currentAggregates = aggregateRunMetrics(runMetrics);
  final generatedAt = DateTime.now().toIso8601String();
  final gitSha = environment['gitSha'] as String?;
  final gitShaShort = gitSha == null
      ? '?'
      : gitSha.substring(0, gitSha.length < 12 ? gitSha.length : 12);
  final gitLabel =
      '${environment['gitBranch'] ?? '?'} @ $gitShaShort'
      '${environment['gitDirty'] == true ? ' (dirty)' : ''}';

  final markdown = StringBuffer()
    ..writeln('# resqlite Benchmark Results')
    ..writeln()
    ..writeln('Generated: $generatedAt')
    ..writeln()
    ..writeln('Libraries compared:')
    ..writeln(
      '- **resqlite** — raw FFI + C JSON/binary serialization + Isolate.exit zero-copy',
    )
    ..writeln('- **sqlite3** — raw FFI, synchronous, per-cell column reads')
    ..writeln('- **sqlite_async** — PowerSync, async connection pool')
    ..writeln()
    ..writeln('Run settings:')
    ..writeln('- Label: `${options.label}`')
    ..writeln('- Repeats: `${options.repeatCount}`')
    ..writeln(
      '- Runtime: `${environment['runtime'] ?? '?'} / Dart ${environment['dartVersion'] ?? '?'}`',
    )
    ..writeln(
      '- OS: `${environment['os'] ?? '?'} ${environment['osVersion'] ?? ''}`',
    )
    ..writeln('- Git: `$gitLabel`')
    ..writeln('- Comparison baseline: `${baseline.fileName}`')
    ..writeln('- Comparison mode: `${baseline.mode}`')
    ..writeln(
      '- Comparison baseline compatibility: `${baseline.compatibilityLabel}`',
    )
    ..writeln()
    ..write(representativeMarkdown);

  if (options.repeatCount > 1) {
    markdown.writeln(renderRepeatStability(currentAggregates));
  }

  if (baseline.shouldCompare) {
    if (!baseline.isCompatible) {
      final warning = _renderBaselineCompatibilityWarning(baseline);
      markdown.writeln(warning);
      print(warning);
    }

    final prevContent = baseline.file!.readAsStringSync();
    final prevName = baseline.fileName;
    final comparison = generateReleaseComparison(
      currentAggregates,
      prevContent,
      prevName,
    );
    markdown.writeln(comparison);
    print(comparison);

    final memComparison = generateMemoryComparison(
      representativeMarkdown,
      prevContent,
    );
    if (memComparison.isNotEmpty) {
      markdown.writeln(memComparison);
      print(memComparison);
    }

    final streamColComparison = generateStreamingColumnComparison(
      representativeMarkdown,
      prevContent,
    );
    if (streamColComparison.isNotEmpty) {
      markdown.writeln(streamColComparison);
      print(streamColComparison);
    }
  } else if (compareFile != null) {
    final skipped = _renderSkippedAutomaticComparison(baseline);
    markdown.writeln(skipped);
    print(skipped);
  } else {
    markdown.writeln('## Comparison');
    markdown.writeln();
    if (options.autoCompare) {
      markdown.writeln(
        'No comparison baseline found. Use `--compare-to=...` or keep a prior run in `benchmark/results`.',
      );
    } else {
      markdown.writeln(
        'Automatic comparison is disabled. Use `--compare-to=...` for an explicit baseline comparison.',
      );
    }
    markdown.writeln();
  }

  final timestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final safeLabel = _sanitizeResultFilenameLabel(options.label);
  final resultsFile = File('${resultsDir.path}/$timestamp-$safeLabel.md');
  final jsonFile = File('${resultsDir.path}/$timestamp-$safeLabel.json');
  await resultsFile.writeAsString(markdown.toString());
  final artifact = buildReleaseRunArtifact(
    label: options.label,
    repeatCount: options.repeatCount,
    markdown: representativeMarkdown,
    aggregates: currentAggregates,
    environment: environment,
    comparisonBaselineFile: baseline.shouldCompare ? baseline.fileName : null,
    comparisonBaselineMode: baseline.shouldCompare ? baseline.mode : null,
    comparisonBaselineCompatibility: baseline.toArtifactJson(),
    generatedAt: generatedAt,
  );
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(artifact),
  );

  print('');
  print('Results saved to: ${resultsFile.path}');
  print('Structured artifact saved to: ${jsonFile.path}');

  if (options.hardwareSummary) {
    _printHardwareSummary(currentAggregates, options.label);
  }

  // Force exit — persistent writer isolate and sqlite_async connections
  // can keep the event loop alive.
  exit(0);
}

void _printHardwareSummary(Map<String, AggregateStats> metrics, String label) {
  // Use section-specific prefixes to avoid ambiguity
  // (e.g. 'resqlite select' would match both select() and selectBytes()).
  // The [main] suffix is at the end of the full key, so we need to match
  // both the section substring and the suffix independently.
  double? _median(String substring, {bool main = false}) {
    for (final key in metrics.keys) {
      if (!key.contains(substring)) continue;
      if (main && !key.endsWith('[main]')) continue;
      if (!main && key.endsWith('[main]')) continue;
      return metrics[key]!.median;
    }
    return null;
  }

  String _ms(String substring, {bool main = false}) =>
      _median(substring, main: main)?.toStringAsFixed(2) ?? '?';

  String _worker(String substring) {
    final wall = _median(substring);
    final mainVal = _median(substring, main: true);
    if (wall == null || mainVal == null) return '?';
    return (wall - mainVal).toStringAsFixed(2);
  }

  var pointDisplay = '?';
  for (final key in metrics.keys) {
    if (key.contains('resqlite qps')) {
      final qps = metrics[key]!.median.round();
      pointDisplay = '${(qps / 1000).round()}K';
      break;
    }
  }

  final date = DateTime.now().toIso8601String().split('T').first;

  print('');
  print('=== Hardware Summary ===');
  print('Copy these rows into the matching tables in');
  print('benchmark/HARDWARE_RESULTS.md and submit a PR.');
  print('');

  print('Devices:');
  print('| $label | [CPU] | [OS] | [Dart] | $date | @[github] |');
  print('');

  void _printTimingRows(String sectionName, List<String> substrings) {
    print(
      '| $label | wall '
      '| ${substrings.map((s) => _ms(s)).join(' | ')} |',
    );
    print(
      '| $label | main '
      '| ${substrings.map((s) => _ms(s, main: true)).join(' | ')} |',
    );
    print(
      '| $label | worker '
      '| ${substrings.map(_worker).join(' | ')} |',
    );
  }

  print('Select → Maps (ms):');
  _printTimingRows('Select → Maps', [
    'Maps / 10 rows',
    'Maps / 100 rows',
    'Maps / 1000 rows',
    'Maps / 10000 rows',
  ]);
  print('');

  print('Select → JSON Bytes (ms):');
  _printTimingRows('Select → JSON Bytes', [
    'Bytes / 10 rows',
    'Bytes / 100 rows',
    'Bytes / 1000 rows',
    'Bytes / 10000 rows',
  ]);
  print('');

  print('Point Query:');
  print('| $label | $pointDisplay |');
  print('');

  print('Batch Insert (ms):');
  _printTimingRows('Batch Insert', [
    'Batch Insert (100 rows)',
    'Batch Insert (1000 rows)',
    'Batch Insert (10000 rows)',
  ]);
  print('');

  print('Concurrent Reads (ms):');
  print(
    '| $label '
    '| ${_ms("concurrent 1x")} '
    '| ${_ms("concurrent 2x")} '
    '| ${_ms("concurrent 4x")} '
    '| ${_ms("concurrent 8x")} |',
  );
  print('');

  print('Transaction (ms):');
  print('| $label | ${_ms("Interactive Transaction")} |');
  print('');

  print('Stream Reactivity (ms):');
  print(
    '| $label '
    '| ${_ms("Invalidation Latency")} '
    '| ${_ms("Fan-out (10 streams)")} |',
  );
}

Future<String> _runSuiteOnce({required bool includeSlow}) async {
  final markdown = StringBuffer();

  print('[1/15] Select → Maps...');
  markdown.write(await runSelectMapsBenchmark());

  print('[2/15] Select → Bytes...');
  markdown.write(await runSelectBytesBenchmark());

  print('[3/15] Schema Shapes...');
  markdown.write(await runSchemaShapesBenchmark());

  print('[4/15] Scaling...');
  markdown.write(await runScalingBenchmark());

  print('[5/15] Concurrent Reads...');
  markdown.write(await runConcurrentReadsBenchmark());

  print('[6/15] Point Query...');
  markdown.write(await runPointQueryBenchmark());

  print('[7/15] Parameterized Queries...');
  markdown.write(await runParameterizedBenchmark());

  print('[8/15] Writes...');
  markdown.write(await runWritesBenchmark());

  print('[9/15] Streaming...');
  markdown.write(await runStreamingBenchmark());

  print('[10/15] Streaming (Column Granularity)...');
  markdown.write(await runDisjointColumnsBenchmark());

  print('[11/15] Keyed PK Subscriptions (A11)...');
  markdown.write(await runKeyedPkSubscriptionsBenchmark());

  print('[12/15] Chat Sim (A5)...');
  markdown.write(await runChatSimBenchmark());

  print('[13/15] Feed Paging (A6)...');
  markdown.write(await runFeedPagingBenchmark());

  print('[14/15] High-Cardinality Stream Fan-out (A11b)...');
  markdown.write(await runHighCardinalityFanoutBenchmark());

  print('[15/16] Memory...');
  markdown.write(await runMemoryBenchmark());

  print('[16/16] SQLite Diagnostics...');
  markdown.write(await runSqliteDiagnosticsBenchmark());

  // Slow workloads — opt-in via --include-slow because they take
  // multiple minutes each. Register here so they append to the
  // standard suite output when enabled.
  if (includeSlow) {
    print('[slow 1/3] Sync Burst (A7)...');
    markdown.write(await runSyncBurstBenchmark());

    print('[slow 2/3] Large Working Set (A9)...');
    markdown.write(await runLargeWorkingSetBenchmark());

    print('[slow 3/3] Many-Streams Writer Throughput (A11c)...');
    markdown.write(await runManyStreamsWriterThroughputBenchmark());
  }

  return markdown.toString();
}

final class _ComparisonBaseline {
  const _ComparisonBaseline._({
    required this.file,
    required this.mode,
    required this.explicit,
    required this.compatibility,
  });

  const _ComparisonBaseline.none()
    : file = null,
      mode = 'none',
      explicit = false,
      compatibility = const BaselineCompatibility(
        compatible: true,
        reasons: [],
      );

  factory _ComparisonBaseline.explicit(
    File file,
    Map<String, Object?> environment,
  ) {
    return _ComparisonBaseline._(
      file: file,
      mode: 'explicit',
      explicit: true,
      compatibility: _evaluateBaselineFile(file, environment),
    );
  }

  factory _ComparisonBaseline.automatic(
    File file,
    Map<String, Object?> environment,
  ) {
    return _ComparisonBaseline._(
      file: file,
      mode: 'automatic',
      explicit: false,
      compatibility: _evaluateBaselineFile(file, environment),
    );
  }

  final File? file;
  final String mode;
  final bool explicit;
  final BaselineCompatibility compatibility;

  bool get isCompatible => compatibility.compatible;

  bool get shouldCompare => file != null && (explicit || isCompatible);

  List<String> get reasons => compatibility.reasons;

  String get fileName {
    final selected = file;
    if (selected == null) return 'none';
    final segments = selected.uri.pathSegments;
    return segments.isEmpty ? selected.path : segments.last;
  }

  String get compatibilityLabel {
    if (file == null) return 'not applicable';
    if (isCompatible) return 'compatible';
    if (explicit) return 'incompatible (explicit comparison)';
    return 'incompatible (automatic comparison skipped)';
  }

  Map<String, Object?>? toArtifactJson() {
    if (file == null) return null;
    return {
      'selectedBaselineFile': fileName,
      'mode': mode,
      'compatible': isCompatible,
      if (reasons.isNotEmpty) 'reasons': reasons,
      'comparisonExecuted': shouldCompare,
    };
  }
}

BaselineCompatibility _evaluateBaselineFile(
  File file,
  Map<String, Object?> environment,
) {
  final artifact = _tryLoadReleaseArtifactSidecar(file);
  return evaluateBaselineCompatibility(
    current: environment,
    baseline: artifact == null ? null : artifactEnvironment(artifact),
  );
}

Map<String, Object?>? _tryLoadReleaseArtifactSidecar(File markdownFile) {
  try {
    return loadReleaseArtifactSidecarForMarkdown(markdownFile);
  } catch (_) {
    return null;
  }
}

String _renderBaselineCompatibilityWarning(_ComparisonBaseline baseline) {
  final buffer = StringBuffer()
    ..writeln('## Baseline Compatibility')
    ..writeln()
    ..writeln(
      'This is an explicit comparison against `${baseline.fileName}`, but the baseline environment differs from the current run:',
    );
  for (final reason in baseline.reasons) {
    buffer.writeln('- $reason');
  }
  buffer
    ..writeln()
    ..writeln('Treat the comparison as a reference check, not a gate.')
    ..writeln();
  return buffer.toString();
}

String _renderSkippedAutomaticComparison(_ComparisonBaseline baseline) {
  final buffer = StringBuffer()
    ..writeln('## Comparison')
    ..writeln()
    ..writeln(
      'Automatic comparison skipped because `${baseline.fileName}` was not captured in a compatible environment:',
    );
  for (final reason in baseline.reasons) {
    buffer.writeln('- $reason');
  }
  buffer
    ..writeln()
    ..writeln(
      'Use `--compare-to=${baseline.file!.path}` to run an explicit reference comparison anyway.',
    )
    ..writeln();
  return buffer.toString();
}

final class _RunAllOptions {
  const _RunAllOptions({
    required this.label,
    required this.repeatCount,
    required this.compareToPath,
    required this.autoCompare,
    required this.hardwareSummary,
    required this.includeSlow,
  });

  final String label;
  final int repeatCount;
  final String? compareToPath;
  final bool autoCompare;
  final bool hardwareSummary;

  /// When true, opt-in "slow" workloads (A7 sync burst, A9 1GB working
  /// set) run as part of the suite. Default is false because those
  /// workloads are minutes-scale individually and dominate the default
  /// run time. Use `--include-slow` to enable them for a comprehensive
  /// cross-device pass.
  final bool includeSlow;
}

_RunAllOptions _parseOptions(List<String> args) {
  var label = 'unlabeled';
  var repeatCount = 5;
  String? compareToPath;
  var autoCompare = true;
  var hardwareSummary = false;
  var includeSlow = false;

  for (final arg in args) {
    if (arg.startsWith('--repeat=')) {
      repeatCount = int.parse(arg.substring('--repeat='.length));
    } else if (arg.startsWith('--compare-to=')) {
      compareToPath = arg.substring('--compare-to='.length);
    } else if (arg == '--no-auto-compare') {
      autoCompare = false;
    } else if (arg == '--hardware-summary') {
      hardwareSummary = true;
    } else if (arg == '--include-slow') {
      includeSlow = true;
    } else if (arg == '--help' || arg == '-h') {
      _printUsageAndExit();
    } else if (!arg.startsWith('--')) {
      label = arg;
    } else {
      throw ArgumentError('Unknown argument: $arg');
    }
  }

  if (repeatCount < 1) {
    throw ArgumentError('--repeat must be >= 1');
  }

  return _RunAllOptions(
    label: label,
    repeatCount: repeatCount,
    compareToPath: compareToPath,
    autoCompare: autoCompare,
    hardwareSummary: hardwareSummary,
    includeSlow: includeSlow,
  );
}

void _printUsageAndExit() {
  print(
    'Usage: dart run benchmark/run_release.dart [label] [--repeat=N] '
    '[--compare-to=PATH] [--no-auto-compare] [--hardware-summary] '
    '[--include-slow]',
  );
  print('');
  print('  --repeat=N           Run the suite N times (default: 5)');
  print(
    '  --compare-to=PATH    Compare against a specific baseline results file',
  );
  print(
    '  --no-auto-compare    Do not infer a baseline from benchmark/results',
  );
  print(
    '  --hardware-summary   Print a copy-pasteable row for HARDWARE_RESULTS.md',
  );
  print('  --include-slow       Also run multi-minute slow workloads');
  print('                       (sync burst, 1GB working set,');
  print('                       many-streams writer throughput)');
  exit(0);
}

_ComparisonBaseline _resolveComparisonBaseline(
  Directory resultsDir,
  _RunAllOptions options,
  Map<String, Object?> environment,
) {
  final explicitPath = options.compareToPath;
  if (explicitPath != null && explicitPath.isNotEmpty) {
    final file = File(explicitPath);
    if (!file.existsSync()) {
      throw ArgumentError('Comparison file not found: $explicitPath');
    }
    return _ComparisonBaseline.explicit(file, environment);
  }

  if (!options.autoCompare) return const _ComparisonBaseline.none();

  final file = _findPreviousResults(resultsDir);
  if (file == null) return const _ComparisonBaseline.none();

  return _ComparisonBaseline.automatic(file, environment);
}

/// Find the most recent .md file in the results directory.
File? _findPreviousResults(Directory dir) {
  if (!dir.existsSync()) return null;

  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md') && !f.path.endsWith('.gitkeep'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path)); // newest first

  return files.isNotEmpty ? files.first : null;
}

/// Ensures the drift-generated `*.g.dart` files under `benchmark/drift/`
/// are fresh relative to their source `.dart` files. If any source is
/// newer than its generated counterpart (or the counterpart is missing),
/// regenerates via `dart run build_runner build` before the benchmark
/// suite runs. Keeps contributors from accidentally benchmarking against
/// stale codegen after a schema edit.
///
/// Fast path when nothing changed: ~50ms (7 stat calls). Slow path
/// when regen is needed: ~5–10s for the build_runner invocation.
Future<void> _ensureDriftCodegenFresh() async {
  final driftDir = Directory('benchmark/drift');
  if (!driftDir.existsSync()) return;

  final sources = driftDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();

  var stale = false;
  for (final source in sources) {
    final genPath = source.path.replaceAll(RegExp(r'\.dart$'), '.g.dart');
    final gen = File(genPath);
    if (!gen.existsSync()) {
      stale = true;
      break;
    }
    if (source.lastModifiedSync().isAfter(gen.lastModifiedSync())) {
      stale = true;
      break;
    }
  }
  if (!stale) return;

  print('Drift codegen stale — running build_runner...');
  final result = await Process.run(
    'dart',
    ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
    // Let build_runner print progress to the same stdout as our run.
    // Important for contributors running from CI where buffered output
    // would obscure which step is currently active.
    runInShell: false,
  );
  if (result.exitCode != 0) {
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    throw StateError(
      'build_runner failed (exit ${result.exitCode}). Fix the drift '
      'schemas under benchmark/drift/ then re-run.',
    );
  }
  print('Drift codegen up-to-date.');
}

String _sanitizeResultFilenameLabel(String label) {
  final sanitized = label
      .replaceAll('"', 'in')
      .replaceAll(RegExp(r'[<>|*?\r\n:]'), '')
      .replaceAll(RegExp(r'[\\/]'), '-')
      .trim();
  return sanitized.isEmpty ? 'run' : sanitized;
}
