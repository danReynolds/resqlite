# Experiment 228: Restore canonical hashes after stream growth

**Date:** 2026-07-14
**Status:** Accepted
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none — focused
  [`benchmark/experiments/canonical_stream_hash.dart`](../benchmark/experiments/canonical_stream_hash.dart);
  three order-flipped passes recorded in
  [`benchmark/results/2026-07-14T10-29-44Z-exp228-canonical-stream-hash.md`](../benchmark/results/2026-07-14T10-29-44Z-exp228-canonical-stream-hash.md).
  No release-suite run is linked because the focused harness is the first lane
  that pairs result growth with the immediately following unchanged rerun.

## Problem

[Exp 077](077-cheap-check-first-sweep.md) made
`resqlite_query_hash` stop hashing cell bytes once a growing result stepped past
the previously emitted row count. The row-count mismatch was enough to prove
that the result had changed, but the function still returned its prefix-only
accumulator as though it were the new result's canonical hash.

`executeQueryIfChanged` caches that returned hash before decoding the changed
rows. On the next rerun, the cached row count now matches the grown result, so
`resqlite_query_hash` walks every row and returns the full hash. The full hash
cannot match the cached prefix hash. Resqlite therefore decodes and publicly
re-emits the unchanged grown result once, even though no value changed.

The existing growing-stream benchmark measured only the write-to-emission leg,
so exp 077's own result could not see this follow-on work. Its measured growth
benefit was also within noise, making a correctness-preserving rollback a
plausible simplification rather than an unbounded performance trade.

## Hypothesis

If every successful `resqlite_query_hash` call returns the canonical hash of
the complete result, a hash accepted as the new stream baseline remains valid
on the next rerun. Removing the row-count early exit should change the focused
grow-then-no-op sequence from one redundant decode per round to zero.

Accept if the worker-level and public-stream regressions pass, all three
9-round focused passes move redundant immediate-no-op decodes from 9/9 to 0/9,
and the complete growth-plus-no-op cycle does not materially regress. The pure
growth leg may move within the 3–5% measurement floor because it now hashes the
appended rows; correctness and the complete cycle are the load-bearing gates.

## Approach

- Delete the `skip_hash` state and its `row_count > last_row_count` branch from
  `resqlite_query_hash`, so every returned hash folds every cell and the final
  row count.
- Remove the now-unused `last_row_count` argument from the private native FFI
  function and its Dart wrapper. The previously emitted row count remains in
  stream state and is still compared as an additional equality guard.
- Add a direct worker-path regression that grows a result, accepts the changed
  hash, then requires an immediate identical `executeQueryIfChanged` call to
  return the unchanged sentinel.
- Add a public `Database.stream` regression that performs the same growth,
  executes a no-op update, and rejects a third emission.
- Add `canonical_stream_hash.dart`, a focused public reader-worker harness with
  5,000 seed rows, 100 appended rows, and an immediate unchanged rerun. It
  reports the growth leg, unchanged leg, combined cycle, and redundant decode
  count over two warmups plus nine measured rounds.

The change removes private implementation state; it adds no public API and no
new runtime mechanism.

## Results

The baseline fails both new regressions: the direct worker call returns a
second `RawQueryResult`, and the public stream emits the identical grown rows a
third time. Both pass after the candidate.

Focused p50 wall time in milliseconds; negative deltas are candidate-faster:

| Pass | Order | Lane | Baseline | Candidate | Delta |
|---|---|---|---:|---:|---:|
| 1 | baseline → candidate | growth | 0.986 | 1.127 | +14.3% |
| 1 | baseline → candidate | immediate unchanged | 0.877 | 0.389 | -55.6% |
| 1 | baseline → candidate | combined cycle | 1.863 | 1.505 | -19.2% |
| 2 | baseline → candidate | growth | 0.948 | 0.995 | +5.0% |
| 2 | baseline → candidate | immediate unchanged | 0.860 | 0.366 | -57.4% |
| 2 | baseline → candidate | combined cycle | 1.812 | 1.370 | -24.4% |
| 3 | candidate → baseline | growth | 1.211 | 0.982 | -18.9% |
| 3 | candidate → baseline | immediate unchanged | 0.982 | 0.356 | -63.7% |
| 3 | candidate → baseline | combined cycle | 2.146 | 1.365 | -36.4% |

Every baseline pass redundantly decodes 9/9 immediate unchanged results; every
candidate pass returns the hash sentinel without decoding, 0/9. The growth leg
is noisy around parity across the flipped order, while the unchanged leg and
combined cycle reproduce candidate-faster with large margins. The candidate
therefore pays at most a small one-time hashing cost when a result grows and
avoids a full native step plus Dart row decode and public emission on the next
no-op invalidation.

## Decision

**Accepted.** A fast-reject value cannot double as the next cached baseline
unless it is canonical. Exp 077's shortcut proved a mismatch correctly but
then persisted a partial hash under the semantics of a complete one. Removing
the shortcut fixes observable duplicate stream emissions, deletes private FFI
and native state, and improves the full sequence the optimization actually
created by 19–36% across the three passes.

The row count remains useful as an equality guard, but it no longer changes how
the content hash is computed. A future early-reject design would need a
separate non-cacheable sentinel or compute the canonical hash while decoding
the changed result; the old growth-only saving was too small to justify either
mechanism today.

## Future Notes

- Keep `canonical_stream_hash.dart` as the durable regression gate for changes
  to `resqlite_query_hash` or stream baseline state. A growth-only benchmark is
  insufficient because the bug appears on the following rerun.
- Hashes stored in `StreamEntry.lastResultHash` must always describe the entire
  corresponding `lastResult` and `lastRowCount`. Any fast reject that has not
  completed the fold must remain visibly non-cacheable.
- PR #155's incremental-view prototype changes which stream results reach this
  fallback, but it does not change the fallback hash contract. The canonical
  baseline remains required for unsupported queries and ordinary reruns.

## Validation

- `dart pub get` in baseline and candidate worktrees
- `dart test test/query_decoder_test.dart test/stream_test.dart` (31/31 pass)
- three order-flipped focused A/B passes of
  `benchmark/experiments/canonical_stream_hash.dart`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/228-canonical-stream-hash.md`
- `dart analyze --fatal-infos`
- `dart test -j 1`
- `git diff --check`
