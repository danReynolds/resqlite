# Experiment 260: result buffer pre-sizing

Collected 2026-08-04 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline is `origin/main` at `62602b7`; candidate is the same tree plus the
main-isolate row-size memory and `grownSlots`. Both arms were built as
native-asset-aware AOT CLI bundles so the decode path is AOT-compiled (exp 193's
requirement for any `Row`/decode change):

```console
dart build cli --target=bin/select_rows_presize.dart --output=<arm>
<arm>/bundle/bin/select_rows_presize --warmup=10 --samples=31
```

The harness source is
[`benchmark/experiments/select_rows_presize.dart`](../experiments/select_rows_presize.dart);
`bin/` is only where `dart build cli` requires the entry point to live.

Each arm run is a fresh process; each lane seeds its own database, warms up 10
selects, and then times 31 `db.select(...)` calls. Pass 1 collects baseline
first, pass 2 collects candidate first (order-flipped confirmation per
`JOURNAL.md`). Values are microseconds.

**No release-suite run accompanies this experiment.** `dart run
benchmark/run_release.dart exp260-result-list-presize --repeat=5` was attempted
twice and segfaulted both times at the `[15/16] Memory` stage inside
`pkg_sqlite3_connection_pool_notify_updates`, in the sqlite_async peer's
`libsqlite3_connection_pool.dylib` — the pre-existing peer regression documented
in #282 ("exp229's own sha ... crashes today at the same [15/16] Memory stage.
Only the peers changed between those runs"). The crash lands inside repeat 1, so
the per-repeat artifact writing that #282 added has nothing to persist. Nothing
in this experiment's diff is linked into that library.

## Lanes

| lane | shape | role |
|---|---|---|
| `int20-10k` | 10k rows × 20 INTEGER (200k slots) | primary — exp 251's widest shape, 39× the initial buffer |
| `int4-5k` | 5k × 4 INTEGER (20k slots) | primary — 20× the initial buffer, below the sacrifice threshold |
| `mixed6-10k` | 10k × the repo's canonical 6-column mixed row (`id` INTEGER + 4 TEXT + REAL, verbatim from `benchmark/shared/seeder.dart`) | primary — the default product row shape |
| `mixed6-1k` | 1k × the canonical row (6k slots) | primary — 4× the initial buffer, the bottom of the useful range |
| `mixed6-200` | 200 × the canonical row | control — fits inside the initial buffer, so the changed growth path is unreachable and both arms run identical code |
| `point1` | `WHERE id = ?`, 200 executions per timed sample | control — the other end of the same argument, and the shape most sensitive to per-request overhead |
| `mispredict-shrink` | `LIMIT ?` at 50 rows, behind six untimed 8000-row executions | guard — hint saturated at its worst, but 50 rows never overflow the initial buffer |
| `mispredict-mid` | `LIMIT ?` at 300 rows, strictly alternating with 8000 | guard — the timed query *does* consult the hint, so this tests the rule that picks it |

## Results

| lane | pass | baseline p50 | candidate p50 | Δ p50 | baseline p90 | candidate p90 | Δ p90 |
|---|---|---:|---:|---:|---:|---:|---:|
| `int20-10k` | 1 | 5822 | 4361 | -25.1% | 5927 | 4558 | -23.1% |
| `int20-10k` | 2 | 5815 | 4372 | -24.8% | 5906 | 4503 | -23.8% |
| `int4-5k` | 1 | 727 | 493 | -32.2% | 798 | 499 | -37.5% |
| `int4-5k` | 2 | 735 | 487 | -33.7% | 778 | 505 | -35.1% |
| `mixed6-10k` | 1 | 3497 | 2321 | -33.6% | 3670 | 3306 | -9.9% |
| `mixed6-10k` | 2 | 3461 | 2342 | -32.3% | 3865 | 3471 | -10.2% |
| `mixed6-1k` | 1 | 219 | 219 | +0.0% | 220 | 224 | +1.8% |
| `mixed6-1k` | 2 | 224 | 218 | -2.7% | 227 | 223 | -1.8% |
| `mixed6-200` | 1 | 47 | 49 | +4.3% | 48 | 50 | +4.2% |
| `mixed6-200` | 2 | 49 | 49 | +0.0% | 55 | 52 | -5.5% |
| `point1` | 1 | 1203 | 1234 | +2.6% | 1464 | 1539 | +5.1% |
| `point1` | 2 | 1231 | 1229 | -0.2% | 1448 | 1403 | -3.1% |
| `mispredict-shrink` | 1 | 71 | 65 | -8.5% | 97 | 82 | -15.5% |
| `mispredict-shrink` | 2 | 70 | 70 | +0.0% | 83 | 83 | +0.0% |
| `mispredict-mid` | 1 | 118 | 110 | -6.8% | 134 | 126 | -6.0% |
| `mispredict-mid` | 2 | 108 | 107 | -0.9% | 124 | 123 | -0.8% |

