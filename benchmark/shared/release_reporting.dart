import 'dart:math' as math;

import 'parse_results.dart';
import 'stats.dart';

const _releaseBootstrapSeed = 0x51A6E11;

Map<String, AggregateStats> aggregateRunMetrics(
  List<Map<String, double>> runMetrics,
) {
  final buckets = <String, List<double>>{};
  for (final run in runMetrics) {
    for (final entry in run.entries) {
      buckets.putIfAbsent(entry.key, () => <double>[]).add(entry.value);
    }
  }
  return {
    for (final entry in buckets.entries) entry.key: AggregateStats(entry.value),
  };
}

String renderRepeatStability(Map<String, AggregateStats> aggregates) {
  final buf = StringBuffer();
  buf.writeln('## Repeat Stability');
  buf.writeln();
  buf.writeln(
    'These rows summarize resqlite wall medians across repeated full-suite runs.',
  );
  buf.writeln(
    'Use this section to judge whether small deltas are real or just noise.',
  );
  buf.writeln();
  buf.writeln(
    '| Benchmark | Median (ms) | 95% CI (ms) | MDE_ci | Range | MAD | Stability |',
  );
  buf.writeln('|---|---|---|---|---|---|---|');

  final keys = aggregates.keys.toList()..sort();
  for (final key in keys) {
    final stats = aggregates[key]!;
    final ci = stats.medianCI(seed: _releaseBootstrapSeed);
    final mdeCiPct = stats.ciMdePct(seed: _releaseBootstrapSeed);
    final shortKey = key.length > 70 ? '${key.substring(0, 67)}...' : key;
    buf.writeln(
      '| $shortKey '
      '| ${stats.median.toStringAsFixed(2)} '
      '| ${ci.low.toStringAsFixed(2)}..${ci.high.toStringAsFixed(2)} '
      '| ${mdeCiPct.toStringAsFixed(1)}% '
      '| ${stats.rangePct.toStringAsFixed(1)}% '
      '| ${stats.madPct.toStringAsFixed(1)}% '
      '| ${stats.stability} |',
    );
  }
  buf.writeln();
  return buf.toString();
}

/// A release comparison's rendered table plus the verdict a caller can act on.
///
/// Same split the memory comparison got in [EXP-262]: the table has always
/// named 🔴 regressions, but nothing could ever *fail* on one — which is how a
/// lane can regress in the very run that measured it and still merge unnoticed.
/// Exposing the counts is what makes [shouldFailOnRegressions] possible.
final class ReleaseComparison {
  const ReleaseComparison({
    required this.markdown,
    required this.wins,
    required this.regressions,
    required this.neutral,
    required this.regressedBenchmarks,
  });

  final String markdown;
  final int wins;
  final int regressions;
  final int neutral;

  /// Benchmark names that regressed beyond their threshold, with the delta, in
  /// the order they appear in the table.
  final List<String> regressedBenchmarks;

  bool get hasRegression => regressions > 0;

  /// Nothing to compare (no shared lanes, or an unparseable side).
  const ReleaseComparison.empty(this.markdown)
    : wins = 0,
      regressions = 0,
      neutral = 0,
      regressedBenchmarks = const [];
}

/// Whether a run should fail because of wall-time regressions. Mirrors
/// [shouldFailOnMemory]; extracted so the decision is testable on its own.
bool shouldFailOnRegressions({
  required bool failOnRegression,
  required ReleaseComparison? comparison,
}) => failOnRegression && comparison != null && comparison.hasRegression;

/// Render-only wrapper kept for callers that just want the table, comparing
/// against the previous run's representative-repeat tables in [previousContent].
String generateReleaseComparison(
  Map<String, AggregateStats> current,
  String previousContent,
  String previousFileName,
) => compareRelease(
  current,
  extractResqliteMedians(previousContent),
  previousFileName,
).markdown;

