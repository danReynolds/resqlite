library;

import 'package:test/test.dart';

import '../benchmark/shared/release_artifact.dart';
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

  group('compareRelease gate', () {
    const lane = 'Select → Maps / 1000 rows / resqlite select()';
    Map<String, AggregateStats> tight(double median) => {
      lane: AggregateStats([median, median, median, median, median]),
    };

    test('a delta beyond the decision threshold counts and names the lane', () {
      final result = compareRelease(tight(2.0), {lane: 1.0}, 'prev.md');

      expect(result.hasRegression, isTrue);
      expect(result.regressions, 1);
      expect(result.regressedBenchmarks.single, contains(lane));
      expect(result.regressedBenchmarks.single, contains('+100'));
      expect(result.markdown, contains('🔴 Regression'));
    });

    test('an improvement counts as a win, not a regression', () {
      final result = compareRelease(tight(1.0), {lane: 2.0}, 'prev.md');

      expect(result.hasRegression, isFalse);
      expect(result.wins, 1);
    });

    test('qps lanes invert direction: higher current is a win', () {
      const qpsLane = 'Point Query Throughput / resqlite qps';
      final result = compareRelease(
        {
          qpsLane: AggregateStats([200.0, 200.0, 200.0, 200.0, 200.0]),
        },
        {qpsLane: 100.0},
        'prev.md',
      );

      expect(result.hasRegression, isFalse);
      expect(result.wins, 1);
    });

    test('the rendered table names which baseline side was compared', () {
      final result = compareRelease(
        tight(1.0),
        {lane: 1.0},
        'prev.md',
        previousSource: 'cross-repeat aggregate medians',
      );

      expect(result.markdown, contains('cross-repeat aggregate medians'));
    });

    group('shouldFailOnRegressions', () {
      ReleaseComparison regressing() =>
          compareRelease(tight(2.0), {lane: 1.0}, 'prev.md');

      test('fails only when the flag is passed and a regression exists', () {
        expect(
          shouldFailOnRegressions(
            failOnRegression: true,
            comparison: regressing(),
          ),
          isTrue,
        );
      });

      test('a regression without the flag does not fail the run', () {
        expect(
          shouldFailOnRegressions(
            failOnRegression: false,
            comparison: regressing(),
          ),
          isFalse,
        );
      });

      test('the flag alone does not fail a clean run', () {
        expect(
          shouldFailOnRegressions(
            failOnRegression: true,
            comparison: compareRelease(tight(1.0), {lane: 1.0}, 'prev.md'),
          ),
          isFalse,
        );
      });

      test('no comparison at all cannot fail the run', () {
        expect(
          shouldFailOnRegressions(failOnRegression: true, comparison: null),
          isFalse,
        );
      });
    });
  });

  group('artifactTrendMetrics', () {
    const lane = 'Streaming / Long-Text Unchanged Fanout / resqlite';

    test('prefers cross-repeat aggregate medians for multi-repeat runs', () {
      final artifact = <String, Object?>{
        'repeatCount': 5,
        'metrics': <String, Object?>{lane: 2.31},
        'repeatAggregates': <String, Object?>{
          lane: <String, Object?>{'median': 1.55, 'madPct': 5.3},
        },
      };

      expect(artifactTrendMetrics(artifact), {lane: 1.55});
    });

    test('single-repeat runs keep the representative metrics', () {
      final artifact = <String, Object?>{
        'repeatCount': 1,
        'metrics': <String, Object?>{lane: 2.31},
        'repeatAggregates': <String, Object?>{
          lane: <String, Object?>{'median': 1.55},
        },
      };

      expect(artifactTrendMetrics(artifact), {lane: 2.31});
    });

    test('missing or empty aggregates fall back to the representative', () {
      expect(
        artifactTrendMetrics(<String, Object?>{
          'repeatCount': 5,
          'metrics': <String, Object?>{lane: 2.31},
        }),
        {lane: 2.31},
      );
      expect(
        artifactTrendMetrics(<String, Object?>{
          'repeatCount': 5,
          'metrics': <String, Object?>{lane: 2.31},
          'repeatAggregates': <String, Object?>{},
        }),
        {lane: 2.31},
      );
    });
  });
}
