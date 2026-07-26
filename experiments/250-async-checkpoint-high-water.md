# Experiment 250: Reject reset/high-water asynchronous WAL checkpoint worker

**Date:** 2026-07-26T09:02:19-04:00
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** focused order-flipped A/B with seven repeats per side, plus
  an order-flipped below-threshold control; raw tables in
  [`benchmark/results/2026-07-26T13-02-19Z-exp250-async-checkpoint-high-water.md`](../benchmark/results/2026-07-26T13-02-19Z-exp250-async-checkpoint-high-water.md)
**Archive:** [`archive/exp-250`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-250)

## Problem

Exp 233 proved that moving the existing 500-frame PASSIVE checkpoint off the
writer can cut the first threshold-crossing commit by 46-56%, but rejected its
level-triggered scheduler. While the asynchronous worker was running,
`pages_in_wal >= 500` remained true, so later commits repeatedly requested or
reran checkpoints. Sustained write p50/p95/p99 and foreground reads regressed,
and the WAL could remain thousands of frames behind.

That rejection left a specific architectural question rather than a generic
retry: can the off-writer ownership win survive if requests rearm only on a new
WAL generation or another 500-page high-water advance?

The current release suite does not establish representative incidence for the
529-frame one-commit shape. Even a mechanically successful candidate would
therefore need a clean sustained result and downstream/release evidence that
inline checkpoint wall is common enough to repay a second connection, isolate,
state machine, and shutdown protocol.

## Hypothesis

Assumption challenged: exp 233's sustained regression came from its
continuously true level trigger rather than from off-writer checkpoint
ownership itself.

The candidate retained the dedicated keyed checkpoint connection and isolate,
but advanced a `next_request_pages` high-water by 500 frames whenever it
scheduled work. A drop in the observed WAL page count rearmed the threshold for
a new generation, including when the first post-restart commit was already
above 500 frames.

The primary gate was at least a 10% first-crossing improvement. The load-bearing
kill conditions were any sustained write p50/p95/p99 regression, any foreground
read regression, or a candidate WAL that did not settle to less than one
500-frame delta after 250 ms.

## Approach

