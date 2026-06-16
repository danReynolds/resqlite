import 'package:test/test.dart';

import '../benchmark/shared/stats.dart';

void main() {
  group('cvPct', () {
    test('returns 0 for fewer than two samples', () {
      expect(cvPct([]), 0);
      expect(cvPct([5.0]), 0);
    });

    test('returns 0 when the mean is zero', () {
      expect(cvPct([-1.0, 1.0]), 0);
    });

    test('is near zero for a tight cluster', () {
      // exp 159 clean phase: CVs 0.01–0.06 (i.e. ~1–6%).
      expect(cvPct([100, 101, 99, 100, 102]), lessThan(2.0));
    });

    test('is large for a drift-contaminated phase', () {
      // exp 159 contaminated phase: CVs 0.20–0.46 (i.e. 20–46%).
      expect(cvPct([119, 165, 88, 140, 95]), greaterThan(20.0));
    });

    test('matches the textbook population CV', () {
      // mean 10, population stddev sqrt(2) -> CV = 14.142...%
      expect(cvPct([8, 12, 8, 12]), closeTo(20.0, 0.001));
    });
  });

  group('AbPass.deltaPct and flagged side', () {
    test('positive delta when candidate is slower; candidate is flagged', () {
      final pass = AbPass(
        baseline: [100, 100, 100],
        candidate: [110, 110, 110],
      );
      expect(pass.deltaPct, closeTo(10.0, 0.001));
      expect(pass.flaggedSideCvPct, pass.candidateCvPct);
      expect(pass.cleanSideCvPct, pass.baselineCvPct);
    });

    test('negative delta when candidate is faster; baseline is flagged', () {
      final pass = AbPass(
        baseline: [100, 100, 100],
        candidate: [90, 90, 90],
      );
      expect(pass.deltaPct, closeTo(-10.0, 0.001));
      expect(pass.flaggedSideCvPct, pass.baselineCvPct);
    });
  });

  group('classifyDriftFlag', () {
    test('exp159-shaped flag dissolves on the order flip -> drift', () {
      // Pass 1 flagged ~+19% with a noisy candidate phase; pass 2
      // order-flipped is neutral with tight CVs.
      final pass1 = AbPass(
        baseline: [100, 101, 99, 100, 102],
        candidate: [119, 165, 88, 140, 95],
      );
      final pass2 = AbPass(
        baseline: [100, 101, 99, 100, 102],
        candidate: [101, 102, 100, 101, 100],
      );
      final result = classifyDriftFlag(pass1, pass2);
      expect(result.verdict, DriftVerdict.driftSuspected);
      expect(result.worstFlaggedCvPct, greaterThan(20.0));
      expect(result.reason, contains('CV'));
    });

    test('same-direction effect with clean CVs -> reproduced', () {
      final pass1 = AbPass(
        baseline: [100, 101, 99, 100, 102],
        candidate: [112, 113, 111, 112, 113],
      );
      final pass2 = AbPass(
        baseline: [100, 99, 101, 100, 100],
        candidate: [113, 112, 112, 111, 113],
      );
      final result = classifyDriftFlag(pass1, pass2);
      expect(result.verdict, DriftVerdict.reproduced);
      expect(result.pass1DeltaPct, greaterThan(10.0));
      expect(result.pass2DeltaPct, greaterThan(10.0));
    });

    test('sign reversal across the flip with clean CVs -> drift', () {
      // exp 167 forEach lookup: +X% then -Y% with comparable, low CVs.
      final pass1 = AbPass(
        baseline: [100, 100, 100, 100],
        candidate: [107, 108, 106, 107],
      );
      final pass2 = AbPass(
        baseline: [100, 100, 100, 100],
        candidate: [92, 93, 91, 92],
      );
      final result = classifyDriftFlag(pass1, pass2);
      expect(result.verdict, DriftVerdict.driftSuspected);
      expect(result.reason, contains('reversed sign'));
    });

    test('both passes below the effect floor -> inconclusive/neutral', () {
      final pass1 = AbPass(
        baseline: [100, 100, 100, 100],
        candidate: [101, 101, 100, 101],
      );
      final pass2 = AbPass(
        baseline: [100, 100, 100, 100],
        candidate: [99, 100, 100, 101],
      );
      final result = classifyDriftFlag(pass1, pass2);
      expect(result.verdict, DriftVerdict.inconclusive);
      expect(result.reason, contains('floor'));
    });

    test('fewer than two runs on any side is inconclusive', () {
      final pass1 = AbPass(baseline: [100], candidate: [120]);
      final pass2 = AbPass(
        baseline: [100, 100],
        candidate: [101, 101],
      );
      final result = classifyDriftFlag(pass1, pass2);
      expect(result.verdict, DriftVerdict.inconclusive);
      expect(result.reason, contains('>= 2 runs'));
    });

    test('CV asymmetry condemns even a same-direction pair', () {
      // Both passes positive and material, but pass 2's candidate phase is
      // wildly noisier than its baseline -> contaminated, drift-suspected.
      final pass1 = AbPass(
        baseline: [100, 101, 99, 100],
        candidate: [112, 113, 111, 112],
      );
      final pass2 = AbPass(
        baseline: [100, 101, 99, 100],
        candidate: [160, 90, 175, 85],
      );
      final result = classifyDriftFlag(pass1, pass2);
      expect(result.verdict, DriftVerdict.driftSuspected);
    });

    test('thresholds are tunable', () {
      // A 5% same-direction effect is reproduced under the default 3%
      // floor but inconclusive if the floor is raised to 8%.
      final pass1 = AbPass(
        baseline: [100, 100, 100, 100],
        candidate: [105, 105, 105, 105],
      );
      final pass2 = AbPass(
        baseline: [100, 100, 100, 100],
        candidate: [105, 105, 105, 105],
      );
      expect(classifyDriftFlag(pass1, pass2).verdict, DriftVerdict.reproduced);
      expect(
        classifyDriftFlag(
          pass1,
          pass2,
          thresholds: const DriftFlagThresholds(effectFloorPct: 8.0),
        ).verdict,
        DriftVerdict.inconclusive,
      );
    });
  });
}
