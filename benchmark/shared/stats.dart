import 'dart:math' as math;

/// Aggregate statistics across repeated runs of a metric.
///
/// Moved from `run_release.dart` to support new suites that need noise-aware
/// thresholds (memory, disjoint-column streaming, point-query stability).
/// Behavior matches the prior private `_AggregateStats` exactly.
final class AggregateStats {
  static const double minimumComparisonThresholdPct = 10.0;
  static const double minimumComparisonThresholdMs = 0.02;
  static const double defaultConfidence = 0.95;
  static const int defaultBootstrapResamples = 2000;

  AggregateStats(List<double> values)
    : runs = List<double>.from(values)..sort();

  factory AggregateStats.from(List<double> samples) => AggregateStats(samples);

  final List<double> runs;

  double get median => medianOfSorted(runs);
  double get min => runs.first;
  double get max => runs.last;
  double get rangePct => median == 0 ? 0 : ((max - min) / median) * 100;

  double get madPct {
    if (runs.length == 1 || median == 0) return 0;
    final deviations = [for (final value in runs) (value - median).abs()]
      ..sort();
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

  ({double low, double high}) medianCI({
    double confidence = defaultConfidence,
    int resamples = defaultBootstrapResamples,
    int? seed,
  }) => bootstrapMedianCI(
    runs,
    confidence: confidence,
    resamples: resamples,
    seed: seed,
  );

  double ciMdePct({
    double confidence = defaultConfidence,
    int resamples = defaultBootstrapResamples,
    int? seed,
  }) => minimumDetectableEffectPct(
    runs,
    confidence: confidence,
    resamples: resamples,
    seed: seed,
  );

  double get madMdePct => madBasedDetectableEffectPct(runs);

  double decisionThresholdPct({
    double confidence = defaultConfidence,
    int resamples = defaultBootstrapResamples,
    int? seed,
  }) => math.max(
    comparisonThresholdPct,
    ciMdePct(confidence: confidence, resamples: resamples, seed: seed),
  );
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
  // Percentile indices for a 0-indexed sorted array: for (1-tail)=0.975
  // and n=2000, we want the value at rank 1950 (1-indexed), i.e. index
  // 1949 (0-indexed). Using `ceil - 1` on the high end makes the
  // resulting interval width match the stated confidence exactly when
  // `tail * resamples` is integer, and stays within 1/resamples
  // otherwise. Copilot flagged the prior formulation as off-by-one.
  final lowIdx = (tail * resamples).floor().clamp(0, resamples - 1);
  final highIdx = (((1 - tail) * resamples).ceil() - 1).clamp(0, resamples - 1);
  return (low: medians[lowIdx], high: medians[highIdx]);
}

/// Minimum detectable effect (%) using CI half-width relative to the median.
///
/// Falls back to `rangePct` when n < 5 (bootstrap CIs are unreliable on
/// very small samples).
///
/// Pass [seed] to get stable MDE values across repeated invocations on
/// the same data — matches the determinism contract of [bootstrapMedianCI].
/// Callers that print "deterministic, seed=..." in their output headers
/// must thread their seed through here, otherwise the printed MDE will
/// drift across re-runs even with identical samples.
double minimumDetectableEffectPct(
  List<double> samples, {
  double confidence = 0.95,
  int resamples = 2000,
  int? seed,
}) {
  if (samples.isEmpty) return 0;
  final stats = AggregateStats(samples);
  if (samples.length < 5) return stats.rangePct;
  final median = stats.median;
  if (median == 0) return 0;
  final ci = bootstrapMedianCI(
    samples,
    confidence: confidence,
    resamples: resamples,
    seed: seed,
  );
  final halfWidth = (ci.high - ci.low) / 2;
  return (halfWidth / median) * 100;
}

/// MAD-based detectable effect (%) — matches the existing comparison
/// threshold (`3 × MAD%`). Useful to print alongside CI-based MDE so the
/// value lines up with the acceptance heuristic already in `run_release.dart`.
double madBasedDetectableEffectPct(List<double> samples) {
  if (samples.isEmpty) return 0;
  return AggregateStats(samples).madPct * 3.0;
}

/// Coefficient of variation (stddev / mean) as a percentage.
///
/// This is the *within-side, within-pass* dispersion the JOURNAL's
/// "Phase-ordered A/B gates confound code deltas with time-correlated
/// drift" lesson tells runners to inspect: when a phase-ordered A/B flags
/// a regression, the flagged phase's per-run CV is the first thing to
/// check, because a drift-contaminated phase shows a much higher CV than
/// the clean phase (exp 159 saw 0.20–0.46 on the contaminated phase vs
/// 0.01–0.06 on the clean one). Uses the population stddev (divide by n)
/// to match the CV figures recorded in prior `*-aggregate.md` files.
///
/// Returns 0 for fewer than two samples or a zero/empty mean (no
/// meaningful dispersion to report).
double cvPct(List<double> samples) {
  if (samples.length < 2) return 0;
  final mean = samples.reduce((a, b) => a + b) / samples.length;
  if (mean == 0) return 0;
  final variance =
      samples.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
      samples.length;
  return (math.sqrt(variance) / mean.abs()) * 100;
}

/// How a phase-ordered A/B regression flag should be read once a second,
/// order-flipped pass exists.
enum DriftVerdict {
  /// Both passes agree on a same-direction, materially-sized effect and
  /// neither side is unusually noisy — the flag is a real code effect.
  reproduced,

