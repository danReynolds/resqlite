// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'shared/parse_results.dart';
import 'shared/release_artifact.dart';
import 'shared/workload_registry.dart';

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

  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );

  final tracked = (output['tracked'] as List?)?.cast<String>() ?? const [];
  print('Wrote ${outFile.path} (${tracked.length} tracked metrics).');
  print('Tracked: ${tracked.join(', ')}');
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
    final content = sidecar == null ? file.readAsStringSync() : null;
    final metrics = sidecar != null
        ? artifactMetrics(sidecar)
        : extractResqliteMedians(content!);
    if (metrics.isEmpty) {
      print('  Skipping $basename (no resqlite metrics found)');
      continue;
    }

    final memoryJson = sidecar != null
        ? artifactMemoryMetrics(sidecar)
        : _memoryMetricsJson(extractMemoryMedians(content!));
    final environment = sidecar != null ? artifactEnvironment(sidecar) : null;
    final sqliteDiagnosticsJson = sidecar != null
        ? artifactSqliteDiagnosticsMetrics(sidecar)
        : _sqliteDiagnosticsJson(extractSqliteDiagnosticsMedians(content!));

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

  _attachBenchmarkRunMappings(experiments, runs);

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
        'readersBusy': entry.value.readersBusy,
      },
  };
}

void _attachBenchmarkRunMappings(
  List<Map<String, Object?>> experiments,
  List<Map<String, Object?>> runs,
) {
  final claimedRunIndices = <int>{};

  // First pass: exact explicit experiment-id matches in the run label,
  // e.g. experiment 088 -> run id "exp088-setlk-timeout".
  for (final exp in experiments) {
    final expNum = (exp['id'] as String).toLowerCase();
    final exactPatterns = ['exp$expNum', 'exp-$expNum'];
    int matchedIdx = -1;
    for (var idx = 0; idx < runs.length; idx++) {
      if (claimedRunIndices.contains(idx)) continue;
      final id = (runs[idx]['id'] as String? ?? '').toLowerCase();
      if (exactPatterns.any(id.contains)) {
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
