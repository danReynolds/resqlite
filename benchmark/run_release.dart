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
import 'dart:io' show Directory, File, Platform, Process, exit, stderr;

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
    extra: {
      'benchmarkMode': 'release',
      'includeSlow': options.includeSlow,
      'skipMemory': options.skipMemory,
    },
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

  // Filenames are fixed up front so each completed repeat can be persisted
  // into them as it lands.
  MemoryComparison? memoryComparison;
  ReleaseComparison? releaseComparison;

  final runTimestamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final safeRunLabel = _sanitizeResultFilenameLabel(options.label);
  final resultsFile = File('${resultsDir.path}/$runTimestamp-$safeRunLabel.md');
  final jsonFile = File('${resultsDir.path}/$runTimestamp-$safeRunLabel.json');

  for (var i = 0; i < options.repeatCount; i++) {
    if (options.repeatCount > 1) {
      print('--- Repeat ${i + 1}/${options.repeatCount} ---');
    }
    // Persist what has completed, after every scenario.
    //
    // The suite runs four libraries in one process, so a segfault anywhere —
    // including in a peer's native code, which is where the current one lives —
    // takes the whole run down. Exp 282 made a completed *repeat* survivable,
    // but the peer crashing today does so at the Memory scenario inside repeat
    // 1, so a full run still produced nothing at all. Persisting per scenario
    // means a crash costs the scenario in flight, not the fourteen before it.
    final markdown = await _runSuiteOnce(
      includeSlow: options.includeSlow,
      skipMemory: options.skipMemory,
      onScenario: (markdownSoFar, completed) async {
        resultsDir.createSync(recursive: true);
        jsonFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(
            buildReleaseRunArtifact(
              label: options.label,
              // Repeats that finished before this one. The in-flight repeat
              // counts only once it completes, so a partial repeat can never
              // inflate the sample count a trend reads.
              repeatCount: runMarkdowns.length,
              markdown: markdownSoFar,
              aggregates: aggregateRunMetrics(runMetrics),
              environment: environment,
              generatedAt: DateTime.now().toIso8601String(),
              scenariosCompleted: completed,
              scenarioTotal: scenarioTotal(
                includeSlow: options.includeSlow,
                skipMemory: options.skipMemory,
              ),
            ),
          ),
        );
      },
    );
    runMarkdowns.add(markdown);
    runMetrics.add(extractResqliteMedians(markdown));

    jsonFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(
        buildReleaseRunArtifact(
          label: options.label,
          repeatCount: runMarkdowns.length,
          markdown: markdown,
          aggregates: aggregateRunMetrics(runMetrics),
          environment: environment,
          generatedAt: DateTime.now().toIso8601String(),
          scenariosCompleted: scenarioTotal(
            includeSlow: options.includeSlow,
            skipMemory: options.skipMemory,
          ),
          scenarioTotal: scenarioTotal(
            includeSlow: options.includeSlow,
            skipMemory: options.skipMemory,
          ),
        ),
      ),
    );
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
    // Prefer the baseline's cross-repeat aggregate medians over its
    // representative-repeat tables: the representative repeat is one sample,
    // and a noisy one on the baseline side reads as a phantom delta on every
    // lane it wobbled.
    final prevSidecar = loadReleaseArtifactSidecarForMarkdown(baseline.file!);
    final prevTrend = prevSidecar == null
        ? const <String, double>{}
        : artifactTrendMetrics(prevSidecar);
    releaseComparison = prevTrend.isNotEmpty
        ? compareRelease(
            currentAggregates,
            prevTrend,
            prevName,
            previousSource: 'cross-repeat aggregate medians',
          )
        : compareRelease(
            currentAggregates,
            extractResqliteMedians(prevContent),
            prevName,
          );
    markdown.writeln(releaseComparison.markdown);
    print(releaseComparison.markdown);

    memoryComparison = compareMemory(representativeMarkdown, prevContent);
    if (memoryComparison.markdown.isNotEmpty) {
      markdown.writeln(memoryComparison.markdown);
      print(memoryComparison.markdown);
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

  // Close the loop at the moment the run is produced.
  //
  // A dirty or single-sample run is dropped from the trend charts, and it used
  // to vanish silently — so the person who produced it never learned it did not
  // count. Of the last thirty runs, twenty-two were dirty and thirteen
  // single-sample, leaving five usable; the rule was already written down and
  // being followed by nobody, which is what an unenforced rule looks like.
  final excluded = <String>[
    if (environment['gitDirty'] == true)
      'the tree is dirty (commit or stash, then re-run)',
    if (options.repeatCount < 2)
      'it is single-sample (--repeat=1); use --repeat=5 for an authoritative number',
  ];
  if (excluded.isNotEmpty) {
    print('');
    print('!! This run will NOT appear on the trend charts, because:');
    for (final reason in excluded) {
      print('   - $reason');
    }
    print('   It is still saved, and still usable as one arm of an A/B.');
  }

  // Memory acceptance criteria.
  //
  // The comparison table has always named regressions and nothing has ever
  // failed on one, which is what the `per-benchmark RSS acceptance criteria`
  // candidate open since 2026-05-02 was asking for. The thresholds are already
  // per-benchmark (bootstrap MDE with a 0.5 MB floor); all that was missing was
  // making the verdict visible and, on request, fatal.
  if (memoryComparison != null && memoryComparison.hasRegression) {
    print('');
    print(
      '!! Memory regression: ${memoryComparison.regressions} benchmark'
      '${memoryComparison.regressions == 1 ? '' : 's'} above threshold',
    );
    for (final name in memoryComparison.regressedBenchmarks) {
      print('   - $name');
    }
    print(
      '   RSS is a lower bound, so a regression here is real even though a '
      'win of the same size might not be.',
    );
  }

  if (options.hardwareSummary) {
    _printHardwareSummary(currentAggregates, options.label);
  }

  final memoryGateFailed = shouldFailOnMemory(
    failOnMemoryRegression: options.failOnMemoryRegression,
    comparison: memoryComparison,
  );
  if (memoryGateFailed) {
    final count = memoryComparison!.regressions;
    print('');
    print(
      '!! Failing the run: --fail-on-memory-regression was passed and the '
      'memory comparison found $count regression${count == 1 ? '' : 's'}.',
    );
  }

  final regressionGateFailed = shouldFailOnRegressions(
    failOnRegression: options.failOnRegression,
    comparison: releaseComparison,
  );
  if (regressionGateFailed) {
    print('');
    print(
      '!! Failing the run: --fail-on-regression was passed and the comparison '
      'found regressions beyond per-lane noise thresholds:',
    );
    for (final name in releaseComparison!.regressedBenchmarks) {
      print('   - $name');
    }
    print(
      '   Either the change regressed the lane (fix it), or the variance is '
      'accepted (document why in the experiment writeup).',
    );
  }

  // Force exit — persistent writer isolate and sqlite_async connections can
  // keep the event loop alive. The status has to be passed explicitly: setting
  // the global `exitCode` and then calling `exit(0)` discards it, which is how
  // the gate above shipped unable to fail anything.
  exit(memoryGateFailed || regressionGateFailed ? 1 : 0);
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

/// Run every scenario once, reporting progress after each one completes.
///
/// [onScenario] receives the markdown accumulated *so far*, plus how many
/// scenarios of [scenarioTotal] have finished. [EXP-262]: the suite runs four
/// libraries in one process, so a segfault anywhere — including in a peer's
/// native code, which is where the current one lives — ends the process. Exp
/// 282 made a completed *repeat* survivable, but the peer that crashes today
/// does so at the Memory scenario inside repeat 1, so nothing was ever
/// persisted. Reporting per scenario means a crash costs the scenario in
/// flight, not the fourteen before it.
Future<String> _runSuiteOnce({
  required bool includeSlow,
  required bool skipMemory,
  required Future<void> Function(String markdownSoFar, int completed)
  onScenario,
}) async {
  final markdown = StringBuffer();
  var completed = 0;
  final total = scenarioTotal(includeSlow: includeSlow, skipMemory: skipMemory);

  Future<void> step(String label, Future<String> Function() run) async {
    print('[${completed + 1}/$total] $label...');
    markdown.write(await run());
    completed++;
    await onScenario(markdown.toString(), completed);
  }

  await step('Select → Maps', runSelectMapsBenchmark);
  await step('Select → Bytes', runSelectBytesBenchmark);
  await step('Schema Shapes', runSchemaShapesBenchmark);
  await step('Scaling', runScalingBenchmark);
  await step('Concurrent Reads', runConcurrentReadsBenchmark);
  await step('Point Query', runPointQueryBenchmark);
  await step('Parameterized Queries', runParameterizedBenchmark);
  await step('Writes', runWritesBenchmark);
  if (Platform.environment['RESQLITE_BENCH_ONLY'] == '1') {
    await step('Streaming (focused separately)', () async {
      return '## Streaming\n\n'
          'Skipped in the Resqlite-only AOT bundle; the durable '
          '`stream_rerun_latency.dart` harness supplies this gate.\n\n';
    });
  } else {
    await step('Streaming', runStreamingBenchmark);
  }
  await step('Streaming (Column Granularity)', runDisjointColumnsBenchmark);
  await step('Keyed PK Subscriptions (A11)', runKeyedPkSubscriptionsBenchmark);
  await step('Chat Sim (A5)', runChatSimBenchmark);
  await step('Feed Paging (A6)', runFeedPagingBenchmark);
  await step(
    'High-Cardinality Stream Fan-out (A11b)',
    runHighCardinalityFanoutBenchmark,
  );
  // The current sqlite_async peer segfaults in its native update-notification
  // path inside the Memory scenario ([EXP-262]: exp 229's own sha crashes at
  // the same stage, so the regression is in the peers, not this repo), which
  // kills the process at scenario 15/16 of repeat 1 — before any repeat
  // completes and any .md artifact is written. --skip-memory trades the
  // Memory section, which the memory gate already tolerates missing, for a
  // run that survives to publish.
  if (!skipMemory) {
    await step('Memory', runMemoryBenchmark);
  }
  await step('SQLite Diagnostics', runSqliteDiagnosticsBenchmark);

  // Slow workloads — opt-in via --include-slow because they take multiple
  // minutes each. Registered here so they append to the standard suite output.
  if (includeSlow) {
    await step('Sync Burst (A7)', runSyncBurstBenchmark);
    await step('Large Working Set (A9)', runLargeWorkingSetBenchmark);
    await step(
      'Many-Streams Writer Throughput (A11c)',
      runManyStreamsWriterThroughputBenchmark,
    );
  }

  return markdown.toString();
}

/// How many scenarios a single repeat runs. Kept next to [_runSuiteOnce] so the
/// progress labels and the persisted `scenarioTotal` cannot drift apart — they
/// already had, the standard suite printing `[1/15]` through `[16/16]`.
int scenarioTotal({required bool includeSlow, bool skipMemory = false}) =>
    (includeSlow ? 19 : 16) - (skipMemory ? 1 : 0);

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
    required this.failOnMemoryRegression,
    required this.failOnRegression,
    required this.compareToPath,
    required this.autoCompare,
    required this.hardwareSummary,
    required this.includeSlow,
    required this.skipMemory,
  });

  final String label;
  final int repeatCount;

  /// Exit non-zero when the memory comparison finds a benchmark above its
  /// per-benchmark threshold. Off by default so a local run still reports the
  /// regression without failing; CI opts in.
  final bool failOnMemoryRegression;

  /// Exit non-zero when the wall-time comparison finds a lane beyond its
  /// per-lane decision threshold (`max(10%, 3 × MAD, MDE_ci)`). Off by default
  /// so a local run still reports; the experiment protocol opts in so a
  /// regression is caught in the run that measures it, not weeks later.
  final bool failOnRegression;
  final String? compareToPath;
  final bool autoCompare;
  final bool hardwareSummary;

  /// When true, opt-in "slow" workloads (A7 sync burst, A9 1GB working
  /// set) run as part of the suite. Default is false because those
  /// workloads are minutes-scale individually and dominate the default
  /// run time. Use `--include-slow` to enable them for a comprehensive
  /// cross-device pass.
  final bool includeSlow;

  /// When true, the Memory scenario is skipped. The current sqlite_async peer
  /// segfaults inside it ([EXP-262]), which otherwise ends the process at
  /// scenario 15/16 of repeat 1 — before any artifact can be written.
  final bool skipMemory;
}

