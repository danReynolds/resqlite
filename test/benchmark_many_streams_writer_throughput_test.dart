/// Unit test for the A11c many-streams writer-throughput workload.
///
/// Uses [runManyStreamsWriterThroughputBenchmarkSmallForTest] at reduced
/// scale (5 streams × 30 writes, no warmup, 1 iteration) so the test
/// completes in a few seconds. The production entry
/// [runManyStreamsWriterThroughputBenchmark] runs at 50 × 500 × 3
/// iterations × 3 peers and takes minutes end-to-end, which is out of
/// scope for a unit test per METHODOLOGY.md § Adding a workload —
/// Definition of Done.
library;

import 'package:test/test.dart';

import '../benchmark/suites/many_streams_writer_throughput.dart';

void main() {
  group('Many-Streams Writer Throughput workload (A11c)', () {
    test('workload meta declares expected identity', () {
      expect(manyStreamsWriterMeta.slug, equals('many_streams_writer'));
      expect(manyStreamsWriterMeta.version, equals(1));
      expect(
        manyStreamsWriterMeta.sectionHeading,
        equals('Many-Streams Writer Throughput (v1)'),
      );
      expect(manyStreamsWriterMeta.metricKey, equals('many_streams_writer_v1'));
    });

    test(
      'runs end-to-end at reduced scale and emits expected shape',
      () async {
        final markdown =
            await runManyStreamsWriterThroughputBenchmarkSmallForTest();

        expect(markdown, contains('## Many-Streams Writer Throughput (v1)'));
        expect(markdown, contains('### 5 streams × 30 writes per scenario'));

        // Reactive peers: resqlite, sqlite_async, drift.
        expect(markdown, contains('| resqlite '));
        expect(markdown, contains('| sqlite_async '));
        expect(markdown, contains('| drift '));
        expect(
          markdown,
          isNot(contains('| sqlite3 ')),
          reason: 'sqlite3 has no streams and must be omitted',
        );

        // Three subsections: baseline, disjoint, overlap, plus the
        // ratio summary table.
        expect(
          markdown,
          contains('### No-streams baseline (30 writes, no subscribers)'),
        );
        expect(
          markdown,
          contains(
            '### Disjoint column writes (SET c = ?, projection = id, a, b)',
          ),
        );
        expect(
          markdown,
          contains(
            '### Overlapping column writes (SET a = ?, projection = id, a, b)',
          ),
        );
        expect(
          markdown,
          contains('### Overlap-vs-disjoint writer-throughput ratio'),
        );

        // 6-column header for baseline (Library + 4 timing + Writes/sec).
        expect(
          markdown,
          contains(
            '| Library | Wall med (ms) | Wall p90 (ms) | '
            'Main med (ms) | Main p90 (ms) | Writes/sec |',
          ),
        );
        // 7-column header for scenario sections (adds Emissions).
        expect(
          markdown,
          contains(
            '| Library | Wall med (ms) | Wall p90 (ms) | '
            'Main med (ms) | Main p90 (ms) | Writes/sec | Emissions |',
          ),
        );
        // 4-column ratio table.
        expect(
          markdown,
          contains(
            '| Library | Disjoint w/s | Overlap w/s | Overlap/disjoint |',
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