## Drift check

`benchmark/ab_drift_check.dart` over the per-run values of both passes:

| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV | reason |
|---|---|---:|---:|---:|---|
| `int20-10k` | REPRODUCED (real effect) | -25.1% | -24.8% | 1.5% | same-direction effect in both passes with comparable per-side CVs |
| `int4-5k` | REPRODUCED (real effect) | -32.2% | -33.7% | 4.8% | same-direction effect in both passes with comparable per-side CVs |
| `mixed6-10k` | REPRODUCED (real effect) | -33.6% | -32.3% | 17.4% | same-direction effect in both passes with comparable per-side CVs |
| `mixed6-1k` | drift-suspected | 0.0% | -2.7% | 65.4% | flagged-side CV asymmetry indicates a drift-contaminated phase, not a code effect |
| `mixed6-200` | inconclusive / neutral | +4.3% | 0.0% | 2.8% | both passes below the 3% effect floor |
| `point1` | inconclusive / neutral | +2.6% | -0.2% | 34.7% | both passes below the 3% effect floor |
| `mispredict-shrink` | inconclusive / neutral | -8.5% | 0.0% | 19.2% | both passes below the 3% effect floor |
| `mispredict-mid` | inconclusive / neutral | -6.8% | -0.9% | 127.8% | both passes below the 3% effect floor |

`mixed6-10k`'s p90 is noisy in both arms (baseline 3670 then 3865 against a
stable ~3480 p50) and moves with the p50 rather than against it; it is not a tail
regression. `mixed6-1k` is the bottom of the range the change can reach — 1000
rows is a 4× overshoot, worth two doublings — and the drift checker correctly
declines to call it.

## Mechanism microbenchmarks

Standalone AOT reproductions of the decode loop over a fixed cell buffer, 40
reps, no database involved. These attribute the end-to-end deltas; they are not
part of the committed harness.

10k × 20 INTEGER (200,000 slots), p50:

| variant | wall |
|---|---:|
| `filled(colCount * 256)` then doubling — today | 2318 µs |
| pre-sized to the exact final length | 865 µs |
| loads + `switch`, no list store | 331 µs |
| `List.filled(200000, null, growable: true)` alone | 405 µs |

Growth in isolation, building to N slots from a 5120-slot start, p50:

| slots | ×2 (today) | ×3 | ×4 | ×8 | exact |
|---:|---:|---:|---:|---:|---:|
| 8,000 | 28 | 33 | 43 | 173 | 12 |
| 20,000 | 66 | 203 | 42 | 141 | 26 |
| 60,000 | 460 | 639 | 296 | 1090 | 187 |
| 200,000 | 2033 | 2040 | 1375 | 1229 | 594 |

A larger growth factor recovers part of the gap but never approaches exact
sizing, and its behaviour swings with where the final size lands relative to a
growth step (×3 at 20,000 slots is worse than ×2). Growing manually with
`setRange` or an explicit copy loop instead of the `length=` setter measured the
same as `length=`, so the cost is the barriered element-wise copy itself, not the
setter.

## Hint placement attribution

Both placements measured against the same baseline binary, p50, pass-1 ordering:

| placement | `int4-5k` (20k slots, `SendPort`) | `int20-10k` (200k slots, sacrificed) |
|---|---:|---:|
| worker-local (per-isolate schema cache) | -30% to -35% | ~-1% |
| carried on the request from main | -32.2% | -25.1% |

`Isolate.exit` ends the worker on any result over `sacrificeSlotThreshold`
(32,768 slots), so a worker-local hint is discarded on exactly the reads with the
most growth to avoid.

Applying the hint to the initial allocation rather than to growth, measured on
the `mispredict-shrink` lane before the design was changed: baseline 68 µs,
candidate 198 µs (+183%) — zero-filling 60,000 slots the 50-row result never
touches costs more than the doubling the hint removes. Applied at the growth step
the same lane is neutral, because a result that fits in the initial buffer never
reaches the code.

## Pool bookkeeping attribution

`point1`, 200 point reads per timed sample, three rounds each, p10 µs:

| build | round 1 | round 2 | round 3 |
|---|---:|---:|---:|
| baseline | 1060 | 1061 | 1061 |
| candidate, two map lookups per request | 1126 | 1117 | 1122 |
| candidate with the pool bookkeeping removed | 1034 | 1056 | 1086 |
| candidate, one map lookup per request (shipped) | 1188 | 1058 | 1032 |

The two-lookup version cost a consistent ~0.3 µs per point read (~6%), and
removing the bookkeeping returned the lane to baseline — which is what
attributes the cost to the pool rather than to the decoder. Reading the entry
once per request, and never creating one for a SQL that has not exceeded the
initial buffer, leaves no consistent sign across rounds.
