library;

import 'package:test/test.dart';

import '../benchmark/shared/release_reporting.dart';
import '../benchmark/shared/stats.dart';
import 'benchmark_pipeline_fixtures.dart';

void main() {
  group('release reporting', () {
    test('repeat stability reports bootstrap CI and CI-based MDE', () {
      final markdown = renderRepeatStability({
        'Select → Maps / 1000 rows / resqlite select()': AggregateStats([
          1.10,
          1.15,
          1.20,
          1.18,
          1.12,
        ]),
      });

      expect(markdown, contains('95% CI (ms)'));
      expect(markdown, contains('MDE_ci'));
      expect(markdown, contains('stable'));
    });

    test('release comparison reports CI-based decision context', () {
      final comparison = generateReleaseComparison(
        {
          'Select → Maps / 1000 rows / resqlite select()': AggregateStats([
            1.18,
            1.19,
            1.20,
            1.21,
            1.22,
          ]),
        },
        fixtureBenchmarkMarkdown,
        'baseline.md',
      );

      expect(comparison, contains('Decision threshold'));
      expect(comparison, contains('MDE_ci'));
      expect(
        comparison,
        contains('max(10%, 3 × current MAD%, current MDE_ci)'),
      );
      expect(
        comparison,
        anyOf(contains('⚪ Within noise'), contains('🟢 Win'), contains('🔴 Regression')),
      );
    });
  });

  group('aggregate stats', () {
    test('CI-aware decision threshold is never looser than MAD threshold', () {
      final stats = AggregateStats([1.0, 1.1, 1.2, 1.1, 1.0]);

      expect(
        stats.decisionThresholdPct(seed: 123),
        greaterThanOrEqualTo(stats.comparisonThresholdPct),
      );

      final ci = stats.medianCI(seed: 123);
      expect(ci.low, lessThanOrEqualTo(stats.median));
      expect(ci.high, greaterThanOrEqualTo(stats.median));
    });
  });
}
