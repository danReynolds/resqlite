# Experiment 252: Reject per-batch dirty-column dependency merge

**Date:** 2026-07-27T06:29:40-04:00
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** focused order-flipped A/B, 31 samples per side; aggregate
  tables and raw decision rows in
  [`benchmark/results/2026-07-27T10-29-40Z-exp252-dirty-column-batch-merge.md`](../benchmark/results/2026-07-27T10-29-40Z-exp252-dirty-column-batch-merge.md)
**Archive:** [`archive/exp-252`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-252)

## Problem

Experiment 106 added column-level stream invalidation. The writer authorizer
captures each cached statement's static SET-column dependencies at prepare
time, and the preupdate hook merges them into the current dirty-column set when
a row is actually modified. SQLite fires that hook once per affected row, so
`executeBatch` repeats the same table/column matching, string comparisons, and
dedup probes for every parameter set even though the cached dependency set does
not change.

Experiment 057 had already rejected the analogous optimization for dirty
*tables*: skipping one repeated table-name comparison did not move 100- or
1000-row batches and stayed below 2% at 10,000 rows. Column tracking makes the
loop wider, however, and a fresh downstream workload made the question
concrete rather than speculative.

Dune's identity sync fetches all devices and peers, then runs two public
`executeBatch` calls:

- devices update `ip`, `last_seen_at`, and `online`;
- peers update `last_seen_at` and `online`.

The pair runs every 2 seconds for the first 20 seconds after connect and every
5 seconds thereafter. That is real, repeated incidence for 2-3-column UPDATE
batches. Experiment 182's 3-6% gain from skipping *all* dependency tracking in
wide no-stream writes supplied an upper bound.

## Hypothesis

Merge each cached writer dependency only on the first preupdate callback for
its actual table during an execute or batch. Later rows using the same static
statement can skip the merge loop.

The predeclared product gate was at least a 3% improvement on a full-footprint
100-device + 100-peer Dune-shaped pair in both baseline/candidate orderings.
A 10,000-row x 20-column UPDATE was a mechanism ceiling only and could not
justify acceptance by itself. One-row and missing-key controls had to remain
neutral, and trigger, cascade, no-op, error, and rollback behavior had to keep
exact dependency precision.

## Approach

