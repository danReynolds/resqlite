# Experiment 260: Size the result buffer from what the SQL returned last time

**Date:** 2026-08-04
**Status:** Accepted
**Category:** Performance
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused AOT A/B, no release run (the suite segfaults
  in the sqlite_async peer, see below); harness
  [`benchmark/experiments/select_rows_presize.dart`](../benchmark/experiments/select_rows_presize.dart),
  full tables and mechanism attribution in
  [`benchmark/results/2026-08-04T13-20-00Z-exp260-result-list-presize.md`](../benchmark/results/2026-08-04T13-20-00Z-exp260-result-list-presize.md)

## Problem

`decodeQuery` writes every decoded cell into one flat `List<Object?>`. It has no
idea how big the result will be, so it starts at 256 rows' worth of slots and
doubles whenever it runs out:

```dart
final values = List<Object?>.filled(colCount * 256, null, growable: true);
...
if (writeIdx + colCount > values.length) {
  values.length = values.length * 2;
}
```

That looks like the textbook amortised-O(1) append, and the repo has treated it
as free since [exp 059](059-row-count-hint.md) tried a row-count hint in April
and concluded that "list growth is already cheap." It is not. Growing a
`List<Object?>` allocates a fresh backing array and copies the live elements
into it one at a time, each with a store barrier; the arrays involved are
hundreds of kilobytes to megabytes, so every step also touches pages the process
has never faulted in. A 200,000-slot result reaches its final size through six
doublings and copies about 322,000 slots on the way — roughly 1.6× the result
itself — through a sequence of allocations totalling ~5 MB of immediate garbage.

A standalone AOT reproduction of the decode loop over a fixed cell buffer puts
numbers on it. For [exp 251](251-step-vs-decode.md)'s widest shape, 10,000 rows
× 20 INTEGER columns:

| variant | wall |
|---|---:|
| today: `filled(colCount * 256)` then doubling | 2318 µs |
| pre-sized to the exact final length | 865 µs |
| loads + `switch`, no list store at all | 331 µs |
| `List.filled(200000, null)` on its own | 405 µs |

Exp 251 measured Dart-side result construction at 2524 µs for that same shape
against 5124 µs of total worker wall. The reproduction lands within 8% of it —
so **buffer growth, not cell decoding, is most of what "Dart result
construction" has been costing.** The switch, the typed-data loads and the
stores together are under 500 µs; the other ~1450 µs is the buffer climbing to
its own size.

Exp 251 explicitly warned that its residual bucket was "an accounting bucket,
not a mechanism" and had to be split before anything was designed against it.
This is that split, and the mechanism it names is one nobody had looked at
because a prior experiment had already declared it cheap.

### Why exp 059's rejection does not stand

Exp 059 built essentially this hint — last row count, remembered in the schema
cache, `rowCount + (rowCount >> 2)` of headroom — and measured nothing. Three
things have changed:

1. **Its stated reason was the instrument, not the mechanism.** The rejection
   reads "below the benchmark noise floor" and "the median is taken across
   iterations, so the one-time penalty is averaged away." The release suite in
   April could not resolve what the focused AOT A/B and
   [`ab_drift_check.dart`](../benchmark/ab_drift_check.dart) (exp 177) resolve
   now.
2. **Its mechanism claim is directly falsifiable and false.** "Even for 10k
   rows, only ~3-4 growths are needed" is true and beside the point: the cost is
   the slots copied, not the number of growths.
3. **Its design carried a regression that cancelled the win.** Exp 059 sized the
   *initial* allocation from the hint, deliberately so that "point queries don't
   waste allocation for a 512-slot list with one row's worth of data." Exp 067 —
   published the same day — measured exactly that shrink and found it regressed
   every small-query workload by 40-44%. Exp 059 never connected the two. A
   design that makes large reads faster and small reads slower nets out to the
   noise it reported.

## Hypothesis

If the decoder is told roughly how large the result will be, it can reach that
size in one allocation instead of six, removing the copies without changing a
single decoded value. The win should scale with how far the result overshoots
the initial buffer, and should be invisible on results that fit inside it.

## Approach

Two decisions carry the design, and both come from the two ways this can go
wrong.

