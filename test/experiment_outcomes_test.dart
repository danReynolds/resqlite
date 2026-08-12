/// Tests for the closed outcome vocabulary.
///
/// The field this guards spent most of its life as a prefix plus free text, and
/// accumulated twenty values — six of them synonyms for "under the noise floor".
/// Nothing rejected a new spelling, so every runner in a hurry invented one, and
/// the field stopped being able to answer the only question it exists for: how
/// do our rejections actually break down.
///
/// So the cases that matter here are the refusals. A validator that accepts an
/// unfamiliar value is indistinguishable from the regex it replaced.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../benchmark/experiment_outcomes.dart';

void main() {
  group('validateOutcome', () {
    test('accepts every documented class/reason pair', () {
      for (final entry in outcomeReasons.entries) {
        for (final reason in entry.value.keys) {
          expect(
            validateOutcome(entry.key, reason),
            isNull,
            reason: '${entry.key}/$reason should be valid',
          );
        }
      }
      expect(validateOutcome('watch', null), isNull);
      expect(validateOutcome('deferred', null), isNull);
    });

    test('refuses a class outside the closed set', () {
      expect(validateOutcome('rejected_below_signal', null), isNotNull);
      expect(validateOutcome('accepted_measurement', null), isNotNull);
    });

    // The exact failure that produced the sprawl: a reason nobody defined,
    // spelled to look like one that exists.
    test('refuses an undefined reason even when it reads plausibly', () {
      expect(validateOutcome('rejected', 'below_signal_bar'), isNotNull);
      expect(validateOutcome('rejected', 'no_stable_signal'), isNotNull);
    });

    test('requires a reason where the class defines them', () {
      expect(validateOutcome('rejected', null), isNotNull);
      expect(validateOutcome('accepted', null), isNotNull);
    });

    test('refuses a reason where the class defines none', () {
      expect(validateOutcome('watch', 'below_signal'), isNotNull);
    });

    test("refuses another class's reason", () {
      expect(validateOutcome('accepted', 'regression'), isNotNull);
      expect(validateOutcome('rejected', 'performance'), isNotNull);
    });

    // `unspecified` records that history never said why. Allowing a new entry
    // to reach for it would reopen the hole the vocabulary exists to close.
    test('unspecified survives on history but cannot be minted', () {
      expect(validateOutcome('rejected', 'unspecified'), isNull);
      expect(
        validateOutcome('rejected', 'unspecified', minting: true),
        isNotNull,
      );
    });
  });

  group('outcomeMatchesStatus', () {
    test('accepted README status admits only the accepted verdict', () {
      expect(outcomeMatchesStatus('accepted', 'accepted'), isTrue);
      expect(outcomeMatchesStatus('rejected', 'accepted'), isFalse);
    });

    // "rejected" in the README means "did not merge", which three verdicts do
    // for different reasons.
    test('rejected README status admits rejected, deferred and watch', () {
      for (final c in ['rejected', 'deferred', 'watch']) {
        expect(outcomeMatchesStatus(c, 'rejected'), isTrue, reason: c);
      }
      expect(outcomeMatchesStatus('accepted', 'rejected'), isFalse);
    });
  });

  group('the committed corpus', () {
    final entries = Directory('experiments/signals/entries')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));

    test('every entry validates against the closed vocabulary', () {
      final failures = <String>[];
      for (final file in entries) {
        final d = json.decode(file.readAsStringSync()) as Map<String, Object?>;
        final error = validateOutcome(
          d['outcomeClass']?.toString(),
          d['outcomeReason']?.toString(),
        );
        if (error != null) failures.add('${file.path}: $error');
      }
      expect(failures, isEmpty);
    });

    // The migration is only trustworthy if the escape hatch stayed the size it
    // was opened at. A second entry appearing here means someone widened the
    // hole rather than reading the record.
    test('only grandfathered entries carry a retired reason', () {
      final found = <String>{};
      for (final file in entries) {
        final d = json.decode(file.readAsStringSync()) as Map<String, Object?>;
        if (retiredOutcomeReasons.contains(d['outcomeReason'])) {
          found.add(file.uri.pathSegments.last.replaceFirst('.json', ''));
        }
      }
      expect(found, grandfatheredUnspecified);
    });
  });
}
