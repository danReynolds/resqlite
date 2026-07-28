# Experiment 255: A stream could emit nothing when a write raced its initial query

**Date:** 2026-07-28
**Status:** Accepted
**Category:** Correctness
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none — correctness fix, guarded by a deterministic
  regression test rather than a benchmark.

## Problem

`db.stream(sql)` promises to emit current results immediately and then re-emit
when writes change them. It could do neither: a stream whose initial query was
still in flight when a write landed went **permanently silent**, never emitting
even its first value.

This surfaced as a long-standing intermittent failure in
`test/write_coalescing_test.dart` — "coalesced writes invalidate watching
streams" — which had been dismissed as a flake (including three times in one
session while shepherding unrelated PRs). It reproduced at roughly **1 in 3**
runs on a loaded machine, and the test file's own comment asserted the shape
"can't flake under load," which is precisely what discouraged looking closer.

The failure output said what was actually happening, once read:

```
Which: emitted x Stream closed.
       which never did emit an event that <8>
```

`emitted x` — nothing at all. Not a stale value: no value.

## Mechanism

`StreamEngine._createStream` registers an entry, adds it to
`_unknownDepsEntries` (so invalidations that arrive before its dependencies are
known still mark it dirty), and runs the initial query. On completion it stored
the result's hash and row count as the comparison baseline, then chose one of
two paths:

```dart
entry.lastResultHash = initialHash;   // baseline set from these rows
...
if (entry.dirty) {
  _requeryQueue.add(entry);           // catch-up re-query
  _flushQueue();
} else {
  entry.emit(initialRows);            // emit only when NOT dirtied
}
```

When a write dirtied the entry mid-flight, the initial rows were discarded
unemitted in favour of the catch-up re-query — but the baseline had already
been taken *from those same rows*. The re-query calls `selectIfChanged`, which
compares against that baseline, finds it identical, and returns
`rows == null` meaning "unchanged, nothing to emit"
([exp 075](075-native-hash-selectifchanged.md) established that short-circuit).
So the initial emission was suppressed as stale and the replacement emission
was suppressed as unchanged. The stream emitted nothing, forever.

The race window is the initial query's duration, so it widens with result size:
trivial on a 4-row table, reliable on a 40k-row one. Opening a stream and
immediately writing is ordinary usage — seeding a list on first paint, for
example — which is why this was reachable at all.

## Approach

The stream must always resolve to an emission — but *which* rows it emits when
a write raced is a second question, and the two answers were measured against
each other in [exp 256](256-stale-initial-emission-tradeoff.md) before choosing.
The shipped behaviour poisons the comparison baseline so the catch-up re-query
is guaranteed to emit, and lets that emission be the stream's first:

```dart
if (entry.dirty) {
  entry.lastResultHash = _poisonedHash;   // guarantees the re-query emits
  entry.lastRowCount = -1;
  _requeryQueue.add(entry);
  _flushQueue();
} else {
  entry.emit(initialRows);
}
```

The poisoning is what makes suppression safe, and is exactly what the bug was
missing: suppressing the initial emission while leaving the baseline set to
those same rows is what let both emissions cancel each other. `_requery`
propagates errors to subscribers, so the stream always resolves to a value or
an error — never silence.

The alternative — emit the known-stale rows immediately, then correct — is
simpler and also fixes the silence, but exp 256 measured it rendering exactly
one stale frame on every raced stream while saving ~1 ms of time-to-correct.

Two hypotheses were tried and discarded before this one — worth recording,
because both looked plausible and neither moved the failure rate:

1. **Test-side registration race** (await the first emission before writing) —
   made the *existing* test pass, but only by avoiding the window rather than
   fixing anything; a fresh test written that way passed with and without the
   library fix, guarding nothing.
2. **Stranded re-query queue** (`_flushQueue` never re-running after
   `inFlight` cleared) — 3/6 failures, unchanged from baseline.

Reading the actual failure text instead of theorising would have reached the
answer immediately; that is the transferable lesson.

## Results

A regression test in `test/stream_test.dart` seeds 40k rows so the write
reliably races the initial query, then asserts the stream emits at all:

| | without fix | with fix |
|---|---|---|
| new regression test | **0 / 5 pass** | **6 / 6 pass** |
| `write_coalescing_test` (the old "flake") | 3 / 6 pass | 8 / 8 pass |

A standalone reproduction on unmodified `main` versus this branch:

```
main:        ✗ stream emitted NOTHING in 4s (permanently silent)
this branch: ✓ emissions: [40008] → final 40008
```

Full stream/write/transaction suites: 140 tests pass.

## Decision

**Accepted.** A user-visible correctness fix: streams no longer drop their
initial emission, and the failure mode was silence rather than staleness, which
is the hardest kind to notice in an application.

The `write_coalescing_test` comment claiming the shape "can't flake under load"
is corrected to describe what it actually guards — a false confidence marker is
worse than no comment, since it actively redirects investigation.
