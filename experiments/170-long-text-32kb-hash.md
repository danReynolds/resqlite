# Experiment 170: 32 KB long-text streaming benchmark + 16-byte FNV fold

**Date:** 2026-06-15
**Status:** Rejected
**Direction:** `long-text-stream-hashing`

## Problem

[Exp 110](110-long-text-fnv-8byte.md) built the 4 KB long-text
unchanged-fanout workload and accepted an 8-byte FNV byte-stream fold
inside `resqlite_query_hash`'s `fnv_combine_bytes`, cutting the new
benchmark's median 76%. After that, `signals.json#long-text-stream-hashing`
moved to `watch` status with a single open candidate dated 2026-04-29:

> broader long-payload workload (≥ 32 KB TEXT cells, mixed BLOB/TEXT)
> — blocked on no benchmark covers payloads larger than the exp 110
> 4 KB shape

So further hash-loop variants are unevaluable on the current suite, and
the direction notes say the obvious 8-byte fold has already been tried.
This experiment fills the named gap (a 32 KB cell workload) and asks the
implementation question the gap was blocking: at 32 KB, does an unrolled
16-byte FNV fold show measurable headroom over the exp 110 8-byte body?

The 16-byte fold is the smallest implementation step that the 4 KB
shape could not differentiate, because the byte-stream loop body is so
short on 4 KB cells that loop overhead is amortized differently from
true long-payload streaming.

## Hypothesis

Two interleaved unaligned 8-byte loads per iteration let the CPU issue
both loads in parallel, halve loop-control overhead, and keep the
serial FNV xor-mul chain identical. On the 4 KB shape exp 110 already
covers, the win (if any) is below noise. On a 32 KB cell shape — large
enough that the byte-stream fold is sustained for ~4096 iterations per
cell — the reduced loop overhead should be visible *if* the byte-stream
fold is the dominant wall component.

If it isn't (e.g. SQLite text retrieval, reader-pool dispatch, or
main-isolate reply scheduling dominate), the 16-byte fold can only
attack a small fraction of wall and the experiment correctly closes the
direction.

Accept the 16-byte fold if the focused 32 KB harness shows a clear win
that survives a two-pass A/B with collection order flipped (per the
exp 159 / [JOURNAL.md](JOURNAL.md) phase-drift lesson). Reject if the
result is flat or worse — the benchmark itself becomes the lasting
contribution either way.

## Approach

1. Added a 32 KB long-text section to `benchmark/suites/streaming.dart`:
   8 unchanged streams, 64 rows of 32 KB ASCII TEXT, one changed
   barrier stream that proves the rerun wave has drained — same shape
   as exp 110's 2c section, scaled so the hashed payload per iteration
   (16 MB) stays inside one quiet machine pass.
2. Registered the new metric in
   `benchmark/shared/workload_registry.dart` as
   `Long-Text 32KB Unchanged Fanout` (on the reactive-micros chart),
   ordered before the generic `Long-Text Unchanged Fanout` pattern so
   the substring-match registry resolves the more specific key first.
3. Added a focused harness
   `benchmark/experiments/long_text_32kb_hash.dart` for direct A/B
   work — 9 measured rounds, 2 warmup, fresh DB per round, same shape
   as the release section so future hash recheck experiments can
   reuse it.
4. Implemented the 16-byte fold inside `fnv_combine_bytes`:

   ```c
   for (; i + 16 <= len; i += 16) {
       uint64_t w0, w1;
       memcpy(&w0, b + i, 8);
       memcpy(&w1, b + i + 8, 8);
       h ^= w0;
       h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
       h ^= w1;
       h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
   }
   /* exp 110 8-byte body for the 8..15-byte tail and small cells */
   for (; i + 8 <= len; i += 8) { ... }
   /* unaligned 0..7 byte tail unchanged */
   for (; i < len; i++) { ... }
   ```

   For inputs of any length the result is byte-for-byte identical to
   the exp 110 8-byte-only body — the new 16-byte body and the 8-byte
   tail feed the same serial xor-mul chain.

