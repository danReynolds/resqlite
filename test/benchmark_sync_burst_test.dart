/// Unit test for the A7 sync burst workload (opt-in / slow).
///
/// Per METHODOLOGY.md § DoD: asserts behavior (subsections present,
/// peer coverage), not timing. Runs A7 once at its production scale
/// so the test is real — if a change breaks A7 end-to-end, the test
/// catches it. A7 is already short enough (~10-30s on M1 Pro) that
/// running it at full scale in CI is acceptable.
library;

import 'package:test/test.dart';

import '../benchmark/suites/sync_burst.dart';

void main() {
  group('Sync Burst workload (A7)', () {
    test('workload meta declares expected identity', () {
      expect(syncBurstMeta.slug, equals('sync_burst'));
      expect(syncBurstMeta.version, equals(1));
      expect(syncBurstMeta.sectionHeading, equals('Sync Burst (v1)'));
      expect(syncBurstMeta.metricKey, equals('sync_burst_v1'));
    });

    test('runs end-to-end and emits expected subsections', () async {
      final markdown = await runSyncBurstBenchmark();

      expect(markdown, contains('## Sync Burst (v1)'));
      expect(
        markdown,
        contains(
            '### Bulk insert: 50000 rows × 500-row chunks'),
      );
      expect(
        markdown,
        contains('### Merge rounds: 10 × 100 rows'),
      );
      expect(
        markdown,
        contains('### Stream emissions during burst (COUNT(*))'),
      );

      // Bulk + merges: all three peers.
      expect(markdown, contains('| resqlite '));
      expect(markdown, contains('| sqlite3 '));
      expect(markdown, contains('| sqlite_async '));

      // Stream emissions subsection: only reactive peers; sqlite3
      // has no streams so it should not appear in that table.
      final streamIdx =
          markdown.indexOf('### Stream emissions during burst');
      expect(streamIdx, isPositive);
      final streamSection = markdown.substring(streamIdx);
      expect(streamSection, contains('| resqlite |'));
      expect(streamSection, contains('| sqlite_async |'));
      expect(
        streamSection,
        isNot(contains('| sqlite3 |')),
        reason: 'sqlite3 has no streams — must be omitted from the '
            'stream-emissions subsection',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
