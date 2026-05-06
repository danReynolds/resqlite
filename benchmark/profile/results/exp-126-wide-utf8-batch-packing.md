# Exp 126 - Wide UTF-8 Batch Parameter Packing

Focused benchmark:

```text
dart run benchmark/experiments/batch_param_flatten.dart --iterations=50 --text-mode=unicode
dart run benchmark/experiments/batch_param_flatten.dart --iterations=50 --text-mode=emoji
```

Baseline was current `origin/main` plus the benchmark harness text-mode option.
Candidate adds the direct UTF-8 batch payload writer behind the same large/wide
guard as exp 125.

## Focused p50 wall time

| Text mode | Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|---:|
| unicode | 10,000 rows x 8 params | 9.903 ms | 8.216 ms | -17.0% |
| unicode | 10,000 rows x 20 params | 21.945 ms | 18.988 ms | -13.5% |
| emoji | 10,000 rows x 8 params | 9.580 ms | 8.358 ms | -12.8% |
| emoji | 10,000 rows x 20 params | 24.187 ms | 17.458 ms | -27.8% |

Small/narrow controls are neutral:

| Text mode | Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|---:|
| unicode | 10,000 rows x 2 params | 4.420 ms | 4.515 ms | +2.1% |
| unicode | 1,000 rows x 8 params | 0.837 ms | 0.832 ms | -0.6% |
| unicode | 1,000 rows x 20 params | 1.618 ms | 1.615 ms | -0.2% |
| emoji | 10,000 rows x 2 params | 4.553 ms | 4.506 ms | -1.0% |
| emoji | 1,000 rows x 8 params | 0.815 ms | 0.881 ms | +8.1% |
| emoji | 1,000 rows x 20 params | 1.660 ms | 1.542 ms | -7.1% |

## Release write-suite guardrail

Baseline command in detached `origin/main` worktree:

```text
/Users/dan/Coding/flutter_arm64/bin/dart run benchmark/suites/writes.dart
```

Candidate command in experiment worktree:

```text
dart run benchmark/suites/writes.dart
```

| Workload | Baseline | Candidate | Delta | Read |
|---|---:|---:|---:|---|
| Batch Insert (100 rows) | 0.089 ms | 0.094 ms | +5.6% | neutral |
| Batch Insert (1,000 rows) | 0.392 ms | 0.415 ms | +5.9% | neutral |
| Batch Insert (10,000 rows) | 3.800 ms | 3.890 ms | +2.4% | neutral |
| Wide Batch Insert (10,000 rows x 20 params) | 13.148 ms | 13.484 ms | +2.6% | neutral |
| tx.executeBatch (100 rows) | 0.097 ms | 0.098 ms | +1.0% | neutral |
| tx.executeBatch (1,000 rows) | 0.398 ms | 0.431 ms | +8.3% | neutral |

The release suite is ASCII-heavy, so it exercises exp 125's existing ASCII
path first. The small positive deltas are within the write-suite's normal
single-pass noise band and do not point at a targeted regression.
