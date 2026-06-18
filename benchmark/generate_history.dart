// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'shared/parse_results.dart';
import 'shared/release_artifact.dart';
import 'shared/workload_registry.dart';

const _jsonEncoder = JsonEncoder.withIndent('  ');

/// Generates `docs/experiments/history.json` from benchmark results and
/// experiment markdown files.
///
/// Usage:
///   dart run benchmark/generate_history.dart
Future<void> main() async {
  final resultsDir = Directory('benchmark/results');
  final experimentsDir = Directory('experiments');
  final outFile = File('docs/experiments/history.json');
  final output = buildHistoryData(
    resultsDir: resultsDir,
    experimentsDir: experimentsDir,
  );

  // 4. Write JSON.
  await outFile.parent.create(recursive: true);

  final wrote = await writeHistoryData(outFile, output);

  final tracked = (output['tracked'] as List?)?.cast<String>() ?? const [];
  if (wrote) {
    print('Wrote ${outFile.path} (${tracked.length} tracked metrics).');
  } else {
    print('${outFile.path} is current (${tracked.length} tracked metrics).');
  }
  print('Tracked: ${tracked.join(', ')}');
}

Future<bool> writeHistoryData(File outFile, Map<String, Object?> output) async {
  final currentText = outFile.existsSync()
      ? await outFile.readAsString()
      : null;
  final currentGenerated = _currentGeneratedTimestamp(currentText);
  if (currentGenerated != null) {
    final stableOutput = Map<String, Object?>.from(output)
      ..['generated'] = currentGenerated;
    if (_jsonEncoder.convert(stableOutput) == currentText!.trimRight()) {
      return false;
    }
  }

  await outFile.writeAsString(_jsonEncoder.convert(output));
  return true;
}

String? _currentGeneratedTimestamp(String? currentText) {
  if (currentText == null) return null;
  try {
    final currentJson = jsonDecode(currentText);
    if (currentJson is Map) {
      final generated = currentJson['generated'];
      if (generated is String) return generated;
    }
  } on FormatException {
    return null;
  }
  return null;
}

Map<String, Object?> buildHistoryData({
  required Directory resultsDir,
  required Directory experimentsDir,
  String? generatedAt,
}) {
  // 1. Parse all benchmark result files.
  final runs = <Map<String, Object?>>[];
  final mdFiles =
      resultsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in mdFiles) {
    final basename = file.path.split('/').last;
    final meta = parseFilenameMetadata(basename);
    if (meta == null) continue;

    final sidecar = loadReleaseArtifactSidecarForMarkdown(file);
    // Markdown is needed both as the fallback metric source AND for fields
    // (Repeats, sqlite3 control numbers) that aren't always promoted into
    // the sidecar JSON, so read it once for both code paths.
    final content = file.readAsStringSync();
    final metrics = sidecar != null
        ? artifactMetrics(sidecar)
        : extractResqliteMedians(content);
    if (metrics.isEmpty) {
      print('  Skipping $basename (no resqlite metrics found)');
      continue;
    }

    final memoryJson = sidecar != null
        ? artifactMemoryMetrics(sidecar)
        : _memoryMetricsJson(extractMemoryMedians(content));
    final environment = sidecar != null ? artifactEnvironment(sidecar) : null;
    final sqliteDiagnosticsJson = sidecar != null
        ? artifactSqliteDiagnosticsMetrics(sidecar)
        : _sqliteDiagnosticsJson(extractSqliteDiagnosticsMedians(content));

    final repeatCount = sidecar != null
        ? (artifactRepeatCount(sidecar) ?? extractRepeatCount(content))
        : extractRepeatCount(content);
    final sqlite3Si = sidecar != null
        ? artifactSqlite3SingleInsertWall(sidecar)
        : extractSqlite3SingleInsertWall(content);
    final noiseReason = _classifyNoise(
      repeatCount: repeatCount,
      sqlite3Si: sqlite3Si,
    );

    runs.add({
      'id': meta.label,
      'date': meta.date,
      'timestamp': meta.timestamp,
      'label': meta.label,
      if (environment != null && environment.isNotEmpty)
        'environment': environment,
      'metrics': metrics,
      if (memoryJson != null && memoryJson.isNotEmpty)
        'memoryMetrics': memoryJson,
      if (sqliteDiagnosticsJson != null && sqliteDiagnosticsJson.isNotEmpty)
        'sqliteDiagnosticsMetrics': sqliteDiagnosticsJson,
      if (repeatCount != null) 'repeatCount': repeatCount,
      if (sqlite3Si.medianMs != null)
        'sqlite3SingleInsertMedianMs': sqlite3Si.medianMs,
      if (sqlite3Si.p90Ms != null) 'sqlite3SingleInsertP90Ms': sqlite3Si.p90Ms,
      if (noiseReason != null) 'noisy': true,
      if (noiseReason != null) 'noisyReason': noiseReason,
    });
  }

  print('Parsed ${runs.length} benchmark runs from ${mdFiles.length} files.');

  final allKeys = <String>{};
  for (final run in runs) {
    allKeys.addAll((run['metrics'] as Map<String, double>).keys);
  }

  // 2. Parse experiments from the README table + individual files.
  final experiments = <Map<String, Object?>>[];

  if (experimentsDir.existsSync()) {
    final readmeFile = File('${experimentsDir.path}/README.md');
    if (readmeFile.existsSync()) {
      final readme = readmeFile.readAsStringSync();
      experiments.addAll(
        _parseExperimentsReadme(readme, experimentsDir, allKeys),
      );
    }
  }

  print('Parsed ${experiments.length} experiments.');

  final benchmarkRunOptOuts = _attachBenchmarkRunMappings(experiments, runs);
  _assertAcceptedExperimentsLinkToCandidates(experiments, runs);
  _assertNewExperimentsLinkOrDeclareRun(experiments, benchmarkRunOptOuts);

  // 3. Resolve the curated metric registry used by the experiments page.
  final catalog = resolveCuratedMetrics(allKeys);

  final output = <String, Object?>{
    'generated': generatedAt ?? DateTime.now().toIso8601String(),
    'runs': runs,
    'experiments': experiments,
    'tracked': catalog.tracked,
    'metricDisplay': catalog.metricDisplay,
    'chartGroups': catalog.chartGroups,
  };

  return output;
}

