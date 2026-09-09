# Exp 287 — streaming-reply batched stream reruns

Host: Darwin 25.2.0, Apple silicon, load average 1.7–2.1 across the session.
Both arms are AOT (`dart build cli`) built from separate worktrees — baseline
at `origin/main` (262da99), candidate on `exp-287-batched-stream-rerun` — and
run as separate processes, alternating arm order between passes. Exp 249's
rejection turned on an in-process toggle manufacturing a false win, so nothing
here uses one.

```
cp benchmark/experiments/stream_rerun_latency.dart      bin/exp287_lat.dart
cp benchmark/experiments/stream_rerun_one_pass_ab.dart  bin/exp287_drain.dart
dart build cli --target=bin/exp287_lat.dart   --output=<dir>
dart build cli --target=bin/exp287_drain.dart --output=<dir>
```

`B`/`C` marks which arm ran first in the pass. Δ is candidate against baseline
within the pass.

## 1. Did the batched path actually engage?

Temporary counter (`-DRESQLITE_EXP287_STATS=true`, removed before merge), JIT,
`stream_rerun_one_pass_ab.dart --lane=fanout --samples=21 --warmup=5` — the
whole 26-burst collection:

| counter | value |
|---|---:|
| rerun members dispatched | 10,400 |
| batched messages carrying them | 432 |
| mean members per batch | 24.1 |
| members that changed (one reply each) | 2,495 (24.0%) |
| members that sent no reply at all | 7,905 (76.0%) |
| reruns that took the scalar path | 0 |

So the candidate replaced 10,400 request sends with 432 and deleted 7,905
replies outright — a 24:1 cut on the request side and a 4:1 cut on the reply
side.

## 2. Backlog drain — the throughput metric

`exp287_drain --lane=fanout --samples=21 --warmup=5`. 100 streams over 100-row
partitions, 200 concurrent writes, timed by exp 283's sentinel: a stream on a
partition the burst never touches, armed after the burst is issued, so its
emission prices the whole backlog rather than a prefix of it.

| pass | first | baseline ms | candidate ms | Δ |
|---|---|---:|---:|---:|
| 1 | B | 5.517 | 6.132 | +11.1% |
| 2 | C | 6.302 | 6.115 | −3.0% |
| 3 | B | 5.949 | 6.168 | +3.7% |
| 4 | C | 6.364 | 6.206 | −2.5% |
| pooled | | 6.033 | 6.155 | **+2.0%** |

Sign flips with order. Zero-ceiling control, the same write burst with nothing
subscribed (`--lane=writes`, 2 passes): −5.2% and +0.7% — the collection's own
floor is about ±5%, and the fan-out deltas sit inside it.

The control also sizes the denominator: the write burst alone is 1.75 ms of the
6.03 ms drain.

## 3. Single-write emission latency — the exp 249 gate

`exp287_lat --trials=60`, 4 order-flipped passes, both scenarios. One write
dirties all 100 streams and changes exactly one; the timer runs from write
issue to that stream's emission.

### 3a. First collection — before the worker-allocation fix

| metric | p1 (B) | p2 (C) | p3 (B) | p4 (C) |
|---|---:|---:|---:|---:|
| homogeneous p50 | +20.5% | −40.8% | −27.2% | −33.5% |
| homogeneous p95 | −26.6% | +29.6% | +52.2% | +24.4% |
| hetero p50 | +90.2% | +77.1% | +74.2% | +16.1% |
| hetero p95 | +7.1% | +154.7% | +47.9% | +194.3% |

The heterogeneous regression reproduced 4/4 and was a defect in the
candidate's flush policy, not in the reply protocol: entries too large to batch
were dispatched scalar *first*, consuming every free worker, so the 90 cheap
partitions stayed queued behind the 10 large ones' re-hashes. The dirty set is
enumerated in stream-registration order, which put the large partitions at the
head. The unbatched path cannot do this because it pulls from one FIFO.

### 3b. Second collection — after splitting the free workers between classes

| metric | p1 (B) | p2 (C) | p3 (B) | p4 (C) |
|---|---:|---:|---:|---:|
| homogeneous p50 | +236.8% | +9.4% | −45.2% | −45.9% |
| homogeneous p95 | +89.1% | +196.2% | −54.4% | −50.6% |
| hetero p50 | −52.2% | −9.3% | −13.2% | −52.0% |
| hetero p95 | +49.3% | +30.2% | +7.3% | +27.5% |

Pass 1's homogeneous arm (candidate p50 1.556 ms against its own 0.373/0.307 in
later passes) is a session-warmup outlier; pass 1 was anomalous for one arm or
the other in both collections.

Reading across both collections: **p50 moves in the candidate's favour** —
homogeneous −27% to −46% in six of eight passes, heterogeneous −9% to −52% in
4/4 after the fix. This is the exp 249 comparison reversing: that experiment
measured homogeneous p50 at **+22%** and heterogeneous at **+66%**.

**p95 does not resolve.** Its direction was positive in 11 of 16 pass-deltas,
but the two collections disagree on homogeneous (+29/+52/+24 then +89/+196/−54/−50),
and a longer single-shot run at 120 trials does not separate the arms:

| arm | scenario | p50 | p75 | p90 | p95 | p99 | max |
|---|---|---:|---:|---:|---:|---:|---:|
| base | homogeneous | 0.732 | 1.515 | 2.851 | 3.344 | 4.008 | 5.061 |
| cand | homogeneous | 0.811 | 2.016 | 2.801 | 3.509 | 4.923 | 6.326 |
| base | homogeneous | 0.832 | 2.219 | 2.819 | 3.672 | 6.045 | 6.181 |
| cand | homogeneous | 1.201 | 1.713 | 2.254 | 2.595 | 3.204 | 3.323 |
| base | hetero | 1.275 | 2.266 | 2.668 | 2.848 | 4.112 | 4.187 |
| cand | hetero | 0.779 | 1.265 | 2.473 | 3.449 | 6.231 | 14.103 |
| base | hetero | 1.349 | 2.201 | 2.812 | 4.122 | 4.620 | 5.157 |
| cand | hetero | 0.763 | 1.087 | 1.669 | 2.953 | 4.808 | 5.055 |

The tail is where static chunk assignment would be expected to lose — a member
at the end of a long chunk cannot be picked up by a worker that has gone idle,
which the FIFO always allows — and the single 14.1 ms candidate sample is the
shape of that, but one sample is not evidence. Recorded as unresolved.

## 4. What this collection decides

The predeclared acceptance rule required the drain to reproduce ≥5% better in
both orders. It is flat, inside the control's own floor, after a 24:1 cut in
request messages and a 4:1 cut in replies. That is the result, and it does not
depend on the unresolved p95.
