# Experiment 269: bound the read, don't predict it

**Date:** 2026-08-11 (verdict corrected 2026-08-12)
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused AOT routing A/B in
  [`benchmark/results/2026-08-11T06-00-00Z-exp269-focused-ab.md`](../benchmark/results/2026-08-11T06-00-00Z-exp269-focused-ab.md),
  release sweep in
  [`benchmark/results/2026-08-11T08-01-12-exp269-enforced-inline-reads.md`](../benchmark/results/2026-08-11T08-01-12-exp269-enforced-inline-reads.md),
  and the decisive opaque-work A/B in
  [`benchmark/results/2026-08-12T10-15-00Z-exp269-opaque-work.md`](../benchmark/results/2026-08-12T10-15-00Z-exp269-opaque-work.md).

> **Rejected after adversarial review.** The small-read speedup is real, but the
> candidate's defining claim is not: rows, payload bytes, VM opcodes, and a
> pre-call stopwatch do not bound how long arbitrary SQLite work may hold the
> calling isolate. The exact tested runtime is preserved at `archive/exp-269`
> (`dd252db49a538777f0c23135f2e466be5c12e2a7`); all runtime changes are reverted
> from the publication branch.

## Problem

[Exp 265](265-inline-main-isolate-select.md) measured that an isolate round trip
is most of a hot point read, then rejected running the query on the calling
isolate because its row-count admission signal could not bound three hazards:
one row may hold a huge value, expensive work may precede the first row, and an
awaited chain of inline reads drains without an event-loop turn.

Exp 269 challenged the broader assumption that those hazards require a worker.
Instead of predicting query cost, it attempted to enforce ceilings while the
query ran.

## Hypothesis

**Assumption challenged: arbitrary `select()` work may run on the calling
isolate if every relevant cost is stopped in flight.**

The candidate retained exp 265's private routing after two small observations,
but added four limits:

- 64 decoded rows;
- 64 KiB of TEXT/BLOB payload, checked before Dart copies each cell;
- 10,000 SQLite VDBE opcodes through a progress handler;
- 1 ms of inline work per event-loop turn, checked before starting another
  inline read.

Crossing a per-query cap reset the statement and re-ran it on a worker. A
per-SQL latch prevented repeating an abort. The proposal would be accepted only
if these limits bounded caller-isolate work for the full supported `select()`
surface while preserving exp 265's point-read win.

## Approach

The prototype reserved a fifth read-only connection for the calling isolate.
After a SQL string had produced two small results, `ReaderPool.select` executed
it synchronously on that connection. `decodeQuery` enforced row and payload
limits, native code installed a progress handler for the VM-step limit, and a
zero-duration timer retired the pool's per-turn stopwatch after the event loop
regained control.

The focused routing harness gained the three guards exp 265 requested:

- a one-row 5 MiB BLOB point read;
- a filtered count and unindexed sort whose work precedes their small result;
- frame-timer lateness during a continuous chain of cheap reads.

Those guards found the failures they were built for. They did not cover work
hidden inside one SQLite operation, lock or I/O waits, first-time preparation,
or application-defined callbacks. The lasting harness therefore also includes
[`select_inline_opaque_work.dart`](../benchmark/experiments/select_inline_opaque_work.dart),
which makes one expensive built-in function call and returns one INTEGER.

## Results

### The latency mechanism is real

The focused AOT comparisons retained the expected large wins:

| lane | final-candidate collection | interpretation |
|---|---:|---|
| `point1` | -60.0% | hot one-row read |
| `point1-wide20` | -64.9% | hot one-row, 21 columns |
| `page20` | -38.2% | 20-row page |
| `page64` | -24.0% | 64-row page |
| `point-under-load` | -89.5% | point read while all workers are busy |
| `concurrent8` | -69.8% | eight point reads, serial inline vs four workers |
| `cap-abort` | +30.5% | one abandoned decode plus worker replay |

Only collection 3 used the final sentinel-based shared-loop implementation, so
it supplies two order-flipped verdicts for that exact runtime. Collections 1 and
2 used the earlier guarded-cap loop and are supporting mechanism evidence, not
additional repetitions of the final candidate.

