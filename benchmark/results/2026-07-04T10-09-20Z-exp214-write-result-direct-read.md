# Exp 214: write result direct-read A/B

**Generated:** 2026-07-04T10:09:20Z  
**Benchmark:** `benchmark/experiments/write_result_direct_read.dart`  
**Runtime:** Dart 3.12.2 stable, macOS arm64  
**Baseline:** `origin/main` at `6e2b28c`  
**Candidate:** `archive/exp-214` prototype

The benchmark reports median microseconds per `Database.execute()` call over
13 samples of 2,000 calls/sample. Negative deltas mean the direct-read
candidate was faster.

## Pair 1: baseline then candidate

| Shape | Baseline us/call | Candidate us/call | Delta |
|---|---:|---:|---:|
| noop update | 6.758 | 6.842 | +1.2% |
| point update | 14.825 | 14.286 | -3.6% |
| param update | 14.578 | 14.347 | -1.6% |

## Pair 2: candidate then baseline

| Shape | Baseline us/call | Candidate us/call | Delta |
|---|---:|---:|---:|
| noop update | 6.885 | 9.800 | +42.3% |
| point update | 14.531 | 16.405 | +12.9% |
| param update | 14.667 | 15.728 | +7.2% |

## Pair 3: baseline then candidate

| Shape | Baseline us/call | Candidate us/call | Delta |
|---|---:|---:|---:|
| noop update | 6.879 | 6.635 | -3.5% |
| point update | 14.577 | 14.539 | -0.3% |
| param update | 14.435 | 14.639 | +1.4% |

## Interpretation

The direct-read prototype did not reproduce a stable win. Pair 1 had a small
candidate-faster signal on the two write-shaped lanes while the no-op floor
was slower. The order-flipped pair then moved every lane candidate-slower,
including shapes where the mechanism is identical, which is broad run drift
or a real regression rather than a targeted scalar-decode win. The confirmation
pair returned to mixed/neutral deltas.

The result is below the merge bar: direct pointer reads avoid a typed-list and
`ByteData` view per write, but that saving is not visible through the public
writer path at this harness resolution.
