# Experiment 268: lazy statement-cache initialization

Collected 2026-08-11 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline is `origin/main` at
`96e67302aba2649874b18823df2038d80e6f5195`; candidate is the same tree with
`stmt_cache_init` setting only `count = 0` instead of zeroing all 128 entries.

Both arms were built as native-asset-aware AOT CLI bundles from the identical
[`benchmark/experiments/stmt_cache_init.dart`](../experiments/stmt_cache_init.dart)
source. A temporary `bin/` entry point existed only because `dart build cli`
requires it and is not part of the experiment sources.

```console
dart build cli --target=bin/_exp268_stmt_cache_init.dart --output=<arm>
<arm>/bundle/bin/_exp268_stmt_cache_init --lane=rss2
<arm>/bundle/bin/_exp268_stmt_cache_init --lane=rss4
<arm>/bundle/bin/_exp268_stmt_cache_init \
  --lane=wall2 --warmup=5 --samples=61 --opens=16
<arm>/bundle/bin/_exp268_stmt_cache_init \
  --lane=wall4 --warmup=5 --samples=61 --opens=16
```

RSS lanes used one fresh process per lane and arm. Twelve passes alternated arm
order. Wall lanes used 16 opens per timed sample and kept close outside the
stopwatch; six passes alternated both arm and lane order. Host checks spanned
roughly 51-62% idle during the collections. The experiment's acceptance gate
was at least 0.5 MB lower peak RSS with no repeated wall regression above 3%.

## Optimized-code attribution

`resqlite_cached_stmt` is 2,136 bytes in the actual native layout, so one
128-entry cache is 273,408 bytes (`0x42c00`). In the baseline AOT bundle's
`resqlite_open_impl`, the reader loop contains:

```asm
mov   w1, #0x2c00
movk  w1, #0x4, lsl #16
bl    _bzero
```

The candidate bundle omits those three instructions. The writer-side clear is
already absent in both bundles because the compiler can eliminate it directly
after the parent `calloc`; only the reader-loop clears survived. This makes the
mechanism prediction 273,408 eagerly written bytes per successfully opened
reader, or 546,816 bytes at two readers and 1,093,632 at four.

## RSS: twelve alternating-order fresh-process passes

All values are exact bytes. `max` is process lifetime max RSS; `growth` is the
lane's max RSS minus RSS immediately before native open.

| pass | rss2 max base | rss2 max cand | rss2 growth base | rss2 growth cand | rss4 max base | rss4 max cand | rss4 growth base | rss4 growth cand |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 18,989,056 | 18,268,160 | 4,276,224 | 3,702,784 | 21,053,440 | 20,037,632 | 6,356,992 | 5,357,568 |
| 2 | 18,939,904 | 18,366,464 | 4,177,920 | 3,653,632 | 21,020,672 | 19,939,328 | 6,307,840 | 5,324,800 |
| 3 | 18,972,672 | 18,317,312 | 4,243,456 | 3,702,784 | 21,102,592 | 19,873,792 | 6,340,608 | 5,242,880 |
| 4 | 18,890,752 | 18,333,696 | 4,177,920 | 3,670,016 | 20,987,904 | 19,972,096 | 6,291,456 | 5,357,568 |
| 5 | 18,874,368 | 18,366,464 | 4,210,688 | 3,719,168 | 20,987,904 | 20,021,248 | 6,324,224 | 5,357,568 |
| 6 | 18,923,520 | 18,350,080 | 4,243,456 | 3,670,016 | 21,086,208 | 19,890,176 | 6,356,992 | 5,242,880 |
| 7 | 19,005,440 | 18,382,848 | 4,227,072 | 3,719,168 | 21,004,288 | 20,070,400 | 6,291,456 | 5,357,568 |
| 8 | 18,956,288 | 18,350,080 | 4,210,688 | 3,670,016 | 21,053,440 | 20,086,784 | 6,324,224 | 5,357,568 |
| 9 | 18,890,752 | 18,317,312 | 4,194,304 | 3,670,016 | 20,987,904 | 19,939,328 | 6,291,456 | 5,242,880 |
| 10 | 18,923,520 | 18,300,928 | 4,210,688 | 3,686,400 | 21,020,672 | 19,906,560 | 6,324,224 | 5,226,496 |
| 11 | 18,890,752 | 18,333,696 | 4,210,688 | 3,670,016 | 21,004,288 | 19,988,480 | 6,307,840 | 5,357,568 |
| 12 | 18,874,368 | 18,317,312 | 4,210,688 | 3,670,016 | 21,004,288 | 19,922,944 | 6,307,840 | 5,324,800 |

