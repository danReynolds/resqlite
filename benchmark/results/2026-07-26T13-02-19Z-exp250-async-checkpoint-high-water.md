# Exp 250 async checkpoint high-water A/B

**Date:** 2026-07-26
**Base:** `origin/main` at `bf3d7b834184`
**Candidate:** archived at `71d489dd290a` (`archive/exp-250`)
**Host:** Darwin 25.2.0 arm64
**Dart:** 3.12.2 stable, macOS arm64

## Method

The same retained harness ran from a detached baseline worktree and the
candidate worktree:

```text
dart run benchmark/experiments/async_checkpoint_high_water.dart \
  --label=<side> --repeats=7 --writes=3000 \
  --read-every=100 --settle-ms=250
```

Two comparisons ran in opposite order: baseline → candidate, then candidate →
baseline. Every repeat used a fresh database. The first-crossing lane is exp
132's 10,000-row x 20-parameter mixed-emoji batch, which produces 529 WAL
frames in one commit. The sustained lane performs 3,000 awaited 8 KiB writes
and samples a foreground read every 100 writes. `wal_checkpoint(NOOP)` records
WAL progress without doing the checkpoint work under test.

An additional order-flipped control used 100 sustained writes and no settle
delay. It stops at 415 WAL frames, below the 500-frame trigger, so the candidate
executes its hook/request bookkeeping but never schedules a checkpoint.

## Decision Summary

Lower is better for latency.

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

The reset/high-water trigger preserves the off-writer first-crossing win and
avoids exp 233's foreground-read regression. It still fails every sustained
write gate by a wide, reproduced margin. It also fails the bounded-WAL gate:
two candidate-first repeats remain 9,165 and 10,316 frames behind after the
250 ms settle window.

## First Threshold-Crossing Raw Wall

| Pair | Side | Repeat wall (ms) | p50 | p95 / max |
|---|---|---|---:|---:|
| baseline first | baseline | 57.138, 52.538, 49.106, 43.622, 39.187, 155.897, 44.779 | 49.106 | 155.897 |
| baseline first | candidate | 34.910, 36.961, 24.067, 21.573, 23.093, 19.718, 20.164 | 23.093 | 36.961 |
| candidate first | candidate | 33.456, 35.154, 20.779, 18.953, 23.885, 25.130, 22.318 | 23.885 | 35.154 |
| candidate first | baseline | 68.942, 64.089, 40.580, 44.621, 74.444, 66.196, 105.019 | 66.196 | 105.019 |

On the primary runs, every baseline immediate and settled sample is
`log=529, checkpointed=529`. Every candidate immediate sample is
`log=529, checkpointed=0`; after 250 ms each is
`log=529, checkpointed=529`. This directly verifies that the candidate replies
before the first checkpoint backfill completes.

## Sustained Per-Repeat Write Tails

| Pair | Side | Repeat | p50 ms | p95 ms | p99 ms | max ms |
|---|---|---:|---:|---:|---:|---:|
| baseline first | baseline | 1 | 0.054 | 0.115 | 0.479 | 34.984 |
| baseline first | baseline | 2 | 0.044 | 0.086 | 0.235 | 12.331 |
| baseline first | baseline | 3 | 0.041 | 0.085 | 0.180 | 15.786 |
| baseline first | baseline | 4 | 0.038 | 0.080 | 0.252 | 41.730 |
| baseline first | baseline | 5 | 0.037 | 0.076 | 1.023 | 136.441 |
| baseline first | baseline | 6 | 0.037 | 0.083 | 0.140 | 14.690 |
| baseline first | baseline | 7 | 0.038 | 0.078 | 0.292 | 25.199 |
| baseline first | candidate | 1 | 0.108 | 0.252 | 0.774 | 2.837 |
| baseline first | candidate | 2 | 0.103 | 0.247 | 1.048 | 4.904 |
| baseline first | candidate | 3 | 0.101 | 0.172 | 0.908 | 3.443 |
| baseline first | candidate | 4 | 0.099 | 0.158 | 0.273 | 3.109 |
| baseline first | candidate | 5 | 0.095 | 0.128 | 0.857 | 8.913 |
| baseline first | candidate | 6 | 0.100 | 0.294 | 0.996 | 13.125 |
| baseline first | candidate | 7 | 0.099 | 0.181 | 1.059 | 10.544 |
| candidate first | candidate | 1 | 0.117 | 0.229 | 0.766 | 3.543 |
| candidate first | candidate | 2 | 0.104 | 0.341 | 0.914 | 4.357 |
| candidate first | candidate | 3 | 0.109 | 0.324 | 1.182 | 8.595 |
| candidate first | candidate | 4 | 0.105 | 0.231 | 0.886 | 3.460 |
| candidate first | candidate | 5 | 0.094 | 0.294 | 0.984 | 4.277 |
| candidate first | candidate | 6 | 0.090 | 0.154 | 0.694 | 7.427 |
| candidate first | candidate | 7 | 0.080 | 0.134 | 0.215 | 4.241 |
| candidate first | baseline | 1 | 0.052 | 0.104 | 0.366 | 15.147 |
| candidate first | baseline | 2 | 0.043 | 0.082 | 0.134 | 15.246 |
| candidate first | baseline | 3 | 0.040 | 0.083 | 0.131 | 14.549 |
| candidate first | baseline | 4 | 0.038 | 0.079 | 0.127 | 26.441 |
| candidate first | baseline | 5 | 0.040 | 0.092 | 0.411 | 53.699 |
| candidate first | baseline | 6 | 0.040 | 0.107 | 0.403 | 18.820 |
| candidate first | baseline | 7 | 0.043 | 0.103 | 0.444 | 17.649 |

