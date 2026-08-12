/// Tests for the peer-drift statistic.
///
/// The thing being separated is a shift in the measuring apparatus from
/// ordinary peer noise, and the two look identical lane by lane — a per-lane
/// threshold fired on 140 of 143 real run-to-run steps. So the cases that
/// matter are the pair: violent but directionless movement must read as calm,
/// and modest but consistent movement must read as a shift.
library;

import 'package:test/test.dart';

import '../benchmark/check_peer_drift.dart';
import '../benchmark/shared/parse_results.dart';

/// Lanes named so they pass the minimum-magnitude filter.
Map<String, double> lanes(List<double> values) => {
  for (var i = 0; i < values.length; i++) 'lane$i': values[i],
};

void main() {
  group('peerShift', () {
    test('identical runs report no movement', () {
      final s = peerShift(
        lanes([1, 2, 3, 4, 5, 6]),
        lanes([1, 2, 3, 4, 5, 6]),
        0.1,
      )!;
      expect(s.median, 0);
      expect(s.lanes, 6);
    });

    // The whole reason this is a median over lanes rather than a per-lane
    // threshold: lanes swinging hard in both directions is what this host does
    // between adjacent runs, and it means nothing.
    test('large but directionless movement stays under the bar', () {
      final s = peerShift(
        lanes([1, 1, 1, 1, 1, 1, 1, 1]),
        lanes([2.0, 0.5, 1.8, 0.4, 1.9, 0.6, 1.7, 0.55]),
        0.1,
      )!;
      expect(s.agreement, lessThan(0.7));
      expect(s.exceeds(0.10, 0.70), isFalse);
    });

    test('consistent movement in one direction is a shift', () {
      final s = peerShift(
        lanes([1, 1, 1, 1, 1, 1, 1, 1]),
        lanes([1.2, 1.25, 1.18, 1.3, 1.22, 1.19, 1.28, 1.21]),
        0.1,
      )!;
      expect(s.median, greaterThan(0.15));
      expect(s.agreement, 1.0);
      expect(s.exceeds(0.10, 0.70), isTrue);
    });

    // A mean would be dragged over the line by one wild lane; the median is
    // what keeps a single outlier from being reported as an environment change.
    test('one wild lane does not manufacture a shift', () {
      final s = peerShift(
        lanes([1, 1, 1, 1, 1, 1, 1, 1]),
        lanes([1.01, 0.99, 1.02, 0.98, 1.0, 1.01, 0.99, 12.0]),
        0.1,
      )!;
      expect(s.median.abs(), lessThan(0.05));
      expect(s.exceeds(0.10, 0.70), isFalse);
    });

    test('lanes below the magnitude floor are excluded', () {
      final s = peerShift(
        {'tiny': 0.001, 'a': 1, 'b': 1, 'c': 1, 'd': 1, 'e': 1},
        {'tiny': 0.02, 'a': 1, 'b': 1, 'c': 1, 'd': 1, 'e': 1},
        0.1,
      )!;
      expect(s.lanes, 5, reason: 'the 0.001 -> 0.02 lane must not count');
      expect(s.median, 0);
    });

    // Too few shared lanes is not a quiet zero — it means the two runs measured
    // different things, and a median over three lanes would invent confidence.
    test('too few shared lanes yields null rather than a verdict', () {
      expect(peerShift(lanes([1, 2, 3]), lanes([1, 2, 3]), 0.1), isNull);
      expect(peerShift(lanes([1, 2, 3, 4, 5]), {'other': 1}, 0.1), isNull);
    });
  });

  group('extractPeerMedians', () {
    const table = '''
## Select → Maps

### 1000 rows

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| resqlite select() | 0.32 | 0.33 | 0.05 | 0.06 |
| sqlite3 select() | 1.23 | 1.32 | 1.23 | 1.32 |
| drift select() | 1.63 | 1.87 | 0.09 | 0.11 |

## Comparison vs Previous Run

| Benchmark | Before | After | Delta |
|---|---|---|---|
| sqlite3 select() | 0.82 | 1.23 | +50% |
''';

    test('peer rows are extracted and resqlite rows are not', () {
      final peers = extractPeerMedians(table);
      expect(peers, contains('Select → Maps / 1000 rows / sqlite3 select()'));
      expect(peers, contains('Select → Maps / 1000 rows / drift select()'));
      expect(
        peers.keys.where((k) => k.contains('resqlite')),
        isEmpty,
        reason: 'resqlite is the subject, not the control',
      );
    });

    // Derived sections restate other sections as deltas. A delta compared
    // against another delta is meaningless, and these rows carry library names
    // too, so they have to be excluded by section rather than by label.
    test('the comparison section is not mistaken for a measurement', () {
      expect(
        extractPeerMedians(table).keys.where((k) => k.startsWith('Comparison')),
        isEmpty,
      );
    });

    test('peer and resqlite lanes are keyed identically', () {
      final peer = extractPeerMedians(table).keys.firstWhere(
        (k) => k.contains('sqlite3'),
      );
      final own = extractResqliteMedians(table).keys.firstWhere(
        (k) => k.endsWith('resqlite select()'),
      );
      expect(
        peer.replaceAll('sqlite3 select()', ''),
        own.replaceAll('resqlite select()', ''),
        reason: 'the two maps are only comparable if keyed the same way',
      );
    });
  });
}