/// Compare current aggregates against a previous run's per-lane medians.
///
/// [previous] should be the previous run's cross-repeat aggregate medians
/// (`artifactTrendMetrics`) when its sidecar exists — comparing against its
/// representative-repeat tables instead puts one noisy repeat on the baseline
/// side of every delta. [previousSource] names which of the two the caller
/// supplied, so the rendered table says what it compared.
ReleaseComparison compareRelease(
  Map<String, AggregateStats> current,
  Map<String, double> previous,
  String previousFileName, {
  String previousSource = 'representative-repeat tables',
}) {
  if (current.isEmpty || previous.isEmpty) {
    return const ReleaseComparison.empty(
      '## Comparison\n\nCould not parse results for comparison.\n',
    );
  }

  final buf = StringBuffer();
  buf.writeln('## Comparison vs Previous Run');
  buf.writeln();
  buf.writeln('Previous: `$previousFileName` ($previousSource)');
  buf.writeln();
  buf.writeln(
    '| Benchmark | Previous (ms) | Current med (ms) | Delta | Decision threshold | MDE_ci | Stability | Status |',
  );
  buf.writeln('|---|---|---|---|---|---|---|---|');

  var wins = 0;
  var regressions = 0;
  var neutral = 0;
  final regressed = <String>[];

  final allKeys = current.keys.where(previous.containsKey).toList()..sort();

  for (final key in allKeys) {
    final prev = previous[key]!;
    final stats = current[key]!;
    final curr = stats.median;
    final delta = curr - prev;
    final pct = prev > 0 ? (delta / prev * 100) : 0.0;
    final mdeCiPct = stats.ciMdePct(seed: _releaseBootstrapSeed);
    final thresholdPct = stats.decisionThresholdPct(
      seed: _releaseBootstrapSeed,
    );
    final thresholdMs = math.max(
      AggregateStats.minimumComparisonThresholdMs,
      math.max(prev, curr) * (thresholdPct / 100),
    );

    final higherIsBetter = key.contains('qps');
    final improvementDelta = higherIsBetter ? -delta : delta;

    String status;
    if (improvementDelta < -thresholdMs) {
      status = '🟢 Win (${pct.toStringAsFixed(0)}%)';
      wins++;
    } else if (improvementDelta > thresholdMs) {
      status =
          '🔴 Regression (${pct > 0 ? '+' : ''}${pct.toStringAsFixed(0)}%)';
      regressions++;
      regressed.add('$key (${pct > 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)');
    } else {
      status = stats.runs.length > 1 ? '⚪ Within noise' : '⚪ Neutral';
      neutral++;
    }

    final shortKey = key.length > 60 ? '${key.substring(0, 57)}...' : key;
    buf.writeln(
      '| $shortKey '
      '| ${prev.toStringAsFixed(2)} '
      '| ${curr.toStringAsFixed(2)} '
      '| ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} '
      '| ±${thresholdPct.toStringAsFixed(0)}% / ±${thresholdMs.toStringAsFixed(2)} ms '
      '| ${mdeCiPct.toStringAsFixed(1)}% '
      '| ${stats.stability} '
      '| $status |',
    );
  }

  buf.writeln();
  buf.writeln(
    '**Summary:** $wins wins, $regressions regressions, $neutral neutral',
  );
  buf.writeln();
  buf.writeln(
    'Decision threshold uses `max(10%, 3 × current MAD%, current MDE_ci)`, '
    'plus an absolute floor of `±0.02 ms`.',
  );
  buf.writeln(
    'MDE_ci is the 95% bootstrap-CI half-width around the repeated-run median. '
    'That keeps stable cases sensitive while treating noisy and ultra-fast cases '
    'more conservatively.',
  );
  buf.writeln();

  if (regressions > 0) {
    buf.writeln(
      '⚠️ **Regressions detected beyond current-run noise.** Review the flagged benchmarks above.',
    );
  } else if (wins > 0) {
    buf.writeln(
      '✅ **No regressions beyond noise.** $wins benchmarks improved.',
    );
  } else {
    buf.writeln('✅ **No changes beyond noise.**');
  }
  buf.writeln();

  return ReleaseComparison(
    markdown: buf.toString(),
    wins: wins,
    regressions: regressions,
    neutral: neutral,
    regressedBenchmarks: regressed,
  );
}