Pooled rows:

| Pair | Side | Samples | p50 ms | p95 ms | p99 ms | max ms |
|---|---|---:|---:|---:|---:|---:|
| baseline first | baseline | 21,000 | 0.040 | 0.084 | 0.308 | 136.441 |
| baseline first | candidate | 21,000 | 0.101 | 0.209 | 0.936 | 13.125 |
| candidate first | candidate | 21,000 | 0.100 | 0.242 | 0.903 | 8.595 |
| candidate first | baseline | 21,000 | 0.042 | 0.092 | 0.345 | 53.699 |

## Foreground Reads

| Pair | Side | Samples | p95 ms | max ms |
|---|---|---:|---:|---:|
| baseline first | baseline | 210 | 0.207 | 4.508 |
| baseline first | candidate | 210 | 0.163 | 0.310 |
| candidate first | candidate | 210 | 0.180 | 1.688 |
| candidate first | baseline | 210 | 0.195 | 1.946 |

Unlike exp 233, foreground-read p95 improves in both orderings. The high-water
policy successfully prevents its continuously armed read-side checkpoint
storm. That benefit is independent of the failed write and WAL gates.

## WAL Progress

Every baseline sustained repeat ends at `log=301, checkpointed=0`, both
immediately and after 250 ms.

Candidate baseline-first immediate pending counts are
`804, 804, 301, 804, 804, 804, 804`; every repeat settles to 301.

Candidate-first repeats 1-5 move from 804 pending immediately to 301 after
250 ms. Repeats 6 and 7 do not advance during the settle window:

| Repeat | Immediate / settled log | Immediate / settled checkpointed | Pending |
|---:|---:|---:|---:|
| 6 | 12,377 | 3,212 | **9,165** |
| 7 | 12,377 | 2,061 | **10,316** |

PASSIVE can return `SQLITE_OK` after partial progress when a reader pins WAL
frames. The candidate consumes the request and retries only after another
500-frame high-water. When the burst ends after that partial call, no event
remains to schedule the unfinished work.

## Below-Threshold Control

All control sustained runs end at `log=415, checkpointed=0`, proving no
checkpoint request fired.

| Pair | Side | Samples | p50 ms | p95 ms | p99 ms | max ms |
|---|---|---:|---:|---:|---:|---:|
| baseline first | baseline | 700 | 0.112 | 0.313 | 0.584 | 1.977 |
| baseline first | candidate | 700 | 0.107 | 0.343 | 0.527 | 2.194 |
| candidate first | candidate | 700 | 0.105 | 0.306 | 0.498 | 2.012 |
| candidate first | baseline | 700 | 0.104 | 0.180 | 0.399 | 2.020 |

Control p50 is -4.5% in the first ordering and +1.0% in the flip. The large
2.4-2.5x primary p50 regression therefore appears only when PASSIVE work and
WAL growth overlap, not on the idle high-water bookkeeping alone. Control
tails are too unstable to make a stronger attribution.

## Outcome

Rejected. Reset/high-water request admission fixes exp 233's level-trigger
storm, but sustained write p50/p95/p99 regress 2.4-3.0x and partial PASSIVE
completion can strand more than 10,000 WAL frames. Independent review also
found that page-count drops are not a strict WAL-generation signal and the
worker lacks startup/runtime failure propagation.

Runtime and checkpoint-specific tests are reverted. The reusable harness
remains on the publication branch; the exact measured prototype is preserved
at `archive/exp-250`.
