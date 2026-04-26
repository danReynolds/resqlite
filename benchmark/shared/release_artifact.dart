import 'dart:convert';
import 'dart:io';

import 'parse_results.dart';
import 'stats.dart';

Map<String, Object?> buildReleaseRunArtifact({
  required String label,
  required int repeatCount,
  required String markdown,
  required Map<String, AggregateStats> aggregates,
  Map<String, Object?>? environment,
  String? comparisonBaselineFile,
  String? generatedAt,
}) {
  final metrics = extractResqliteMedians(markdown);
  final memory = extractMemoryMedians(markdown);
  final sqliteDiagnostics = extractSqliteDiagnosticsMedians(markdown);
  final streamingColumn = extractStreamingColumnMedians(markdown);
  final benchmarkSummary = _benchmarkSummaryJson(parseBenchmarkSections(markdown));

  return {
    'schemaVersion': 3,
    'kind': 'release-benchmark-run',
    'generatedAt': generatedAt ?? DateTime.now().toIso8601String(),
    'label': label,
    'repeatCount': repeatCount,
    if (environment != null && environment.isNotEmpty)
      'environment': environment,
    if (comparisonBaselineFile != null)
      'comparisonBaselineFile': comparisonBaselineFile,
    'metrics': metrics,
    if (memory.isNotEmpty) 'memoryMetrics': _memoryMetricsJson(memory),
    if (sqliteDiagnostics.isNotEmpty)
      'sqliteDiagnosticsMetrics': _sqliteDiagnosticsJson(sqliteDiagnostics),
    if (streamingColumn.isNotEmpty)
      'streamingColumnMetrics': _streamingColumnJson(streamingColumn),
    if (aggregates.isNotEmpty) 'repeatAggregates': _aggregatesJson(aggregates),
    if (benchmarkSummary.isNotEmpty) 'benchmarkSummary': benchmarkSummary,
  };
}

Map<String, Object?>? loadReleaseArtifactSidecarForMarkdown(File markdownFile) {
  final jsonPath = markdownFile.path.replaceFirst(RegExp(r'\.md$'), '.json');
  final jsonFile = File(jsonPath);
  if (!jsonFile.existsSync()) return null;
  final decoded = json.decode(jsonFile.readAsStringSync());
  return decoded is Map<String, Object?> ? decoded : null;
}

Map<String, double> artifactMetrics(Map<String, Object?> artifact) {
  return _doubleMap(artifact['metrics']);
}

Map<String, Object?>? artifactEnvironment(Map<String, Object?> artifact) {
  final value = artifact['environment'];
  return value is Map<String, Object?> ? value : null;
}

Map<String, Object?>? artifactMemoryMetrics(Map<String, Object?> artifact) {
  final value = artifact['memoryMetrics'];
  return value is Map<String, Object?> ? value : null;
}

Map<String, Object?>? artifactSqliteDiagnosticsMetrics(
  Map<String, Object?> artifact,
) {
  final value = artifact['sqliteDiagnosticsMetrics'];
  return value is Map<String, Object?> ? value : null;
}

