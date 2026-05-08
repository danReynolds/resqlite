# Experiment 131 - Wide Batch Transaction Shape

Profile harness: `benchmark/profile/wide_batch_transaction_shape.dart`

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/wide_batch_transaction_shape.dart --markdown --repeats=5
```

## Counters

| pass | workload | scenario | wall_ms | native_total_us | batch_call_us | param_pack_us | tx_begin_us | tx_commit_us | stmt_us | bind_us | step_us | reset_us | residual_us | preupdate_us | sets |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | top-level batch | 28.72 | 12012 | 12012 | 15830 | 23 | 2999 | 29 | 1711 | 5682 | 263 | 1305 | 375 | 10000 |
| 1 | mixed ASCII text | manual tx + nested batch | 34.87 | 13147 | 8695 | 21369 | 347 | 4105 | 44 | 1664 | 5383 | 266 | 1338 | 359 | 10000 |
| 1 | mixed Unicode text | top-level batch | 37.17 | 13749 | 13749 | 23231 | 30 | 5635 | 47 | 1611 | 5309 | 267 | 850 | 368 | 10000 |
| 1 | mixed Unicode text | manual tx + nested batch | 27.62 | 11990 | 8053 | 15548 | 33 | 3904 | 58 | 1692 | 5131 | 274 | 898 | 412 | 10000 |
| 1 | mixed emoji text | top-level batch | 26.09 | 15704 | 15704 | 10321 | 21 | 7756 | 32 | 1699 | 5000 | 245 | 951 | 324 | 10000 |
| 1 | mixed emoji text | manual tx + nested batch | 29.08 | 22528 | 7975 | 6465 | 37 | 14516 | 42 | 1548 | 5259 | 270 | 856 | 332 | 10000 |
| 2 | mixed ASCII text | top-level batch | 13.25 | 10187 | 10187 | 3010 | 22 | 2937 | 29 | 1457 | 4658 | 240 | 844 | 318 | 10000 |
| 2 | mixed ASCII text | manual tx + nested batch | 13.23 | 10222 | 7295 | 2958 | 21 | 2906 | 40 | 1491 | 4717 | 249 | 798 | 336 | 10000 |
| 2 | mixed Unicode text | top-level batch | 15.39 | 10439 | 10439 | 4905 | 28 | 3427 | 39 | 1503 | 4380 | 220 | 842 | 338 | 10000 |
| 2 | mixed Unicode text | manual tx + nested batch | 14.90 | 10465 | 6862 | 4386 | 22 | 3581 | 46 | 1412 | 4415 | 253 | 736 | 292 | 10000 |
| 2 | mixed emoji text | top-level batch | 22.07 | 15783 | 15783 | 6221 | 20 | 8593 | 24 | 1344 | 4746 | 245 | 811 | 355 | 10000 |
| 2 | mixed emoji text | manual tx + nested batch | 20.66 | 14694 | 6946 | 5885 | 37 | 7711 | 33 | 1351 | 4563 | 233 | 766 | 298 | 10000 |
| 3 | mixed ASCII text | top-level batch | 11.86 | 9048 | 9048 | 2777 | 23 | 2307 | 26 | 1336 | 4325 | 211 | 820 | 309 | 10000 |
| 3 | mixed ASCII text | manual tx + nested batch | 12.17 | 9261 | 6853 | 2829 | 26 | 2382 | 35 | 1333 | 4448 | 260 | 777 | 341 | 10000 |
| 3 | mixed Unicode text | top-level batch | 14.27 | 9965 | 9965 | 4258 | 27 | 3106 | 30 | 1400 | 4394 | 215 | 793 | 302 | 10000 |
| 3 | mixed Unicode text | manual tx + nested batch | 14.34 | 10164 | 6900 | 4102 | 43 | 3221 | 29 | 1409 | 4437 | 233 | 792 | 334 | 10000 |
| 3 | mixed emoji text | top-level batch | 19.82 | 13917 | 13917 | 5846 | 29 | 7063 | 36 | 1345 | 4395 | 238 | 811 | 318 | 10000 |
| 3 | mixed emoji text | manual tx + nested batch | 20.66 | 14726 | 6678 | 5875 | 25 | 8023 | 32 | 1333 | 4364 | 238 | 711 | 291 | 10000 |
| 4 | mixed ASCII text | top-level batch | 11.91 | 9159 | 9159 | 2711 | 23 | 2283 | 27 | 1314 | 4496 | 248 | 768 | 321 | 10000 |
| 4 | mixed ASCII text | manual tx + nested batch | 12.36 | 9289 | 6883 | 3008 | 26 | 2380 | 41 | 1405 | 4422 | 262 | 753 | 311 | 10000 |
| 4 | mixed Unicode text | top-level batch | 13.64 | 9427 | 9427 | 4161 | 23 | 2807 | 25 | 1351 | 4231 | 224 | 766 | 316 | 10000 |
| 4 | mixed Unicode text | manual tx + nested batch | 13.84 | 9547 | 6547 | 4243 | 24 | 2976 | 31 | 1362 | 4219 | 224 | 711 | 336 | 10000 |
| 4 | mixed emoji text | top-level batch | 20.63 | 14751 | 14751 | 5833 | 25 | 7812 | 30 | 1358 | 4538 | 230 | 758 | 308 | 10000 |
| 4 | mixed emoji text | manual tx + nested batch | 20.44 | 14468 | 6859 | 5910 | 24 | 7585 | 40 | 1360 | 4443 | 245 | 771 | 318 | 10000 |
| 5 | mixed ASCII text | top-level batch | 11.98 | 9256 | 9256 | 2678 | 30 | 2571 | 34 | 1307 | 4274 | 245 | 795 | 297 | 10000 |
| 5 | mixed ASCII text | manual tx + nested batch | 11.73 | 8941 | 6594 | 2740 | 20 | 2327 | 31 | 1340 | 4228 | 238 | 757 | 296 | 10000 |
| 5 | mixed Unicode text | top-level batch | 14.20 | 10059 | 10059 | 4095 | 22 | 3158 | 24 | 1434 | 4445 | 224 | 752 | 318 | 10000 |
| 5 | mixed Unicode text | manual tx + nested batch | 14.01 | 9596 | 6650 | 4360 | 23 | 2923 | 35 | 1322 | 4321 | 243 | 729 | 295 | 10000 |
| 5 | mixed emoji text | top-level batch | 19.77 | 13966 | 13966 | 5755 | 29 | 6909 | 33 | 1414 | 4534 | 238 | 809 | 336 | 10000 |
| 5 | mixed emoji text | manual tx + nested batch | 20.13 | 14243 | 6875 | 5832 | 27 | 7341 | 31 | 1334 | 4552 | 236 | 722 | 312 | 10000 |

## Derived split

| pass | workload | scenario | bind / native | step / native | commit / native | reset / native | residual / native | preupdate / step |
|---:|---|---|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | top-level batch | 14.24% | 47.30% | 24.97% | 2.19% | 10.86% | 6.60% |
| 1 | mixed ASCII text | manual tx + nested batch | 12.66% | 40.94% | 31.22% | 2.02% | 10.18% | 6.67% |
| 1 | mixed Unicode text | top-level batch | 11.72% | 38.61% | 40.98% | 1.94% | 6.18% | 6.93% |
| 1 | mixed Unicode text | manual tx + nested batch | 14.11% | 42.79% | 32.56% | 2.29% | 7.49% | 8.03% |
| 1 | mixed emoji text | top-level batch | 10.82% | 31.84% | 49.39% | 1.56% | 6.06% | 6.48% |
| 1 | mixed emoji text | manual tx + nested batch | 6.87% | 23.34% | 64.44% | 1.20% | 3.80% | 6.31% |
| 2 | mixed ASCII text | top-level batch | 14.30% | 45.72% | 28.83% | 2.36% | 8.29% | 6.83% |
| 2 | mixed ASCII text | manual tx + nested batch | 14.59% | 46.15% | 28.43% | 2.44% | 7.81% | 7.12% |
| 2 | mixed Unicode text | top-level batch | 14.40% | 41.96% | 32.83% | 2.11% | 8.07% | 7.72% |
| 2 | mixed Unicode text | manual tx + nested batch | 13.49% | 42.19% | 34.22% | 2.42% | 7.03% | 6.61% |
| 2 | mixed emoji text | top-level batch | 8.52% | 30.07% | 54.44% | 1.55% | 5.14% | 7.48% |
| 2 | mixed emoji text | manual tx + nested batch | 9.19% | 31.05% | 52.48% | 1.59% | 5.21% | 6.53% |
| 3 | mixed ASCII text | top-level batch | 14.77% | 47.80% | 25.50% | 2.33% | 9.06% | 7.14% |
| 3 | mixed ASCII text | manual tx + nested batch | 14.39% | 48.03% | 25.72% | 2.81% | 8.39% | 7.67% |
| 3 | mixed Unicode text | top-level batch | 14.05% | 44.09% | 31.17% | 2.16% | 7.96% | 6.87% |
| 3 | mixed Unicode text | manual tx + nested batch | 13.86% | 43.65% | 31.69% | 2.29% | 7.79% | 7.53% |
| 3 | mixed emoji text | top-level batch | 9.66% | 31.58% | 50.75% | 1.71% | 5.83% | 7.24% |
| 3 | mixed emoji text | manual tx + nested batch | 9.05% | 29.63% | 54.48% | 1.62% | 4.83% | 6.67% |
| 4 | mixed ASCII text | top-level batch | 14.35% | 49.09% | 24.93% | 2.71% | 8.39% | 7.14% |
| 4 | mixed ASCII text | manual tx + nested batch | 15.13% | 47.60% | 25.62% | 2.82% | 8.11% | 7.03% |
| 4 | mixed Unicode text | top-level batch | 14.33% | 44.88% | 29.78% | 2.38% | 8.13% | 7.47% |
| 4 | mixed Unicode text | manual tx + nested batch | 14.27% | 44.19% | 31.17% | 2.35% | 7.45% | 7.96% |
| 4 | mixed emoji text | top-level batch | 9.21% | 30.76% | 52.96% | 1.56% | 5.14% | 6.79% |
| 4 | mixed emoji text | manual tx + nested batch | 9.40% | 30.71% | 52.43% | 1.69% | 5.33% | 7.16% |
| 5 | mixed ASCII text | top-level batch | 14.12% | 46.18% | 27.78% | 2.65% | 8.59% | 6.95% |
| 5 | mixed ASCII text | manual tx + nested batch | 14.99% | 47.29% | 26.03% | 2.66% | 8.47% | 7.00% |
| 5 | mixed Unicode text | top-level batch | 14.26% | 44.19% | 31.39% | 2.23% | 7.48% | 7.15% |
| 5 | mixed Unicode text | manual tx + nested batch | 13.78% | 45.03% | 30.46% | 2.53% | 7.60% | 6.83% |
| 5 | mixed emoji text | top-level batch | 10.12% | 32.46% | 49.47% | 1.70% | 5.79% | 7.41% |
| 5 | mixed emoji text | manual tx + nested batch | 9.37% | 31.96% | 51.54% | 1.66% | 5.07% | 6.85% |

## Reading the table

- `top-level batch` calls `resqlite_run_batch_profiled`, so `batch_call_us` includes the profiled native BEGIN and COMMIT.
- `manual tx + nested batch` calls native BEGIN, `resqlite_run_batch_nested_profiled`, then native COMMIT. Its `batch_call_us` is row-loop work without transaction-control wall; `native_total_us` adds the external BEGIN/COMMIT stopwatches back in.
- Both scenarios bypass writer-isolate and stream invalidation overhead; this is a native transaction-shape audit, not an end-to-end API benchmark.