  /// The flag did not survive the order flip: the effect changed sign
  /// between passes, or it only appeared in a pass whose flagged side was
  /// far noisier than its counterpart. This is the exp 159 signature —
  /// machine drift that landed on one time block.
  driftSuspected,

  /// Not enough comparable data to classify (a pass is missing runs, or
  /// every reading is below [DriftFlagThresholds.effectFloorPct]).
  inconclusive,
}

/// Tunable thresholds for [classifyDriftFlag]. Defaults match the
/// heuristics recorded across exp 144 / 159 / 167 / 171 / 173 aggregates.
final class DriftFlagThresholds {
  const DriftFlagThresholds({
    this.cvAsymmetryRatio = 4.0,
    this.cleanCvPct = 8.0,
    this.effectFloorPct = 3.0,
  });

  /// A flagged side whose CV is at least this many times its counterpart's
  /// CV (and above [cleanCvPct]) is treated as drift-contaminated. Exp 159
  /// saw ~0.30 vs ~0.03 — a 10× gap; 4× is a conservative trigger.
  final double cvAsymmetryRatio;

  /// A flagged-side CV at or below this percent is "clean enough" that
  /// asymmetry alone does not condemn the pass.
  final double cleanCvPct;

  /// Median deltas with magnitude below this percent are treated as no
  /// effect, so a sign change between two sub-floor passes is not read as
  /// a meaningful reversal.
  final double effectFloorPct;
}

/// Per-pass A/B reading for one scenario: the baseline and candidate
/// per-run values collected within a single collection pass.
final class AbPass {
  AbPass({required this.baseline, required this.candidate, this.label});

  final List<double> baseline;
  final List<double> candidate;
  final String? label;

  /// Candidate-vs-baseline median delta as a percent of the baseline
  /// median. Positive = candidate slower (regression direction).
  double get deltaPct {
    final b = AggregateStats(baseline).median;
    final c = AggregateStats(candidate).median;
    if (b == 0) return 0;
    return ((c - b) / b) * 100;
  }

  double get baselineCvPct => cvPct(baseline);
  double get candidateCvPct => cvPct(candidate);

