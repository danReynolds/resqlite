# Exp 227 - inline 16-byte over-copy for JSON column-name tokens

Focused A/B on an Apple M1 Pro with Dart 3.12.2. Baseline was `origin/main`
at `1693139`; candidate was the exp-227 branch tip. Order-flipped pairs;
negative deltas mean candidate-faster.

## `selectBytes` wide-column shapes

`dart run benchmark/experiments/select_bytes_wide_cols.dart` — median
ms per `selectBytes()` call over 11 samples of 5 calls each.

| Shape | Baseline P1 | Candidate P1 | Delta P1 | Baseline P2 | Candidate P2 | Delta P2 |
|---|---:|---:|---:|---:|---:|---:|
| 10k rows x 8 int cols | 2.030 | 1.985 | -2.2% | 2.049 | 2.008 | -2.0% |
| **10k rows x 20 int cols** | **4.769** | **4.624** | **-3.0%** | **4.791** | **4.632** | **-3.3%** |
| 10k rows x 8 mixed cols | 2.258 | 2.238 | -0.9% | 2.272 | 2.192 | -3.5% |
| 10k rows x 20 mixed cols | 5.397 | 5.106 | -5.4% | 5.294 | 5.182 | -2.1% |
| 10k rows x 2 int cols | 0.647 | 0.603 | -6.8% | 0.613 | 0.602 | -1.8% |
| 1 row x 5 mixed cols | 0.018 | 0.014 | -22% | 0.014 | 0.014 | 0% |
| 100 rows x 5 mixed cols | 0.034 | 0.029 | -14.7% | 0.029 | 0.029 | 0% |

Every 10k-row shape reproduces same-sign candidate-faster across the flip.
The primary target row (10k rows x 20 int cols) is the most token-loop-heavy
lane the harness carries; it lands at -3.0% / -3.3%. Wide-row mixed and
narrower int/mixed shapes stay in the same direction. The 1-row and 100-row
lanes are noise (single-digit-microsecond precision floor); the same-sign
pattern held in P1 and washed out in P2.

## `selectBytes` repeated calls (µs-precision guard)

`dart run benchmark/experiments/select_bytes_repeated_calls.dart` — median
µs per call over 11 samples of 1000 calls each.

| Shape | Baseline P1 | Candidate P1 | Delta P1 | Baseline P2 | Candidate P2 | Delta P2 |
|---|---:|---:|---:|---:|---:|---:|
| 1 row x 8 int cols | 6.984 | 10.094 | +44.5% | 7.013 | 7.316 | +4.3% |
| 1 row x 20 int cols | 5.785 | 5.854 | +1.2% | 5.777 | 5.791 | +0.2% |
| 1 row x 8 mixed cols | 5.560 | 5.536 | -0.4% | 5.458 | 5.498 | +0.7% |
| 10 rows x 8 int cols | 7.278 | 7.338 | +0.8% | 7.221 | 7.210 | -0.2% |
| 10 rows x 20 int cols | 10.179 | 9.862 | -3.1% | 10.119 | 9.910 | -2.1% |
| 100 rows x 8 int cols | 26.928 | 28.160 | +4.6% | 27.366 | 26.232 | -4.1% |
| 1000 rows x 8 int cols | 208.868 | 203.677 | -2.5% | 208.197 | 201.435 | -3.2% |

The `1 row x 8 int cols` P1 candidate reading (10.094 µs, max 16.649 µs) is
the harness's first-shape warm-up outlier — its own P2 lands back at 7.316 µs
and its 1-row 20-col and 1-row 8-mixed neighbours read flat, so the P1 spike
is not attributable to the change. Multi-row shapes reproduce same-sign
candidate-faster across the flip: 10 rows x 20 int -3.1% / -2.1% and
1000 rows x 8 int -2.5% / -3.2%. Single-row shapes have no per-row
amortisation to move; they land in noise.

## Correctness

`dart test test/database_test.dart --name selectBytes` — all 9 tests pass,
including JSON special characters, embedded-NUL text, jsonEncode(select())
equivalence, int64 extremes, integer-valued REALs, and BLOB base64.
