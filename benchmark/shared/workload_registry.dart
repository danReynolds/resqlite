/// Curated benchmark metadata shared by benchmark generators and docs.
///
/// This is intentionally small and opinionated: it captures the
/// benchmark keys we want surfaced by default on the experiments page,
/// along with their short labels and chart grouping. The source keys
/// still come from parsed benchmark results; this registry only decides
/// which ones matter for the default experience.

final class CuratedMetricDefinition {
  const CuratedMetricDefinition({
    required this.pattern,
    required this.displayName,
    required this.chartId,
  });

  /// Substring used to resolve the canonical metric key from the parsed
  /// benchmark result set.
  final String pattern;

  /// Short label shown on charts and delta pills.
  final String displayName;

  /// Destination chart group on the experiments page.
  final String chartId;
}

final class ResolvedMetricCatalog {
  const ResolvedMetricCatalog({
    required this.tracked,
    required this.metricDisplay,
    required this.chartGroups,
  });

  final List<String> tracked;
  final Map<String, String> metricDisplay;
  final Map<String, List<String>> chartGroups;
}

/// Fixed chart order used by the experiments page.
const experimentChartIds = [
  'chartReads',
  'chartWrites',
  'chartTransactions',
  'chartConcurrency',
  'chartScenarios',
  'chartReactiveMicros',
  'chartThroughput',
];

/// Curated metrics for the experiments page.
const curatedMetricDefinitions = [
  CuratedMetricDefinition(
    pattern: '1000 rows / resqlite select()',
    displayName: 'select() 1K rows',
    chartId: 'chartReads',
  ),
  CuratedMetricDefinition(
    pattern: '1000 rows / resqlite selectBytes()',
    displayName: 'selectBytes() 1K rows',
    chartId: 'chartReads',
  ),
  CuratedMetricDefinition(
    pattern: 'Wide (20 cols',
    displayName: 'schema wide 20 cols',
    chartId: 'chartReads',
  ),
  CuratedMetricDefinition(
    pattern: 'Single Inserts',
    displayName: 'single inserts (100)',
    chartId: 'chartWrites',
  ),
  CuratedMetricDefinition(
    pattern: 'Batch Insert (1000 rows)',
    displayName: 'batch insert 1K',
    chartId: 'chartWrites',
  ),
  CuratedMetricDefinition(
    pattern: 'Wide Batch Insert (10000 rows x 20 params)',
    displayName: 'wide batch 10K x20',
    chartId: 'chartWrites',
  ),
  CuratedMetricDefinition(
    pattern: 'Interactive Transaction',
    displayName: 'interactive tx',
    chartId: 'chartTransactions',
  ),
  CuratedMetricDefinition(
    pattern: 'Transaction Read (1000 rows)',
    displayName: 'tx read 1K rows',
    chartId: 'chartTransactions',
  ),
  CuratedMetricDefinition(
    pattern: 'Batched Write Inside Transaction (1000 rows)',
    displayName: 'tx batch 1K rows',
    chartId: 'chartTransactions',
  ),
  CuratedMetricDefinition(
    pattern: 'Parameterized',
    displayName: 'parameterized 100q',
    chartId: 'chartConcurrency',
  ),
  CuratedMetricDefinition(
    pattern: 'concurrent 4x',
    displayName: 'concurrent 4x',
    chartId: 'chartConcurrency',
  ),
  CuratedMetricDefinition(
    pattern: 'Reactive feed with 100 concurrent writes',
    displayName: 'feed reactive (A6)',
    chartId: 'chartScenarios',
  ),
  CuratedMetricDefinition(
    pattern: 'Sync Burst',
    displayName: 'sync burst bulk (A7)',
    chartId: 'chartScenarios',
  ),
  CuratedMetricDefinition(
    pattern: 'Keyed PK Subscriptions',
    displayName: 'keyed subscriptions (A11)',
    chartId: 'chartScenarios',
  ),
  CuratedMetricDefinition(
    pattern: 'High-Cardinality Stream Fan-out',
    displayName: 'fan-out (A11b)',
    chartId: 'chartScenarios',
  ),
  CuratedMetricDefinition(
    pattern: 'Many-Streams Writer Throughput',
    displayName: 'writer fanout (A11c)',
    chartId: 'chartScenarios',
  ),
  CuratedMetricDefinition(
    pattern: 'Invalidation Latency',
    displayName: 'invalidation latency',
    chartId: 'chartReactiveMicros',
  ),
  CuratedMetricDefinition(
    pattern: 'Fan-out (10 streams)',
    displayName: 'fan-out 10 streams',
    chartId: 'chartReactiveMicros',
  ),
  CuratedMetricDefinition(
    pattern: 'Stream Churn (100 cycles)',
    displayName: 'stream churn 100 cycles',
    chartId: 'chartReactiveMicros',
  ),
  CuratedMetricDefinition(
    pattern: 'Unchanged Fanout Throughput',
    displayName: 'unchanged fanout',
    chartId: 'chartReactiveMicros',
  ),
  // The 32KB definition must come before the generic "Long-Text Unchanged
  // Fanout" pattern so the more specific 32KB key is claimed first; the
  // generic pattern is a substring of the 32KB one, so the order matters
  // for `resolveCuratedMetrics`'s `usedKeys` book-keeping.
  CuratedMetricDefinition(
    pattern: 'Long-Text 32KB Unchanged Fanout',
    displayName: 'long-text 32KB unchanged',
    chartId: 'chartReactiveMicros',
  ),
  CuratedMetricDefinition(
    pattern: 'Long-Text Unchanged Fanout',
    displayName: 'long-text unchanged',
    chartId: 'chartReactiveMicros',
  ),
  CuratedMetricDefinition(
    pattern: 'resqlite qps',
    displayName: 'point query qps',
    chartId: 'chartThroughput',
  ),
];

ResolvedMetricCatalog resolveCuratedMetrics(Iterable<String> allKeys) {
  final keys = allKeys.toList();
  final tracked = <String>[];
  final metricDisplay = <String, String>{};
  final chartGroups = {
    for (final chartId in experimentChartIds) chartId: <String>[],
  };
  final usedKeys = <String>{};

  for (final definition in curatedMetricDefinitions) {
    final key = keys.cast<String?>().firstWhere(
      (candidate) =>
          candidate != null &&
          !candidate.endsWith('[main]') &&
          !usedKeys.contains(candidate) &&
          candidate.contains(definition.pattern),
      orElse: () => null,
    );
    if (key == null) continue;

    tracked.add(key);
    metricDisplay[key] = definition.displayName;
    chartGroups[definition.chartId]!.add(key);
    usedKeys.add(key);
  }

  return ResolvedMetricCatalog(
    tracked: tracked,
    metricDisplay: metricDisplay,
    chartGroups: chartGroups,
  );
}
