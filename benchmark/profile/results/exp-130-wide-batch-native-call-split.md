# Experiment 130 - Wide Batch Native Call Split

Profile-mode harness: `benchmark/profile/wide_batch_native_call_split.dart`

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/wide_batch_native_call_split.dart --markdown --repeats=5
```

## Counters

| pass | workload | wall_ms | native_write_us | stmt_us | tx_begin_us | tx_commit_us | tx_rollback_us | bind_us | step_us | reset_us | native_residual_us | preupdate_us | sets | binds | steps | resets | preupdates |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | 27.43 | 9297 | 26 | 20 | 2200 | 0 | 1376 | 4425 | 218 | 1032 | 305 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 1 | mixed Unicode text | 38.29 | 9851 | 26 | 20 | 2923 | 0 | 1364 | 4495 | 265 | 758 | 279 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 1 | mixed emoji text | 30.92 | 13181 | 31 | 26 | 6437 | 0 | 1358 | 4380 | 230 | 719 | 289 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 2 | mixed ASCII text | 16.04 | 9391 | 48 | 26 | 2213 | 0 | 1345 | 4423 | 232 | 1104 | 313 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 2 | mixed Unicode text | 20.07 | 10322 | 28 | 26 | 3649 | 0 | 1313 | 4338 | 228 | 740 | 279 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 2 | mixed emoji text | 37.08 | 13044 | 32 | 22 | 6033 | 0 | 1337 | 4646 | 239 | 735 | 304 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 3 | mixed ASCII text | 16.24 | 9002 | 34 | 22 | 2247 | 0 | 1304 | 4347 | 276 | 772 | 323 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 3 | mixed Unicode text | 18.89 | 9805 | 43 | 24 | 3043 | 0 | 1356 | 4386 | 214 | 739 | 306 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 3 | mixed emoji text | 23.38 | 13225 | 27 | 17 | 6347 | 0 | 1424 | 4435 | 209 | 766 | 323 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 4 | mixed ASCII text | 16.26 | 9009 | 38 | 26 | 2452 | 0 | 1315 | 4152 | 217 | 809 | 307 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 4 | mixed Unicode text | 18.13 | 9589 | 31 | 23 | 2874 | 0 | 1365 | 4340 | 233 | 723 | 291 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 4 | mixed emoji text | 22.60 | 13116 | 31 | 26 | 6355 | 0 | 1307 | 4447 | 206 | 744 | 309 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 5 | mixed ASCII text | 22.96 | 9151 | 28 | 26 | 2534 | 0 | 1328 | 4213 | 217 | 805 | 281 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 5 | mixed Unicode text | 19.04 | 10601 | 25 | 23 | 4100 | 0 | 1311 | 4159 | 234 | 749 | 303 | 10000 | 10000 | 10000 | 10001 | 10000 |
| 5 | mixed emoji text | 24.02 | 13848 | 34 | 29 | 7063 | 0 | 1282 | 4446 | 232 | 762 | 292 | 10000 | 10000 | 10000 | 10001 | 10000 |

## Derived split

| pass | workload | bind / native | step / native | reset / native | tx begin / native | tx commit / native | stmt / native | residual / native | preupdate / step | bind_us / set | step_us / set | reset_us / set |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | 14.80% | 47.60% | 2.34% | 0.22% | 23.66% | 0.28% | 11.10% | 6.89% | 0.138 | 0.443 | 0.022 |
| 1 | mixed Unicode text | 13.85% | 45.63% | 2.69% | 0.20% | 29.67% | 0.26% | 7.69% | 6.21% | 0.136 | 0.450 | 0.026 |
| 1 | mixed emoji text | 10.30% | 33.23% | 1.74% | 0.20% | 48.84% | 0.24% | 5.45% | 6.60% | 0.136 | 0.438 | 0.023 |
| 2 | mixed ASCII text | 14.32% | 47.10% | 2.47% | 0.28% | 23.57% | 0.51% | 11.76% | 7.08% | 0.135 | 0.442 | 0.023 |
| 2 | mixed Unicode text | 12.72% | 42.03% | 2.21% | 0.25% | 35.35% | 0.27% | 7.17% | 6.43% | 0.131 | 0.434 | 0.023 |
| 2 | mixed emoji text | 10.25% | 35.62% | 1.83% | 0.17% | 46.25% | 0.25% | 5.63% | 6.54% | 0.134 | 0.465 | 0.024 |
| 3 | mixed ASCII text | 14.49% | 48.29% | 3.07% | 0.24% | 24.96% | 0.38% | 8.58% | 7.43% | 0.130 | 0.435 | 0.028 |
| 3 | mixed Unicode text | 13.83% | 44.73% | 2.18% | 0.24% | 31.04% | 0.44% | 7.54% | 6.98% | 0.136 | 0.439 | 0.021 |
| 3 | mixed emoji text | 10.77% | 33.53% | 1.58% | 0.13% | 47.99% | 0.20% | 5.79% | 7.28% | 0.142 | 0.444 | 0.021 |
| 4 | mixed ASCII text | 14.60% | 46.09% | 2.41% | 0.29% | 27.22% | 0.42% | 8.98% | 7.39% | 0.132 | 0.415 | 0.022 |
| 4 | mixed Unicode text | 14.24% | 45.26% | 2.43% | 0.24% | 29.97% | 0.32% | 7.54% | 6.71% | 0.137 | 0.434 | 0.023 |
| 4 | mixed emoji text | 9.96% | 33.91% | 1.57% | 0.20% | 48.45% | 0.24% | 5.67% | 6.95% | 0.131 | 0.445 | 0.021 |
| 5 | mixed ASCII text | 14.51% | 46.04% | 2.37% | 0.28% | 27.69% | 0.31% | 8.80% | 6.67% | 0.133 | 0.421 | 0.022 |
| 5 | mixed Unicode text | 12.37% | 39.23% | 2.21% | 0.22% | 38.68% | 0.24% | 7.07% | 7.29% | 0.131 | 0.416 | 0.023 |
| 5 | mixed emoji text | 9.26% | 32.11% | 1.68% | 0.21% | 51.00% | 0.25% | 5.50% | 6.57% | 0.128 | 0.445 | 0.023 |

## Reading the table

- `bind_us`, `step_us`, and `reset_us` are summed inside the native 10,000-row batch loop.
- `tx_begin_us`, `tx_commit_us`, and `tx_rollback_us` are cached transaction-control statement wall for the top-level batch. Nested batches report zero transaction wall.
- `preupdate_us` is measured inside SQLite preupdate callbacks and is a subset of `step_us`, not an additive bucket.
- `native_residual_us` is the Dart-observed native call wall minus the measured native buckets. Treat it as FFI crossing, loop bookkeeping, clock skew, and measurement overhead.
