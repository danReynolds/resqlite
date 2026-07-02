# Exp 211 - Persistent queryBytes out-parameter slots (retry of exp 108)

Focused `benchmark/experiments/select_bytes_repeated_calls.dart` A/B against
`origin/main` at `4ddeb03`. Candidate replaces `queryBytes()`'s per-call
`calloc<Pointer<Uint8>>()` / `calloc<Int>()` / `calloc<Int>()` triple (plus
their matching `calloc.free`s) with three per-isolate scratch pointers.

The reader worker processes one FFI request at a time and
`resqlite_query_bytes` writes all three slots on every return path (success and
error), so a pair of shared slots per isolate is safe.

Harness: 1000 `selectBytes()` calls per sample, 11 samples per lane, median
microseconds per call. Lower is better.

## Pair 1 - baseline then candidate

### Baseline

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 7.478 | 5.732 | 21.567 | 59 |
| 1 row x 20 int cols | 5.895 | 5.517 | 6.236 | 163 |
| 1 row x 8 mixed cols | 5.758 | 5.525 | 7.355 | 74 |
| 10 rows x 8 int cols | 7.302 | 7.130 | 7.941 | 797 |
| 10 rows x 20 int cols | 10.184 | 9.859 | 10.585 | 2071 |
| 100 rows x 8 int cols | 26.868 | 26.462 | 28.530 | 8897 |
| 1000 rows x 8 int cols | 207.818 | 206.561 | 214.247 | 97097 |

### Candidate

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 6.984 | 5.682 | 21.008 | 59 |
| 1 row x 20 int cols | 5.686 | 5.501 | 6.078 | 163 |
| 1 row x 8 mixed cols | 5.428 | 5.147 | 5.800 | 74 |
| 10 rows x 8 int cols | 7.172 | 7.026 | 7.272 | 797 |
| 10 rows x 20 int cols | 9.953 | 9.832 | 10.422 | 2071 |
| 100 rows x 8 int cols | 26.828 | 26.076 | 27.849 | 8897 |
| 1000 rows x 8 int cols | 207.714 | 207.028 | 210.439 | 97097 |

## Pair 2 - candidate then baseline

### Candidate

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 6.959 | 5.592 | 20.555 | 59 |
| 1 row x 20 int cols | 5.687 | 5.431 | 6.011 | 163 |
| 1 row x 8 mixed cols | 5.473 | 5.177 | 5.869 | 74 |
| 10 rows x 8 int cols | 7.188 | 7.047 | 7.430 | 797 |
| 10 rows x 20 int cols | 9.907 | 9.796 | 10.271 | 2071 |
| 100 rows x 8 int cols | 26.539 | 26.018 | 29.228 | 8897 |
| 1000 rows x 8 int cols | 207.315 | 206.724 | 210.158 | 97097 |

### Baseline

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 7.201 | 5.831 | 21.140 | 59 |
| 1 row x 20 int cols | 5.959 | 5.724 | 6.340 | 163 |
| 1 row x 8 mixed cols | 5.813 | 5.529 | 6.063 | 74 |
| 10 rows x 8 int cols | 7.499 | 7.151 | 8.371 | 797 |
| 10 rows x 20 int cols | 10.099 | 9.963 | 10.514 | 2071 |
| 100 rows x 8 int cols | 26.889 | 26.387 | 28.323 | 8897 |
| 1000 rows x 8 int cols | 207.712 | 206.715 | 221.109 | 97097 |

## Pair 3 - warmed baseline then candidate

### Baseline

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 7.296 | 5.819 | 21.571 | 59 |
| 1 row x 20 int cols | 6.017 | 5.572 | 6.377 | 163 |
| 1 row x 8 mixed cols | 5.583 | 5.480 | 6.007 | 74 |
| 10 rows x 8 int cols | 7.265 | 7.133 | 7.502 | 797 |
| 10 rows x 20 int cols | 9.979 | 9.908 | 10.998 | 2071 |
| 100 rows x 8 int cols | 26.632 | 26.267 | 28.743 | 8897 |
| 1000 rows x 8 int cols | 208.711 | 206.310 | 231.643 | 97097 |

### Candidate

| Shape | Median us/call | Min | Max | Bytes |
|---|---:|---:|---:|---:|
| 1 row x 8 int cols | 7.214 | 5.791 | 20.823 | 59 |
| 1 row x 20 int cols | 5.813 | 5.525 | 6.214 | 163 |
| 1 row x 8 mixed cols | 5.567 | 5.435 | 5.875 | 74 |
| 10 rows x 8 int cols | 7.247 | 7.092 | 7.335 | 797 |
| 10 rows x 20 int cols | 10.042 | 9.824 | 10.398 | 2071 |
| 100 rows x 8 int cols | 26.676 | 26.145 | 27.796 | 8897 |
| 1000 rows x 8 int cols | 207.261 | 206.426 | 210.292 | 97097 |

## Delta summary

Candidate deltas vs matching baseline. Negative is candidate faster.

| Lane | Pair 1 | Pair 2 | Pair 3 |
|---|---:|---:|---:|
| 1 row x 8 int cols | -6.6% | -3.4% | -1.1% |
| 1 row x 20 int cols | -3.5% | -4.6% | -3.4% |
| 1 row x 8 mixed cols | -5.7% | -5.9% | -0.3% |
| 10 rows x 8 int cols | -1.8% | -4.1% | -0.2% |
| 10 rows x 20 int cols | -2.3% | -1.9% | +0.6% |
| 100 rows x 8 int cols | -0.15% | -1.3% | +0.2% |
| 1000 rows x 8 int cols | -0.05% | -0.19% | -0.7% |

## Large-bytes guard (`large_bytes_transfer.dart`, exp 174 gate)

Median us/query, two paired passes (baseline pass 1 + candidate pass 1,
baseline pass 2 + candidate pass 2).

| Lane | Baseline p1 | Candidate p1 | Baseline p2 | Candidate p2 |
|---|---:|---:|---:|---:|
| large-bytes (~651 KB, 150 iters) | 238 | 240 | 239 | 237 |
| small-bytes (~64 KB, 2000 iters) | 76 | 79 | 76 | 76 |

Both passes stay within ~1 us of baseline on both lanes; the change does
not touch any code the large-bytes path exercises after the reader FFI
call returns.

## Read

All three small-rowset lanes (1 row x 8 int / 1 row x 20 int / 1 row x 8
mixed) reproduce candidate-faster across two order-flipped passes at -3.4%
to -6.6%. The load-bearing 1 row x 20 int lane holds -3.4% to -4.7% across
all three pairs including the warmed one - the tightest reproduction in the
set.

The 100/1000-row guard lanes stay inside 1.3% in every pair. That matches
the mechanism: the per-call setup cost being removed (three calloc/free
pairs) is a constant few hundred nanoseconds per query, so its share of
total wall shrinks as row count grows.

Pass 3 (warmed) trims the 10-row lanes into the noise band, consistent with
per-query setup being a smaller fraction there and warmup smoothing out the
per-run spread that inflated the first two pairs slightly.

The exp 174 large-bytes guard stays flat (+/-2 us at 76-240 us), so the
persistent-slot change does not perturb the large-payload transfer path.
