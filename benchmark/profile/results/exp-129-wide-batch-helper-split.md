# Experiment 129 - Wide Batch Write Helper Split

Profile-mode harness: `benchmark/profile/wide_batch_write_helper_split.dart`

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/wide_batch_write_helper_split.dart --markdown --repeats=5
```

## Counters

| pass | workload | shape | wall_ms | writer_requests | roundtrip_us | write_call_us | param_pack_us | native_write_us | write_residual_us | dirty_fetch_us | roundtrip_residual_us |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | 10000 rows x 20 params | 29.03 | 1 | 28307 | 19897 | 11130 | 8367 | 400 | 1167 | 7243 |
| 1 | mixed Unicode text | 10000 rows x 20 params | 36.77 | 1 | 36492 | 27379 | 18572 | 8727 | 80 | 57 | 9056 |
| 1 | mixed emoji text | 10000 rows x 20 params | 33.90 | 1 | 33818 | 27662 | 14223 | 13380 | 59 | 44 | 6112 |
| 2 | mixed ASCII text | 10000 rows x 20 params | 14.37 | 1 | 14312 | 10832 | 3053 | 7728 | 51 | 39 | 3441 |
| 2 | mixed Unicode text | 10000 rows x 20 params | 18.28 | 1 | 18237 | 13471 | 4962 | 8435 | 74 | 48 | 4718 |
| 2 | mixed emoji text | 10000 rows x 20 params | 42.55 | 1 | 42479 | 21858 | 7811 | 13974 | 73 | 66 | 20555 |
| 3 | mixed ASCII text | 10000 rows x 20 params | 15.50 | 1 | 15450 | 10729 | 2902 | 7788 | 39 | 50 | 4671 |
| 3 | mixed Unicode text | 10000 rows x 20 params | 17.02 | 1 | 16953 | 12751 | 4212 | 8466 | 73 | 57 | 4145 |
| 3 | mixed emoji text | 10000 rows x 20 params | 25.63 | 1 | 25561 | 21419 | 6303 | 15036 | 80 | 59 | 4083 |
| 4 | mixed ASCII text | 10000 rows x 20 params | 15.81 | 1 | 15737 | 10892 | 3312 | 7528 | 52 | 50 | 4795 |
| 4 | mixed Unicode text | 10000 rows x 20 params | 16.48 | 1 | 16423 | 12383 | 4131 | 8205 | 47 | 49 | 3991 |
| 4 | mixed emoji text | 10000 rows x 20 params | 23.95 | 1 | 23920 | 20212 | 5567 | 14607 | 38 | 45 | 3663 |
| 5 | mixed ASCII text | 10000 rows x 20 params | 21.91 | 1 | 21843 | 10168 | 2557 | 7552 | 59 | 51 | 11624 |
| 5 | mixed Unicode text | 10000 rows x 20 params | 17.05 | 1 | 17006 | 12872 | 4106 | 8721 | 45 | 46 | 4088 |
| 5 | mixed emoji text | 10000 rows x 20 params | 23.77 | 1 | 23696 | 19270 | 5862 | 13345 | 63 | 63 | 4363 |

## Derived split

| pass | workload | roundtrip / wall | write call / roundtrip | param pack / write call | native write / write call | write residual / write call | param pack / wall | native write / wall |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | mixed ASCII text | 97.51% | 70.29% | 55.94% | 42.05% | 2.01% | 38.34% | 28.82% |
| 1 | mixed Unicode text | 99.25% | 75.03% | 67.83% | 31.87% | 0.29% | 50.51% | 23.74% |
| 1 | mixed emoji text | 99.75% | 81.80% | 51.42% | 48.37% | 0.21% | 41.95% | 39.47% |
| 2 | mixed ASCII text | 99.63% | 75.68% | 28.19% | 71.34% | 0.47% | 21.25% | 53.80% |
| 2 | mixed Unicode text | 99.78% | 73.87% | 36.83% | 62.62% | 0.55% | 27.15% | 46.15% |
| 2 | mixed emoji text | 99.84% | 51.46% | 35.74% | 63.93% | 0.33% | 18.36% | 32.85% |
| 3 | mixed ASCII text | 99.66% | 69.44% | 27.05% | 72.59% | 0.36% | 18.72% | 50.24% |
| 3 | mixed Unicode text | 99.61% | 75.21% | 33.03% | 66.39% | 0.57% | 24.75% | 49.74% |
| 3 | mixed emoji text | 99.74% | 83.80% | 29.43% | 70.20% | 0.37% | 24.59% | 58.67% |
| 4 | mixed ASCII text | 99.53% | 69.21% | 30.41% | 69.11% | 0.48% | 20.95% | 47.61% |
| 4 | mixed Unicode text | 99.64% | 75.40% | 33.36% | 66.26% | 0.38% | 25.06% | 49.78% |
| 4 | mixed emoji text | 99.85% | 84.50% | 27.54% | 72.27% | 0.19% | 23.24% | 60.98% |
| 5 | mixed ASCII text | 99.71% | 46.55% | 25.15% | 74.27% | 0.58% | 11.67% | 34.47% |
| 5 | mixed Unicode text | 99.72% | 75.69% | 31.90% | 67.75% | 0.35% | 24.08% | 51.14% |
| 5 | mixed emoji text | 99.69% | 81.32% | 30.42% | 69.25% | 0.33% | 24.66% | 56.14% |

## Reading the table

- `param_pack_us` is Dart-side batch matrix construction: row walking, string byte measurement/encoding, blob copying, struct writes, and the single native buffer allocation.
- `native_write_us` is the `resqlite_run_batch*` call after params are packed: SQLite transaction control, binding, stepping, and statement reset work.
- `write_residual_us` is the remainder inside the write helper, mostly Dart wrapper overhead and freeing the packed parameter buffer.
