# Experiment 104: Re-eval of exp 094 (dirty/read table string reuse) under A11c fan-out

**Date:** 2026-04-25
**Status:** Rejected

## Problem

[Exp 094](094-dirty-read-string-reuse.md) (Apr 23, 2026) made
`read_set_add` and `dirty_set_add` keep the existing `strdup` buffer
when a reused slot already held the same table name, eliminating one
`free`/`strdup` pair per stable-table capture cycle.

It was rejected with: *"Focused dispatch was effectively flat and the
full suite produced no wins; native branch/lifetime complexity is not
justified."* The full release comparison reported **0 wins, 14
regressions, 139 neutral.**

094's rejection happened **before A11c existed.** [A11c
(Many-Streams Writer Throughput)](../benchmark/suites/many_streams_writer_throughput.dart)
landed two days later (Apr 25) on
[#39](https://github.com/danReynolds/resqlite/pull/39). It is
structurally a focused-dispatch suite under fan-out: 50 streams × 500
writes × ⌈50/4⌉ pool round-trips means thousands of stream-side
`read_set_add` calls and writer-side `dirty_set_add` calls per timed
loop, all hitting the same handful of table names repeatedly.

[Exp 105](105-reader-pool-sizing.md) — also rejected, also Apr 25 —
explicitly identified A11c as the right test bed for re-evaluating
this class:

> The real lever for A11c is **batching the per-write fan-out
> itself**, not parallelizing it harder. Re-query batching (revisit
> exp 071 / 093 / 094 under A11c) and column-tracking dispatch
> elision (exp 052) both remain on the table.

This experiment is the **094 leg of that revisit.** Pattern-matches
[exp 065](065-json1-reevaluation.md) — explicit re-eval of an earlier
rejection under a workload that didn't exist when the original verdict
was rendered.

## Hypothesis

094's target — one `free` + one `strdup` per stable-table capture — is
real but small (~hundreds of ns per pair). On the original suite the
amplification factor was ≈1 capture per query, so the ceiling was
below MDE. A11c amplifies it: at N=50 streams × 500 writes, the
writer's dirty-table emit fires 50 × 500 = 25,000 times in the timed
loop, and the reader pool replays each subscribed stream's
`selectIfChanged` against a fresh capture — multiplying the
`read_set_add` traffic per write by `⌈50/4⌉=13` pool round-trips.

If the per-pair cost lifts above the noise floor under that
multiplier, A11c writer throughput should rise materially without
regressing anything else (the change is local to the slot-reuse
branch and its semantic invariant — that names returned to Dart stay
valid until the next capture cycle — is preserved).

## Approach

The implementation is a literal port of 094's idea to current
`native/resqlite.c` (the file has evolved since 094 was authored:
`stmt_cache_entry_set_read_tables`, `read_set_load_from_cache_entry`,
and the surrounding allocator are post-094 additions, but the two
target functions are line-for-line the same as when 094 was written —
no merge/cherry-pick conflicts, no semantic drift).

094 did not have an `archive/exp-094` tag of its own implementation —
the existing `archive/exp-094` tag is for an unrelated *renumbered*
094 (skip `sqlite3_column_count` FFI on cache hit, also rejected). So
this is a port of the idea from 094's writeup, not a cherry-pick:

```c
// read_set_add — A11c-relevant on stream-side reads
if (s->count < s->allocated) {
    if (strcmp(s->names[s->count], table_name) == 0) {
        s->count++;
        return;        // reuse strdup buffer; no free, no strdup
    }
    free(s->names[s->count]);
}
s->names[s->count] = strdup(table_name);

// dirty_set_add — A11c-relevant on writer-side dirty emit
//   (same shape, RESQLITE_MAX_DIRTY_TABLES)
```

Tested locally; **reverted before commit** since the result was below
the noise floor (see Results). The implementation sketch above is
preserved here for any future cherry-pick if measurement conditions
shift.

## Results

Artifacts:

- Baseline: [`benchmark/results/2026-04-25T19-43-21-baseline-for-exp105.md`](../benchmark/results/2026-04-25T19-43-21-baseline-for-exp105.md)
  *(reused — same hardware, same day, same `--include-slow` invocation;
  pre-dates the candidate by minutes)*
- Candidate: [`benchmark/results/2026-04-25T20-39-51-exp104-094-reeval-candidate.md`](../benchmark/results/2026-04-25T20-39-51-exp104-094-reeval-candidate.md)

The harness picked `2026-04-25T19-47-54-exp105-reader-pool-8.md` (the
exp 105 cap=8 *rejected* candidate) as its automatic comparison
anchor because it was the most recent file in `benchmark/results/`,
not the cap=4 baseline that's actually relevant. The deltas reported
in the candidate file's "Comparison vs Previous Run" table compare
against cap=8 and are therefore "less bad than the rejected
exp 105 candidate" rather than "vs current main." The numbers below
are computed manually against the cap=4 baseline, which is the
correct anchor.

### A11c writer throughput (50 streams × 500 writes, primary signal)

| Scenario | Baseline (ms) | Candidate (ms) | Baseline w/s | Candidate w/s | Δ w/s |
|---|---:|---:|---:|---:|---:|
| No-streams baseline | 9.98 | 13.80 | 50,110 | 36,232 | **−28%** *(noisy: baseline CV 30%, candidate CV 30%)* |
| Disjoint (50 streams) | 126.39 | 121.36 | 3,956 | 4,120 | +4% *(within ±16% MDE_ci)* |
| Overlap (50 streams) | 111.69 | 114.08 | 4,477 | 4,383 | −2% *(within ±20% MDE_ci)* |

The two stream-fan-out scenarios — the actual amplification target —
moved by a few percent in opposite directions, both well inside the
candidate's bootstrap CI. The no-streams baseline's −28 % w/s looks
large in isolation but lives in a high-variance row (CV 30 % on both
sides) and is not corroborated by any other write or read benchmark
showing similar regression direction; without repeats it is
indistinguishable from run-to-run drift.

### Suite-level summary

**8 wins, 10 regressions, 152 neutral** in the harness's automatic
comparison vs the cap=8 anchor. After back-out: the wins are
"recovered from cap=8 catastrophe" rather than "improved over cap=4"
(e.g. *High-Cardinality Stream Fan-out −47 %* and *4× Concurrent
Reads −69 %* are both reverting cap=8's regressions, not new gains).
None of the 10 regressions point at an isolated change driven by the
fast-path itself; they pattern-match run-to-run drift on small-row
schema-shape and scaling rows.

### Concurrent reads (1× / 2× / 4× / 8×) vs cap=4 baseline

094's original hypothesis touched the read-set capture path. Cross-check:

| Concurrency | Baseline (ms) | Candidate (ms) | Δ |
|---:|---:|---:|---:|
| 1× | 0.29 | 0.31 | +7 % *(within 10 % noise)* |
| 2× | 0.37 | 0.33 | −11 % *(within 10 % noise)* |
| 4× | 0.41 | 0.45 | +10 % *(within 10 % noise)* |
| 8× | 0.76 | 0.84 | +11 % *(within 16 % CV)* |

No directional signal — three rows trend slightly slower, one
slightly faster. Per-cycle savings on `read_set_add` are not lifting
the read path at any concurrency level.

## Decision

**Rejected.** Even under A11c-shaped fan-out — the maximum
amplification we currently have for `read_set_add` / `dirty_set_add`
traffic — the 094 fast-path's deltas are inside the noise band on
every workload it should affect:

- A11c disjoint **+4 % w/s** (within ±16 % MDE_ci)
- A11c overlap **−2 % w/s** (within ±20 % MDE_ci)
- Concurrent reads **±10 %** at every concurrency level

This empirically validates 094's original rejection rationale
*(*"focused dispatch was effectively flat"*)* under stronger
amplification: the per-cycle `free`/`strdup` pair is real but lives
below the harness's measurement floor. The native branch + lifetime
complexity is still not justified.

Pattern-matches exp 102 (savepoint string cache, also rejected on
"theoretically removable, practically below noise") and the broader
late-2026 cluster of rejected micro-shaves on the dispatch path
(071, 076, 081, 093, 094, 095, 099, 102). The codebase has chased
this lever to the floor; further per-call savings on read-set /
dirty-set capture should wait for a structural change that
significantly increases per-write traffic — A11c is already the
heaviest workload available and it isn't enough.

Code reverted before commit. Writeup keeps the implementation sketch
in *Approach* for cherry-pick if a future workload (e.g.
many-streams-many-tables) ever amplifies the path further.

