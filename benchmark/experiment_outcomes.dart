/// The closed vocabulary for how an experiment ended.
///
/// `outcomeClass` used to be `^(accepted(_.+)?|rejected(_.+)?|...)$` — a prefix
/// with a free-text tail. The tail was doing three jobs at once: the verdict,
/// the reason behind it, and sometimes what survived the rejection. Three facts
/// in one string with no closed set produced twenty spellings for twenty-odd
/// distinct outcomes, six of them synonyms for "under the noise floor"
/// (`below_signal`, `below_current_signal`, `below_signal_bar`, `no_signal`,
/// `no_stable_signal`, `after_noise_check`). A field spelled six ways cannot be
/// grouped, and grouping is the only reason to have the field: the question it
/// exists to answer is "how do our rejections actually break down", and it
/// could not answer it.
///
/// So the axes are separated. [outcomeClasses] is the verdict, [outcomeReasons]
/// is why, and `outcomeNote` carries any nuance neither one holds. Both lists
/// are closed — a new value is a deliberate edit here, reviewed once, rather
/// than a new spelling invented at 3am by whichever runner is holding the pen.
library;

/// The verdict. What happened to the change.
const outcomeClasses = <String, String>{
  'accepted': 'The experiment merged.',
  'rejected': 'The experiment did not merge.',
  'deferred':
      'Viable but deliberately postponed — the blocker is scope or timing, '
      'not evidence.',
  'watch':
      'No change proposed; the run recorded a condition to re-examine when '
      'external context moves.',
  'in_review': 'Not yet dispositioned. Never a resting state.',
};

/// Why the verdict fell that way, per verdict. `null` means the class takes no
/// reason: `watch` and `deferred` are already their own explanation.
const outcomeReasons = <String, Map<String, String>>{
  'accepted': {
    'performance': 'Shipped a measured improvement on the runtime path.',
    'measurement':
        'Shipped measurement, tooling, or a harness rather than a runtime '
        'change. Valid only when it unblocks a named decision.',
    'correctness':
        'Shipped for correctness or safety. Any performance effect was '
        'secondary to the defect it closed.',
  },
  'rejected': {
    'below_signal':
        'The effect could not be distinguished from noise: under the MDE, '
        'inside the threshold, or not stable across passes. The single most '
        'common rejection, and the one the old vocabulary spelled six ways.',
    'regression': 'It measurably made things worse.',
    'tradeoff':
        'The win was real and reproduced, but its cost — complexity, safety, '
        'memory, or public API surface — was judged not worth paying. '
        'Exp 265 is the archetype: -74.8% on the most common read shape, '
        'rejected because the worst case put an unbounded copy on the '
        "caller's isolate.",
    'premise_refuted':
        "The hypothesis's premise turned out to be false, so the question "
        'stopped being worth asking in that form. The change is not merely '
        'unshipped; the reasoning that motivated it is retired.',
    'benchmark_gap':
        'The workload never exercised the changed path, so the run could not '
        'decide anything. The deliverable is the missing benchmark, not the '
        'change.',
    'unspecified':
        'The record does not state a reason. Not a category so much as a '
        'visible hole — it exists so that a migrated entry cannot silently '
        'acquire a reason nobody wrote down. New entries must not use it.',
  },
};

/// Reasons a new entry may not choose, even though migrated entries carry them.
///
/// Backfilling `unspecified` onto history is honest; minting it going forward
/// would re-open the hole the closed vocabulary exists to close.
const retiredOutcomeReasons = <String>{'unspecified'};

/// The entries allowed to keep a [retiredOutcomeReasons] value.
///
/// Exactly the set the migration could not classify from the written record —
/// today that is exp 241, whose entry never says which way the sacrifice
/// re-evaluation fell. Closed by construction: anything not listed here is held
/// to the current vocabulary, so the hole cannot quietly grow. Shrinking it is
/// a small, welcome piece of archaeology.
const grandfatheredUnspecified = <String>{'241'};

/// Validates a class/reason pair, returning a human-readable error or `null`.
///
/// [minting] is true for an entry being written now, which is held to the
/// stricter rule — see [retiredOutcomeReasons].
String? validateOutcome(
  String? outcomeClass,
  String? outcomeReason, {
  bool minting = false,
}) {
  if (outcomeClass == null) return 'outcomeClass is required';
  if (!outcomeClasses.containsKey(outcomeClass)) {
    return 'outcomeClass "$outcomeClass" is not in the closed set '
        '(${outcomeClasses.keys.join(', ')}). Put nuance in outcomeNote, not '
        'in a new spelling.';
  }
  final allowed = outcomeReasons[outcomeClass];
  if (allowed == null) {
    return outcomeReason == null
        ? null
        : 'outcomeClass "$outcomeClass" takes no outcomeReason, '
              'got "$outcomeReason"';
  }
  if (outcomeReason == null) {
    return 'outcomeClass "$outcomeClass" requires an outcomeReason '
        '(${allowed.keys.join(', ')})';
  }
  if (!allowed.containsKey(outcomeReason)) {
    return 'outcomeReason "$outcomeReason" is not valid for '
        '"$outcomeClass" (${allowed.keys.join(', ')})';
  }
  if (minting && retiredOutcomeReasons.contains(outcomeReason)) {
    return 'outcomeReason "$outcomeReason" is retired and may not be used by '
        'a new entry — state the actual reason';
  }
  return null;
}

/// Whether [outcomeClass] is consistent with an `index/NNN.json` README status.
///
/// The two are written in different files by the same run and drift apart when
/// only one is updated — the promotion path from `in_review` is where that
/// happens most.
/// `rejected` is the README's catch-all for "did not merge", so it admits the
/// three verdicts that all mean that for different reasons.
bool outcomeMatchesStatus(String outcomeClass, String status) =>
    switch (status) {
      'accepted' => outcomeClass == 'accepted',
      'rejected' => const {
        'rejected',
        'deferred',
        'watch',
      }.contains(outcomeClass),
      'in_review' => outcomeClass == 'in_review',
      _ => true,
    };