**The hint lives on the main isolate, not in the worker.** The obvious home is
the per-worker schema cache, which already keys on SQL — and that is what the
first implementation did. It won 30-35% on mid-sized reads and ~1% on the
largest ones, which is exactly backwards. The cause is the sacrifice path: a
result over `sacrificeSlotThreshold` (32,768 slots) is handed to main via
`Isolate.exit` and **the worker isolate that produced it dies**. Any hint it
learned dies with it, so the results with the most growth to avoid are always
decoded by an isolate that has never seen the SQL. Worse, even under the
threshold a hint learned by one of four pool workers describes only the
executions that landed on that worker.

So `ReaderPool` keeps the memory and stamps it onto each `ReadRequest`, and the
worker uses the request's hint in preference to its own. The per-isolate
fallback stays for the writer isolate, which decodes `tx.select` results, is
long-lived, and is never sacrificed.

**The hint sizes growth, never the initial allocation.** This is what keeps exp
059's regression from coming back, and it is a stronger guarantee than a floor
would be. `grownSlots` is consulted only when the buffer overflows:

```dart
int grownSlots(int colCount, int current, int rowHint) {
  final doubled = current * 2;
  final hinted = colCount * rowHint;
  return hinted > doubled ? hinted : doubled;
}
```

By the time that runs, the result has already proven it is larger than the
initial buffer. A result that fits — a point read, a 200-row list — never
reaches the code at all and executes byte-identical instructions to a build with
no hint in it. The failure mode a size hint would otherwise have is real and was
measured: an early version applied the hint to the initial allocation, and a
`SELECT ... LIMIT ?` alternating between 8,000 and 50 rows made the 50-row
execution **2.8× slower** (68 µs → 198 µs), because zero-filling 60,000 slots it
would never use cost more than the doubling it avoided. Moving the hint to the
growth step took that lane to neutral by construction.

The remembered value is the smaller of the statement's last two row counts, plus
25% headroom, and stays at "no opinion" until two executions have been seen
(`RowSizeMemory`). One observation is not enough to act on: a statement whose
size swings with its parameters would otherwise size every execution for its
largest result. Taking the minimum lets such a statement settle at the small end
— no win, but no tax — while a stable one converges after one extra execution.

`ReaderPool` only creates an entry for a SQL that has returned more rows than
the initial buffer holds, and reads the entry once per request rather than once
on dispatch and once on completion. Both exist for the same reason: a point read
must not pay for a mechanism it can never use. The first version cost 0.3 µs per
point read — about 6%, confirmed by building a variant with the pool bookkeeping
removed and watching the lane return to baseline — which the single lookup
brought back under the effect floor.

## Results

Two order-flipped passes, fresh AOT process per arm, 31 samples per lane,
verdicts from `ab_drift_check.dart`.

| lane | pass 1 | pass 2 | verdict |
|---|---:|---:|---|
| `int20-10k` (10k × 20 INTEGER, 200k slots) | −25.1% | −24.8% | REPRODUCED |
| `int4-5k` (5k × 4 INTEGER, 20k slots) | −32.2% | −33.7% | REPRODUCED |
| `mixed6-10k` (canonical product row × 10k) | −33.6% | −32.3% | REPRODUCED |
| `mixed6-1k` (canonical product row × 1k) | 0.0% | −2.7% | neutral |
| `mixed6-200` (control) | +4.3% | 0.0% | neutral |
| `point1` (control, 200 reads/sample) | +2.6% | −0.2% | neutral |
| `mispredict-shrink` (guard) | −8.5% | 0.0% | neutral |
| `mispredict-mid` (guard) | −6.8% | −0.9% | neutral |

A repeated `select()` that returns thousands of rows is **a quarter to a third
faster end to end** — not the decode step, the whole public call including the
reader round trip and the transfer. The canonical 6-column product row at 10,000
rows, which is the shape the repo's own seeder produces, goes from 3.5 ms to
2.3 ms. The effect scales with how far the result overshoots the initial buffer,
which is why the 5,000-row × 4-column lane (20× overshoot) gains more in
percentage terms than the 10,000-row × 20-column one (39× overshoot but a much
larger absolute floor of real decode work underneath it).

`mixed6-1k` is the bottom of the useful range: 1,000 rows is a 4× overshoot,
worth two doublings, and the saving disappears into noise.

The two control lanes are what make the rest believable. Both return fewer rows
than the initial buffer holds, so the changed growth path is unreachable and the
decode loop runs identical code in both binaries — they move +4.3%/0.0% and
+2.6%/−0.2%, opposite signs and inside the 3% floor. That rules out the
systematic per-worktree binary offset that invalidated exp 254's first
comparison, and it is also the direct evidence that small reads pay nothing:
`point1` is a real point query, timed 200 executions at a time so a 1 µs
stopwatch tick is not 16% of the measurement.

