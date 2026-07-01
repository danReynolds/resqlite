# Experiment 209: Heterogeneous Read Batch

**Date:** 2026-07-01T11:11:39Z
**Status:** Accepted
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none — focused
`benchmark/experiments/heterogeneous_read_batch.dart`, order-flipped pair on a
quiet box. No release-suite run; no public read lane is dominated by many
small heterogeneous reads issued together (release-suite lanes are shaped
around either wide batch inserts, single-shot big-payload selects, or
streaming fan-out), so the focused harness is the durable gate here.

## Problem

[Exp 208](208-heterogeneous-write-batch.md) accepted the explicit-semantics
version of [exp 197](197-true-group-commit-moonshot.md)'s ceiling for
*writes*: `db.executeStatements([...WriteStatement...])` collapses N
heterogeneous writer-isolate round trips into one, and a single SQLite
transaction. That win is now shipped for the write path.

The read path has a symmetric gap. To issue N unrelated SELECTs today the
caller uses `Future.wait([db.select(...)])`. Each future is a full reader-pool
`_dispatch` walk plus a main→worker→main round trip, and the reader pool caps
at `clamp(numProcessors - 1, 2, 4)` workers by design ([exp 105]). When per-query
SQLite work is smaller than the round-trip cost — small point-query dashboards,
prefetch bursts, "load these five widgets" pages — the round trips dominate.

There is no way to express "run these N unrelated reads together" today. The
question is whether an explicit read-batch surface can capture the same
round-trip amortization for the read side that exp 208 captured for the write
side, without breaking parallelism guarantees on the shapes where fan-out is
actually the right tool.

## Hypothesis

Assumption challenged: **each SELECT must pay its own reader-pool round trip;
reader-pool parallelism always beats round-trip amortization**.

The bet is that below the reader-pool round-trip floor, amortization wins;
above it, parallelism wins. If both effects reproduce cleanly on the same
harness, an explicit `db.selectAll(...)` surface is justified — it does not
compete with parallel fan-out, it complements it, and the caller picks
based on the shape of the work.

The moonshot is *rejected* if the small-read lanes fail to clear a ~15% win
band or if the large-read guard fails to show the expected regression
(meaning the batching path leaks some other cost that would make it a
universally worse `select` fan-out).

## Approach

Added one public value object:

```dart
const ReadStatement('SELECT body FROM items WHERE id = ?', [1])
```

and one database method:

```dart
final results = await db.selectAll([
  const ReadStatement('SELECT body FROM users WHERE id = ?', [1]),
  const ReadStatement('SELECT COUNT(*) AS c FROM tasks'),
  const ReadStatement('SELECT value FROM settings WHERE key = ?', ['theme']),
]);
final user = results[0].single;
final taskCount = results[1].single['c'];
```

The reader worker handles a new `SelectBatchRequest` sealed variant. Each
statement runs on the worker's dedicated reader connection through the
existing `executeQuery` path — no encoder change, no separate FFI surface,
just N sequential prepared-statement acquires + step loops on one worker.
The sacrifice decision aggregates estimated bytes across the batch, so a
batch containing one huge query still triggers sacrifice while a fanout of
small results does not.

Failure semantics stay explicit: if any statement fails, the batch aborts
on that statement and the original `ResqliteQueryException` propagates with
the failing SQL / parameters intact — statements before the failure have
already executed on their read snapshot; statements after have not run.

Inside a `transaction`, `selectAll` falls back to sequential
`Transaction.select` calls so the batch sees the transaction's uncommitted
writes (matching `db.select`, which routes through `Transaction.current`
when one is active).

Full detail lives in the code:

- `lib/src/read_statement.dart` — public `ReadStatement` value
- `lib/src/reader/read_worker.dart` — new `SelectBatchRequest` variant +
  worker-side aggregation loop
- `lib/src/reader/reader_pool.dart` — `ReaderPool.selectAll(...)`
- `lib/src/database.dart` — `Database.selectAll(...)` with the
  transaction-fallback branch

## Results