int? artifactRepeatCount(Map<String, Object?> artifact) {
  final value = artifact['repeatCount'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// Read sqlite3's `Single Inserts (100 sequential)` wall numbers out of a
/// release-run sidecar's `benchmarkSummary` payload.
Sqlite3SingleInsertWall artifactSqlite3SingleInsertWall(
  Map<String, Object?> artifact,
) {
  final summary = artifact['benchmarkSummary'];
  if (summary is! Map) return const Sqlite3SingleInsertWall();
  final sectionsValue = summary['sections'];
  if (sectionsValue is! List) return const Sqlite3SingleInsertWall();
  for (final section in sectionsValue) {
    if (section is! Map) continue;
    if (section['title'] != 'Write Performance') continue;
    if (section['subtitle'] != 'Single Inserts (100 sequential)') continue;
    final entries = section['entries'];
    if (entries is! List) continue;
    for (final entry in entries) {
      if (entry is! List || entry.length != 2) continue;
      if (entry[0] != 'sqlite3 execute()') continue;
      final values = entry[1];
      if (values is! List || values.isEmpty) continue;
      final med = values.isNotEmpty ? values[0] : null;
      final p90 = values.length > 1 ? values[1] : null;
      return Sqlite3SingleInsertWall(
        medianMs: med is num ? med.toDouble() : null,
        p90Ms: p90 is num ? p90.toDouble() : null,
      );
    }
  }
  return const Sqlite3SingleInsertWall();
}

List<Map<String, Object?>>? artifactBenchmarks(Map<String, Object?> artifact) {
  final summary = artifact['benchmarkSummary'];
  if (summary is Map) {
    final sectionsValue = summary['sections'];
    if (sectionsValue is List) {
      final sections = <Map<String, Object?>>[];
      for (final section in sectionsValue) {
        if (section is! Map) continue;
        final title = section['title']?.toString();
        if (title == null || title.isEmpty) continue;
        final subtitle = section['subtitle']?.toString();
        final entriesValue = section['entries'];
        final entries = <Map<String, Object?>>[];
        if (entriesValue is List) {
          for (final rawEntry in entriesValue) {
            if (rawEntry is List && rawEntry.length == 2) {
              final library = rawEntry[0]?.toString();
              final values = rawEntry[1];
              if (library == null || values is! List) continue;
              entries.add({
                'library': library,
                'values': [
                  for (final value in values)
                    if (value == null)
                      null
                    else
                      (value as num).toDouble(),
                ],
              });
            }
          }
        }
        sections.add({
          'key': subtitle != null && subtitle.isNotEmpty
              ? '$title / $subtitle'
              : title,
          'title': title,
          'subtitle': subtitle,
          'entries': entries,
        });
      }
      if (sections.isNotEmpty) return sections;
    }
  }

  final value = artifact['benchmarks'];
  if (value is! List) return null;
  return [
    for (final entry in value)
      if (entry is Map<String, Object?>)
        entry
      else
        Map<String, Object?>.from(entry as Map),
  ];
}

List<Map<String, Object?>> parseBenchmarkSections(String content) {
  final sections = <Map<String, Object?>>[];
  final lines = content.split('\n');

  String? currentSection;
  String? currentSubsection;

  for (final line in lines) {
    if (line.startsWith('## ')) {
      currentSection = line.substring(3).trim();
      currentSubsection = null;
      if (currentSection.startsWith('Comparison') ||
          currentSection.startsWith('Repeat') ||
          currentSection.startsWith('resqlite Benchmark')) {
        currentSection = null;
      }
      continue;
    }
    if (line.startsWith('### ')) {
      currentSubsection = line.substring(4).trim();
      continue;
    }

    if (currentSection == null) continue;
    if (!line.startsWith('|') || line.contains('---')) continue;

    final cells = line
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (cells.length < 2) continue;

    final firstCell = cells[0].toLowerCase();
    if (firstCell == 'library' ||
        firstCell == 'rows' ||
        firstCell == 'concurrency' ||
        firstCell == 'n') {
      continue;
    }

    final sectionKey = currentSubsection != null
        ? '$currentSection / $currentSubsection'
        : currentSection;

    final section = sections.firstWhere(
      (s) => s['key'] == sectionKey,
      orElse: () {
        final created = <String, Object?>{
          'key': sectionKey,
          'title': currentSection,
          'subtitle': currentSubsection,
          'entries': <Map<String, Object?>>[],
        };
        sections.add(created);
        return created;
      },
    );

    final entries = section['entries'] as List<Map<String, Object?>>;
    final library = cells[0];
    final values = <double?>[];
    for (var i = 1; i < cells.length; i++) {
      values.add(double.tryParse(cells[i]));
    }

    entries.add({'library': library, 'values': values});
  }

  return sections;
}

Map<String, Object?> _aggregatesJson(Map<String, AggregateStats> aggregates) {
  return {
    for (final entry in aggregates.entries)
      entry.key: {
        'median': entry.value.median,
        'madPct': entry.value.madPct,
        'stability': entry.value.stability,
        'comparisonThresholdPct': entry.value.comparisonThresholdPct,
      },
  };
}

Map<String, Object?> _benchmarkSummaryJson(List<Map<String, Object?>> sections) {
  return {
    'sections': [
      for (final section in sections)
        {
          'title': section['title'],
          if (section['subtitle'] case final subtitle?)
            if (subtitle.toString().isNotEmpty) 'subtitle': subtitle,
          'entries': [
            for (final entry in (section['entries'] as List<Map<String, Object?>>))
              [entry['library'], entry['values']],
          ],
        },
    ],
  };
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

Map<String, Object?> _streamingColumnJson(
  Map<String, StreamingColumnMetric> streamingColumn,
) {
  return {
    for (final entry in streamingColumn.entries)
      entry.key: {
        'reemits': entry.value.reemits,
        'drainMs': entry.value.drainMs,
        'ratio': entry.value.ratio,
      },
  };
}

Map<String, double> _doubleMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      entry.key.toString(): (entry.value as num).toDouble(),
  };
}