## Results

Focused harness `benchmark/experiments/long_text_32kb_hash.dart`,
9 rounds per pass on the same machine, build cache warm, back-to-back.
Two passes with collection order flipped (per the exp 159 /
`JOURNAL.md` phase-drift lesson).

| Pass | Order | Baseline (8-byte) median | Candidate (16-byte) median | Delta |
|---|---|---:|---:|---:|
| 1 | candidate first | 3.067 ms | 3.205 ms | +4.5% |
| 2 | baseline first  | 2.863 ms | 3.209 ms | +12.1% |

Within-pass spread for both sides was 2.6 → 6.0 ms (factor ≈ 2.3×).
The candidate medians sit slightly above the baseline medians on both
passes, but each pass's signal is well inside its own variance. There
is no order-flip artifact — flipping the collection order did not
flip the sign of the delta.

Why so little signal: at 32 KB cells with the production reader-pool
size of 4, hashing parallelizes to ~2 streams/worker, so each worker
hashes ~4 MB per burst. At ≈3 ns / 8-byte fold that is ≈1.5 ms per
worker. Observed median wall is ≈3 ms, so the byte-stream fold is at
most ~50 % of wall, and the 16-byte fold can only attack the loop-
control portion of that. A generous 10 % hash-loop saving shrinks to
≈5 % wall — under the run-to-run noise this benchmark exhibits.

Correctness was covered by the existing `long text hash detects changes
after chunk boundary` stream test plus the new 32 KB workload's
`expectNoEmissionForSameContent` assertion. No release-suite guardrail
pass is needed because the C body was reverted (see Decision).

## Decision

Rejected — "premise refuted" escape hatch from `RUNNER_INSTRUCTIONS.md`.

The 16-byte fold is structurally sound and changes nothing visible
about the hash; it just doesn't have enough wall to attack. The
32 KB-cell workload — the named blocker in the open candidate — is the
durable contribution: future hash-loop experiments now have a workload
that exercises the byte-stream fold for thousands of iterations per
cell, and this run's measurements close the open candidate by showing
that even at 32 KB the byte-stream fold is not the dominant wall
component on the current reader-pool shape.

`native/resqlite.c`'s `fnv_combine_bytes` was reverted to the exp 110
8-byte body. The new 32 KB section in `streaming.dart`, the curated
metric in `workload_registry.dart`, and the focused
`long_text_32kb_hash.dart` harness are kept.

## Future Notes

- The remaining wall on 32 KB streams is dominated by reader-pool
  dispatch + SQLite text retrieval + main-isolate reply scheduling.
  Future hash work should not retry FNV unrolling without a workload
  that isolates the hash loop further (e.g., a single-stream
  long-payload shape that bypasses the parallel reader pool, or a
  micro-benchmark that calls `resqlite_query_hash` directly without
  the FFI/IPC stack).
- The blob/text mixed shape the open candidate also called out is
  still uncovered. A future runner that wants to attack BLOB hashing
  should add a mixed BLOB/TEXT variant rather than another TEXT-only
  scaling sweep.
- Do not re-introduce the 16-byte fold body to `fnv_combine_bytes`
  without a new measurement showing the byte-stream fold is a
  material fraction of a stream-workload wall. The current 32 KB
  data point closes that case for the current reader-pool shape.

## Validation

- `dart pub get`
- `dart analyze native/resqlite.c lib/ benchmark/suites/streaming.dart
  benchmark/shared/workload_registry.dart
  benchmark/experiments/long_text_32kb_hash.dart test/stream_test.dart`
- `dart test test/stream_test.dart` (27 / 27 pass, including the
  existing `long text hash detects changes after chunk boundary`
  regression coverage)
- Two-pass focused A/B over the new 32 KB harness (table above)
