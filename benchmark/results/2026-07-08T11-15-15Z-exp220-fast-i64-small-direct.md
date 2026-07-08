# Exp 220 - fast_i64_to_str small non-negative direct-write fast path

Focused `benchmark/experiments/select_bytes_int_heavy.dart` A/B against
`origin/main` at `e45b038`. Candidate adds a `0..9999` direct-write branch at
the top of `fast_i64_to_str` in `native/resqlite.c`, skipping the `tmp[]`
scratch, the sign-normalization branch, and the trailing `memcpy` for values
that land in the fast path. Values outside `[0, 9999]` fall through to the
existing exp-192 two-digit lookup path unchanged; output bytes are byte-
identical across the whole int64 range.

The harness is extended with two new lanes at the top of the run that isolate
the fast path (`10k rows x 20 small non-neg ints (0..9999)` and the 8-column
sibling). The exp-192 baseline lanes below them keep the mixed-magnitude
uniform-`[-2^29, 2^29)` distribution, in which essentially every cell falls
through the fast-path gate.

Harness reports median microseconds per `selectBytes()` query. Lower is
better.

## Pair 1 - baseline then candidate

| Lane | Baseline us/query | Candidate us/query | Delta |
|---|---:|---:|---:|
| 10k rows x 20 small non-neg ints (0..9999) | 4897 | 4331 | -11.6% |
| 10k rows x 8 small non-neg ints (0..9999) | 2183 | 1945 | -10.9% |
| 10k rows x 8 small ints | 2572 | 2645 | +2.8% |
| 10k rows x 20 small ints | 5790 | 5985 | +3.4% |
| 10k rows x 20 big ints (~18 digits) | 7228 | 7284 | +0.8% |
| 10k rows x 8 mixed (4 int + 2 text + 2 real) | 8664 | 8654 | -0.1% |
| 1k rows x 2 ints | 98 | 98 | 0.0% |

## Pair 2 - candidate then baseline

| Lane | Baseline us/query | Candidate us/query | Delta |
|---|---:|---:|---:|
| 10k rows x 20 small non-neg ints (0..9999) | 4842 | 4336 | -10.4% |
| 10k rows x 8 small non-neg ints (0..9999) | 2189 | 1976 | -9.7% |
| 10k rows x 8 small ints | 2589 | 2657 | +2.6% |
| 10k rows x 20 small ints | 5783 | 5953 | +2.9% |
| 10k rows x 20 big ints (~18 digits) | 7301 | 7350 | +0.7% |
| 10k rows x 8 mixed (4 int + 2 text + 2 real) | 8684 | 8637 | -0.5% |
| 1k rows x 2 ints | 99 | 107 | +8.1% |

## Interpretation

The `0..9999` fast path reproduces its target win on both new lanes across
the order-flipped pair: `10k x 20 small non-neg` moves -11.6% and -10.4%,
`10k x 8 small non-neg` moves -10.9% and -9.7%. Every cell in those lanes
hits the direct-write branch, so the win magnitude is the pure per-cell
saving from the eliminated `tmp[]` write, `memcpy` from `tmp` to `buf`, and
sign-normalization branch.

The exp-192 baseline `small ints` lanes reproduce a small **regression** in
the same direction across the flip: `10k x 20 small ints` +3.4% / +2.9%,
`10k x 8 small ints` +2.8% / +2.6%. That distribution is uniform in
`[-2^29, 2^29)`, so essentially every cell (>99.999%) falls through the
fast-path gate. The reproduced ~3% cost is the added compare-and-branch on
`(unsigned long long)val < 10000ULL` per cell; the branch predictor learns
"always fall through" cleanly, so this is instruction-count overhead, not
mispredict penalty.

The big-int (`~18 digits`) regression guard stays neutral (+0.8% / +0.7%,
below the 3% effect floor). The mixed lane is neutral. The 1k x 2 sub-100us
lane hit a slow outlier in pair 2 but is not load-bearing at that resolution.

## Verdict

Rejected. The primary target reproduces ~10-11%, but the reproduced ~3%
regression on the load-bearing `small ints` lane sits well above the sub-1%
guards that exp 190 / 192 / 194 / 195 / 216 shipped with. Without production
evidence that `0..9999` INTEGER columns dominate a real workload, adding a
per-cell branch that slows mixed-magnitude and negative-signed integer
encoding by ~3% is not a clear trade.

The runtime prototype is preserved at `archive/exp-220`. The extended harness
is the durable contribution: any future runner attempting a small-int
encoder specialization must now clear both `10k x 20 small non-neg (0..9999)`
and `10k x 20 small ints` on the same file.