The archived prototype at
[`archive/exp-252`](https://github.com/danReynolds/resqlite/tree/archive/exp-252)
(`92c5910`) made no Dart or public API change.

It added one 64-bit pending mask to the native writer:

1. each bit represented one cached `dep_columns` entry;
2. a single execute initialized the mask before its step, while a batch
   initialized it once for the whole parameter-set loop;
3. each preupdate callback considered only pending dependencies whose table
   matched the table SQLite actually modified, merged those columns, and
   cleared only those bits;
4. dependencies for a cross-table conditional trigger remained pending until
   that trigger actually fired on a later row;
5. unreliable dependency metadata still forced the existing conservative
   table-level fallback before the mask fast path;
6. the active cache entry remained scoped strictly to `sqlite3_step`, and
   normal, bind-error, step-error, setup, and no-row exits cleared all mask
   state; and
7. a compile-time assertion tied the mask width to the existing 64-column
   dependency cap.

The retained benchmark mirrors Dune's exact two UPDATE statements and its full
13-column device / 9-column peer row footprint. It prebuilds alternating
parameter matrices, validates sentinel rows, and checkpoints outside the timed
region to normalize WAL history.

Three focused tests prevent conservative fallback from hiding precision bugs:

- a no-match row and a non-firing row precede the first conditional
  cross-table trigger in one batch, while an unrelated target column is already
  dirty in the same commit;
- an all-no-match batch must clear pending state before a later
  `sqlite3_exec` fallback write; and
- a nested batch whose second row violates a UNIQUE constraint must clear
  pending state after savepoint rollback before the surviving outer transaction
  writes a watched column.

## Results

The unchanged harness ran from separate `origin/main` and candidate worktrees.
Each side warmed eight times and recorded 31 samples. The first pair ran
baseline then candidate; the second reversed the order. Lower is better.

| Pair | Shape | Baseline p50 | Candidate p50 | Delta |
|---|---|---:|---:|---:|
| baseline first | 100 devices + 100 peers | 424 us | 632 us | **+49.1%** |
| candidate first | 100 devices + 100 peers | 350 us | 404 us | **+15.4%** |
| baseline first | 1000 devices + 1000 peers | 3290 us | 3591 us | +9.1% |
| candidate first | 1000 devices + 1000 peers | 2543 us | 2491 us | -2.0% |
| baseline first | missing-key 100 + 100 control | 112 us | 120 us | +7.1% |
| candidate first | missing-key 100 + 100 control | 116 us | 110 us | -5.2% |
| baseline first | 10k rows x 20 SET columns | 29738 us | 10543 us | **-64.5%** |
| candidate first | 10k rows x 20 SET columns | 26647 us | 10412 us | **-60.9%** |

The pending mask proves its mechanism at the synthetic ceiling: 20 static
column dependencies merged across 10,000 rows become 2.6-2.8x faster. That is a
real reduction in repeated native work, not a failed implementation.

It does not translate to the downstream product shape. The load-bearing
100+100 row is slower at p50 in both orderings instead of at least 3% faster,
and 1000+1000 is mixed at +9% / -2%. The missing-key control changes sign
across the flip, and the smaller product rows are neutral-to-slower with noisy
microsecond distributions. At Dune's 2-3 SET columns, the removed native loop
is too small relative to two public writer-isolate requests, parameter binding,
SQLite row writes, transactions, dependency harvest, and replies.

The wide ceiling cannot carry the decision. It needs 10,000 rows and 20 SET
columns—two orders of magnitude more rows than the product gate and roughly
seven to ten times its dependency width.

## Decision

**Rejected.** The implementation is bounded, internal, and correctness-safe,
but the representative 100+100 Dune-shaped gate fails in both orderings.
Keeping a native mask, lifecycle state, and a 64-column coupling for a win that
appears only at the synthetic 10k x 20 ceiling would optimize the benchmark
rather than the observed product.

The runtime change is reverted. The exact measured prototype remains at
`archive/exp-252`; the downstream-shaped harness and lifecycle/trigger tests
remain as reusable evidence and guards.

Do not retry per-row dirty-column merge caching for ordinary narrow status
batches. Reopen only if a representative downstream trace shows repeated
UPDATE batches in the thousands of rows with materially wider SET lists, or if
a native profile shows this merge loop consumes enough public write wall to
clear a product-shaped gate.

## Transferable lesson

A large mechanism ceiling establishes that work exists, not that removing it
has aggregate value. Preserving the downstream row footprint and timing the
unchanged public operation can reverse the apparent decision: this candidate
is 2.6-2.8x faster at its 10k x 20 inner-loop ceiling and still has no usable
win on the repeated workload that motivated it.

## Validation

Archived prototype:

- exact full-footprint Dune-shaped benchmark with sentinel validation
- two cross-worktree, order-flipped A/B comparisons, 31 samples per side
- 10k x 20 mechanism ceiling and missing-key fixed-overhead control
- trigger, FK-cascade, conditional later-row trigger, all-no-op batch, nested
  batch-error/savepoint rollback, and transaction coverage
- independent native lifecycle and trigger/FK precision review
- native build through Dart package build hooks
- focused Dart analysis and `git diff --check`

Final publication branch:

- runtime source restored byte-for-byte to `origin/main`
- exact prototype pushed to `archive/exp-252`
- retained benchmark and focused lifecycle tests
- `dart run build_runner build --delete-conflicting-outputs`
- experiment finalizer and terminal-disposition check
- `dart analyze --fatal-infos`
- full serial suite: 341/341
- JSON validation and `git diff --check`
