# Experiment 176: Row.containsKey identity fast path

**Date:** 2026-06-16
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused `row_map_facade` A/B (order-stable, 3 passes per side, quiet box) + release-suite `Select → Maps` artifact

## Problem

Exp 158 added a schema-name **identity fast path** to `RowSchema.indexOf`: for
schemas with at most 32 columns, a lookup first does a short
`identical(names[i], key)` scan and only falls back to the private
`HashMap<String, int>` index when the supplied key is equal-but-non-identical
(or the schema is wider than 32 columns). That cut `row_map_facade` *hot lookup*
−52% because the common full-consumption pattern (`for (final key in row.keys) row[key]`)
re-feeds the schema's own interned name objects, so the identity scan hits before
any hashing.

`Row.containsKey`, however, was never routed through that fast path. It went
straight to the raw map:

```dart
bool containsKey(Object? key) =>
    key is String && _schema._indexByName.containsKey(key);
```

So every `containsKey` call hashed the key string, even when the caller passed
an interned column name that an `identical()` scan would resolve without
hashing. Exp 158's results table lists `containsKey` as "neutral" — but that
row compared Row vs a `LinkedHashMap` with `containsKey` *unchanged* on both
sides of exp 158's diff. It is **not** evidence that routing `containsKey`
through the identity path is neutral; that path was simply never applied to
`containsKey`.

A fresh baseline confirms the gap. On the `row_map_facade` benchmark (8-column
schema, key `'updated_at'` supplied as a string literal that is `identical` to
`names[5]`):

| lane | Row median (baseline) | LinkedHashMap median |
|---|---:|---:|
| hot lookup (`operator[]`, exp 158 path) | ~3.95 ms | ~5.25 ms |
| **containsKey (raw HashMap)** | **~13.0 ms** | ~9.35 ms |

`containsKey` does strictly *less* work than `hot lookup` (one membership probe
vs two value lookups) yet ran ~3.3× slower and was ~+3.6 ms **slower than a
plain `LinkedHashMap`** — the direct signature of paying the HashMap hash that
the identity scan was built to skip.

## Hypothesis

Routing `Row.containsKey` through the exp 158 identity fast path (via a shared
`RowSchema.containsName(name) => indexOf(name) >= 0` helper) will reproduce the
`operator[]` win on the `containsKey` lane for the interned-key case: drop the
Row `containsKey` median toward the `hot lookup` level and flip it from slower
to at-parity-or-faster than `LinkedHashMap`, with no public API change and no
movement on the `hot lookup` control lane.

Behavior is identical: `indexOf` returns the column index when the name is
present (by identity or by map fallback) and `-1` otherwise, so `>= 0` is
exactly membership. The negative case (`containsKey('nonexistent')`) still falls
through the identity miss to the `HashMap` and returns `-1 >= 0` → `false`.

## Approach

`lib/src/row.dart`:

- Added `RowSchema.containsName(String name) => indexOf(name) >= 0`, sharing the
  existing identity-then-HashMap path.
- `Row.containsKey` now calls `_schema.containsName(key)` instead of
  `_schema._indexByName.containsKey(key)`. `Row` no longer reaches into the
  private map field directly — both `operator[]` and `containsKey` go through
  the schema's lookup methods.

One-line behavioral change plus a documented helper; no new fields, no
allocation change, no public surface change.

## Results

Focused `row_map_facade` A/B, fresh worktree off `origin/main`, three passes per
side on a quiet box. The `hot lookup` lane is the control (unchanged by this
diff).

| lane | baseline Row (3 passes) | candidate Row (3 passes) | delta |
|---|---:|---:|---:|
| **containsKey** | 12.869 / 13.006 / 13.192 ms | 10.027 / 10.039 / 9.941 ms | **−23%** |
| hot lookup (control) | 3.889 / 3.962 / 3.997 ms | 4.038 / 3.936 / 3.922 ms | neutral |

Row-vs-`LinkedHashMap` on the `containsKey` lane flipped from **+3.6 ms slower**
(baseline) to roughly at-parity (candidate delta −0.9 / +0.8 / +0.8 ms across
passes — straddling zero). The control lane is flat across the diff, so the
movement is the targeted path, not a machine-wide shift.

Honest framing of the size of the win:

- The identity scan removes the *hash*, not all per-call overhead. Candidate
  `containsKey` (~10 ms) is still well above `hot lookup` (~3.9 ms) because
  `containsKey` still pays the `MapMixin.containsKey` dispatch and the
  `key is String` type check that `operator[]` does not. So this is a clean
  −23%, not the −52% exp 158 measured on `operator[]`.
- The win is **interned-key-specific**, exactly like the exp 158 `operator[]`
  fast path. In the real decode path the schema names come from
  `fastDecodeText` (freshly allocated, non-canonical strings), so a
  user-supplied string literal will generally **not** be `identical` to a
  decoded name and `containsName` will fall through to the `HashMap` — the same
  cost as before, never worse. The benchmark hits the identity path because both
  the schema and the probe key are string literals (canonicalized to the same
  object). The win materializes for callers that re-feed `row.keys` or for the
  common literal-vs-literal schema (e.g. `RowSchema` built from constant names),
  not for arbitrary literal-vs-decoded-name probes.

Release-suite `Select → Maps` artifact
(`benchmark/results/<date>-exp176-containskey-identity.md`) is committed as the
public dated lane. It does not isolate `containsKey` (the suite iterates fields,
it does not membership-probe), so it is expected to be neutral there — the
focused facade A/B carries the signal.

## Decision

**Accept for review.**

Bounded one-line behavioral change that closes a real gap exp 158 left open:
`Row.containsKey` paid a HashMap hash on a path where its sibling `operator[]`
already had an identity shortcut. The change is behavior-identical, removes the
last direct `_indexByName` reach-out from `Row`, and turns the `containsKey`
lane from slower-than-`LinkedHashMap` to at-parity, reproducibly across three
order-stable passes with a flat control lane. Touches `lib/`, so it gets a human
glance per the disposition policy.

Reject calculus for a future runner: this is the right move while the identity
fast path exists at all. Reopen/revisit only if exp 158's identity scan itself
is removed or its 32-column cap changes — `containsName` simply inherits whatever
`indexOf` does, so the two stay coupled by construction.

## Future Notes

- If a future workload supplies `containsKey` with keys that are equal-but-not-
  identical to decoded schema names at high frequency (the identity miss case),
  the cost reverts to the `HashMap` probe — same as before this change, never
  worse. No additional work is warranted unless such a workload is shown to be
  hot.
- This does not reopen larger result-shape changes (exp 158 Future Notes still
  apply). It is a consistency fix inside the same private schema index.

## Validation

- `dart pub get`
- `dart analyze lib/src/row.dart` — clean
- `dart test test/database_test.dart` — 49 passed, including the
  `containsKey('id')` / `containsKey('name')` / `containsKey('nonexistent')`
  assertions that exercise both the identity-hit and HashMap-fallback paths
- `dart test test/query_decoder_test.dart` — passed
- Focused facade A/B: `dart run benchmark/experiments/row_map_facade.dart`
  (3 passes per side)
- Release-suite artifact: `dart run benchmark/run_release.dart exp176-containskey-identity`
