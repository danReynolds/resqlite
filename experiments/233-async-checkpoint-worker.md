# Experiment 233: Reject asynchronous WAL checkpoint worker

**Date:** 2026-07-17T06:27:37-04:00
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** focused order-flipped A/B with seven repeats per side; raw tables in [`benchmark/results/2026-07-17T10-27-37Z-exp233-async-checkpoint-worker.md`](../benchmark/results/2026-07-17T10-27-37Z-exp233-async-checkpoint-worker.md)
**Archive:** [`archive/exp-233`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-233)

## Problem

Resqlite's writer WAL hook runs a PASSIVE checkpoint synchronously when a
commit leaves at least 500 frames in the WAL. Exp 029 established why the
policy exists: periodic PASSIVE checkpoints substantially reduce write tails
compared with leaving checkpoint timing to SQLite. But placing the checkpoint
inside the hook means the threshold-crossing write cannot reply until the
checkpoint has copied eligible frames.

On Friday's moonshot cadence, that made a useful architecture question: is the
checkpoint policy right but its ownership wrong? SQLite allows a writable
connection other than the writer to initiate a PASSIVE checkpoint after the
commit releases the write lock. Moving that I/O to a dedicated worker could
preserve the policy while removing maintenance work from user-visible commit
latency.

## Hypothesis

Assumption challenged: a threshold-triggered checkpoint must run synchronously
on the writer connection that received the WAL hook.

The candidate replaced the hook's inline checkpoint with a coalesced request,
then woke a dedicated Dart isolate owning a second keyed writable connection
after the commit completed. The primary acceptance target was at least a 10%
improvement on the first known 529-frame crossing. The kill conditions were a
failure to improve sustained write p99, a foreground-read regression, or a WAL
that did not settle after the burst.

The prototype's complexity budget allowed one private connection, one isolate,
two private FFI calls, a small native request state machine, and explicit close
coordination. No public API change was allowed. A narrow first-crossing win
would still need representative evidence that inline checkpoint wall is common
enough to repay this lifecycle surface before shipping.

## Approach

The archived prototype:

1. opened a dedicated writable checkpoint connection with the same encryption
   key and base SQLite configuration as the writer;
2. changed the WAL hook to mark an `idle / requested / running /
   running-rerun` state protected by a SQLite mutex instead of checkpointing;
3. let the writer isolate atomically claim the request after each successful
   top-level commit and send a one-way wakeup to a checkpoint isolate;
4. ran `sqlite3_wal_checkpoint_v2(..., SQLITE_CHECKPOINT_PASSIVE, ...)` on that
   isolate and coalesced requests that arrived during the call;
5. joined the writer first and performed an unconditional final PASSIVE drain
   before freeing the native database handle, covering cross-sender message
   ordering during close.

The focused harness separated the attractive one-shot result from the risky
sustained shape. Its threshold lane reused exp 132's 10,000-row x 20-parameter
mixed-emoji batch, which creates 529 WAL frames in one commit. Its sustained
lane performed 3,000 awaited 8 KiB writes per repeat, sampled foreground reads
every 100 writes, and observed WAL progress with non-mutating
`wal_checkpoint(NOOP)` calls immediately and after 250 ms.

## Results

Two seven-repeat comparisons ran in opposite order. Lower is better.

| Pair | Metric | Baseline | Candidate | Delta |
|---|---|---:|---:|---:|
| baseline first | first crossing p50 | 61.883 ms | 27.027 ms | **-56.3%** |
| baseline first | sustained write p50 | 0.041 ms | 0.138 ms | **+236.6%** |
| baseline first | sustained write p95 | 0.109 ms | 0.493 ms | **+352.3%** |
| baseline first | sustained write p99 | 0.659 ms | 1.502 ms | **+127.9%** |
| baseline first | foreground read p95 | 0.218 ms | 0.259 ms | **+18.8%** |
| candidate first | first crossing p50 | 66.178 ms | 35.878 ms | **-45.8%** |
| candidate first | sustained write p50 | 0.044 ms | 0.117 ms | **+165.9%** |
| candidate first | sustained write p95 | 0.112 ms | 0.373 ms | **+233.0%** |
| candidate first | sustained write p99 | 0.429 ms | 1.069 ms | **+149.2%** |
| candidate first | foreground read p95 | 0.207 ms | 0.325 ms | **+57.0%** |

The first-crossing mechanism works: it cuts p50 wall by 46-56%, and every
candidate repeat moves from `529/0` frames checkpointed immediately to
`529/529` after 250 ms. The writer replies before the checkpoint I/O completes.

The architecture fails under sustained writes. Pooled write p50 becomes
2.7-3.4x slower, p95 becomes 3.3-4.5x slower, p99 becomes 2.3-2.5x slower, and
foreground-read p95 regresses in both orderings. The candidate WAL reaches
12,377 frames; in the candidate-first comparison, two of seven repeats still
have 2,689 and 3,625 frames pending after 250 ms.

The trigger is the problem. `pages_in_wal >= 500` is safe when the inline
checkpoint completes before the writer returns and the WAL can reset on the
next write. With an asynchronous worker, the writer continues while that
level remains true. Later commits repeatedly request or rerun PASSIVE
checkpoints, so coalescing limits messages but does not prevent a checkpoint
storm competing with the foreground workload.

## Decision

**Rejected.** The one-shot ceiling is real, but this off-writer scheduler fails
all three sustained kill conditions and adds substantial lifecycle/state
surface. Runtime code, checkpoint-worker-specific tests, and the focused
harness are removed from the publication branch; the exact candidate and
harness are preserved at `archive/exp-233`, and the raw A/B result remains in
the publication record.

Do not retry the same level-triggered worker. Reopen only with a reset-aware or
high-water trigger that cannot remain armed throughout a write burst, then use
the sustained write/read lane as the load-bearing adoption gate rather than the
first threshold crossing. A representative downstream trace showing inline
checkpoint wall is materially user-visible would also be required before a
narrow runtime win could repay a second connection, isolate, state machine, and
shutdown protocol.

## Transferable lesson

Offloading maintenance work changes the semantics of its trigger. A level check
that is naturally self-clearing when work runs inline can become permanently
true when execution is asynchronous. Coalescing wakeups is not enough; an
asynchronous maintenance loop also needs an explicit generation, reset, or
high-water re-arm rule, and its benchmark must include sustained foreground
contention rather than only the first event.

## Validation

Archived prototype:

- `dart run build_runner build --delete-conflicting-outputs`
- `dart analyze`
- focused database, transaction, encryption, native portability, and build-hook
  tests: 101/101
- checkpoint threshold, close-drain, and encrypted-connection integration
  tests: 3/3
- strict Clang `-Wall -Wextra -Werror` syntax build
- direct native 792-frame claim/coalesce/PASSIVE smoke
- two order-flipped focused A/B comparisons, seven repeats per side
- `git diff --check`

Final publication branch validation is recorded after the runtime revert.
