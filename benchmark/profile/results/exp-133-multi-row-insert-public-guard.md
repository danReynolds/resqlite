# Experiment 133 - Public Multi-row INSERT Guard

Command:

```text
dart run benchmark/profile/multi_row_insert_public_guard.dart --markdown --repeats=7 --rows=10000
```

| workload | fallback_wall_ms | optimized_wall_ms | delta |
|---|---:|---:|---:|
| narrow 2 params | 4.68 | 3.14 | -33.0% |
| wide mixed ASCII | 16.34 | 14.76 | -9.7% |
| blob-heavy 8 params | 10.41 | 9.41 | -9.6% |

## Raw rows

| pass | workload | mode | wall_ms |
|---:|---|---|---:|
| 1 | narrow 2 params | fallback quoted | 21.66 |
| 1 | narrow 2 params | optimized | 14.54 |
| 1 | wide mixed ASCII | fallback quoted | 34.24 |
| 1 | wide mixed ASCII | optimized | 25.93 |
| 1 | blob-heavy 8 params | fallback quoted | 13.94 |
| 1 | blob-heavy 8 params | optimized | 12.12 |
| 2 | narrow 2 params | fallback quoted | 6.16 |
| 2 | narrow 2 params | optimized | 2.94 |
| 2 | wide mixed ASCII | fallback quoted | 15.43 |
| 2 | wide mixed ASCII | optimized | 14.53 |
| 2 | blob-heavy 8 params | fallback quoted | 10.30 |
| 2 | blob-heavy 8 params | optimized | 8.90 |
| 3 | narrow 2 params | fallback quoted | 4.26 |
| 3 | narrow 2 params | optimized | 3.81 |
| 3 | wide mixed ASCII | fallback quoted | 15.24 |
| 3 | wide mixed ASCII | optimized | 14.47 |
| 3 | blob-heavy 8 params | fallback quoted | 10.41 |
| 3 | blob-heavy 8 params | optimized | 8.90 |
| 4 | narrow 2 params | fallback quoted | 4.08 |
| 4 | narrow 2 params | optimized | 3.14 |
| 4 | wide mixed ASCII | fallback quoted | 17.42 |
| 4 | wide mixed ASCII | optimized | 17.29 |
| 4 | blob-heavy 8 params | fallback quoted | 10.53 |
| 4 | blob-heavy 8 params | optimized | 9.73 |
| 5 | narrow 2 params | fallback quoted | 4.68 |
| 5 | narrow 2 params | optimized | 3.17 |
| 5 | wide mixed ASCII | fallback quoted | 17.45 |
| 5 | wide mixed ASCII | optimized | 14.68 |
| 5 | blob-heavy 8 params | fallback quoted | 11.85 |
| 5 | blob-heavy 8 params | optimized | 9.41 |
| 6 | narrow 2 params | fallback quoted | 4.38 |
| 6 | narrow 2 params | optimized | 3.06 |
| 6 | wide mixed ASCII | fallback quoted | 16.34 |
| 6 | wide mixed ASCII | optimized | 16.34 |
| 6 | blob-heavy 8 params | fallback quoted | 10.00 |
| 6 | blob-heavy 8 params | optimized | 9.55 |
| 7 | narrow 2 params | fallback quoted | 5.31 |
| 7 | narrow 2 params | optimized | 3.07 |
| 7 | wide mixed ASCII | fallback quoted | 15.12 |
| 7 | wide mixed ASCII | optimized | 14.76 |
| 7 | blob-heavy 8 params | fallback quoted | 9.83 |
| 7 | blob-heavy 8 params | optimized | 8.44 |