_RunAllOptions _parseOptions(List<String> args) {
  var label = 'unlabeled';
  var repeatCount = 5;
  var failOnMemoryRegression = false;
  var failOnRegression = false;
  String? compareToPath;
  var autoCompare = true;
  var hardwareSummary = false;
  var includeSlow = false;
  var skipMemory = false;

  for (final arg in args) {
    if (arg == '--fail-on-memory-regression') {
      failOnMemoryRegression = true;
    } else if (arg == '--fail-on-regression') {
      failOnRegression = true;
    } else if (arg.startsWith('--repeat=')) {
      repeatCount = int.parse(arg.substring('--repeat='.length));
    } else if (arg.startsWith('--compare-to=')) {
      compareToPath = arg.substring('--compare-to='.length);
    } else if (arg == '--no-auto-compare') {
      autoCompare = false;
    } else if (arg == '--hardware-summary') {
      hardwareSummary = true;
    } else if (arg == '--include-slow') {
      includeSlow = true;
    } else if (arg == '--skip-memory') {
      skipMemory = true;
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
    failOnMemoryRegression: failOnMemoryRegression,
    failOnRegression: failOnRegression,
    compareToPath: compareToPath,
    autoCompare: autoCompare,
    hardwareSummary: hardwareSummary,
    includeSlow: includeSlow,
    skipMemory: skipMemory,
  );
}

void _printUsageAndExit() {
  print(
    'Usage: dart run benchmark/run_release.dart [label] [--repeat=N] '
    '[--compare-to=PATH] [--no-auto-compare] [--hardware-summary] '
    '[--include-slow] [--skip-memory] [--fail-on-regression] '
    '[--fail-on-memory-regression]',
  );
  print('');
  print('  --repeat=N           Run the suite N times (default: 5)');
  print(
    '  --fail-on-memory-regression  Exit non-zero if any benchmark exceeds '
    'its per-benchmark RSS threshold',
  );
  print(
    '  --compare-to=PATH    Compare against a specific baseline results file',
  );
  print(
    '  --no-auto-compare    Do not infer a baseline from benchmark/results',
  );
  print(
    '  --hardware-summary   Print a copy-pasteable row for HARDWARE_RESULTS.md',
  );
  print(
    '  --skip-memory        Skip the Memory scenario (the current '
    'sqlite_async peer segfaults inside it — see exp 262)',
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