/// Decide whether a release-mode benchmark run is too noisy to chart on
/// the experiments timeline. Returns a human-readable reason string when
/// the run is noisy, or `null` when the run is clean enough to plot.
///
/// Two layered checks:
///
///  1. **Single-sample runs** (`Repeats: 1`) — the released methodology
///     publishes 5-sample medians. Single-sample numbers are kept on disk
///     for historical and comparison-baseline purposes, but they are not
///     statistically authoritative and have produced the bulk of the
///     visible chart spikes (entire 04-09 morning cluster + exp088).
///
///  2. **sqlite3 control elevated** — sqlite3 is the unchanged peer in
///     the `Single Inserts (100 sequential)` workload. If its wall-time
///     numbers in a given run sit far outside the typical envelope (~1–6
///     ms median, ~2–15 ms p90 on the recorded hardware), every library
///     in that run measured during background load and the resqlite
///     numbers are not comparable to neighbouring runs. Catches the
///     `readme-numbers` (sqlite3 13.76 ms median) and `state-check-verify`
///     (sqlite3 p90 118 ms) anomalies even though both have multi-sample
///     repeats.
///
/// Thresholds are intentionally loose (8 ms median / 30 ms p90) — a 2×
/// margin above the worst clean run we've seen — so the gate fires only
/// on clear-cut machine-load anomalies, not on hardware variation.
String? _classifyNoise({
  required int? repeatCount,
  required Sqlite3SingleInsertWall sqlite3Si,
}) {
  if (repeatCount == 1) {
    return 'single-sample run (Repeats: 1) — not statistically authoritative';
  }
  final med = sqlite3Si.medianMs;
  if (med != null && med > 8.0) {
    return 'sqlite3 control elevated '
        '(single-insert wall median ${med.toStringAsFixed(2)} ms) — '
        'background load suspected';
  }
  final p90 = sqlite3Si.p90Ms;
  if (p90 != null && p90 > 30.0) {
    return 'sqlite3 control p90 elevated '
        '(single-insert wall p90 ${p90.toStringAsFixed(1)} ms) — '
        'background load suspected';
  }
  return null;
}

