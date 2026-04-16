import 'dart:math' as math;

/// Aggregate statistics across repeated runs of a metric.
///
/// Moved from `run_all.dart` to support new suites that need noise-aware
/// thresholds (memory, disjoint-column streaming, point-query stability).
/// Behavior matches the prior private `_AggregateStats` exactly.
final class AggregateStats {
  static const double minimumComparisonThresholdPct = 10.0;
  static const double minimumComparisonThresholdMs = 0.02;

  AggregateStats(List<double> values)
      : runs = List<double>.from(values)..sort();

  factory AggregateStats.from(List<double> samples) =>
      AggregateStats(samples);

  final List<double> runs;

  double get median => medianOfSorted(runs);
  double get min => runs.first;
  double get max => runs.last;
  double get rangePct => median == 0 ? 0 : ((max - min) / median) * 100;

  double get madPct {
    if (runs.length == 1 || median == 0) return 0;
    final deviations = [
      for (final value in runs) (value - median).abs(),
    ]..sort();
    return (medianOfSorted(deviations) / median) * 100;
  }

  String get stability {
    if (runs.length == 1) return 'single run';
    if (madPct <= 3) return 'stable';
    if (madPct <= 8) return 'moderate';
    return 'noisy';
  }

  double get comparisonThresholdPct =>
      math.max(minimumComparisonThresholdPct, madPct * 3.0);
}

/// Median of a pre-sorted list. Returns 0 for an empty list.
double medianOfSorted(List<double> sortedValues) {
  if (sortedValues.isEmpty) return 0;
  final mid = sortedValues.length ~/ 2;
  if (sortedValues.length.isOdd) return sortedValues[mid];
  return (sortedValues[mid - 1] + sortedValues[mid]) / 2;
}

/// Percentile bootstrap CI on the median.
///
/// Resamples [samples] with replacement [resamples] times, computes the
/// median of each resample, and returns the (low, high) percentiles
/// corresponding to [confidence].
///
/// Deterministic when [seed] is provided — useful for tests and for
/// stable CI values across runs of the same data.
({double low, double high}) bootstrapMedianCI(
  List<double> samples, {
  double confidence = 0.95,
  int resamples = 2000,
  int? seed,
}) {
  if (samples.isEmpty) return (low: 0, high: 0);
  if (samples.length == 1) return (low: samples.first, high: samples.first);

  final rng = seed != null ? math.Random(seed) : math.Random();
  final n = samples.length;
  final medians = List<double>.filled(resamples, 0);
  final buffer = List<double>.filled(n, 0);

  for (var r = 0; r < resamples; r++) {
    for (var i = 0; i < n; i++) {
      buffer[i] = samples[rng.nextInt(n)];
    }
    buffer.sort();
    medians[r] = medianOfSorted(buffer);
  }

  medians.sort();
  final tail = (1 - confidence) / 2;
  final lowIdx = (tail * resamples).floor().clamp(0, resamples - 1);
  final highIdx = ((1 - tail) * resamples).ceil().clamp(0, resamples - 1);
  return (low: medians[lowIdx], high: medians[highIdx]);
}

/// Minimum detectable effect (%) using CI half-width relative to the median.
///
/// Falls back to `rangePct` when n < 5 (bootstrap CIs are unreliable on
/// very small samples).
double minimumDetectableEffectPct(
  List<double> samples, {
  double confidence = 0.95,
  int resamples = 2000,
}) {
  if (samples.isEmpty) return 0;
  final stats = AggregateStats(samples);
  if (samples.length < 5) return stats.rangePct;
  final median = stats.median;
  if (median == 0) return 0;
  final ci = bootstrapMedianCI(samples,
      confidence: confidence, resamples: resamples);
  final halfWidth = (ci.high - ci.low) / 2;
  return (halfWidth / median) * 100;
}

/// MAD-based detectable effect (%) — matches the existing comparison
/// threshold (`3 × MAD%`). Useful to print alongside CI-based MDE so the
/// value lines up with the acceptance heuristic already in `run_all.dart`.
double madBasedDetectableEffectPct(List<double> samples) {
  if (samples.isEmpty) return 0;
  return AggregateStats(samples).madPct * 3.0;
}

final class BenchmarkTiming {
  BenchmarkTiming(this.label);

  final String label;
  final List<int> wallUs = [];
  final List<int> mainUs = [];

  void record({required int wallMicroseconds, required int mainMicroseconds}) {
    wallUs.add(wallMicroseconds);
    mainUs.add(mainMicroseconds);
  }

  void recordWallOnly(int wallMicroseconds) {
    wallUs.add(wallMicroseconds);
    mainUs.add(wallMicroseconds); // synchronous = all on main
  }

  Stats get wall => Stats(wallUs);
  Stats get main => Stats(mainUs);
}

/// Computed statistics (median, p90, mean) for a set of timing samples.
final class Stats {
  Stats(List<int> raw) : _sorted = List.of(raw)..sort();

  final List<int> _sorted;

  double get medianMs => _sorted[_sorted.length ~/ 2] / 1000.0;
  double get p90Ms => _sorted[(_sorted.length * 0.9).floor()] / 1000.0;
  double get meanMs {
    final sum = _sorted.fold<int>(0, (a, b) => a + b);
    return sum / _sorted.length / 1000.0;
  }
}

String fmtMs(double ms) => ms.toStringAsFixed(2).padLeft(8);

/// Print a comparison table for a set of timings at a given row count.
void printComparisonTable(String title, List<BenchmarkTiming> timings) {
  print('');
  print(title);
  print('-' * title.length);
  print('');

  final labelWidth = timings.map((t) => t.label.length).reduce(math.max) + 2;

  print(
    '${'Library'.padRight(labelWidth)}'
    '${'Wall med'.padLeft(10)}'
    '${'Wall p90'.padLeft(10)}'
    '${'Main med'.padLeft(10)}'
    '${'Main p90'.padLeft(10)}',
  );
  print('${''.padRight(labelWidth, '-')}'
      '${''.padRight(10, '-')}'
      '${''.padRight(10, '-')}'
      '${''.padRight(10, '-')}'
      '${''.padRight(10, '-')}');

  for (final t in timings) {
    print(
      '${t.label.padRight(labelWidth)}'
      '${fmtMs(t.wall.medianMs)} ms'
      '${fmtMs(t.wall.p90Ms)} ms'
      '${fmtMs(t.main.medianMs)} ms'
      '${fmtMs(t.main.p90Ms)} ms',
    );
  }
  print('');
}

/// Generate markdown table for a set of timings.
String markdownTable(String title, List<BenchmarkTiming> timings) {
  final buf = StringBuffer();
  buf.writeln('### $title');
  buf.writeln('');
  buf.writeln(
    '| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |',
  );
  buf.writeln('|---|---|---|---|---|');
  for (final t in timings) {
    buf.writeln(
      '| ${t.label} '
      '| ${t.wall.medianMs.toStringAsFixed(2)} '
      '| ${t.wall.p90Ms.toStringAsFixed(2)} '
      '| ${t.main.medianMs.toStringAsFixed(2)} '
      '| ${t.main.p90Ms.toStringAsFixed(2)} |',
    );
  }
  buf.writeln('');
  return buf.toString();
}
