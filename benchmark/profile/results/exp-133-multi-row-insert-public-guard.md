# Experiment 133 - Public Multi-row INSERT Guard

Command:

```text
dart run benchmark/profile/multi_row_insert_public_guard.dart --markdown --repeats=21 --rows=10000
```

| workload | fallback_wall_ms | optimized_wall_ms | quoted_optimized_wall_ms | optimized_delta | quoted_delta |
|---|---:|---:|---:|---:|---:|
| narrow 2 params | 4.48 | 3.22 | 3.07 | -28.1% | -31.5% |
| wide mixed ASCII | 18.11 | 17.30 | 17.54 | -4.4% | -3.2% |
| blob-heavy 8 params | 12.33 | 10.93 | 10.37 | -11.3% | -15.9% |

## Raw rows

| pass | workload | mode | wall_ms |
|---:|---|---|---:|
| 1 | narrow 2 params | fallback comment | 18.43 |
| 1 | narrow 2 params | optimized | 10.08 |
| 1 | narrow 2 params | optimized quoted | 7.95 |
| 1 | wide mixed ASCII | fallback comment | 31.05 |
| 1 | wide mixed ASCII | optimized | 25.16 |
| 1 | wide mixed ASCII | optimized quoted | 29.34 |
| 1 | blob-heavy 8 params | fallback comment | 22.88 |
| 1 | blob-heavy 8 params | optimized | 21.37 |
| 1 | blob-heavy 8 params | optimized quoted | 14.36 |
| 2 | narrow 2 params | fallback comment | 5.50 |
| 2 | narrow 2 params | optimized | 4.13 |
| 2 | narrow 2 params | optimized quoted | 3.87 |
| 2 | wide mixed ASCII | fallback comment | 25.26 |
| 2 | wide mixed ASCII | optimized | 16.45 |
| 2 | wide mixed ASCII | optimized quoted | 16.32 |
| 2 | blob-heavy 8 params | fallback comment | 22.64 |
| 2 | blob-heavy 8 params | optimized | 11.50 |
| 2 | blob-heavy 8 params | optimized quoted | 37.52 |
| 3 | narrow 2 params | fallback comment | 5.70 |
| 3 | narrow 2 params | optimized | 3.24 |
| 3 | narrow 2 params | optimized quoted | 3.29 |
| 3 | wide mixed ASCII | fallback comment | 19.79 |
| 3 | wide mixed ASCII | optimized | 18.41 |
| 3 | wide mixed ASCII | optimized quoted | 24.00 |
| 3 | blob-heavy 8 params | fallback comment | 12.71 |
| 3 | blob-heavy 8 params | optimized | 13.15 |
| 3 | blob-heavy 8 params | optimized quoted | 11.61 |
| 4 | narrow 2 params | fallback comment | 4.40 |
| 4 | narrow 2 params | optimized | 3.01 |
| 4 | narrow 2 params | optimized quoted | 2.85 |
| 4 | wide mixed ASCII | fallback comment | 18.33 |
| 4 | wide mixed ASCII | optimized | 27.24 |
| 4 | wide mixed ASCII | optimized quoted | 15.09 |
| 4 | blob-heavy 8 params | fallback comment | 20.59 |
| 4 | blob-heavy 8 params | optimized | 9.28 |
| 4 | blob-heavy 8 params | optimized quoted | 18.52 |
| 5 | narrow 2 params | fallback comment | 4.40 |
| 5 | narrow 2 params | optimized | 3.55 |
| 5 | narrow 2 params | optimized quoted | 3.03 |
| 5 | wide mixed ASCII | fallback comment | 16.15 |
| 5 | wide mixed ASCII | optimized | 16.19 |
| 5 | wide mixed ASCII | optimized quoted | 15.41 |
| 5 | blob-heavy 8 params | fallback comment | 10.01 |
| 5 | blob-heavy 8 params | optimized | 8.80 |
| 5 | blob-heavy 8 params | optimized quoted | 8.84 |
| 6 | narrow 2 params | fallback comment | 4.44 |
| 6 | narrow 2 params | optimized | 3.45 |
| 6 | narrow 2 params | optimized quoted | 3.13 |
| 6 | wide mixed ASCII | fallback comment | 17.17 |
| 6 | wide mixed ASCII | optimized | 16.95 |
| 6 | wide mixed ASCII | optimized quoted | 17.36 |
| 6 | blob-heavy 8 params | fallback comment | 12.98 |
| 6 | blob-heavy 8 params | optimized | 10.28 |
| 6 | blob-heavy 8 params | optimized quoted | 10.69 |
| 7 | narrow 2 params | fallback comment | 4.44 |
| 7 | narrow 2 params | optimized | 3.58 |
| 7 | narrow 2 params | optimized quoted | 3.35 |
| 7 | wide mixed ASCII | fallback comment | 16.89 |
| 7 | wide mixed ASCII | optimized | 26.28 |
| 7 | wide mixed ASCII | optimized quoted | 17.56 |
| 7 | blob-heavy 8 params | fallback comment | 12.14 |
| 7 | blob-heavy 8 params | optimized | 10.03 |
| 7 | blob-heavy 8 params | optimized quoted | 9.50 |
| 8 | narrow 2 params | fallback comment | 5.09 |
| 8 | narrow 2 params | optimized | 3.02 |
| 8 | narrow 2 params | optimized quoted | 3.15 |
| 8 | wide mixed ASCII | fallback comment | 27.33 |
| 8 | wide mixed ASCII | optimized | 17.22 |
| 8 | wide mixed ASCII | optimized quoted | 32.81 |
| 8 | blob-heavy 8 params | fallback comment | 12.60 |
| 8 | blob-heavy 8 params | optimized | 11.90 |
| 8 | blob-heavy 8 params | optimized quoted | 11.64 |
| 9 | narrow 2 params | fallback comment | 6.93 |
| 9 | narrow 2 params | optimized | 3.77 |
| 9 | narrow 2 params | optimized quoted | 2.98 |
| 9 | wide mixed ASCII | fallback comment | 18.73 |
| 9 | wide mixed ASCII | optimized | 19.76 |
| 9 | wide mixed ASCII | optimized quoted | 17.54 |
| 9 | blob-heavy 8 params | fallback comment | 11.86 |
| 9 | blob-heavy 8 params | optimized | 32.95 |
| 9 | blob-heavy 8 params | optimized quoted | 9.07 |
| 10 | narrow 2 params | fallback comment | 4.18 |
| 10 | narrow 2 params | optimized | 3.39 |
| 10 | narrow 2 params | optimized quoted | 3.40 |
| 10 | wide mixed ASCII | fallback comment | 15.09 |
| 10 | wide mixed ASCII | optimized | 22.34 |
| 10 | wide mixed ASCII | optimized quoted | 15.85 |
| 10 | blob-heavy 8 params | fallback comment | 11.83 |
| 10 | blob-heavy 8 params | optimized | 9.90 |
| 10 | blob-heavy 8 params | optimized quoted | 9.91 |
| 11 | narrow 2 params | fallback comment | 4.58 |
| 11 | narrow 2 params | optimized | 4.30 |
| 11 | narrow 2 params | optimized quoted | 3.20 |
| 11 | wide mixed ASCII | fallback comment | 16.02 |
| 11 | wide mixed ASCII | optimized | 15.03 |
| 11 | wide mixed ASCII | optimized quoted | 15.35 |
| 11 | blob-heavy 8 params | fallback comment | 10.85 |
| 11 | blob-heavy 8 params | optimized | 10.06 |
| 11 | blob-heavy 8 params | optimized quoted | 9.79 |
| 12 | narrow 2 params | fallback comment | 4.21 |
| 12 | narrow 2 params | optimized | 3.22 |
| 12 | narrow 2 params | optimized quoted | 3.24 |
| 12 | wide mixed ASCII | fallback comment | 17.26 |
| 12 | wide mixed ASCII | optimized | 17.30 |
| 12 | wide mixed ASCII | optimized quoted | 33.13 |
| 12 | blob-heavy 8 params | fallback comment | 24.07 |
| 12 | blob-heavy 8 params | optimized | 10.80 |
| 12 | blob-heavy 8 params | optimized quoted | 10.37 |
| 13 | narrow 2 params | fallback comment | 4.25 |
| 13 | narrow 2 params | optimized | 3.20 |
| 13 | narrow 2 params | optimized quoted | 3.05 |
| 13 | wide mixed ASCII | fallback comment | 17.82 |
| 13 | wide mixed ASCII | optimized | 16.62 |
| 13 | wide mixed ASCII | optimized quoted | 15.60 |
| 13 | blob-heavy 8 params | fallback comment | 12.33 |
| 13 | blob-heavy 8 params | optimized | 11.88 |
| 13 | blob-heavy 8 params | optimized quoted | 12.11 |
| 14 | narrow 2 params | fallback comment | 4.42 |
| 14 | narrow 2 params | optimized | 3.38 |
| 14 | narrow 2 params | optimized quoted | 3.27 |
| 14 | wide mixed ASCII | fallback comment | 19.50 |
| 14 | wide mixed ASCII | optimized | 19.61 |
| 14 | wide mixed ASCII | optimized quoted | 17.70 |
| 14 | blob-heavy 8 params | fallback comment | 11.90 |
| 14 | blob-heavy 8 params | optimized | 10.93 |
| 14 | blob-heavy 8 params | optimized quoted | 9.99 |
| 15 | narrow 2 params | fallback comment | 7.33 |
| 15 | narrow 2 params | optimized | 3.12 |
| 15 | narrow 2 params | optimized quoted | 3.01 |
| 15 | wide mixed ASCII | fallback comment | 18.11 |
| 15 | wide mixed ASCII | optimized | 16.89 |
| 15 | wide mixed ASCII | optimized quoted | 25.93 |
| 15 | blob-heavy 8 params | fallback comment | 11.47 |
| 15 | blob-heavy 8 params | optimized | 19.61 |
| 15 | blob-heavy 8 params | optimized quoted | 8.81 |
| 16 | narrow 2 params | fallback comment | 4.91 |
| 16 | narrow 2 params | optimized | 2.93 |
| 16 | narrow 2 params | optimized quoted | 2.83 |
| 16 | wide mixed ASCII | fallback comment | 19.04 |
| 16 | wide mixed ASCII | optimized | 16.19 |
| 16 | wide mixed ASCII | optimized quoted | 15.12 |
| 16 | blob-heavy 8 params | fallback comment | 34.51 |
| 16 | blob-heavy 8 params | optimized | 8.96 |
| 16 | blob-heavy 8 params | optimized quoted | 8.70 |
| 17 | narrow 2 params | fallback comment | 4.09 |
| 17 | narrow 2 params | optimized | 3.08 |
| 17 | narrow 2 params | optimized quoted | 2.99 |
| 17 | wide mixed ASCII | fallback comment | 17.31 |
| 17 | wide mixed ASCII | optimized | 17.34 |
| 17 | wide mixed ASCII | optimized quoted | 23.94 |
| 17 | blob-heavy 8 params | fallback comment | 11.23 |
| 17 | blob-heavy 8 params | optimized | 10.09 |
| 17 | blob-heavy 8 params | optimized quoted | 10.38 |
| 18 | narrow 2 params | fallback comment | 5.34 |
| 18 | narrow 2 params | optimized | 2.68 |
| 18 | narrow 2 params | optimized quoted | 2.81 |
| 18 | wide mixed ASCII | fallback comment | 18.86 |
| 18 | wide mixed ASCII | optimized | 18.16 |
| 18 | wide mixed ASCII | optimized quoted | 32.74 |
| 18 | blob-heavy 8 params | fallback comment | 12.99 |
| 18 | blob-heavy 8 params | optimized | 11.16 |
| 18 | blob-heavy 8 params | optimized quoted | 11.40 |
| 19 | narrow 2 params | fallback comment | 4.58 |
| 19 | narrow 2 params | optimized | 3.06 |
| 19 | narrow 2 params | optimized quoted | 2.99 |
| 19 | wide mixed ASCII | fallback comment | 19.24 |
| 19 | wide mixed ASCII | optimized | 28.60 |
| 19 | wide mixed ASCII | optimized quoted | 25.20 |
| 19 | blob-heavy 8 params | fallback comment | 25.88 |
| 19 | blob-heavy 8 params | optimized | 14.87 |
| 19 | blob-heavy 8 params | optimized quoted | 9.15 |
| 20 | narrow 2 params | fallback comment | 4.47 |
| 20 | narrow 2 params | optimized | 3.11 |
| 20 | narrow 2 params | optimized quoted | 3.07 |
| 20 | wide mixed ASCII | fallback comment | 15.81 |
| 20 | wide mixed ASCII | optimized | 14.20 |
| 20 | wide mixed ASCII | optimized quoted | 14.14 |
| 20 | blob-heavy 8 params | fallback comment | 10.57 |
| 20 | blob-heavy 8 params | optimized | 8.67 |
| 20 | blob-heavy 8 params | optimized quoted | 8.61 |
| 21 | narrow 2 params | fallback comment | 4.48 |
| 21 | narrow 2 params | optimized | 3.10 |
| 21 | narrow 2 params | optimized quoted | 3.02 |
| 21 | wide mixed ASCII | fallback comment | 16.32 |
| 21 | wide mixed ASCII | optimized | 15.06 |
| 21 | wide mixed ASCII | optimized quoted | 15.81 |
| 21 | blob-heavy 8 params | fallback comment | 10.88 |
| 21 | blob-heavy 8 params | optimized | 21.12 |
| 21 | blob-heavy 8 params | optimized quoted | 18.16 |