Focused benchmark:
`benchmark/experiments/heterogeneous_read_batch.dart` — three lanes on the
same seeded database (10 000-row table, indexed by category), order-flipped
pair. Full harness output is in
`benchmark/results/2026-07-01T11-11-39Z-exp209-heterogeneous-read-batch.md`.

Median deltas across the two order-flipped passes:

| Lane | Shape | Parallel median | Batch median | Δ |
|---|---|---:|---:|---:|
| point | 20 single-row PK lookups | 0.366 / 0.259 ms | 0.099 / 0.103 ms | **−72.9% / −60.2%** |
| medium | 20 × ~10-row list SELECTs | 0.281 / 0.259 ms | 0.151 / 0.149 ms | **−46.3% / −42.5%** |
| large [guard] | 4 × 10 000-row SELECTs | 1.567 / 1.640 ms | 6.397 / 4.506 ms | **+308% / +175%** |

Reading these together: **the small-read lanes reproduce a large batch win
(≈ 2.5× to 3.7× on point, ≈ 1.75× to 1.9× on medium)** — same sign, same
ordering across the order flip, magnitude drifting slightly with which side
runs later. **The large-read guard reproduces the expected regression** (≈
2.75× to 4.1× slower), which is not a bug but the shape confirming the
trade-off: one worker running four 10 k-row reads back-to-back cannot beat
four workers running them in parallel.

That guard result is *load-bearing* for the acceptance decision — it proves
`selectAll` is not a universal substitute for parallel `select` fan-out. It
is the right tool when many small heterogeneous reads are issued together;
`Future.wait([db.select(...)])` is the right tool when each read is
individually expensive enough for the reader-pool fan-out to matter.

Correctness is covered by `test/select_all_test.dart`:

- results returned in statement order,
- empty-list is a no-op returning `const []`,
- a failing statement aborts the batch and the exception carries that
  statement's own SQL, and
- inside a `transaction`, the batch sees uncommitted writes.

The full `dart test` run passes on this branch.

## Outcome

**Accepted**: explicit read-batch amortization is a real win on
the small-heterogeneous-reads shape (`Future.wait` fanout is round-trip
bound there), and the large-read guard confirms the trade-off is a
publish-time knob rather than a hidden default. The public API mirrors
[exp 208](208-heterogeneous-write-batch.md)'s `executeStatements(...)`
shape, so callers get symmetric explicit-batching surfaces for reads and
writes.

Category is `moonshot`: this challenges the assumption that
reader-pool parallelism always beats round-trip amortization, and it
reopens the specific class of small-many-reads workloads that no prior
experiment could evaluate. If the two lanes had failed to reproduce a
same-direction win, or if the guard had *not* regressed (implying the
prototype had leaked a cost that made parallel fan-out uniformly worse),
the direction would have been rejected on evidence.

## Journal-worthy?

Yes — the shape "batch-then-parallel isn't a monotone win; the two are
complementary at the round-trip floor" is a transferable lesson beyond
this experiment. Exp 148's rejection (worker→main reply batching) proved
one direction of that lesson; this experiment proves the symmetric
direction (main→worker request batching). I've drafted a journal entry.

## Next signals

- The reader pool's cap of `clamp(numProcessors - 1, 2, 4)` workers
  interacts with the batch/parallel trade-off: on a machine with a much
  larger reader pool, the point-lane crossover would move. Future signals
  work in this direction should include the reader pool cap in the
  comparison, not just per-query SQLite work.
- A `selectBytesAll(...)` mirror is a plausible follow-up but has a
  concrete complication: `selectBytes` currently returns a `Uint8List`
  view over the reader's persistent `json_buf`, and a batch would need
  either per-item buffer copies (which erode the exp 174 view-transfer
  win) or a re-designed reply shape. Do not extend this prototype to
  bytes without addressing that first. The workload gate would be
  `heterogeneous_read_batch.dart` extended with a bytes lane, not a new
  harness.
- The current sacrifice threshold treats the batch as "one big result"
  for the sacrifice decision. If workloads emerge where a batch mixes
  many small results with one huge one, the sacrifice heuristic may
  under-fire; that is not a load-bearing case today.
