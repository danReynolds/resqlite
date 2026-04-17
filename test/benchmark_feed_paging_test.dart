/// Unit test for the A6 feed paging workload.
///
/// Per METHODOLOGY.md § Adding a workload — Definition of Done:
/// asserts behavior (schema, subsections, peer coverage), not timing.
library;

import 'package:test/test.dart';

import '../benchmark/suites/feed_paging.dart';

void main() {
  group('Feed Paging workload (A6)', () {
    test('workload meta declares expected identity', () {
      expect(feedPagingMeta.slug, equals('feed_paging'));
      expect(feedPagingMeta.version, equals(1));
      expect(feedPagingMeta.sectionHeading, equals('Feed Paging (v1)'));
      expect(feedPagingMeta.metricKey, equals('feed_paging_v1'));
    });

    test('runs end-to-end with both subsections and correct peer coverage',
        () async {
      final markdown = await runFeedPagingBenchmark();

      expect(markdown, contains('## Feed Paging (v1)'));
      expect(markdown, contains('### Keyset pagination'));
      expect(markdown, contains('### Reactive feed with 100 concurrent writes'));

      // Part A — all three peers.
      expect(markdown, contains('| resqlite '));
      expect(markdown, contains('| sqlite3 '));
      expect(markdown, contains('| sqlite_async '));

      // Part B — sqlite3 MUST NOT appear in the reactive subsection.
      // Sanity-check: the reactive subsection's table should contain
      // resqlite + sqlite_async only. We can't easily isolate the
      // subsection here without parsing; instead, assert both
      // reactive peers appear at least once in the markdown.
      final reactiveIdx =
          markdown.indexOf('### Reactive feed with 100 concurrent writes');
      expect(reactiveIdx, isPositive);
      final reactiveSection = markdown.substring(reactiveIdx);
      expect(reactiveSection, contains('| resqlite '));
      expect(reactiveSection, contains('| sqlite_async '));
      expect(
        reactiveSection,
        isNot(contains('| sqlite3 ')),
        reason: 'sqlite3 has no streams and must be omitted from '
            'the reactive subsection',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