Map<String, Object?> _memoryMetricsJson(Map<String, MemoryMetric> memory) {
  return {
    for (final entry in memory.entries)
      entry.key: {
        'rssDeltaMedMB': entry.value.rssDeltaMedMB,
        'rssDeltaP90MB': entry.value.rssDeltaP90MB,
        'ciLowMB': entry.value.ciLowMB,
        'ciHighMB': entry.value.ciHighMB,
        'mdeMB': entry.value.mdeMB,
      },
  };
}

Map<String, Object?> _sqliteDiagnosticsJson(
  Map<String, SqliteDiagnosticsMetric> sqliteDiagnostics,
) {
  return {
    for (final entry in sqliteDiagnostics.entries)
      entry.key: {
        'sqliteTotalKiB': entry.value.sqliteTotalKiB,
        'pageCacheKiB': entry.value.pageCacheKiB,
        'schemaKiB': entry.value.schemaKiB,
        'stmtKiB': entry.value.stmtKiB,
        'walKiB': entry.value.walKiB,
        if (entry.value.jsonBufKiB != null)
          'jsonBufKiB': entry.value.jsonBufKiB,
        'readersBusy': entry.value.readersBusy,
      },
  };
}

/// Maps each experiment to a benchmark run and returns the set of
/// experiment ids (lowercased) that explicitly opted out of release-run
/// mapping via a `**Benchmark Run:**` header (`none`/`n/a`/`tracelite`/...).
/// The opt-out set is reused by [_assertNewExperimentsLinkOrDeclareRun] to
/// tell a deliberate "no release run" from a forgotten result file.
Set<String> _attachBenchmarkRunMappings(
  List<Map<String, Object?>> experiments,
  List<Map<String, Object?>> runs,
) {
  final claimedRunIndices = <int>{};
  final skipRunMappingIds = <String>{};
  for (final exp in experiments) {
    if (exp.remove('_skipBenchmarkRunMapping') == true) {
      skipRunMappingIds.add((exp['id'] as String).toLowerCase());
    }
  }

  // First pass: exact explicit experiment-id matches in the run label,
  // e.g. experiment 088 -> run id "exp088-setlk-timeout".
  //
  // Match only when the run id *starts with* expNNN. A `contains` check
  // would also match `baseline-for-expNNN` siblings, which then compete
  // by iteration order and can claim the slot first — pointing the chart
  // at the pre-change baseline instead of the candidate. (Structural
  // exclusion via `comparisonBaselineFile` graphs over-excludes because
  // a run can be both a candidate and a baseline for a later A/B.)
  for (final exp in experiments) {
    final expId = exp['id'] as String;
    if (skipRunMappingIds.contains(expId)) continue;
    final expNum = expId.toLowerCase();
    final exactPatterns = ['exp$expNum', 'exp-$expNum'];
    int matchedIdx = -1;
    for (var idx = 0; idx < runs.length; idx++) {
      if (claimedRunIndices.contains(idx)) continue;
      final id = (runs[idx]['id'] as String? ?? '').toLowerCase();
      if (exactPatterns.any(id.startsWith)) {
        matchedIdx = idx;
        break;
      }
    }
    if (matchedIdx >= 0) {
      exp['benchmarkRun'] = {
        'id': runs[matchedIdx]['id'],
        'date': runs[matchedIdx]['date'],
        'timestamp': runs[matchedIdx]['timestamp'],
        'source': 'exact',
      };
      claimedRunIndices.add(matchedIdx);
    }
  }

  final byDate = <String, List<Map<String, Object?>>>{};
  for (final exp in experiments) {
    if (skipRunMappingIds.contains(exp['id'] as String)) continue;
    if (exp['benchmarkRun'] != null) continue;
    final date = exp['date'] as String? ?? '';
    if (date.isEmpty) continue;
    (byDate[date] ??= []).add(exp);
  }

  final runsByDate = <String, List<int>>{};
  for (var i = 0; i < runs.length; i++) {
    final date = runs[i]['date'] as String? ?? '';
    if (date.isEmpty) continue;
    (runsByDate[date] ??= []).add(i);
  }

  for (final entry in byDate.entries) {
    final date = entry.key;
    final dateExps = entry.value;
    final dateRuns = (runsByDate[date] ?? const <int>[])
        .where((idx) => !claimedRunIndices.contains(idx))
        .toList();

    if (dateRuns.isEmpty) {
      String? bestDate;
      var bestDist = double.infinity;
      for (final rd in runsByDate.keys) {
        final candidateRuns = runsByDate[rd]!
            .where((idx) => !claimedRunIndices.contains(idx))
            .toList();
        if (candidateRuns.isEmpty) continue;
        final dist =
            (DateTime.parse(rd).millisecondsSinceEpoch -
                    DateTime.parse(date).millisecondsSinceEpoch)
                .abs()
                .toDouble();
        if (dist < bestDist) {
          bestDist = dist;
          bestDate = rd;
        }
      }

      if (bestDate != null && bestDist < 3 * 86400000) {
        final fallbackRuns = runsByDate[bestDate]!
            .where((idx) => !claimedRunIndices.contains(idx))
            .toList();
        for (var j = 0; j < dateExps.length; j++) {
          final preferredIndex = j < fallbackRuns.length
              ? j
              : fallbackRuns.length - 1;
          final runIdx = _pickClosestUnclaimedRun(
            fallbackRuns,
            preferredIndex,
            claimedRunIndices,
          );
          if (runIdx == null) continue;
          dateExps[j]['benchmarkRun'] = {
            'id': runs[runIdx]['id'],
            'date': runs[runIdx]['date'],
            'timestamp': runs[runIdx]['timestamp'],
            'source': 'nearby',
          };
          claimedRunIndices.add(runIdx);
        }
      }
      continue;
    }

    for (var j = 0; j < dateExps.length; j++) {
      final proportionalIndex = (j * dateRuns.length / dateExps.length)
          .floor()
          .clamp(0, dateRuns.length - 1);
      final runIdx = _pickClosestUnclaimedRun(
        dateRuns,
        proportionalIndex,
        claimedRunIndices,
      );
      if (runIdx == null) continue;
      dateExps[j]['benchmarkRun'] = {
        'id': runs[runIdx]['id'],
        'date': runs[runIdx]['date'],
        'timestamp': runs[runIdx]['timestamp'],
        'source': 'same-day',
      };
      claimedRunIndices.add(runIdx);
    }
  }

  return skipRunMappingIds;
}

