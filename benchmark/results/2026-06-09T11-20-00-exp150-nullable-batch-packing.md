# resqlite Focused Benchmark Results

Generated: 2026-06-09T11:20:00

Run settings:
- Label: `exp150-nullable-batch-packing`
- Repeats: `1`
- Runtime: `dart-vm / Dart 3.12.1`
- OS: `macos Version 26.2 (Build 25C56)`
- Baseline git: `origin/main @ 72a2b92` with temporary `nullable-ascii`
  benchmark mode only
- Candidate git: `exp-150-param-encoding-hotpath`

Command:

```text
dart run benchmark/experiments/batch_param_flatten.dart \
  --warmup=8 --iterations=40 --text-mode=<mode>
```

## Batch Param Flatten

Focused writer-isolate batch preparation plus SQLite batch execution timing.
The `nullable-ascii` mode sets text columns in row 0 to `NULL` and later rows
to ASCII strings, exposing the first-row string-probe blind spot fixed by
experiment 150.

### Nullable ASCII 10000 x8

| Library | Wall med (ms) | Wall p90 (ms) |
|---|---:|---:|
| resqlite baseline | 13.552 | 25.039 |
| resqlite candidate | 11.152 | 14.466 |

### Nullable ASCII 10000 x20

| Library | Wall med (ms) | Wall p90 (ms) |
|---|---:|---:|
| resqlite baseline | 25.738 | 39.925 |
| resqlite candidate | 21.723 | 41.516 |

### ASCII Guardrail 10000 x8

| Library | Wall med (ms) | Wall p90 (ms) |
|---|---:|---:|
| resqlite baseline | 10.309 | 16.359 |
| resqlite candidate | 10.338 | 13.740 |

### ASCII Guardrail 10000 x20

| Library | Wall med (ms) | Wall p90 (ms) |
|---|---:|---:|
| resqlite baseline | 21.625 | 33.316 |
| resqlite candidate | 20.179 | 37.152 |

### Unicode Guardrail 10000 x8

| Library | Wall med (ms) | Wall p90 (ms) |
|---|---:|---:|
| resqlite baseline | 13.317 | 15.770 |
| resqlite candidate | 13.469 | 21.407 |

### Unicode Guardrail 10000 x20

| Library | Wall med (ms) | Wall p90 (ms) |
|---|---:|---:|
| resqlite baseline | 29.085 | 47.617 |
| resqlite candidate | 30.499 | 52.874 |
