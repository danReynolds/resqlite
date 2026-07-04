# Exp 215 - Persistent `executeWrite` result-buffer slot (retry of exp 095)

Focused `benchmark/experiments/write_result_direct_read.dart` A/B against
`origin/main` at `0915dde`. Candidate replaces the per-call
`calloc<Uint8>(_writeResultSize)` + matching `calloc.free(resultBuf)` inside
`executeWrite()` with a single persistent 16-byte scratch buffer at file
scope, following exp 211's exp 108 revisit shape for the reader-side
`queryBytes()` slots.

The writer isolate processes one FFI request at a time and
`resqlite_execute` writes both scalar fields on every SQLite success return;
on `rc != 0` `executeWrite()` throws before reading the buffer, so stale
values from a prior successful call are never observable.

Harness: 2000 `Database.execute()` calls per sample, 13 samples per shape,
median microseconds per call. Lower is better.

## Pair 1 - baseline then candidate

### Baseline

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 6.505 | 6.133 | 22.274 |
| point update | 14.024 | 13.906 | 17.936 |
| param update | 14.139 | 13.984 | 15.725 |

### Candidate

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 6.605 | 6.132 | 22.524 |
| point update | 13.948 | 13.780 | 17.692 |
| param update | 14.127 | 13.883 | 15.777 |

## Pair 2 - candidate then baseline

### Candidate

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 6.571 | 6.176 | 22.572 |
| point update | 14.296 | 13.945 | 18.210 |
| param update | 14.189 | 13.954 | 15.889 |

### Baseline

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 6.630 | 6.216 | 24.026 |
| point update | 14.623 | 13.979 | 18.366 |
| param update | 14.674 | 14.096 | 16.047 |

## Pair 3 - baseline then candidate (contaminated by baseline drift)

### Baseline

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 9.115 | 8.073 | 24.090 |
| point update | 15.855 | 14.703 | 20.834 |
| param update | 14.778 | 14.259 | 17.130 |

### Candidate

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 6.798 | 6.128 | 21.834 |
| point update | 13.935 | 13.787 | 20.335 |
| param update | 13.995 | 13.851 | 15.767 |

Baseline pair 3 shifted well above pairs 1/2/4 on every shape (noop min
8.073 us vs 6.13-6.22 us elsewhere), so its deltas are not
mechanism-attributable. Recorded for completeness; not counted in the
verdict.

## Pair 4 - baseline then candidate (rerun to disambiguate pair 3)

### Baseline

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 6.824 | 6.313 | 22.270 |
| point update | 14.597 | 13.963 | 19.556 |
| param update | 14.781 | 14.171 | 16.580 |

### Candidate

| Shape | Median us/call | Min | Max |
|---|---:|---:|---:|
| noop update | 6.538 | 6.127 | 24.392 |
| point update | 13.992 | 13.798 | 18.603 |
| param update | 14.012 | 13.912 | 15.793 |

## Delta summary (candidate vs matching pair baseline, negative = candidate faster)

| Shape | P1 (b -> c) | P2 (c -> b) | P3* (b -> c drifted) | P4 (b -> c rerun) |
|---|---:|---:|---:|---:|
| noop update  | +1.5 % | -0.9 % | -25.4 %* | -4.2 % |
| point update | -0.5 % | -2.2 % | -12.1 %* | -4.1 % |
| param update | -0.1 % | -3.3 % |  -5.3 %* | -5.2 % |

Candidate `us/call` is stable across all four pairs (noop 6.54-6.80,
point 13.94-14.30, param 13.99-14.19). Baseline is noisier — pair 3 is a
system-drift outlier, and pair 1 noop happens to be the lowest baseline
noop reading of all four passes.