/// Catch the case where an Accepted experiment's chart slot points at
/// a baseline-shaped run *while* a better-shaped candidate also exists
/// in the run list. That's the "linker grabbed the wrong file" failure
/// (which produced the exp-109 chart mixup) — the right data is sitting
/// right next to the wrong choice.
///
/// Stays silent when only a baseline-shaped run exists for the date
/// (legacy experiments predating the per-experiment-result-file
/// convention, where the baseline is genuinely the only data point).
void _assertAcceptedExperimentsLinkToCandidates(
  List<Map<String, Object?>> experiments,
  List<Map<String, Object?>> runs,
) {
  final issues = <String>[];
  final baselinePattern = RegExp(r'(^|[-_])(baseline|pre)([-_]|$)');
  for (final exp in experiments) {
    if (exp['status'] != 'accepted') continue;
    final run = exp['benchmarkRun'];
    if (run is! Map) continue;
    final runId = (run['id'] as String? ?? '').toLowerCase();
    if (runId.isEmpty) continue;
    if (!baselinePattern.hasMatch(runId)) continue;

    final expNum = (exp['id'] as String).toLowerCase();
    final betterCandidate = runs.any((r) {
      final id = (r['id'] as String? ?? '').toLowerCase();
      return id.startsWith('exp$expNum') || id.startsWith('exp-$expNum');
    });
    if (!betterCandidate) continue;

    issues.add(
      '  exp ${exp['id']} (${exp['title']}) -> $runId '
      '— linker picked a baseline-shaped run even though a candidate '
      '(exp$expNum-*) exists',
    );
  }
  if (issues.isEmpty) return;
  stderr.writeln(
    'Accepted experiments are linked to a baseline run when a candidate '
    'is available:\n'
    '${issues.join('\n')}\n'
    'This is usually the experiment->run linker picking the wrong file. '
    'Inspect `_attachBenchmarkRunMappings` in benchmark/generate_history.dart.',
  );
  exit(1);
}

