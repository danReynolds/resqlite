# Exp 125 - Wide ASCII batch parameter encoding

Generated: 2026-05-05T18:20:00Z

Branch: `exp-125-wide-ascii-batch-params`
Base: `origin/main` at `1c8f30e15a8d`

## Focused Batch Param Flatten

Command:

```text
dart run benchmark/experiments/batch_param_flatten.dart --iterations=60
```

| Shape | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| 10,000 rows x 2 params | 3.829 ms | 3.613 ms | -5.6% |
| 10,000 rows x 8 params | 7.639 ms | 6.218 ms | -18.6% |
| 10,000 rows x 20 params | 17.199 ms | 12.760 ms | -25.8% |
| 1,000 rows x 8 params | 0.706 ms | 0.690 ms | -2.3% |
| 1,000 rows x 20 params | 1.376 ms | 1.139 ms | -17.2% |

## Release Write Suite Guardrail

Command:

```text
dart run benchmark/suites/writes.dart
```

| Write workload | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| Batch Insert (100 rows) | 0.097 ms | 0.089 ms | -8.2% |
| Batch Insert (1,000 rows) | 0.413 ms | 0.401 ms | -2.9% |
| Batch Insert (10,000 rows) | 3.998 ms | 3.848 ms | -3.8% |
| Wide Batch Insert (10,000 rows x 20 params) | 18.201 ms | 13.031 ms | -28.4% |
| tx.executeBatch (100 rows) | 0.105 ms | 0.100 ms | -4.8% |
| tx.executeBatch (1,000 rows) | 0.448 ms | 0.402 ms | -10.3% |

## Local Rejected Variants

- Stable column-kind specialization regressed focused 10k x20 p50 from
  17.247 ms to 18.347 ms in a 30-iteration pass.
- Raising the reusable native parameter buffer cap was unstable and carried a
  memory-retention tradeoff, so it was not kept.

## Validation

```text
dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart test/database_test.dart
dart test test/database_test.dart test/transaction_test.dart --timeout 60s
dart run build_runner build --delete-conflicting-outputs
dart run benchmark/suites/writes.dart
```
