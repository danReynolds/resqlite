# Exp 289 writer-rerun opaque-work guard

**Date:** 2026-09-13T10:13:28Z
**Host:** Apple silicon, macOS 26.2 (25C56)
**Dart:** 3.12.2 stable, macos_arm64
**Harness:** `benchmark/experiments/writer_rerun_opaque_guard.dart`

## Question

Can exp 289's writer-side rerun admission guarantee that a newly arriving
write waits no more than its declared 64 microsecond ceiling?

The guard opens a one-row stream whose query evaluates
`length(randomblob(16 MiB))`. The first write invalidates the stream. The
second write enters on the next event turn, after a point-in-time idle check
may already have admitted the rerun. Each sample opens a fresh database, so
the archived candidate has no history and its row cap admits this first
rerun. The query's row count is one while its synchronous SQLite work is
deliberately large and opaque to row-count admission. The probe directly
falsifies the unpriced first admission; the separate code audit establishes
that an old timing cannot impose a hard bound on later work.

## Results

| Runtime | Revision | Min | Median | Max |
|---|---|---:|---:|---:|
| current main | `90619dc` | 74 us | 82 us | 26,031 us |
| exp 289 prototype | `79c0646` (`archive/exp-289`) | 51,206 us | 51,958 us | 53,589 us |

The prototype serialized the complete rerun ahead of the second write in all
seven samples. Its minimum observed wait was 51.2 ms, more than **800 times**
the declared 64 us ceiling. The median was about 634 times current main's
median. Current main had one 26 ms scheduling/CPU-contention outlier, but six
of seven writes returned in 74-95 us; the prototype had no fast sample.

Because `randomblob()` changes the digest, the candidate performs both the
hash pass and the decode pass on the writer. The fresh-database samples
exercise the candidate's unpriced first admission. Code review found that its
first two reruns have no timing history, later admission uses the smaller of
two old samples, and the stopwatch begins after statement acquisition; this
probe does not itself run a fast-then-slow history sequence. More
fundamentally, a write can arrive after the idle check and before any
synchronous SQLite call completes. The candidate therefore fails its
predeclared no-write-delay rule independently of its latency wins.

## Raw output

Current main:

```text
samples=7 payloadBytes=16777216
sample=1 second_write_us=26031
sample=2 second_write_us=95
sample=3 second_write_us=77
sample=4 second_write_us=86
sample=5 second_write_us=82
sample=6 second_write_us=74
sample=7 second_write_us=78
min_us=74 median_us=82.0 max_us=26031
```

Archived exp 289 prototype:

```text
samples=7 payloadBytes=16777216
sample=1 second_write_us=53589
sample=2 second_write_us=51206
sample=3 second_write_us=52910
sample=4 second_write_us=51632
sample=5 second_write_us=52990
sample=6 second_write_us=51958
sample=7 second_write_us=51893
min_us=51206 median_us=51958.0 max_us=53589
```