| lane / metric | baseline median | candidate median | median delta | mean delta | paired savings range |
|---|---:|---:|---:|---:|---:|
| 2 readers, max RSS | 18,923,520 | 18,333,696 | **−589,824 (−3.12%)** | −593,920 | 507,904-720,896 |
| 2 readers, growth | 4,210,688 | 3,670,016 | **−540,672 (−12.84%)** | −532,480 | 491,520-573,440 |
| 4 readers, max RSS | 21,012,480 | 19,955,712 | **−1,056,768 (−5.03%)** | −1,055,403 | 933,888-1,228,800 |
| 4 readers, growth | 6,316,032 | 5,341,184 | **−974,848 (−15.44%)** | −1,006,251 | 933,888-1,114,112 |

The candidate is lower in every one of the 48 paired RSS observations. Going
from two to four readers increases mean savings by 461,483 bytes in max RSS and
473,771 bytes in growth, or 231-237 KB per added reader. That is 84-87% of the
273,408-byte code prediction: directionally and proportionally consistent,
but not an exact match under page-granular, process-wide max RSS. The expected
value lies inside the observed pass ranges, so the result supports attribution
without pretending max RSS is a byte-exact allocator counter.

## Native open wall time

Values are per-open medians in microseconds. Odd passes collected baseline
first; even passes candidate first. Lane order also flipped.

| lane | p1 base/cand | p2 base/cand | p3 base/cand | p4 base/cand | p5 base/cand | p6 base/cand | median-of-pass medians base/cand | delta |
|---|---|---|---|---|---|---|---|---:|
| `wall2` | 589.6 / 596.4 | 682.9 / 611.4 | 639.1 / 590.0 | 597.6 / 579.6 | 606.3 / 575.2 | 582.1 / 584.8 | 602.0 / 587.4 | **−2.42%** |
| `wall4` | 770.3 / 745.3 | 763.8 / 728.3 | 751.3 / 737.4 | 743.9 / 717.8 | 746.4 / 758.1 | 766.9 / 736.3 | 757.6 / 736.9 | **−2.73%** |

The candidate wins four of six `wall2` passes and five of six `wall4` passes.
The three candidate-slower comparisons are +1.15%, +0.46%, and +1.57%; none
reaches the 3% guard, much less reproduces across an order flip. Open time is
therefore non-regressing, with a small same-direction aggregate improvement as
expected from removing reader-side writes.

## Full-cache and eviction guards

The existing
[`benchmark/experiments/stmt_cache_pressure.dart`](../experiments/stmt_cache_pressure.dart)
was built as a second pair of AOT bundles and run for four alternating-order
passes, 41 samples per lane. `point1` covers the first initialized slot and a
hot hit, `rotate128` fills every slot then hits, and `churn-unique` evicts on
every new statement. These paths are identical after initialization, so the
gate is equivalence within 3%, not a win.

| lane | p1 delta | p2 delta | p3 delta | p4 delta | base/cand median-of-pass medians | aggregate delta |
|---|---:|---:|---:|---:|---:|---:|
| `point1` | +3.04% | −1.02% | +1.04% | −1.92% | 1361.0 / 1354.5 µs | −0.48% |
| `rotate128` | −1.88% | −1.34% | −2.65% | +2.02% | 1553.0 / 1543.5 µs | −0.61% |
| `churn-unique` | −0.55% | −1.12% | −2.95% | +2.21% | 3067.0 / 3051.5 µs | −0.51% |

All three aggregate within 0.7%; sign reversals and the single +3.04% point
sample make these neutral controls, not claimed secondary wins.

## Correctness

The focused serial run passed 23 tests:

```console
dart test \
  test/stmt_cache_pressure_test.dart \
  test/stream_cache_hit_reliability_test.dart \
  test/stream_overflow_fallback_test.dart \
  test/stream_trigger_cascade_test.dart \
  test/native_deps_fault_test.dart -j 1

dart test test/database_test.dart \
  --name 'immediate close is safe and idempotent|execute + select|selectBytes returns valid JSON' \
  --timeout 60s -j 1
```

This covers an empty cache, the first writer and reader slots, 400-statement
fill/eviction, parameter and projection identity, dependency reliability and
allocation-failure fallback. One pre-existing coverage gap remains explicit:
the `selectBytes` token test does not combine cached JSON-name tokens with more
than 128 distinct statements. The change does not add a new ownership path;
`stmt_cache_entry_init` still zeroes every slot before first use or reuse.