/// The first experiment number for which a chartable experiment must either
/// link a benchmark run or explicitly declare that it has none. Experiments
/// below the cutoff predate the per-experiment-result-file convention (or the
/// `**Benchmark Run:**` opt-out header) and are grandfathered so the guard
/// targets only new work. Bump this only alongside a backfill pass that
/// annotates the older silently-unmapped experiments.
const int _benchmarkRunDeclarationCutoff = 178;

/// Catch the silent chart-invisibility failure the resqlite-experiment skill
/// warns about: a chartable experiment whose linker found *no* benchmark run
/// AND which never declared that absence. That happens when a runner forgets
/// to commit the `benchmark/results/<ts>-expNNN.md` file (or gives it a date
/// that does not match the doc's `**Date:**`). The experiment then quietly
/// drops off the chart with no error.
///
/// The repo already has the intended opt-out signal — a `**Benchmark Run:**`
/// header reading `none` / `n/a` / `tracelite` / ... (see
/// [_skipsReleaseBenchmarkRunMapping]) — for experiments measured with a
/// focused harness or Tracelite A/B rather than a release run. This guard
/// makes that declaration *mandatory* for a `null` run so a forgotten result
/// file is no longer indistinguishable from a deliberate "no release run".
///
/// Scoped to accepted/in-review experiments (the statuses the chart plots) at
/// or above [_benchmarkRunDeclarationCutoff]; rejected experiments commonly
/// and legitimately carry no release run, and pre-cutoff experiments are
/// grandfathered.
///
/// Pure detector used by [_assertNewExperimentsLinkOrDeclareRun]; returns one
/// human-readable issue line per offending experiment (empty when clean), so
/// the rule is unit-testable without the `exit(1)` side effect.
List<String> findUndeclaredMissingRunExperiments(
  List<Map<String, Object?>> experiments,
  Set<String> benchmarkRunOptOuts, {
  int cutoff = _benchmarkRunDeclarationCutoff,
}) {
  final issues = <String>[];
  for (final exp in experiments) {
    final status = exp['status'];
    if (status != 'accepted' && status != 'in_review') continue;
    if (exp['benchmarkRun'] != null) continue;

    final id = exp['id'] as String;
    final num = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), ''));
    if (num == null || num < cutoff) continue;

    // Declared "no release run" via the **Benchmark Run:** header — fine.
    if (benchmarkRunOptOuts.contains(id.toLowerCase())) continue;

    issues.add(
      '  exp $id (${exp['title']}, $status) has no linked benchmark run '
      'and no **Benchmark Run:** declaration',
    );
  }
  return issues;
}

void _assertNewExperimentsLinkOrDeclareRun(
  List<Map<String, Object?>> experiments,
  Set<String> benchmarkRunOptOuts,
) {
  final issues = findUndeclaredMissingRunExperiments(
    experiments,
    benchmarkRunOptOuts,
  );
  if (issues.isEmpty) return;
  stderr.writeln(
    'Chartable experiments are missing a benchmark run and a declaration of '
    'its absence:\n'
    '${issues.join('\n')}\n'
    'Either commit a benchmark/results/<timestamp>-expNNN.md whose date '
    "matches the experiment doc's **Date:**, or — if the experiment was "
    'measured with a focused harness or Tracelite A/B and has no release '
    'run — add a `**Benchmark Run:**` header to the experiment doc declaring '
    'that (e.g. `**Benchmark Run:** none (Tracelite A/B; ...)`). Without one, '
    'the experiment silently drops off the experiments chart. See '
    '`_assertNewExperimentsLinkOrDeclareRun` in '
    'benchmark/generate_history.dart.',
  );
  exit(1);
}

int? _pickClosestUnclaimedRun(
  List<int> candidates,
  int preferredIndex,
  Set<int> claimedRunIndices,
) {
  if (candidates.isEmpty) return null;

  for (var offset = 0; offset < candidates.length; offset++) {
    final left = preferredIndex - offset;
    if (left >= 0) {
      final candidate = candidates[left];
      if (!claimedRunIndices.contains(candidate)) return candidate;
    }

    if (offset == 0) continue;

    final right = preferredIndex + offset;
    if (right < candidates.length) {
      final candidate = candidates[right];
      if (!claimedRunIndices.contains(candidate)) return candidate;
    }
  }

  return null;
}

