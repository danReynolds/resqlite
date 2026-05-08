# Experiment 127 - Writer-Isolate Wall vs SQLite Step Wall

Profile-mode harness: `benchmark/profile/writer_isolate_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention (inherited from `audit_workloads.dart`): `wall_us` is writer-side burst wall — the stopwatch stops on the last write. Emission drains run after the stopwatch so the wall denominator is not padded with idle waiting.

`writer_handler_us` is the cumulative wall the writer dispatch loop spent inside *every* non-snapshot `WriterRequest` (`ExecuteRequest`, `BatchRequest`, `BeginRequest`, `CommitRequest`, `RollbackRequest`, `QueryRequest`, `CloseRequest`), including each message's Dart-side prologue/epilogue (request decode, dirty-table read, response build, reply send). `writer_sqlite_us` is narrower — it is the wall spent inside the FFI *write* helpers (`executeWrite`, `executeBatchWrite`, `executeNestedBatchWrite`), so it is incremented from `_handleExecute` and `_handleBatch` only. On the audit workloads here the user only issues `db.execute`, so handler dispatch is dominated by `ExecuteRequest` and the difference `handler_us - sqlite_us` is the writer-side Dart wall on that request type.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_isolate_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | handler_us | sqlite_us | handler_count | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 33.63 | 17443 | 11792 | 500 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 39.12 | 14293 | 8731 | 500 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 87.37 | 19589 | 11160 | 500 | 0 | 0 | 32 |
| keyed PK subscriptions | 50 streams x 200 random writes | 18.94 | 6895 | 4415 | 200 | 0 | 0 | 3 |

## Derived fractions

| workload | handler_us / wall_us | sqlite_us / wall_us | dart_us / wall_us | sqlite_us / handler_us | us per handler call | us per sqlite call |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 51.87% | 35.06% | 16.80% | 67.60% | 34.89 | 23.58 |
| A11c disjoint | 36.53% | 22.32% | 14.22% | 61.09% | 28.59 | 17.46 |
| A11c overlap | 22.42% | 12.77% | 9.65% | 56.97% | 39.18 | 22.32 |
| keyed PK subscriptions | 36.41% | 23.32% | 13.10% | 64.03% | 34.48 | 22.07 |

## Reading the table

- `handler_us / wall_us` is the fraction of writer-side burst wall where the writer isolate was actually busy in its handler loop. The remainder is wall the writer was idle — waiting for the next request to arrive after the previous one returned to the main isolate.
- `sqlite_us / wall_us` is the fraction of writer-side burst wall spent inside the FFI write helpers. This is the floor on what writer-side dispatch optimizations could possibly leave; if it is close to `handler_us / wall_us`, the writer is already spending almost all of its busy time in SQLite proper.
- `dart_us / wall_us` is the writer-side Dart wall fraction — request decode, dirty-table read, response build, reply send. Future writer-side dispatch experiments are bounded by this fraction.
- `sqlite_us / handler_us` is the same idea normalized to the writer-busy wall. It abstracts over how saturated the writer isolate is across the burst.
- `parked_total` and `max_parked` should both stay at zero post-exp-120, reproducing exp 120's acceptance signal as a sanity check.

## Interpretation

See `experiments/127-writer-isolate-wall-split.md` for the decision and follow-up notes attached to these numbers.
