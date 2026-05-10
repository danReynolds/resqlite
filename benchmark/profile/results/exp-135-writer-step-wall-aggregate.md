# Experiment 135 - Writer Step Wall vs Dispatch Wall Audit

Profile-mode harness: `benchmark/profile/writer_step_wall_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention: `wall_us` is writer-side burst wall — the stopwatch stops on the last write (matches exp 119 / exp 121). Writer counters are snapshotted from the writer isolate via `Database.snapshotWriterProfileCounters()`.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_step_wall_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | handler_us | sqlite_us | dispatch_us | handler_count | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 34.35 | 17609 | 12073 | 5536 | 500 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 37.18 | 13029 | 8107 | 4922 | 500 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 84.57 | 20765 | 11418 | 9347 | 500 | 0 | 0 | 22 |
| keyed PK subscriptions | 50 streams x 200 random writes | 18.41 | 5747 | 4012 | 1735 | 200 | 0 | 0 | 3 |

## Derived fractions

| workload | handler_us / wall_us | sqlite_us / wall_us | dispatch_us / wall_us | sqlite_us / handler_us | us per handler | sqlite_us per handler | dispatch_us per handler |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 51.26% | 35.14% | 16.11% | 68.56% | 35.22 | 24.15 | 11.07 |
| A11c disjoint | 35.04% | 21.80% | 13.24% | 62.22% | 26.06 | 16.21 | 9.84 |
| A11c overlap | 24.55% | 13.50% | 11.05% | 54.99% | 41.53 | 22.84 | 18.69 |
| keyed PK subscriptions | 31.21% | 21.79% | 9.42% | 69.81% | 28.73 | 20.06 | 8.68 |

## Reading the table

- `handler_us` is the cumulative wall the writer isolate spent between request receipt and `replyPort.send`, summed over every handled message during the workload. It includes Dart-side dispatch (param allocation, dirty-table marshalling) and the FFI calls themselves.
- `sqlite_us` is the cumulative wall spent specifically inside the FFI calls that drive SQLite — `resqliteExecute`, `resqliteRunBatch`, `resqliteRunBatchNested`, the transaction-control stmts, and the prepare+step portion of transaction reads.
- `dispatch_us = handler_us - sqlite_us` is the writer-side Dart dispatch wall: param packing, `getDirtyTableDependencies`, message send, and any Dart-only bookkeeping inside the handler.
- `sqlite_us / handler_us` is the share of writer-isolate handler wall actually spent in SQLite. A high share means writer-side dispatch optimization has little room; a low share means the inverse.
- `parked_total` and `max_parked` should both stay at zero post-exp-120, reproducing exp 120's acceptance signal as a sanity check on top of the new counters.

## Interpretation

See `experiments/135-writer-step-wall-audit.md` for the decision and follow-up notes attached to these numbers.
