# Exp 252 dirty-column batch merge A/B

**Date:** 2026-07-27
**Base:** `origin/main` at `1fd52b5a385b`
**Candidate:** `92c591046584` (`archive/exp-252`)
**Host:** Darwin 25.2.0 arm64
**Dart:** 3.12.2 stable, macOS arm64

## Method

The unchanged focused harness ran in separate baseline and candidate worktrees:

```text
dart run benchmark/experiments/dirty_column_batch_merge.dart \
  --warmup=8 --samples=31 --sizes=1,10,100,1000 --wide-rows=10000
```

Two comparisons ran in opposite order: baseline then candidate, followed by
candidate then baseline. Each lane used a fresh database. Parameter matrices
were prebuilt and alternated outside the timed region, every key matched a
distinct seeded row, and sentinel queries verified the final values.
`wal_checkpoint(TRUNCATE)` normalized WAL history after each warmup and sample,
outside the stopwatch.

The product shape mirrors Dune's identity sync and preserves its full row
footprint: one `executeBatch` updates `ip`, `last_seen_at`, and `online` on
devices, immediately followed by another updating `last_seen_at` and `online`
on peers. The stopwatch covers both public calls. Dune performs this pair every
2 seconds for the first 20 seconds after connect and every 5 seconds
thereafter.

The 20-column UPDATE is an intentionally synthetic mechanism ceiling. The
missing-key row fires no preupdate hooks and measures only the candidate's
fixed mask lifecycle overhead.

## Decision summary

Lower is better. Delta is `(candidate - baseline) / baseline`.

| Pair | Shape | Baseline p50 | Candidate p50 | Delta |
|---|---|---:|---:|---:|
| baseline first | Dune 1 device + 1 peer | 148 us | 245 us | +65.5% |
| baseline first | Dune 10 + 10 | 199 us | 220 us | +10.6% |
| baseline first | **Dune 100 + 100** | **424 us** | **632 us** | **+49.1%** |
| baseline first | Dune 1000 + 1000 | 3290 us | 3591 us | +9.1% |
| baseline first | missing-key 100 + 100 | 112 us | 120 us | +7.1% |
| baseline first | 10k rows x 20 SET columns | 29738 us | 10543 us | **-64.5%** |
| candidate first | Dune 1 device + 1 peer | 157 us | 157 us | 0.0% |
| candidate first | Dune 10 + 10 | 193 us | 242 us | +25.4% |
| candidate first | **Dune 100 + 100** | **350 us** | **404 us** | **+15.4%** |
| candidate first | Dune 1000 + 1000 | 2543 us | 2491 us | -2.0% |
| candidate first | missing-key 100 + 100 | 116 us | 110 us | -5.2% |
| candidate first | 10k rows x 20 SET columns | 26647 us | 10412 us | **-60.9%** |

The mechanism is real: when a statement modifies 20 columns across 10,000
rows, merging its static dependency set once makes the batch 2.6-2.8x faster.
The product gate fails in both orderings. The 100+100 Dune-shaped p50 is 15-49%
slower rather than at least 3% faster, and the 1000+1000 row moves +9% / -2%.
The small and missing-key controls also change sign or remain noisy, so there
is no stable fixed-overhead claim.

The wide result does not rescue the candidate. It requires two orders of
magnitude more rows and roughly seven to ten times the SET-column width of the
downstream workload that motivated the experiment.

## Distribution summary

| Pair | Side | Shape | p10 | p50 | p90 |
|---|---|---|---:|---:|---:|
| baseline first | baseline | Dune 100 + 100 | 369 us | 424 us | 1733 us |
| baseline first | candidate | Dune 100 + 100 | 343 us | 632 us | 1006 us |
| candidate first | candidate | Dune 100 + 100 | 333 us | 404 us | 556 us |
| candidate first | baseline | Dune 100 + 100 | 333 us | 350 us | 404 us |
| baseline first | baseline | Dune 1000 + 1000 | 2707 us | 3290 us | 4958 us |
| baseline first | candidate | Dune 1000 + 1000 | 2540 us | 3591 us | 5029 us |
| candidate first | candidate | Dune 1000 + 1000 | 2266 us | 2491 us | 2620 us |
| candidate first | baseline | Dune 1000 + 1000 | 2409 us | 2543 us | 2678 us |
| baseline first | baseline | missing-key 100 + 100 | 110 us | 112 us | 117 us |
| baseline first | candidate | missing-key 100 + 100 | 117 us | 120 us | 178 us |
| candidate first | candidate | missing-key 100 + 100 | 108 us | 110 us | 130 us |
| candidate first | baseline | missing-key 100 + 100 | 114 us | 116 us | 122 us |
| baseline first | baseline | wide 10k x 20 | 28163 us | 29738 us | 31305 us |
| baseline first | candidate | wide 10k x 20 | 10034 us | 10543 us | 17141 us |
| candidate first | candidate | wide 10k x 20 | 9878 us | 10412 us | 11816 us |
| candidate first | baseline | wide 10k x 20 | 26243 us | 26647 us | 27474 us |

