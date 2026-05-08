# Experiment 130 - Wide Batch Native Call Split

Profile-mode harness: `benchmark/profile/wide_batch_native_call_split.dart`

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/wide_batch_native_call_split.dart --markdown --repeats=5
```

## Counters

| pass | workload | wall_ms | native_write_us | stmt_us | tx_begin_us | tx_commit_us | tx_rollback_us | bind_us | step_us | reset_us | native_residual_us | preupdate_us | sets | binds | steps | resets | preupdates |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | 31.63 | 10440 | 26 | 21 | 2607 | 0 | 1619 | 4817 | 263 | 1087 | 295 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 1 | mixed Unicode text | 40.78 | 10260 | 29 | 29 | 3176 | 0 | 1402 | 4581 | 235 | 808 | 332 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 1 | mixed emoji text | 34.55 | 12940 | 33 | 29 | 6031 | 0 | 1395 | 4451 | 269 | 732 | 287 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 2 | mixed ASCII text | 17.71 | 9800 | 34 | 23 | 2458 | 0 | 1427 | 4530 | 255 | 1073 | 285 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 2 | mixed Unicode text | 20.84 | 10343 | 39 | 29 | 3231 | 0 | 1366 | 4702 | 217 | 759 | 359 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 2 | mixed emoji text | 41.72 | 13123 | 30 | 28 | 6154 | 0 | 1324 | 4547 | 240 | 800 | 300 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 3 | mixed ASCII text | 18.06 | 9280 | 26 | 29 | 2509 | 0 | 1372 | 4363 | 236 | 745 | 308 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 3 | mixed Unicode text | 21.84 | 9898 | 29 | 25 | 3090 | 0 | 1360 | 4449 | 219 | 726 | 342 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 3 | mixed emoji text | 24.67 | 13754 | 36 | 25 | 6878 | 0 | 1411 | 4444 | 215 | 745 | 275 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 4 | mixed ASCII text | 18.39 | 9604 | 43 | 29 | 2442 | 0 | 1355 | 4747 | 239 | 749 | 322 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 4 | mixed Unicode text | 20.17 | 10655 | 34 | 30 | 3645 | 0 | 1356 | 4558 | 221 | 811 | 333 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 4 | mixed emoji text | 22.43 | 12607 | 26 | 27 | 5619 | 0 | 1388 | 4518 | 231 | 798 | 305 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 5 | mixed ASCII text | 27.84 | 9400 | 32 | 29 | 2771 | 0 | 1301 | 4228 | 239 | 800 | 294 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 5 | mixed Unicode text | 21.18 | 10021 | 34 | 32 | 3214 | 0 | 1351 | 4394 | 242 | 754 | 283 | 10000 | 10000 | 10000 | 10000 | 10000 |
| 5 | mixed emoji text | 24.93 | 13327 | 25 | 24 | 6531 | 0 | 1327 | 4433 | 224 | 763 | 285 | 10000 | 10000 | 10000 | 10000 | 10000 |

## Derived split

| pass | workload | bind / native | step / native | reset / native | tx begin / native | tx commit / native | stmt / native | residual / native | preupdate / step | bind_us / set | step_us / set | reset_us / set |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | 15.51% | 46.14% | 2.52% | 0.20% | 24.97% | 0.25% | 10.41% | 6.12% | 0.162 | 0.482 | 0.026 |
| 1 | mixed Unicode text | 13.66% | 44.65% | 2.29% | 0.28% | 30.96% | 0.28% | 7.88% | 7.25% | 0.140 | 0.458 | 0.024 |
| 1 | mixed emoji text | 10.78% | 34.40% | 2.08% | 0.22% | 46.61% | 0.26% | 5.66% | 6.45% | 0.140 | 0.445 | 0.027 |
| 2 | mixed ASCII text | 14.56% | 46.22% | 2.60% | 0.23% | 25.08% | 0.35% | 10.95% | 6.29% | 0.143 | 0.453 | 0.025 |
| 2 | mixed Unicode text | 13.21% | 45.46% | 2.10% | 0.28% | 31.24% | 0.38% | 7.34% | 7.64% | 0.137 | 0.470 | 0.022 |
| 2 | mixed emoji text | 10.09% | 34.65% | 1.83% | 0.21% | 46.89% | 0.23% | 6.10% | 6.60% | 0.132 | 0.455 | 0.024 |
| 3 | mixed ASCII text | 14.78% | 47.02% | 2.54% | 0.31% | 27.04% | 0.28% | 8.03% | 7.06% | 0.137 | 0.436 | 0.024 |
| 3 | mixed Unicode text | 13.74% | 44.95% | 2.21% | 0.25% | 31.22% | 0.29% | 7.33% | 7.69% | 0.136 | 0.445 | 0.022 |
| 3 | mixed emoji text | 10.26% | 32.31% | 1.56% | 0.18% | 50.01% | 0.26% | 5.42% | 6.19% | 0.141 | 0.444 | 0.021 |
| 4 | mixed ASCII text | 14.11% | 49.43% | 2.49% | 0.30% | 25.43% | 0.45% | 7.80% | 6.78% | 0.136 | 0.475 | 0.024 |
| 4 | mixed Unicode text | 12.73% | 42.78% | 2.07% | 0.28% | 34.21% | 0.32% | 7.61% | 7.31% | 0.136 | 0.456 | 0.022 |
| 4 | mixed emoji text | 11.01% | 35.84% | 1.83% | 0.21% | 44.57% | 0.21% | 6.33% | 6.75% | 0.139 | 0.452 | 0.023 |
| 5 | mixed ASCII text | 13.84% | 44.98% | 2.54% | 0.31% | 29.48% | 0.34% | 8.51% | 6.95% | 0.130 | 0.423 | 0.024 |
| 5 | mixed Unicode text | 13.48% | 43.85% | 2.41% | 0.32% | 32.07% | 0.34% | 7.52% | 6.44% | 0.135 | 0.439 | 0.024 |
| 5 | mixed emoji text | 9.96% | 33.26% | 1.68% | 0.18% | 49.01% | 0.19% | 5.73% | 6.43% | 0.133 | 0.443 | 0.022 |

## Reading the table

- `bind_us`, `step_us`, and `reset_us` are summed inside the native 10,000-row batch loop.
- `tx_begin_us`, `tx_commit_us`, and `tx_rollback_us` are cached transaction-control statement wall for the top-level batch. Nested batches report zero transaction wall.
- `preupdate_us` is measured inside SQLite preupdate callbacks and is a subset of `step_us`, not an additive bucket.
- `native_residual_us` is the Dart-observed native call wall minus the measured native buckets. Treat it as FFI crossing, loop bookkeeping, clock skew, and measurement overhead.
