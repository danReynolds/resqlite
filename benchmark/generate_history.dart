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

    runs.add({
      'id': meta.label,
      'date': meta.date,
      'timestamp': meta.timestamp,
      'label': meta.label,
      'metrics': metrics,
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
  'resqlite qps',
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
    String? problem;
    String? hypothesis;
    final expFile = File('${experimentsDir.path}/$filename');
    if (expFile.existsSync()) {
      final content = expFile.readAsStringSync();
      final dateMatch = RegExp(r'\*\*Date:\*\*\s*(\d{4}-\d{2}-\d{2})').firstMatch(content);
      date = dateMatch?.group(1);
      final commitMatch = RegExp(r'\*\*Commit:\*\*\s*\[`?([a-f0-9]+)`?\]').firstMatch(content);
      commit = commitMatch?.group(1);
      problem = _extractSection(content, 'Problem');
      hypothesis = _extractSection(content, 'Hypothesis');
    }

    experiments.add({
      'id': id,
      'title': title,
      'date': date ?? '',
      'status': currentStatus,
      'summary': impact,
      'commit': commit,
      'problem': problem,
      'hypothesis': hypothesis,
    });
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

/// Extract the first paragraph of a `## Section` from markdown content.
/// Returns null if the section is not found.
String? _extractSection(String content, String sectionName) {
  final pattern = RegExp(
    '^## $sectionName\n+',
    multiLine: true,
  );
  final match = pattern.firstMatch(content);
  if (match == null) return null;

  final afterHeader = content.substring(match.end);
  // Take lines until the next heading or blank-line gap.
  final lines = <String>[];
  for (final line in afterHeader.split('\n')) {
    if (line.startsWith('## ') || (lines.isNotEmpty && line.trim().isEmpty)) {
      break;
    }
    if (line.trim().isNotEmpty) lines.add(line.trim());
  }
  if (lines.isEmpty) return null;
  final text = lines.join(' ');
  // Truncate long sections to keep JSON reasonable.
  return text.length > 500 ? '${text.substring(0, 497)}...' : text;
}