The two guards say the mispredict tax is gone rather than merely small.
`mispredict-shrink` runs the timed 50-row execution behind six 8,000-row ones, so
the hint is saturated at its worst — and it cannot matter, because 50 rows never
overflow the initial buffer. `mispredict-mid` times a 300-row execution in strict
alternation with an 8,000-row one, where the hint *is* consulted: the min-of-two
rule settles it at 375 rows, below what doubling gives, so the lane falls back to
baseline behaviour on its own.

Memory was not measured — no RSS or heap sampling was taken, and the numbers
below are arithmetic on the allocation path, not a result. What the arithmetic
says is worth stating precisely, because the two halves do not point the same
way:

| shape | peak capacity | total allocated |
|---|---:|---:|
| `int20-10k` | −23.7% | −60.8% |
| `int4-5k` | −23.7% | −59.7% |
| `mixed6-10k` | −23.7% | −60.8% |
| `mixed6-1k` | **+22.1%** | −16.0% |
| 2048 rows × 6 columns | **+25.0%** | −26.7% |

**Total bytes allocated fall everywhere**, by 14-61%, because the intermediate
arrays a doubling sequence leaves behind stop existing — a 200k-slot query
allocates ~250k slots instead of ~650k. That is the half this change actually
controls, and it is why the transient garbage claim holds.

**Peak capacity is not a guaranteed improvement.** Doubling's overshoot is
whatever the result's size happens to be relative to a power-of-two boundary,
between 1× and 2×; a converged hint's is always 1.25×. So a result that
overshoots a boundary — all three primary lanes — ends up in a buffer 23.7%
smaller, but one that lands *just under* a boundary ends up 22-25% larger.
`mixed6-1k` is exactly that case, in this harness. The live footprint of one
in-flight result can therefore be up to a quarter larger than before, and a
workload that cares about peak rather than churn should be measured rather than
inferred from this.

## Outcome

**Accepted.** A reproduced 25-34% on repeated multi-thousand-row `select()`
reads, with results returning byte-identical rows, no public API change, and
control lanes proving small reads are untouched.

Where it applies: any SQL executed more than once that returns more rows than
the 256-row initial buffer. That is most of what a reactive database does —
stream re-queries, list views, paginated feeds — and the second execution
onwards gets the full effect. A one-shot query, or one returning a few hundred
rows, is unchanged.

This closes exp 059 as *wrongly rejected* rather than merely re-tested: its
mechanism was sound, its measurement could not see it, and its placement of the
hint on the initial allocation carried exp 067's regression in the same change.

Would reopen the sizing question if the Dart VM ever grows a `List<Object?>`
without a per-element barriered copy, at which point the remaining growth cost
would be the allocation alone and the hint would be worth re-timing. Would
revisit the min-of-two rule if a real workload showed a statement whose row
count is stable but whose *first* two executions disagree, which would delay its
convergence by one execution.

## Test plan

- `dart analyze --fatal-infos lib/ test/result_buffer_sizing_test.dart benchmark/experiments/select_rows_presize.dart` — clean
- `test/result_buffer_sizing_test.dart` — the growth target can never come out
  below plain doubling, the memory rule's convergence, and end-to-end row
  correctness for a swinging `LIMIT ?`, a result that outgrows its hint, and a
  result that shrinks after a `DELETE`
- `dart test` — 424 tests pass across the full suite
- focused A/B, two order-flipped passes, `ab_drift_check.dart` REPRODUCED on
  every primary lane and neutral on every control and guard
- `dart run benchmark/run_release.dart exp260-result-list-presize --repeat=5` —
  **attempted twice, no artifact.** Both runs segfaulted at the `[15/16] Memory`
  stage inside `pkg_sqlite3_connection_pool_notify_updates`, in the sqlite_async
  peer's `libsqlite3_connection_pool.dylib`. That is the pre-existing peer
  regression [#282](https://github.com/danReynolds/resqlite/pull/282) documents
  ("exp229's own sha ... crashes today at the same [15/16] Memory stage. Only the
  peers changed between those runs"); the crash lands inside repeat 1, so #282's
  per-repeat artifact writing has nothing to persist. Nothing in this diff is
  linked into that library, and no scenario before it reported an error.
