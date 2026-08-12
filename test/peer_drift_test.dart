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

    // `--min-ms=0` is a reasonable "show me every lane" request. Without a
    // guard of its own, a zero baseline divides to NaN, and since every NaN
    // comparison is false the tool then reports a confident all-clear.
    test('a zero baseline is dropped even when the floor is disabled', () {
      final s = peerShift(
        {'z': 0, 'a': 1, 'b': 1, 'c': 1, 'd': 1, 'e': 1, 'f': 1},
        {'z': 5, 'a': 1, 'b': 1, 'c': 1, 'd': 1, 'e': 1, 'f': 1},
        0,
      )!;
      expect(s.lanes, 6);
      expect(s.median.isNaN, isFalse);
      expect(s.median, 0);
    });

    // A zero median has no sign to agree with, so `agreement` is then counting
    // unchanged lanes. Callers must branch on this rather than print the
    // agreement figure as a direction.
    test('a zero median reports no direction', () {
      final s = peerShift(
        lanes([1, 1, 1, 1, 1, 1]),
        lanes([1, 1, 1, 1, 1.5, 0.5]),
        0.1,
      )!;
      expect(s.median, 0);
      expect(s.hasDirection, isFalse);
      expect(s.unchanged, 4);
    });

    test('a nonzero median does report a direction', () {
      final s = peerShift(
        lanes([1, 1, 1, 1, 1, 1]),
        lanes([1.2, 1.2, 1.2, 1.2, 1.2, 1.2]),
        0.1,
      )!;
      expect(s.hasDirection, isTrue);
      expect(s.unchanged, 0);
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
    // too, so the table's own header is what has to exclude them.
    test('the comparison section is not mistaken for a measurement', () {
      expect(
        extractPeerMedians(table).keys.where((k) => k.startsWith('Comparison')),
        isEmpty,
      );
    });

    // Regression: excluding derived tables by section title missed
    // `Memory Comparison vs Previous Run`, which does not start with
    // `Comparison`, and put 430 lanes of megabytes — read from the *previous*
    // run's column — into a map of milliseconds. A `Benchmark` header is the
    // property that actually marks a table as derived.
    test(
      'a Benchmark-headed delta table is excluded whatever it is called',
      () {
        const derived = '''
## Memory Comparison vs Previous Run

| Benchmark | Prev (MB) | Curr (MB) | Delta | MDE | Status |
|---|---|---|---|---|---|
| Memory / Batch insert 10k rows / sqlite3 executeBatch() | 4.06 | 0.00 | -4.06 MB | ±0.50 MB | ⚪ Within MDE |
| Memory / Batch insert 10k rows / drift batch() | 0.52 | 0.00 | -0.52 MB | ±0.50 MB | 🟢 Win |
''';
        expect(extractPeerMedians(derived), isEmpty);
      },
    );

    test('a Library-headed table in an oddly named section is kept', () {
      const odd = '''
## Some Future Section Nobody Predicted

| Library | Wall med (ms) | Wall p90 (ms) | Main med (ms) | Main p90 (ms) |
|---|---|---|---|---|
| sqlite3 select() | 1.23 | 1.32 | 1.23 | 1.32 |
''';
      expect(extractPeerMedians(odd), hasLength(2));
    });

    test('peer and resqlite lanes are keyed identically', () {
      final peer = extractPeerMedians(
        table,
      ).keys.firstWhere((k) => k.contains('sqlite3'));
      final own = extractResqliteMedians(
        table,
      ).keys.firstWhere((k) => k.endsWith('resqlite select()'));
      expect(
        peer.replaceAll('sqlite3 select()', ''),
        own.replaceAll('resqlite select()', ''),
        reason: 'the two maps are only comparable if keyed the same way',
      );
    });
  });
}