## Decision-row raw samples

### Baseline first

```text
baseline Dune 100+100:
581,600,497,423,505,379,429,360,349,354,376,369,5647,397,384,479,394,374,7515,414,446,1287,1733,3749,426,403,424,435,414,457,395

candidate Dune 100+100:
498,1483,1232,774,818,867,463,619,343,449,333,1006,328,713,371,835,562,957,608,424,632,940,1769,784,811,659,607,454,610,322,721

baseline Dune 1000+1000:
2753,2707,3253,3290,3444,3254,3657,2987,2859,2932,3058,2661,2688,2781,2926,2681,3134,21870,3912,3541,4743,5879,3299,3500,3857,4802,4958,5450,3072,3716,4560

candidate Dune 1000+1000:
2828,3883,2948,2524,2540,2556,2482,3591,3036,2948,2634,3219,2979,2861,2511,3936,4404,4203,3597,5137,3605,5029,4077,4908,2931,7690,3836,3719,6497,4016,3182

baseline wide 10k x 20:
29214,28873,31138,29097,31545,29738,30060,28727,29365,29992,30196,28809,27969,28163,31305,29027,28053,28099,28412,30904,30830,30437,28798,30498,30376,30377,32272,30609,31311,28794,29022

candidate wide 10k x 20:
10025,10099,9785,10156,10482,15397,10337,10282,10034,9983,10661,10500,10467,24148,22938,27207,10921,15001,12328,10823,10828,10311,10702,10678,10167,17141,10135,10543,11874,10583,10389
```

### Candidate first

```text
candidate Dune 100+100:
556,516,390,908,546,354,338,439,333,341,463,335,844,404,365,448,505,442,345,479,471,493,327,771,343,478,360,396,323,336,315

baseline Dune 100+100:
454,445,387,380,555,371,386,375,345,350,343,346,333,343,373,382,404,340,341,352,375,320,327,371,340,333,335,335,341,326,389

candidate Dune 1000+1000:
2282,2266,2522,2600,2316,2274,2250,2266,2226,2606,2590,2527,2491,2620,2739,2438,2390,2597,2481,2511,2581,2335,2289,2457,2820,2322,2285,2643,2560,2498,2615

baseline Dune 1000+1000:
2459,3029,2969,2561,2450,2456,2525,2594,2565,2543,2508,2850,2566,2605,2474,2464,2678,2584,2528,2485,2416,2385,2327,2270,2409,2565,2564,2551,2560,2554,2520

candidate wide 10k x 20:
10279,12876,10460,10454,10645,9878,10463,10740,10586,10500,13670,10370,10196,10545,9782,9845,9676,10167,10892,14254,10261,10160,10192,10550,10735,10172,10078,10019,10069,10412,11816

baseline wide 10k x 20:
27315,26647,26542,27107,26290,30547,27474,27371,27260,26911,26560,27474,26943,27183,26509,28766,26826,26659,26727,26311,26282,26060,26518,26639,26289,29337,25823,26168,26348,26243,26267
```

## Outcome

Rejected. The exact prototype is preserved at `archive/exp-252`; the runtime
change is reverted on the publication branch. The product result says not to
add a pending-dependency mask for ordinary 2-3-column status batches. Reopen
only with representative downstream evidence of repeated UPDATE batches in
the thousands of rows with materially wider SET lists, or a native profile
showing this merge loop consumes enough public write wall to clear the product
gate.

