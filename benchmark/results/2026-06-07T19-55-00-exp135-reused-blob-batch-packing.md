# resqlite Experiment 135 Results

Generated: 2026-06-07T19:55:00

Run settings:
- Label: `exp135-reused-blob-batch-packing`
- Runtime: `dart-vm / Dart 3.11.5`
- OS: `macos`
- Git: `exp-135-blob-batch-packing @ 4c96104`
- Comparison baseline: `origin/main @ 8c91b32`

## Batch Param Marshal: Reused 256-Byte BLOBs

This focused pass measures only Dart-side batch parameter packing:
`allocateBatchParams` followed by `freeParamBuffer`. It avoids SQLite storage
copy noise so the BLOB arena-copy optimization is directly visible.

Command:

```text
dart run benchmark/experiments/batch_param_flatten.dart --measure=marshal --warmup=20 --iterations=100 --blob-bytes=256 --blob-mode=reused
```

| Shape | Baseline p50 (ms) | Candidate p50 (ms) | Delta |
|---|---:|---:|---:|
| 1,000 rows x 8 params | 0.471 | 0.184 | -60.9% |
| 10,000 rows x 8 params | 4.154 | 1.338 | -67.8% |
| 1,000 rows x 20 params | 0.962 | 0.298 | -69.0% |
| 10,000 rows x 20 params | 11.763 | 6.236 | -47.0% |

## Write-Suite Guardrail

The release write suite's wide batch row uses fresh tiny BLOBs, so exp 135 is
expected to be neutral there. This candidate pass is recorded as a guardrail,
not as the acceptance signal.

Command:

```text
dart run benchmark/suites/writes.dart
```

| Workload | resqlite p50 (ms) | resqlite p90 (ms) |
|---|---:|---:|
| Batch Insert (100 rows) | 0.145 | 0.836 |
| Batch Insert (1,000 rows) | 0.459 | 1.136 |
| Batch Insert (10,000 rows) | 5.149 | 9.055 |
| Wide Batch Insert (10,000 rows x 20 params) | 14.943 | 26.278 |
| tx.executeBatch (100 rows) | 0.120 | 0.249 |
| tx.executeBatch (1,000 rows) | 0.472 | 0.881 |

## Decision

Accept for review. Repeated large `Uint8List` object identity is cheap to
detect and safe to reuse inside the synchronous batch arena. Equal-but-distinct
BLOB payloads remain out of scope because byte hashing or comparison would need
its own workload and decision threshold.
