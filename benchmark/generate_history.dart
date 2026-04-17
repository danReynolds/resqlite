// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'shared/parse_results.dart';

/// Generates `docs/experiments/history.json` from benchmark results and
/// experiment markdown files.
///
/// Usage:
///   dart run benchmark/generate_history.dart
Future<void> main() async {
  final resultsDir = Directory('benchmark/results');
  final experimentsDir = Directory('experiments');
  final outFile = File('docs/experiments/history.json');

  // 1. Parse all benchmark result files.
  final runs = <Map<String, Object?>>[];
  final mdFiles = resultsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in mdFiles) {
    final basename = file.path.split('/').last;
    final meta = parseFilenameMetadata(basename);
    if (meta == null) continue;

    final content = file.readAsStringSync();
    final metrics = extractResqliteMedians(content);
    if (metrics.isEmpty) {
      print('  Skipping $basename (no resqlite metrics found)');
      continue;
    }

    // Memory metrics come from a separate section of the markdown and
    // are optional (older results have no `## Memory` block). Captured
    // under a distinct namespace so chart code can treat them separately.
    final memory = extractMemoryMedians(content);
    final memoryJson = {
      for (final entry in memory.entries)
        entry.key: {
          'rssDeltaMedMB': entry.value.rssDeltaMedMB,
          'rssDeltaP90MB': entry.value.rssDeltaP90MB,
          'ciLowMB': entry.value.ciLowMB,
          'ciHighMB': entry.value.ciHighMB,
          'mdeMB': entry.value.mdeMB,
        },
    };

    runs.add({
      'id': meta.label,
      'date': meta.date,
      'timestamp': meta.timestamp,
      'label': meta.label,
      'metrics': metrics,
      if (memoryJson.isNotEmpty) 'memoryMetrics': memoryJson,
    });
  }

  print('Parsed ${runs.length} benchmark runs from ${mdFiles.length} files.');

  // 2. Parse experiments from the README table + individual files.
  final experiments = <Map<String, Object?>>[];

  if (experimentsDir.existsSync()) {
    final readmeFile = File('${experimentsDir.path}/README.md');
    if (readmeFile.existsSync()) {
      final readme = readmeFile.readAsStringSync();
      experiments.addAll(_parseExperimentsReadme(readme, experimentsDir));
    }
  }

  print('Parsed ${experiments.length} experiments.');

  // 3. Build the tracked metrics list — curated keys for default chart display.
  final tracked = <String>[];
  final allKeys = <String>{};
  for (final run in runs) {
    allKeys.addAll((run['metrics'] as Map<String, double>).keys);
  }

  // Find the best matching key for each desired metric.
  for (final pattern in _trackedPatterns) {
    final match = allKeys.firstWhere(
      (k) => k.contains(pattern),
      orElse: () => '',
    );
    if (match.isNotEmpty && !match.endsWith('[main]')) {
      tracked.add(match);
    }
  }

  // 4. Write JSON.
  await outFile.parent.create(recursive: true);

  final output = {
    'generated': DateTime.now().toIso8601String(),
    'runs': runs,
    'experiments': experiments,
    'tracked': tracked,
  };

  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );

  print('Wrote ${outFile.path} (${tracked.length} tracked metrics).');
  print('Tracked: ${tracked.join(', ')}');
}

/// Patterns used to find the curated tracked metrics from all available keys.
const _trackedPatterns = [
  '1000 rows / resqlite select()',
  '1000 rows / resqlite selectBytes()',
  'Wide (20 cols',
  'Single Inserts',
  'Batch Insert (1000 rows)',
  'Parameterized',
  'concurrent 4x',
  'Invalidation Latency',
  // Experiment 075 target: reactive streams where every re-query's
  // result is unchanged. First benchmark that specifically exercises
  // the worker-side hash short-circuit path.
  'Unchanged Fanout Throughput',
  'resqlite qps',
  // Scenario-level trajectories (Track A Phase 1+).
  'Keyed PK Subscriptions',
  // Chat Sim emits 4 op-type subsections; pattern matches "Chat Sim"
  // generically — the generator picks up the first match, which will
  // be the 'Insert message' op. For the full per-op picture, readers
  // consult the dashboard scenarios tab.
  'Chat Sim',
];

/// Parse experiment entries from the README.md table rows and individual files.
List<Map<String, Object?>> _parseExperimentsReadme(
  String readme,
  Directory experimentsDir,
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
    final impact = match.group(4)!
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
      final dateMatch = RegExp(r'\*\*Date:\*\*\s*(\d{4}-\d{2}-\d{2})').firstMatch(content);
      date = dateMatch?.group(1);
      final commitMatch = RegExp(r'\*\*Commit:\*\*\s*\[`?([a-f0-9]+)`?\]').firstMatch(content);
      commit = commitMatch?.group(1);
      // Archive tag — added for rejected experiments whose code was
      // preserved via `git tag archive/exp-NNN` before branch deletion.
      // See the resqlite-experiment skill doc for the workflow.
      final archiveMatch = RegExp(
        r'\*\*Archive:\*\*\s*\[`?(archive/[^`\]]+)`?\]',
      ).firstMatch(content);
      archive = archiveMatch?.group(1);
      problem = _extractSection(content, 'Problem') ??
          _extractSection(content, 'Background') ??
          _extractSection(content, 'Analysis');
      hypothesis = _extractSection(content, 'Hypothesis');
      // Try all known heading variants for implementation.
      final built = _extractSection(content, 'What We Built') ??
          _extractSection(content, 'What We Tested') ??
          _extractSection(content, 'What Changed') ??
          _extractSection(content, 'Change') ??
          _extractSection(content, 'Changes') ??
          _extractSection(content, 'Code Changes') ??
          _extractSection(content, 'Design') ??
          _extractSection(content, 'Approaches Tested');
      // Try all known heading variants for results.
      final results = _extractSection(content, 'Results') ??
          _extractSection(content, 'Result') ??
          _extractSection(content, 'Benchmark') ??
          _extractSection(content, 'Detailed Findings');
      // Try all known heading variants for reasoning.
      final whyAccepted = _extractSection(content, 'Decision') ??
          _extractSection(content, 'Why Accepted') ??
          _extractSection(content, 'Recommendation') ??
          _extractSection(content, 'Why It Works');
      final whyRejected = _extractSection(content, 'Why Rejected') ??
          _extractSection(content, 'Why It Failed') ??
          _extractSection(content, 'Takeaway');

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
    final aNum = int.tryParse(
          (a['id'] as String).replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
    final bNum = int.tryParse(
          (b['id'] as String).replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
    return aNum.compareTo(bNum);
  });

  return experiments;
}

/// Extract the full content of a `## Section` from markdown content,
/// up to the next `##` heading. Returns null if the section is not found.
String? _extractSection(String content, String sectionName) {
  final pattern = RegExp(
    '^## $sectionName\\s*\n+',
    multiLine: true,
  );
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