/// A memory comparison's rendered table plus the verdict a caller can act on.
///
/// [EXP-262](../../experiments/262-release-scenario-persistence.md): the table
/// has always named regressions; nothing could ever *fail* on one, which is what
/// the long-open "per-benchmark RSS acceptance criteria" candidate was asking
/// for. Splitting the counts out of the markdown is what makes a gate possible.
final class MemoryComparison {
  const MemoryComparison({
    required this.markdown,
    required this.wins,
    required this.regressions,
    required this.neutral,
    required this.regressedBenchmarks,
  });

  /// Empty when neither run carried a `## Memory` section.
  final String markdown;

  final int wins;
  final int regressions;
  final int neutral;

  /// Benchmark names that regressed beyond their threshold, with the delta, in
  /// the order they appear in the table.
  final List<String> regressedBenchmarks;

  bool get hasRegression => regressions > 0;

  /// Neither run carried a `## Memory` section, so there is nothing to render
  /// and nothing to gate on.
  const MemoryComparison.empty()
    : markdown = '',
      wins = 0,
      regressions = 0,
      neutral = 0,
      regressedBenchmarks = const [];
}

/// Whether a run should fail because of memory.
///
/// Extracted so the decision is testable on its own. It shipped in review
/// unable to fail anything — the runner set the global `exitCode` and then
/// called `exit(0)`, which discards it — and the unit tests of [compareMemory]
/// could not have caught that, because they tested the comparison rather than
/// what the caller did with it.
bool shouldFailOnMemory({
  required bool failOnMemoryRegression,
  required MemoryComparison? comparison,
}) => failOnMemoryRegression && comparison != null && comparison.hasRegression;

/// Render-only wrapper kept for callers that just want the table.
String generateMemoryComparison(
  String currentMarkdown,
  String previousContent,
) => compareMemory(currentMarkdown, previousContent).markdown;

MemoryComparison compareMemory(String currentMarkdown, String previousContent) {
  final current = extractMemoryMedians(currentMarkdown);
  final previous = extractMemoryMedians(previousContent);

  if (current.isEmpty && previous.isEmpty)
    return const MemoryComparison.empty();

  final buf = StringBuffer();
  buf.writeln('## Memory Comparison vs Previous Run');
  buf.writeln();

  if (current.isEmpty) {
    buf.writeln('Current run has no `## Memory` section.');
    buf.writeln();
    return MemoryComparison(
      markdown: buf.toString(),
      wins: 0,
      regressions: 0,
      neutral: 0,
      regressedBenchmarks: const [],
    );
  }
  if (previous.isEmpty) {
    buf.writeln(
      'Previous run has no `## Memory` section — baseline unavailable. '
      'Current values recorded for next-run comparison.',
    );
    buf.writeln();
    return MemoryComparison(
      markdown: buf.toString(),
      wins: 0,
      regressions: 0,
      neutral: 0,
      regressedBenchmarks: const [],
    );
  }

  buf.writeln('| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |');
  buf.writeln('|---|---|---|---|---|---|');

  const minThresholdMB = 0.5;

  var wins = 0;
  var regressions = 0;
  var neutral = 0;
  final regressed = <String>[];

  final keys = current.keys.where(previous.containsKey).toList()..sort();
  for (final key in keys) {
    final prev = previous[key]!.rssDeltaMedMB;
    final currM = current[key]!;
    final curr = currM.rssDeltaMedMB;
    final delta = curr - prev;
    final threshold = math.max(minThresholdMB, currM.mdeMB);

    String status;
    if (delta < -threshold) {
      status = '🟢 Win (${delta.toStringAsFixed(2)} MB)';
      wins++;
    } else if (delta > threshold) {
      status = '🔴 Regression (+${delta.toStringAsFixed(2)} MB)';
      regressions++;
      regressed.add('$key (+${delta.toStringAsFixed(2)} MB)');
    } else {
      status = '⚪ Within MDE';
      neutral++;
    }

    final shortKey = key.length > 60 ? '${key.substring(0, 57)}...' : key;
    buf.writeln(
      '| $shortKey '
      '| ${prev.toStringAsFixed(2)} '
      '| ${curr.toStringAsFixed(2)} '
      '| ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} MB '
      '| ±${threshold.toStringAsFixed(2)} MB '
      '| $status |',
    );
  }

  buf.writeln();
  buf.writeln(
    '**Memory summary:** $wins wins, $regressions regressions, $neutral neutral',
  );
  buf.writeln();
  buf.writeln(
    'Threshold uses per-benchmark MDE (95% bootstrap CI half-width on '
    'the median), with a `±0.5 MB` floor. RSS deltas are still a **lower '
    'bound** on real allocation change — the VM retains heap pages after '
    'GC, so sub-MDE wins may be real but invisible here.',
  );
  buf.writeln();

  return MemoryComparison(
    markdown: buf.toString(),
    wins: wins,
    regressions: regressions,
    neutral: neutral,
    regressedBenchmarks: regressed,
  );
}