/// Parse experiment entries from the README.md table rows and individual files.
List<Map<String, Object?>> _parseExperimentsReadme(
  String readme,
  Directory experimentsDir,
  Set<String> allKeys,
) {
  final experiments = <Map<String, Object?>>[];
  final lines = readme.split('\n');

  // Match table rows like:
  // | [001](001-c-native-json-serialization.md) | C-native JSON serialization | 3.5x faster bytes path | [`4acfb57`](...) |
  // | [006](006-string-interning.md) | String interning | Hash lookup cost exceeded dedup savings |
  final rowPattern = RegExp(
    r'^\|\s*\[(\d+\w?)\]\(([^)]+)\)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|',
  );

  String currentStatus = 'accepted';

  for (final line in lines) {
    if (line.startsWith('## Accepted')) {
      currentStatus = 'accepted';
    } else if (line.startsWith('## In Review')) {
      currentStatus = 'in_review';
    } else if (line.startsWith('## Rejected')) {
      currentStatus = 'rejected';
    }

    final match = rowPattern.firstMatch(line);
    if (match == null) continue;

    final id = match.group(1)!;
    final filename = match.group(2)!;
    final title = match.group(3)!.trim();
    final impact = match
        .group(4)!
        .replaceAll(RegExp(r'\[`?[a-f0-9]+`?\]\([^)]*\)'), '')
        .replaceAll('|', '')
        .trim();

    // Read the individual experiment file for date, commit, and content.
    String? date;
    String? commit;
    String? archive;
    String? problem;
    String? hypothesis;
    final expFile = File('${experimentsDir.path}/$filename');
    if (expFile.existsSync()) {
      final content = expFile.readAsStringSync();
      final dateMatch = RegExp(
        r'\*\*Date:\*\*\s*(\d{4}-\d{2}-\d{2})',
      ).firstMatch(content);
      date = dateMatch?.group(1);
      final benchmarkRunHeader = _experimentHeaderValue(
        content,
        'Benchmark Run',
      );
      final skipBenchmarkRunMapping = _skipsReleaseBenchmarkRunMapping(
        benchmarkRunHeader,
      );
      final commitMatch = RegExp(
        r'\*\*Commit:\*\*\s*\[`?([a-f0-9]+)`?\]',
      ).firstMatch(content);
      commit = commitMatch?.group(1);
      // Archive tag — added for rejected experiments whose code was
      // preserved via `git tag archive/exp-NNN` before branch deletion.
      // See the resqlite-experiment skill doc for the workflow.
      final archiveMatch = RegExp(
        r'\*\*Archive:\*\*\s*\[`?(archive/[^`\]]+)`?\]',
      ).firstMatch(content);
      archive = archiveMatch?.group(1);
      problem =
          _extractSection(content, 'Problem') ??
          _extractSection(content, 'Background') ??
          _extractSection(content, 'Analysis');
      hypothesis = _extractSection(content, 'Hypothesis');
      // Try all known heading variants for implementation.
      final built =
          _extractSection(content, 'Approach') ??
          _extractSection(content, 'What We Built') ??
          _extractSection(content, 'What We Tested') ??
          _extractSection(content, 'What Changed') ??
          _extractSection(content, 'Change') ??
          _extractSection(content, 'Changes') ??
          _extractSection(content, 'Code Changes') ??
          _extractSection(content, 'Design') ??
          _extractSection(content, 'Approaches Tested');
      // Try all known heading variants for results.
      final results =
          _extractSection(content, 'Results') ??
          _extractSection(content, 'Result') ??
          _extractSection(content, 'Benchmark') ??
          _extractSection(content, 'Detailed Findings');
      // Try all known heading variants for reasoning.
      final whyAccepted =
          _extractSection(content, 'Decision') ??
          _extractSection(content, 'Why Accepted') ??
          _extractSection(content, 'Recommendation') ??
          _extractSection(content, 'Why It Works');
      final whyRejected =
          _extractSection(content, 'Why Rejected') ??
          _extractSection(content, 'Why It Failed') ??
          _extractSection(content, 'Takeaway');
      final primaryMetrics = _resolveMetricPatterns(
        _parseMetricPatterns(_extractSection(content, 'Primary Metrics')),
        allKeys,
      );
      final guardrailMetrics = _resolveMetricPatterns(
        _parseMetricPatterns(
          _extractSection(content, 'Guardrail Metrics') ??
              _extractSection(content, 'Guardrails'),
        ),
        allKeys,
      );

      experiments.add({
        'id': id,
        'title': title,
        'date': date ?? '',
        'status': currentStatus,
        'summary': impact,
        'commit': commit,
        if (skipBenchmarkRunMapping) '_skipBenchmarkRunMapping': true,
        if (archive != null) 'archive': archive,
        'problem': problem,
        'hypothesis': hypothesis,
        'approach': built,
        'results': results,
        'reasoning': whyAccepted ?? whyRejected,
        if (primaryMetrics.isNotEmpty) 'primaryMetrics': primaryMetrics,
        if (guardrailMetrics.isNotEmpty) 'guardrailMetrics': guardrailMetrics,
      });
    } else {
      experiments.add({
        'id': id,
        'title': title,
        'date': date ?? '',
        'status': currentStatus,
        'summary': impact,
        'commit': commit,
      });
    }
  }

  // Sort by experiment number.
  experiments.sort((a, b) {
    final aNum =
        int.tryParse((a['id'] as String).replaceAll(RegExp(r'[^0-9]'), '')) ??
        0;
    final bNum =
        int.tryParse((b['id'] as String).replaceAll(RegExp(r'[^0-9]'), '')) ??
        0;
    return aNum.compareTo(bNum);
  });

  return experiments;
}