The exact prototype at
[`archive/exp-250`](https://github.com/danReynolds/resqlite/tree/archive/exp-250)
(`71d489d`) made no public API change. It:

1. opened a second writable connection with the same encryption key and SQLite
   configuration as the writer;
2. let the writer WAL hook track the last observed main-WAL page count and the
   next 500-page high-water under a SQLite mutex;
3. detected WAL restart from any observed page-count drop, rather than requiring
   a below-500 observation;
4. used a coalesced `idle / requested / running / running-rerun` state machine,
   with the writer isolate claiming requests after successful top-level commits;
5. ran PASSIVE checkpoints on a dedicated Dart isolate and explicitly adopted
   an overtaken claimed request during close;
6. preserved the existing inline PASSIVE path for attached WAL schemas, because
   the main-only checkpoint connection cannot checkpoint them; and
7. added focused restart, attached-WAL, sustained, close-race, encryption, and
   first-crossing tests.

The retained
[`benchmark/experiments/async_checkpoint_high_water.dart`](../benchmark/experiments/async_checkpoint_high_water.dart)
uses exp 132's 10,000-row x 20-parameter mixed-emoji batch for the known
529-frame first crossing. Its sustained lane performs 3,000 awaited 8 KiB
writes, samples a foreground read every 100 writes, and observes WAL progress
with non-mutating `wal_checkpoint(NOOP)` probes immediately and after 250 ms.

A 100-write control stops at 415 frames, so it exercises the candidate's hook
and request bookkeeping without ever scheduling a checkpoint.

## Results

Two seven-repeat comparisons ran in opposite order. Lower is better.

| Pair | Metric | Baseline | Candidate | Delta |
|---|---|---:|---:|---:|
| baseline first | first crossing p50 | 49.106 ms | 23.093 ms | **-53.0%** |
| baseline first | sustained write p50 | 0.040 ms | 0.101 ms | **+152.5%** |
| baseline first | sustained write p95 | 0.084 ms | 0.209 ms | **+148.8%** |
| baseline first | sustained write p99 | 0.308 ms | 0.936 ms | **+203.9%** |
| baseline first | foreground read p95 | 0.207 ms | 0.163 ms | -21.3% |
| candidate first | first crossing p50 | 66.196 ms | 23.885 ms | **-63.9%** |
| candidate first | sustained write p50 | 0.042 ms | 0.100 ms | **+138.1%** |
| candidate first | sustained write p95 | 0.092 ms | 0.242 ms | **+163.0%** |
| candidate first | sustained write p99 | 0.345 ms | 0.903 ms | **+161.7%** |
| candidate first | foreground read p95 | 0.195 ms | 0.180 ms | -7.7% |

The high-water trigger preserves the attractive first-crossing result and
improves it slightly relative to exp 233: candidate p50 is 53-64% lower, and
the immediate/settled WAL samples move from `529/0` to `529/529`. The writer
reply no longer waits for the backfill.

It still fails every sustained write gate. Pooled p50 becomes 2.4-2.5x slower,
p95 2.5-2.6x slower, and p99 2.6-3.0x slower in both orderings. Foreground-read
p95 improves, showing that high-water scheduling did remove exp 233's read-side
checkpoint storm, but that does not rescue the foreground write regressions.

The order-flipped below-threshold control locates the damage more narrowly.
With no checkpoint request possible, pooled p50 moves from 0.112 to 0.107 ms
(-4.5%) in the first pair and 0.104 to 0.105 ms (+1.0%) in the flip. The
candidate's inert request bookkeeping is therefore neutral at p50; the large
sustained regression appears only once PASSIVE work overlaps WAL growth.

The WAL gate also fails. Baseline ends every sustained repeat at a stable
301-frame remainder. Candidate pair 1 settles there, and the first five repeats
of pair 2 do too. But pair-2 repeats 6 and 7 return `SQLITE_OK` after only
partially checkpointing the WAL and remain unchanged after 250 ms:

| Repeat | WAL log | Checkpointed | Pending after 250 ms |
|---:|---:|---:|---:|
| 6 | 12,377 | 3,212 | **9,165** |
| 7 | 12,377 | 2,061 | **10,316** |

This is not exp 233's level-trigger bug. PASSIVE can legitimately return
`SQLITE_OK` with `checkpointed < log` when a reader pins frames. The candidate
consumes the high-water request after that bounded call and has no safe retry
until another 500 frames arrive. Immediate retry would spin against a
long-lived reader; a correct design needs delayed/backed-off retry ownership,
cancellation, and close semantics.

Independent review found two additional correctness gaps in the archived
prototype:

- Page-count drop is only an observable proxy for WAL generation. If the first
  commit after restart lands at a count equal to or above the last observed
  count but still below `next_request_pages`, the hook cannot identify the new
  generation and can leave an already-above-threshold WAL unrequested. Strict
  reset semantics need a real generation signal, not only a count comparison.
- The checkpoint isolate has no `onExit` / `onError` lifecycle channel.
  Entrypoint failure before its handshake can hang open; later worker death can
  hang close and leave native state `RUNNING`, suppressing future claims.

The focused restart test proves the observable-drop case, not the impossible
count-only generation distinction. These gaps are recorded against the archive;
they were not patched after the measured candidate was rejected.

## Decision

**Rejected.** Reset/high-water rearming fixes the specific continuously armed
trigger from exp 233 and preserves a 53-64% one-shot win, but off-writer
checkpoint ownership still makes sustained write p50/p95/p99 2.4-3.0x slower.
It can also strand more than 10,000 pending frames after a partial PASSIVE
completion.

Runtime code and checkpoint-worker-specific tests were reverted. The focused
harness remains as the durable gate, and the exact tested prototype is
preserved at `archive/exp-250`.

This closes another scheduler-only retry. Do not add delayed retry timers,
another worker protocol, or more state on speculation: the current release
evidence still does not show that synchronous 500-frame checkpoint wall is a
representative user problem. Reopen only with:

1. a downstream/release trace showing material real-world checkpoint incidence;
   and
2. either a materially simpler SQLite-native ownership mechanism or a bounded
   partial-progress retry design with a real generation signal, worker-failure
   propagation, backoff, cancellation, close draining, and neutral sustained
   write tails.

## Transferable Lesson

Bounding asynchronous request admission does not bound maintenance completion.
A reset/high-water scheduler can prevent a level-trigger storm while still
forgetting unfinished work: PASSIVE's return code describes whether the call
failed, not whether all eligible frames were copied. Admission generation and
partial-progress retry are separate state machines, and both need explicit
load and close policies.

## Validation

Archived prototype:

- focused Dart analysis: clean
- high-water checkpoint and core database tests: 63/63
- checkpoint restart, attached-WAL, sustained, close-race, and encryption
  integration tests: 6/6
- native build through package build hooks
- two order-flipped focused A/B comparisons, seven repeats per side
- two order-flipped below-threshold control comparisons
- independent concurrency/state review
- `git diff --check`

Final publication branch:

- runtime and checkpoint-worker-specific tests reverted; exact prototype pushed
  to `archive/exp-250`
- all restored package/runtime sources are byte-identical to `origin/main`
- `dart run build_runner build --delete-conflicting-outputs`
- `dart run benchmark/finalize_experiment.dart \
  --experiment=experiments/250-async-checkpoint-high-water.md`
- `dart run benchmark/check_experiment_dispositions.dart`
- `dart analyze --fatal-infos`
- full serial suite: 338/338
- JSON validation and `git diff --check`
