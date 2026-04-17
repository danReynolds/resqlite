/// Unit test for the A11b high-cardinality stream fan-out workload.
///
/// Uses [runHighCardinalityFanoutBenchmarkSmallForTest] at reduced
/// scale (20 streams × 50 writes, no warmup, 1 iteration) so the test
/// completes in a few seconds. The production entry
/// [runHighCardinalityFanoutBenchmark] runs at 100 × 200 and takes
/// ~90s end-to-end, which is out of scope for a unit test per
/// METHODOLOGY.md § Adding a workload — Definition of Done.
library;

import 'package:test/test.dart';

import '../benchmark/suites/high_cardinality_fanout.dart';

void main() {
  group('High-Cardinality Stream Fan-out workload (A11b)', () {
    test('workload meta declares expected identity', () {
      expect(highCardinalityFanoutMeta.slug,
          equals('high_cardinality_fanout'));
      expect(highCardinalityFanoutMeta.version, equals(1));
      expect(highCardinalityFanoutMeta.sectionHeading,
          equals('High-Cardinality Stream Fan-out (v1)'));
      expect(highCardinalityFanoutMeta.metricKey,
          equals('high_cardinality_fanout_v1'));
    });

    test('runs end-to-end at reduced scale and emits expected shape',
        () async {
      final markdown =
          await runHighCardinalityFanoutBenchmarkSmallForTest();

      expect(markdown, contains('## High-Cardinality Stream Fan-out (v1)'));
      expect(markdown, contains('### 20 streams × 50 writes'));

      // Two reactive peers.
      expect(markdown, contains('| resqlite '));
      expect(markdown, contains('| sqlite_async '));
      expect(
        markdown,
        isNot(contains('| sqlite3 ')),
        reason: 'sqlite3 has no streams and must be omitted',
      );

      // 8-column header (Wall med/p90, Main med/p90, Init drain, Write
      // burst, Emissions plus the Library column).
      expect(
        markdown,
        contains('| Library | Wall med (ms) | Wall p90 (ms) | '
            'Main med (ms) | Main p90 (ms) | Init drain (ms) | '
            'Write burst (ms) | Emissions |'),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
