library;

import 'package:test/test.dart';

import '../benchmark/suites/point_query.dart';

void main() {
  group('adaptive point-query sampling', () {
    test('uses at least one batch and preserves sample count', () {
      final plan = planAdaptivePointQueryMeasurement(
        estimatedBatchUs: 4000,
      );

      expect(plan.batchesPerSample, greaterThanOrEqualTo(1));
      expect(plan.sampleCount, kPointQuerySampleCount);
    });

    test('increases batch size for faster estimated batches', () {
      final fast = planAdaptivePointQueryMeasurement(
        estimatedBatchUs: 1000,
      );
      final slow = planAdaptivePointQueryMeasurement(
        estimatedBatchUs: 10000,
      );

      expect(
        fast.batchesPerSample,
        greaterThanOrEqualTo(slow.batchesPerSample),
      );
    });

    test('summary describes the adaptive schedule', () {
      expect(
        summarizeAdaptivePointQueryPlan(),
        contains('${kPointQuerySampleCount} samples'),
      );
      expect(summarizeAdaptivePointQueryPlan(), contains('target'));
    });
  });
}