String? _experimentHeaderValue(String content, String label) {
  final match = RegExp(
    '^\\*\\*${RegExp.escape(label)}:\\*\\*\\s*(.+)\$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(content);
  return match?.group(1)?.trim();
}

bool _skipsReleaseBenchmarkRunMapping(String? benchmarkRun) {
  if (benchmarkRun == null) return false;
  final normalized = benchmarkRun.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (normalized.startsWith('none')) return true;
  if (normalized.startsWith('n/a')) return true;
  if (normalized.startsWith('not applicable')) return true;
  // Tracelite A/B experiments keep their structured decision artifacts under
  // build/. They should not be auto-linked to same-day release benchmark runs.
  if (normalized.startsWith('tracelite')) return true;
  return false;
}

List<String> _parseMetricPatterns(String? section) {
  if (section == null || section.isEmpty) return const [];

  final patterns = <String>[];
  final seen = <String>{};
  for (final rawLine in section.split('\n')) {
    final line = rawLine.trim();
    if (!line.startsWith('- ') && !line.startsWith('* ')) continue;
    final pattern = line.substring(2).trim().replaceAll('`', '');
    if (pattern.isNotEmpty && seen.add(pattern)) {
      patterns.add(pattern);
    }
  }
  return patterns;
}

List<String> _resolveMetricPatterns(
  List<String> patterns,
  Set<String> allKeys,
) {
  if (patterns.isEmpty) return const [];

  final resolved = <String>[];
  final seen = <String>{};
  for (final pattern in patterns) {
    String? match;
    if (allKeys.contains(pattern) && !pattern.endsWith('[main]')) {
      match = pattern;
    } else {
      for (final key in allKeys) {
        if (key.endsWith('[main]')) continue;
        if (key.contains(pattern)) {
          match = key;
          break;
        }
      }
    }
    if (match != null && seen.add(match)) {
      resolved.add(match);
    }
  }
  return resolved;
}

/// Extract the full content of a `## Section` from markdown content,
/// up to the next `##` heading. Returns null if the section is not found.
String? _extractSection(String content, String sectionName) {
  final pattern = RegExp('^## $sectionName\\s*\n+', multiLine: true);
  final match = pattern.firstMatch(content);
  if (match == null) return null;

  final afterHeader = content.substring(match.end);
  // Take all lines until the next ## heading.
  final lines = <String>[];
  for (final line in afterHeader.split('\n')) {
    if (line.startsWith('## ')) break;
    lines.add(line);
  }

  // Join and trim trailing whitespace.
  final text = lines.join('\n').trim();
  if (text.isEmpty) return null;

  // Truncate very long sections to keep JSON manageable.
  return text.length > 800 ? '${text.substring(0, 797)}...' : text;
}