  /// The CV of the side that carries the regression. When the candidate is
  /// slower (positive delta), drift would inflate the candidate side; when
  /// faster, the baseline side. This is the phase whose noise the JOURNAL
  /// lesson says to inspect first.
  double get flaggedSideCvPct => deltaPct >= 0 ? candidateCvPct : baselineCvPct;

  double get cleanSideCvPct => deltaPct >= 0 ? baselineCvPct : candidateCvPct;
}

/// Result of classifying a flagged scenario across two order-flipped passes.
final class DriftClassification {
  const DriftClassification({
    required this.verdict,
    required this.reason,
    required this.pass1DeltaPct,
    required this.pass2DeltaPct,
    required this.worstFlaggedCvPct,
  });

  final DriftVerdict verdict;
  final String reason;
  final double pass1DeltaPct;
  final double pass2DeltaPct;

  /// The larger of the two passes' flagged-side CVs — the headline noise
  /// number to print next to the verdict.
  final double worstFlaggedCvPct;
}

/// Mechanizes the JOURNAL's order-flipped drift check for one scenario.
///
/// [pass1] is the standard-order pass that produced the flag; [pass2] is
/// the order-flipped confirmation pass (candidate collected first). The
/// classifier reproduces, by rule, the manual reasoning runners have been
/// applying by hand in every recent `*-aggregate.md`:
///
/// 1. If either pass's flagged side is far noisier than its clean side
///    (CV asymmetry above [DriftFlagThresholds.cvAsymmetryRatio] and above
///    [DriftFlagThresholds.cleanCvPct]), the effect is *drift-suspected* —
///    the flagged phase caught a drift block (exp 159).
/// 2. Else if the two passes disagree on sign (one materially positive,
///    one materially negative), the flag did not survive the flip —
///    *drift-suspected* (exp 167's reversed `forEach lookup`).
/// 3. Else if both passes show a same-direction effect above the floor,
///    the flag is *reproduced*.
/// 4. Otherwise (both below floor, or missing data) it is *inconclusive* —
///    typically meaning "neutral, no real effect".
DriftClassification classifyDriftFlag(
  AbPass pass1,
  AbPass pass2, {
  DriftFlagThresholds thresholds = const DriftFlagThresholds(),
}) {
  if (pass1.baseline.length < 2 ||
      pass1.candidate.length < 2 ||
      pass2.baseline.length < 2 ||
      pass2.candidate.length < 2) {
    return DriftClassification(
      verdict: DriftVerdict.inconclusive,
      reason: 'each side of each pass needs >= 2 runs to classify',
      pass1DeltaPct: pass1.deltaPct,
      pass2DeltaPct: pass2.deltaPct,
      worstFlaggedCvPct: math.max(
        pass1.flaggedSideCvPct,
        pass2.flaggedSideCvPct,
      ),
    );
  }

  final worstFlaggedCv = math.max(
    pass1.flaggedSideCvPct,
    pass2.flaggedSideCvPct,
  );

  bool isContaminated(AbPass pass) {
    final flagged = pass.flaggedSideCvPct;
    final clean = pass.cleanSideCvPct;
    if (flagged <= thresholds.cleanCvPct) return false;
    if (clean == 0) return true;
    return flagged / clean >= thresholds.cvAsymmetryRatio;
  }

  if (isContaminated(pass1) || isContaminated(pass2)) {
    return DriftClassification(
      verdict: DriftVerdict.driftSuspected,
      reason:
          'flagged-side CV asymmetry (worst flagged CV '
          '${worstFlaggedCv.toStringAsFixed(1)}%) indicates a '
          'drift-contaminated phase, not a code effect',
      pass1DeltaPct: pass1.deltaPct,
      pass2DeltaPct: pass2.deltaPct,
      worstFlaggedCvPct: worstFlaggedCv,
    );
  }

  final d1 = pass1.deltaPct;
  final d2 = pass2.deltaPct;
  final d1Material = d1.abs() >= thresholds.effectFloorPct;
  final d2Material = d2.abs() >= thresholds.effectFloorPct;

  if (d1Material && d2Material && (d1 > 0) != (d2 > 0)) {
    return DriftClassification(
      verdict: DriftVerdict.driftSuspected,
      reason:
          'effect reversed sign across the order flip '
          '(${d1.toStringAsFixed(1)}% then ${d2.toStringAsFixed(1)}%); '
          'flag did not survive',
      pass1DeltaPct: d1,
      pass2DeltaPct: d2,
      worstFlaggedCvPct: worstFlaggedCv,
    );
  }

  if (d1Material && d2Material) {
    return DriftClassification(
      verdict: DriftVerdict.reproduced,
      reason:
          'same-direction effect in both passes '
          '(${d1.toStringAsFixed(1)}% then ${d2.toStringAsFixed(1)}%) '
          'with comparable per-side CVs',
      pass1DeltaPct: d1,
      pass2DeltaPct: d2,
      worstFlaggedCvPct: worstFlaggedCv,
    );
  }

  return DriftClassification(
    verdict: DriftVerdict.inconclusive,
    reason:
        'both passes below the ${thresholds.effectFloorPct.toStringAsFixed(0)}% '
        'effect floor (${d1.toStringAsFixed(1)}% then '
        '${d2.toStringAsFixed(1)}%) — read as neutral',
    pass1DeltaPct: d1,
    pass2DeltaPct: d2,
    worstFlaggedCvPct: worstFlaggedCv,
  );
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

/// Computed statistics (median, p90, p99, max, mean) for a set of timing
/// samples.
///
/// The `p99Ms` and `maxMs` getters are intentionally NOT surfaced in the
/// release-mode markdown tables emitted by `run_release.dart` — those
/// tables feed the public dashboard, and their column layout is
/// consumed by downstream parsers (`parse_results.dart`,
/// `generate_devices.dart`, `generate_history.dart`, the dashboard JS
/// in `docs/benchmarks/index.html`). Adding columns would silently
/// break column-index-based extraction.
///
/// Profile-mode harnesses read these getters directly. New experiments use
/// `benchmark/profile/run_tracelite_profile.dart`; p99/max are where
/// tail-latency regressions actually hide.
final class Stats {
  Stats(List<int> raw) : _sorted = List.of(raw)..sort();

  final List<int> _sorted;

  double get medianMs => _sorted[_sorted.length ~/ 2] / 1000.0;
  double get p90Ms => _sorted[(_sorted.length * 0.9).floor()] / 1000.0;

  /// 99th percentile. Surfaces tail-latency regressions that p90 misses —
  /// exp 083 showed passive WAL checkpoints drove p99 +57% on merge
  /// workloads while p50/p90 were unchanged.
  double get p99Ms => _sorted[(_sorted.length * 0.99).floor()] / 1000.0;

  /// Maximum observed timing. Useful for spotting outlier spikes (GC
  /// pauses, OS scheduler preemption, filesystem variability) that
  /// don't move percentiles but can drop frames in a UI app.
  double get maxMs => _sorted.last / 1000.0;

  double get meanMs {
    final sum = _sorted.fold<int>(0, (a, b) => a + b);
    return sum / _sorted.length / 1000.0;
  }
}

String fmtMs(double ms) => ms.toStringAsFixed(3).padLeft(9);

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
  print(
    '${''.padRight(labelWidth, '-')}'
    '${''.padRight(10, '-')}'
    '${''.padRight(10, '-')}'
    '${''.padRight(10, '-')}'
    '${''.padRight(10, '-')}',
  );

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
      '| ${t.wall.medianMs.toStringAsFixed(3)} '
      '| ${t.wall.p90Ms.toStringAsFixed(3)} '
      '| ${t.main.medianMs.toStringAsFixed(3)} '
      '| ${t.main.p90Ms.toStringAsFixed(3)} |',
    );
  }
  buf.writeln('');
  return buf.toString();
}