String generateStreamingColumnComparison(
  String currentMarkdown,
  String previousContent,
) {
  final current = extractStreamingColumnMedians(currentMarkdown);
  final previous = extractStreamingColumnMedians(previousContent);

  if (current.isEmpty && previous.isEmpty) return '';

  final buf = StringBuffer();
  buf.writeln('## Streaming (Column Granularity) Comparison');
  buf.writeln();

  if (current.isEmpty) {
    buf.writeln(
      'Current run has no `## Streaming (Column Granularity)` section.',
    );
    buf.writeln();
    return buf.toString();
  }
  if (previous.isEmpty) {
    buf.writeln(
      'Previous run has no `## Streaming (Column Granularity)` section — '
      'baseline unavailable. Current values recorded for next-run '
      'comparison.',
    );
    buf.writeln();
    return buf.toString();
  }

  buf.writeln(
    '| Benchmark | Prev re-emits | Curr re-emits | Delta | Threshold | Status |',
  );
  buf.writeln('|---|---|---|---|---|---|');

  const reemitThreshold = 100;

  var wins = 0;
  var regressions = 0;
  var neutral = 0;

  final keys = current.keys.where(previous.containsKey).toList()..sort();
  for (final key in keys) {
    final prev = previous[key]!.reemits;
    final curr = current[key]!.reemits;
    final delta = curr - prev;

    final isOverlapping = key.toLowerCase().contains('overlapping');
    String status;
    if (delta.abs() <= reemitThreshold) {
      status = '⚪ Within noise';
      neutral++;
    } else if (isOverlapping) {
      status = delta < 0
          ? '🔴 Invalidation elided ($delta) — writes not firing'
          : '🔴 More re-emits (+$delta)';
      regressions++;
    } else {
      if (delta < 0) {
        status = '🟢 Fewer re-emits ($delta)';
        wins++;
      } else {
        status = '🔴 More re-emits (+$delta)';
        regressions++;
      }
    }

    final shortKey = key.length > 60 ? '${key.substring(0, 57)}...' : key;
    buf.writeln(
      '| $shortKey '
      '| $prev '
      '| $curr '
      '| ${delta >= 0 ? '+' : ''}$delta '
      '| ±$reemitThreshold '
      '| $status |',
    );
  }

  buf.writeln();
  buf.writeln(
    '**Granularity summary:** $wins fewer-re-emit, $regressions more-re-emit, $neutral neutral',
  );
  buf.writeln();
  buf.writeln(
    'For **disjoint** workloads, fewer re-emits means tighter dependency '
    'tracking — a library with column-level tracking approaches zero. '
    'For **overlapping** workloads, the count should stay stable across '
    'runs; a drop there means writes are being silently elided.',
  );
  buf.writeln();

  return buf.toString();
}
