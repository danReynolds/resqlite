# Experiment 127 - Writer-Isolate Wall vs SQLite Step Wall

Profile-mode harness: `benchmark/profile/writer_isolate_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention (inherited from `audit_workloads.dart`): `wall_us` is writer-side burst wall — the stopwatch stops on the last write. Emission drains run after the stopwatch so the wall denominator is not padded with idle waiting.

Writer counters cover `ExecuteRequest` and `BatchRequest` only. `writer_handler_us` is the cumulative wall the writer dispatch loop spent inside any timed `WriterRequest`, including its Dart-side prologue/epilogue (param decode, dirty-table read, response build, reply send). `writer_sqlite_us` is the subset spent inside the FFI write helpers (`executeWrite`, `executeBatchWrite`, `executeNestedBatchWrite`). The difference is the writer-side Dart wall.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_isolate_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | handler_us | sqlite_us | handler_count | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 33.30 | 17088 | 11242 | 500 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 40.24 | 13930 | 8367 | 500 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 84.51 | 21400 | 11253 | 500 | 0 | 0 | 25 |
| keyed PK subscriptions | 50 streams x 200 random writes | 19.32 | 6519 | 4400 | 200 | 0 | 0 | 3 |

## Derived fractions

| workload | handler_us / wall_us | sqlite_us / wall_us | dart_us / wall_us | sqlite_us / handler_us | us per handler call | us per sqlite call |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 51.32% | 33.76% | 17.56% | 65.79% | 34.18 | 22.48 |
| A11c disjoint | 34.62% | 20.79% | 13.82% | 60.06% | 27.86 | 16.73 |
| A11c overlap | 25.32% | 13.32% | 12.01% | 52.58% | 42.80 | 22.51 |
| keyed PK subscriptions | 33.74% | 22.77% | 10.97% | 67.50% | 32.59 | 22.00 |

## Reading the table

- `handler_us / wall_us` is the fraction of writer-side burst wall where the writer isolate was actually busy in its handler loop. The remainder is wall the writer was idle — waiting for the next request to arrive after the previous one returned to the main isolate.
- `sqlite_us / wall_us` is the fraction of writer-side burst wall spent inside the FFI write helpers. This is the floor on what writer-side dispatch optimizations could possibly leave; if it is close to `handler_us / wall_us`, the writer is already spending almost all of its busy time in SQLite proper.
- `dart_us / wall_us` is the writer-side Dart wall fraction — request decode, dirty-table read, response build, reply send. Future writer-side dispatch experiments are bounded by this fraction.
- `sqlite_us / handler_us` is the same idea normalized to the writer-busy wall. It abstracts over how saturated the writer isolate is across the burst.
- `parked_total` and `max_parked` should both stay at zero post-exp-120, reproducing exp 120's acceptance signal as a sanity check.

## Interpretation

See `experiments/127-writer-isolate-wall-split.md` for the decision and follow-up notes attached to these numbers.
