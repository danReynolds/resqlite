# Experiment 267: statement cache capacity

Collected 2026-08-10 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline is `origin/main` at `3e4a6ad`; candidate is the same tree with
`STMT_CACHE_MAX`, `_schemaCacheMax` and `ReaderPool.rowSizeMemoryMax` raised
from 32 to 128, and `stmt_cache_insert` reclaiming the least-recently-used slot
in place instead of compacting the array. Both arms were built as
native-asset-aware AOT CLI bundles from an identical harness source, so the
decode path is AOT-compiled (exp 193's requirement) and only `lib/` and
`native/` differ:

```console
dart build cli   # entry point copied to bin/, one relative import rewritten
<arm>/bundle/bin/stmt_cache_pressure --lane=<lane> --warmup=5 --samples=51
```

The harness source is
[`benchmark/experiments/stmt_cache_pressure.dart`](../experiments/stmt_cache_pressure.dart);
`bin/` is only where `dart build cli` requires the entry point to live, and the
baseline arm was built from the candidate's copy of it. Every lane is
**lane-isolated** — one fresh process per lane per arm — and passes alternate
collection order (odd baseline-first, even candidate-first).

Every lane issues the same 256 point reads per sample, spread over the lane's
statement set, so medians are directly comparable across lanes and no lane is
decided by stopwatch resolution. Values are microseconds per sample.

## Per-pass medians (baseline / candidate)

| lane | pass 1 | pass 2 | pass 3 | pass 4 | peak RSS MB |
|---|---|---|---|---|---|
| `rotate8` | 1460 / 1612 | 1449 / 1482 | 1654 / 1461 | 1469 / 1525 | 30.2 / 31.1 |
| `rotate24` | 1369 / 1381 | 1322 / 1343 | 1392 / 1391 | 1380 / 1367 | 30.3 / 31.1 |
| `rotate32` | 1462 / 1473 | 1699 / 1447 | 1520 / 1481 | 1447 / 1477 | 30.1 / 31.0 |
| `rotate40` | 3282 / 1468 | 3397 / 1658 | 3383 / 1401 | 3387 / 1453 | 30.2 / 31.1 |
| `rotate64` | 3539 / 1584 | 3643 / 1551 | 3537 / 1541 | 3905 / 1909 | 30.3 / 31.1 |
| `rotate128` | 3531 / 1584 | 3605 / 1605 | 3539 / 1547 | 3679 / 1982 | 30.1 / 31.2 |
| `point1` | 1390 / 1349 | 1428 / 1387 | 1428 / 1358 | 1371 / 1362 | 30.1 / 30.9 |
| `churn-unique` | 3687 / 3230 | 3704 / 3167 | 3673 / 3275 | 3690 / 3333 | 30.2 / 31.4 |

## Deltas and drift verdicts

`benchmark/ab_drift_check.dart` was run twice — over passes 1+2, then over
passes 3+4 — so every verdict below is two independent order-flipped pairs.

| lane | role | p1 | p2 | p3 | p4 | mean | verdict (1+2) | verdict (3+4) |
|---|---|---:|---:|---:|---:|---:|---|---|
| `rotate40` | primary | −55.3% | −51.2% | −58.6% | −57.1% | **−55.5%** | reproduced | reproduced |
| `rotate64` | primary | −55.2% | −57.4% | −56.4% | −51.1% | **−55.1%** | reproduced | reproduced |
| `rotate128` | primary | −55.1% | −55.5% | −56.3% | −46.1% | **−53.3%** | reproduced | reproduced |
| `churn-unique` | guard | −12.4% | −14.5% | −10.8% | −9.7% | **−11.9%** | reproduced | reproduced |
| `rotate32` | boundary | +0.8% | −14.8% | −2.6% | +2.1% | −3.6% | neutral | neutral |
| `rotate24` | control | +0.9% | +1.6% | −0.1% | −0.9% | +0.4% | neutral | neutral |
| `rotate8` | control | +10.4% | +2.3% | −11.7% | +3.8% | +1.2% | neutral | drift-suspected |
| `point1` | control | −2.9% | −2.9% | −4.9% | −0.7% | −2.8% | neutral | neutral |

## The rejected first version

The first candidate raised the three caps and left `stmt_cache_insert`
unchanged. Four order-flipped passes on the same harness:

| lane | p1 | p2 | p3 | p4 | mean |
|---|---:|---:|---:|---:|---:|
| `rotate40` | −56.9% | −56.0% | −55.6% | −54.3% | −55.7% |
| `rotate64` | −58.4% | −53.5% | −54.6% | −53.1% | −54.9% |
| `rotate128` | −42.4% | −55.5% | −55.6% | −54.2% | −51.9% |
| `churn-unique` | **+39.0%** | **+43.8%** | **+42.7%** | **+42.7%** | **+42.1%** |
| `rotate32` | −2.3% | −4.1% | −3.3% | −3.6% | −3.3% |
| `rotate24` | −4.3% | +3.8% | −2.4% | −2.0% | −1.2% |
| `point1` | +10.2% | +0.0% | −2.9% | −1.7% | +1.4% |

The primaries are within a point of the shipped version, so the whole
difference between the two candidates lives in the guard lane. The cause was
identified by arithmetic before the second version was built: the eviction
`memmove` shifts `(STMT_CACHE_MAX − 1) × sizeof(resqlite_cached_stmt)` bytes
per prepare, which is 50 KB at 32 entries and 203 KB at 128. `churn-unique`
prepares 256 statements per sample, so the extra traffic is
`256 × 153 KB ≈ 39 MB` per sample; at ~20 GB/s that is ~2.0 ms against a
measured delta of 1.53 ms (5191 − 3660 µs). Removing the shift entirely took
the lane to −11.9%, because the baseline's own 12.8 MB/sample was ~640 µs of
its 3688 µs.

## Memory, from SQLite's side

`benchmark/suites/sqlite_diagnostics.dart`, `Statement cache footprint`
section, 48 distinct SELECT texts — a workload already past the old 32-entry
cliff:

| arm | SQLite total KiB | Stmt KiB | JSON buf KiB |
|---|---:|---:|---:|
| baseline | 3238.7 | 70.5 | 64.0 |
| candidate | 3271.6 | 103.4 | 64.0 |

The `JSON buffer reclaim` guard is unchanged at 64.0 KiB in both arms.

## Host

`top -l 1` reported 62-72% idle across the session, with Chrome and Spotlight
indexing the main other consumers. The controls moving in both directions and
staying inside the floor is the evidence that this did not decide anything;
`rotate8`, the shortest lane, is the one that did not survive it and is
reported as drift-suspected rather than as a small effect.
