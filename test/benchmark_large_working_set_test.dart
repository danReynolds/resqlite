/// Unit test for the A9 large working set workload.
///
/// Uses [runLargeWorkingSetBenchmarkSmallForTest] at 20K rows rather
/// than 5M so the test completes in seconds. Production
/// [runLargeWorkingSetBenchmark] seeds ~1 GB and takes a few minutes
/// the first time; that's out of scope for a DoD unit test.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/suites/large_working_set.dart';

void main() {
  group('Large Working Set workload (A9)', () {
    setUpAll(() async {
      // Clean cached seed between test runs so we're not depending on
      // a stale fixture from a previous invocation.
      final cached = File(
          'benchmark/results/_cache/large_working_set_test.db');
      if (cached.existsSync()) {
        await cached.delete();
      }
    });

    test('workload meta declares expected identity', () {
      expect(largeWorkingSetMeta.slug, equals('large_working_set'));
      expect(largeWorkingSetMeta.version, equals(1));
      expect(largeWorkingSetMeta.sectionHeading,
          equals('Large Working Set (v1)'));
      expect(largeWorkingSetMeta.metricKey,
          equals('large_working_set_v1'));
    });

    test('runs end-to-end at reduced scale and emits warm + cold sections',
        () async {
      final markdown =
          await runLargeWorkingSetBenchmarkSmallForTest();

      expect(markdown, contains('## Large Working Set (v1)'));
      expect(markdown, contains('### Warm cache'));
      expect(markdown, contains('### Cold cache'));

      // All four peers must be present (read-only workload, no
      // capability filter).
      expect(markdown, contains('| resqlite '));
      expect(markdown, contains('| sqlite3 '));
      expect(markdown, contains('| sqlite_async '));
      expect(markdown, contains('| drift '));

      // Each section has a point-query and range-scan column.
      expect(
        markdown,
        contains('| Library | Point p50 (ms) | Point p90 (ms) | '
            'Range p50 (ms) | Range p90 (ms) |'),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
