/// Unit test for the A11 keyed PK subscriptions workload.
///
/// Per METHODOLOGY.md § Adding a workload — Definition of Done:
/// asserts behavior (schema, op counts, peer set), not timing.
library;

import 'package:test/test.dart';

import '../benchmark/suites/keyed_pk_subscriptions.dart';

void main() {
  group('Keyed PK Subscriptions workload (A11)', () {
    test('workload meta declares expected identity', () {
      expect(keyedPkMeta.slug, equals('keyed_pk_subscriptions'));
      expect(keyedPkMeta.version, equals(1));
      expect(keyedPkMeta.sectionHeading,
          equals('Keyed PK Subscriptions (v1)'));
      expect(keyedPkMeta.metricKey, equals('keyed_pk_subscriptions_v1'));
    });

    test('runs end-to-end without errors and emits the expected table shape',
        () async {
      final markdown = await runKeyedPkSubscriptionsBenchmark();

      expect(markdown, contains('## Keyed PK Subscriptions (v1)'));
      expect(
        markdown,
        contains('| Library | Wall med (ms) | Wall p90 (ms) | '
            'Main med (ms) | Main p90 (ms) | '
            'Total emits | Observed hits |'),
      );
      // Must include all reactive peers: resqlite, sqlite_async, drift.
      expect(markdown, contains('resqlite'));
      expect(markdown, contains('sqlite_async'));
      expect(markdown, contains('drift'));
      // sqlite3 has no streams; must NOT appear.
      expect(
        markdown,
        isNot(contains('sqlite3 ')),
        reason: 'sqlite3.dart has no reactive streams and must be omitted',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
