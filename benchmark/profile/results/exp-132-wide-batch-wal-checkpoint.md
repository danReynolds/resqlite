# Experiment 132 - Wide Batch WAL Checkpoint Audit

Profile harness: `benchmark/profile/wide_batch_wal_checkpoint.dart`

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/wide_batch_wal_checkpoint.dart --markdown --repeats=5 --rows=10000
```

## Median profile

| workload | scenario | wall_ms | native_us | commit_us | checkpoint_us | commit_minus_checkpoint_us | wal_pages_max | wal_bytes | manual_checkpoint_us |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| mixed ASCII text | baseline hook (500 pages) | 13.23 | 9896 | 2559 | 0 | 2559 | 373 | 1536792 | 3100 |
| mixed ASCII text | candidate hook (1000 pages) | 12.47 | 9422 | 2481 | 0 | 2481 | 373 | 1536792 | 2519 |
| mixed ASCII text | defer hook (5000 pages) | 12.35 | 9461 | 2559 | 0 | 2559 | 373 | 1536792 | 3309 |
| mixed ASCII text | disable hook checkpoint | 12.29 | 9373 | 2538 | 0 | 2538 | 373 | 1536792 | 2833 |
| mixed Unicode text | baseline hook (500 pages) | 14.70 | 10061 | 3013 | 0 | 3013 | 457 | 1882872 | 3082 |
| mixed Unicode text | candidate hook (1000 pages) | 14.53 | 10037 | 3152 | 0 | 3152 | 457 | 1882872 | 3526 |
| mixed Unicode text | defer hook (5000 pages) | 14.54 | 10229 | 3133 | 0 | 3133 | 457 | 1882872 | 2874 |
| mixed Unicode text | disable hook checkpoint | 14.98 | 10435 | 3172 | 0 | 3172 | 457 | 1882872 | 3125 |
| mixed emoji text | baseline hook (500 pages) | 20.74 | 14146 | 7075 | 2686 | 3341 | 529 | 2179512 | 341 |
| mixed emoji text | candidate hook (1000 pages) | 17.26 | 11112 | 3670 | 0 | 3670 | 529 | 2179512 | 3994 |
| mixed emoji text | defer hook (5000 pages) | 18.21 | 11940 | 4660 | 0 | 4660 | 529 | 2179512 | 5101 |
| mixed emoji text | disable hook checkpoint | 16.59 | 10619 | 3804 | 0 | 3804 | 529 | 2179512 | 3949 |

## Raw profile rows

| pass | workload | scenario | wall_ms | native_us | commit_us | checkpoint_us | commit_minus_checkpoint_us | wal_hook_count | wal_pages_max | checkpoint_count | checkpoint_busy_count | checkpoint_pages | wal_bytes | manual_checkpoint_us |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | baseline hook (500 pages) | 22.04 | 9896 | 2559 | 0 | 2559 | 1 | 373 | 0 | 0 | 0 | 1536792 | 4821 |
| 1 | mixed ASCII text | candidate hook (1000 pages) | 25.52 | 9827 | 3083 | 0 | 3083 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2280 |
| 1 | mixed ASCII text | defer hook (5000 pages) | 25.07 | 13598 | 2559 | 0 | 2559 | 1 | 373 | 0 | 0 | 0 | 1536792 | 3397 |
| 1 | mixed ASCII text | disable hook checkpoint | 12.83 | 9927 | 2470 | 0 | 2470 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2833 |
| 1 | mixed Unicode text | baseline hook (500 pages) | 23.75 | 10061 | 2877 | 0 | 2877 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2693 |
| 1 | mixed Unicode text | candidate hook (1000 pages) | 27.26 | 10748 | 3659 | 0 | 3659 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3044 |
| 1 | mixed Unicode text | defer hook (5000 pages) | 15.10 | 10229 | 3133 | 0 | 3133 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2874 |
| 1 | mixed Unicode text | disable hook checkpoint | 15.28 | 10426 | 3264 | 0 | 3264 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2723 |
| 1 | mixed emoji text | baseline hook (500 pages) | 20.74 | 13225 | 5898 | 2628 | 3270 | 1 | 529 | 1 | 0 | 529 | 2179512 | 199 |
| 1 | mixed emoji text | candidate hook (1000 pages) | 16.85 | 10653 | 3288 | 0 | 3288 | 1 | 529 | 0 | 0 | 0 | 2179512 | 2957 |
| 1 | mixed emoji text | defer hook (5000 pages) | 18.21 | 11940 | 4660 | 0 | 4660 | 1 | 529 | 0 | 0 | 0 | 2179512 | 3411 |
| 1 | mixed emoji text | disable hook checkpoint | 18.32 | 12328 | 5355 | 0 | 5355 | 1 | 529 | 0 | 0 | 0 | 2179512 | 6907 |
| 2 | mixed ASCII text | baseline hook (500 pages) | 12.49 | 9371 | 2320 | 0 | 2320 | 1 | 373 | 0 | 0 | 0 | 1536792 | 3251 |
| 2 | mixed ASCII text | candidate hook (1000 pages) | 12.41 | 9491 | 2481 | 0 | 2481 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2519 |
| 2 | mixed ASCII text | defer hook (5000 pages) | 11.99 | 9317 | 2496 | 0 | 2496 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2763 |
| 2 | mixed ASCII text | disable hook checkpoint | 12.29 | 9330 | 2651 | 0 | 2651 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2536 |
| 2 | mixed Unicode text | baseline hook (500 pages) | 14.91 | 10579 | 3598 | 0 | 3598 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3678 |
| 2 | mixed Unicode text | candidate hook (1000 pages) | 14.38 | 10037 | 3293 | 0 | 3293 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3963 |
| 2 | mixed Unicode text | defer hook (5000 pages) | 14.54 | 10311 | 3307 | 0 | 3307 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3155 |
| 2 | mixed Unicode text | disable hook checkpoint | 14.98 | 10559 | 3172 | 0 | 3172 | 1 | 457 | 0 | 0 | 0 | 1882872 | 8691 |
| 2 | mixed emoji text | baseline hook (500 pages) | 22.36 | 15720 | 8008 | 2686 | 5322 | 1 | 529 | 1 | 0 | 529 | 2179512 | 512 |
| 2 | mixed emoji text | candidate hook (1000 pages) | 18.82 | 11652 | 4268 | 0 | 4268 | 1 | 529 | 0 | 0 | 0 | 2179512 | 4328 |
| 2 | mixed emoji text | defer hook (5000 pages) | 19.01 | 13006 | 5324 | 0 | 5324 | 1 | 529 | 0 | 0 | 0 | 2179512 | 5593 |
| 2 | mixed emoji text | disable hook checkpoint | 18.12 | 11869 | 4281 | 0 | 4281 | 1 | 529 | 0 | 0 | 0 | 2179512 | 3949 |
| 3 | mixed ASCII text | baseline hook (500 pages) | 13.52 | 10536 | 3300 | 0 | 3300 | 1 | 373 | 0 | 0 | 0 | 1536792 | 3100 |
| 3 | mixed ASCII text | candidate hook (1000 pages) | 12.47 | 9422 | 2360 | 0 | 2360 | 1 | 373 | 0 | 0 | 0 | 1536792 | 3449 |
| 3 | mixed ASCII text | defer hook (5000 pages) | 12.35 | 9461 | 2626 | 0 | 2626 | 1 | 373 | 0 | 0 | 0 | 1536792 | 3309 |
| 3 | mixed ASCII text | disable hook checkpoint | 12.16 | 9373 | 2538 | 0 | 2538 | 1 | 373 | 0 | 0 | 0 | 1536792 | 3507 |
| 3 | mixed Unicode text | baseline hook (500 pages) | 14.70 | 10418 | 3691 | 0 | 3691 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3082 |
| 3 | mixed Unicode text | candidate hook (1000 pages) | 13.90 | 9596 | 2851 | 0 | 2851 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3977 |
| 3 | mixed Unicode text | defer hook (5000 pages) | 14.15 | 9848 | 3032 | 0 | 3032 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2672 |
| 3 | mixed Unicode text | disable hook checkpoint | 13.86 | 9803 | 2985 | 0 | 2985 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3125 |
| 3 | mixed emoji text | baseline hook (500 pages) | 21.41 | 15439 | 8360 | 4022 | 4338 | 1 | 529 | 1 | 0 | 529 | 2179512 | 394 |
| 3 | mixed emoji text | candidate hook (1000 pages) | 17.26 | 11112 | 3748 | 0 | 3748 | 1 | 529 | 0 | 0 | 0 | 2179512 | 3994 |
| 3 | mixed emoji text | defer hook (5000 pages) | 16.38 | 10360 | 3366 | 0 | 3366 | 1 | 529 | 0 | 0 | 0 | 2179512 | 5101 |
| 3 | mixed emoji text | disable hook checkpoint | 16.59 | 10619 | 3804 | 0 | 3804 | 1 | 529 | 0 | 0 | 0 | 2179512 | 5882 |
| 4 | mixed ASCII text | baseline hook (500 pages) | 13.23 | 10413 | 3412 | 0 | 3412 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2314 |
| 4 | mixed ASCII text | candidate hook (1000 pages) | 12.48 | 9306 | 2508 | 0 | 2508 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2617 |
| 4 | mixed ASCII text | defer hook (5000 pages) | 11.71 | 9021 | 2205 | 0 | 2205 | 1 | 373 | 0 | 0 | 0 | 1536792 | 3544 |
| 4 | mixed ASCII text | disable hook checkpoint | 11.73 | 8961 | 2194 | 0 | 2194 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2929 |
| 4 | mixed Unicode text | baseline hook (500 pages) | 14.29 | 9760 | 2825 | 0 | 2825 | 1 | 457 | 0 | 0 | 0 | 1882872 | 4435 |
| 4 | mixed Unicode text | candidate hook (1000 pages) | 14.62 | 10321 | 3152 | 0 | 3152 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3526 |
| 4 | mixed Unicode text | defer hook (5000 pages) | 15.58 | 11559 | 4729 | 0 | 4729 | 1 | 457 | 0 | 0 | 0 | 1882872 | 4228 |
| 4 | mixed Unicode text | disable hook checkpoint | 14.82 | 10435 | 3050 | 0 | 3050 | 1 | 457 | 0 | 0 | 0 | 1882872 | 3544 |
| 4 | mixed emoji text | baseline hook (500 pages) | 20.10 | 14146 | 7075 | 3734 | 3341 | 1 | 529 | 1 | 0 | 529 | 2179512 | 290 |
| 4 | mixed emoji text | candidate hook (1000 pages) | 17.69 | 11535 | 3670 | 0 | 3670 | 1 | 529 | 0 | 0 | 0 | 2179512 | 4320 |
| 4 | mixed emoji text | defer hook (5000 pages) | 18.99 | 12977 | 5271 | 0 | 5271 | 1 | 529 | 0 | 0 | 0 | 2179512 | 11235 |
| 4 | mixed emoji text | disable hook checkpoint | 16.00 | 10032 | 3133 | 0 | 3133 | 1 | 529 | 0 | 0 | 0 | 2179512 | 2827 |
| 5 | mixed ASCII text | baseline hook (500 pages) | 11.94 | 9098 | 2260 | 0 | 2260 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2025 |
| 5 | mixed ASCII text | candidate hook (1000 pages) | 11.94 | 9194 | 2373 | 0 | 2373 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2155 |
| 5 | mixed ASCII text | defer hook (5000 pages) | 13.15 | 10365 | 3244 | 0 | 3244 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2493 |
| 5 | mixed ASCII text | disable hook checkpoint | 12.68 | 9887 | 2974 | 0 | 2974 | 1 | 373 | 0 | 0 | 0 | 1536792 | 2606 |
| 5 | mixed Unicode text | baseline hook (500 pages) | 14.34 | 10024 | 3013 | 0 | 3013 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2483 |
| 5 | mixed Unicode text | candidate hook (1000 pages) | 14.53 | 9934 | 3020 | 0 | 3020 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2666 |
| 5 | mixed Unicode text | defer hook (5000 pages) | 14.08 | 9570 | 2925 | 0 | 2925 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2458 |
| 5 | mixed Unicode text | disable hook checkpoint | 15.79 | 10738 | 3624 | 0 | 3624 | 1 | 457 | 0 | 0 | 0 | 1882872 | 2891 |
| 5 | mixed emoji text | baseline hook (500 pages) | 18.51 | 12794 | 5829 | 2558 | 3271 | 1 | 529 | 1 | 0 | 529 | 2179512 | 341 |
| 5 | mixed emoji text | candidate hook (1000 pages) | 16.13 | 10070 | 3283 | 0 | 3283 | 1 | 529 | 0 | 0 | 0 | 2179512 | 2719 |
| 5 | mixed emoji text | defer hook (5000 pages) | 16.24 | 10360 | 3450 | 0 | 3450 | 1 | 529 | 0 | 0 | 0 | 2179512 | 2960 |
| 5 | mixed emoji text | disable hook checkpoint | 16.31 | 10371 | 3317 | 0 | 3317 | 1 | 529 | 0 | 0 | 0 | 2179512 | 3197 |

## Concurrent reader guardrail

| scenario | write_wall_ms | read_count | read_median_us | read_p90_us | read_max_us | wal_bytes | manual_checkpoint_us |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline hook (500 pages) | 66.63 | 1198 | 23 | 55 | 6602 | 2228952 | 1964 |
| candidate hook (1000 pages) | 52.38 | 1263 | 17 | 36 | 3123 | 3576192 | 4299 |
| defer hook (5000 pages) | 53.18 | 1401 | 15 | 35 | 6133 | 3576192 | 5396 |
| disable hook checkpoint | 55.07 | 1558 | 14 | 41 | 4833 | 3576192 | 4141 |

## Stream guardrail

| scenario | expected_emissions | observed_emissions | final_count | write_wall_ms |
|---|---:|---:|---:|---:|
| baseline hook (500 pages) | 6 | 6 | 2500 | 45.50 |
| candidate hook (1000 pages) | 6 | 6 | 2500 | 41.06 |
| defer hook (5000 pages) | 6 | 6 | 2500 | 44.39 |
| disable hook checkpoint | 6 | 6 | 2500 | 40.90 |

## Sustained checkpoint sweep

| scenario | batches | rows_per_batch | total_wall_ms | batch_median_us | batch_p90_us | batch_max_us | max_commit_us | checkpointed_batches | total_checkpoint_us | max_checkpoint_us | max_wal_pages | wal_bytes | manual_checkpoint_us |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline hook (500 pages) | 60 | 2000 | 340.98 | 3288 | 6419 | 8448 | 5555 | 12 | 39832 | 3877 | 585 | 2410232 | 275 |
| candidate hook (1000 pages) | 60 | 2000 | 328.20 | 3344 | 4764 | 12006 | 9062 | 6 | 31581 | 8523 | 1089 | 4486712 | 4047 |
| 2000-page hook | 60 | 2000 | 332.95 | 3257 | 4010 | 20359 | 17584 | 3 | 35358 | 14643 | 2098 | 8643792 | 3141 |
| 5000-page hook | 60 | 2000 | 322.14 | 3479 | 4266 | 19701 | 16962 | 1 | 16206 | 16206 | 5009 | 20637112 | 16891 |
| disable hook checkpoint | 60 | 2000 | 307.33 | 3508 | 4016 | 4691 | 1818 | 0 | 0 | 0 | 6875 | 28325032 | 23914 |

## Reading the table

- `checkpoint_us` is measured inside the native wal hook, so it is also included in `commit_us`.
- `manual_passive_checkpoint_us` is the deferred cleanup cost paid after the measured write when the hook did not checkpoint during COMMIT.
- Reader and stream guardrails use the public `Database` API path; profile rows use the native profile helper directly to isolate SQLite-side wall.
- The sustained sweep repeats 60 emoji batches of 2,000 rows on one connection to expose periodic checkpoint tail latency.