The 5 MiB BLOB and scan guards were neutral after their SQL strings had latched
to worker dispatch, and direct routing tests confirmed their first large
execution aborted. A cheap-read chain with a 1 ms turn budget reduced the
focused timer-lateness sample from 2381 us under dispatch to 1147 us; making the
budget unreachable produced 33,344 us. This proves the budget yields a chain of
already-cheap reads. It does not prove one synchronous read is bounded.

The same-host release sweep against the actual parent commit recorded 1 win, 0
regressions, and 168 neutral metrics. That is a collateral-damage check, not a
product-value receipt: the sole win was the synthetic point-query throughput
lane, while representative chat/feed lanes were neutral.

### The safety premise is false

The decisive probe arms this SQL with two one-byte executions, then requests a
16 MiB value:

```sql
SELECT length(randomblob(?)) AS n
```

It returns one INTEGER, copies no result payload, and completes in far fewer
than 10,000 VDBE opcodes. The expensive byte generation happens inside one
SQLite function opcode, beyond every proposed cap. Three same-process samples:

| arm | elapsed us | 1 ms timer fired before `select()` returned? |
|---|---|---|
| parent `96e6730` | 27,629 / 25,975 / 26,032 | yes / yes / yes |
| candidate `dd252db` | 27,790 / 26,105 / 26,203 | **no / no / no** |

The database work costs the same in both arms. Current main parks the caller on
a worker, so the timer runs; the candidate executes synchronously and blocks the
calling isolate for 26-28 ms. The nominal 1 ms per-turn budget is exceeded by
more than 25x, proving it cannot cap one read, without crossing a row, byte, or
opcode limit.

Code audit found this is a class of failures, not one unusual built-in:

- SQLite checks the progress handler at selected VM loop boundaries, not inside
  an individual opcode. A user function, collation, virtual table, VFS/page
  fault, or busy wait may therefore consume arbitrary wall time before another
  check. Reader connections retain a 5-second busy timeout.
- Statement acquisition, parameter packing, and a cold prepare occur before the
  progress handler is installed. The dedicated inline connection is cold on its
  first inline execution of each SQL string.
- The payload limit is checked in Dart after native `resqlite_step_row` has
  already scanned the complete TEXT value to classify it as ASCII, so it does
  not bound native work for a wide TEXT cell.
- Every inline error is swallowed and replayed on a worker. Read-only SQLite
  connections prevent database-file writes, but extension functions and virtual
  tables may have observable external or connection-local effects, so replay is
  not generally side-effect-free.
- The calling isolate's decoder cache is process-global and keyed only by SQL.
  Two `Database` objects using identical SQL against different result schemas
  can reuse the wrong `RowSchema`, returning incorrect column names.

Supporting configuration problems reinforced the disposition: the advertised
`RESQLITE_INLINE_ROW_MAX=0` kill switch still admits zero-row statements; the
byte-cap/transfer-threshold invariant is assert-only in release builds; and the
per-SQL abort latch is evicted with the same 128-entry row-memory cache, allowing
dynamic-SQL churn to re-arm a previously rejected statement.

## Decision

**Rejected.** Exp 269 proves that caller-isolate execution can remove 24-90% of
hot small-read latency, but it does not make arbitrary `select()` work safe to
run there. An opcode counter is a useful cancellation mechanism; it is not a
wall-time preemption boundary. A stopwatch read before entering synchronous
native work is an admission check, not an execution budget.

No runtime, build-hook, diagnostic, or test-only API change is kept. The final
branch retains only the focused routing harness additions, the opaque-work
probe, benchmark receipts, and the experiment/index/signal sources. The exact
prototype remains at `archive/exp-269` for inspection, not for reuse as a
shipping base.

### Reopen conditions

Do not retry another caller-isolate policy for the existing arbitrary-SQL
`select()` contract using a richer predictor or more SQLite counters. Reopen
only if at least one of these changes the architecture:

1. an explicit restricted API whose SQL/function/VFS surface makes synchronous
   wall time genuinely bounded and whose semantics permit that trade;
2. a preemptible native execution mechanism that can yield or transfer control
   during an individual SQLite operation without replaying observable work; or
3. representative device evidence justifying a deliberately synchronous API,
   with the blocking semantics public rather than hidden behind `select()`.

For the current API, keep worker-first execution. Future attempts should run the
opaque-work probe before optimizing happy-path routing, and should distinguish
"a cheap-read chain yields" from "one read cannot monopolize the caller".
