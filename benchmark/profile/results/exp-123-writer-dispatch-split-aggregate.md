# Experiment 123 - Writer Dispatch / Native Wall Split

Profile-mode harness: `benchmark/profile/writer_dispatch_split_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention: `wall_us` is writer-side burst wall — the stopwatch stops on the last write. The `writerProfileSnapshot()` round-trip and emission drains run after the stopwatch so the denominator is not padded with idle waiting.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_dispatch_split_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | writer_handler_us | writer_handler_count | writer_native_us | writer_native_count | invalidate_us | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 42.91 | 24592 | 500 | 16960 | 500 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 46.78 | 23028 | 500 | 17462 | 500 | 7442 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 107.78 | 38954 | 500 | 28457 | 500 | 10691 | 0 | 0 | 27 |
| keyed PK subscriptions | 50 streams x 200 random writes | 23.41 | 10122 | 200 | 7151 | 200 | 2426 | 0 | 0 | 3 |
| wide batch insert | 1 batch x 10000 rows x 20 params | 39.02 | 36981 | 1 | 12684 | 1 | 0 | 0 | 0 | 0 |

## Derived fractions

| workload | writer_handler / wall | native / handler | dispatch overhead / wall | us per write (handler) | us per write (native) | us per write (dispatch) |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 57.31% | 68.97% | 17.79% | 49.18 | 33.92 | 15.26 |
| A11c disjoint | 49.23% | 75.83% | 11.90% | 46.06 | 34.92 | 11.13 |
| A11c overlap | 36.14% | 73.05% | 9.74% | 77.91 | 56.91 | 20.99 |
| keyed PK subscriptions | 43.23% | 70.65% | 12.69% | 50.61 | 35.76 | 14.86 |
| wide batch insert | 94.78% | 34.30% | 62.27% | 36981.00 | 12684.00 | 24297.00 |

## Reading the table

- `wall_us` is writer-side burst wall (main isolate stopwatch, stops on the last write).
- `writer_handler_us` is the cumulative writer-isolate wall spent inside `_handleExecute` + `_handleBatch` bodies — message receive through reply send, including parameter encoding, the FFI write call, dirty-table extraction, and reply marshalling.
- `writer_native_us` is the subset spent specifically inside the FFI write call (`resqliteExecute` / `resqliteRunBatch` / `resqliteRunBatchNested`) — i.e. SQLite-side prepare/bind/step/reset/commit work plus the FFI crossing itself.
- `native / handler` is the headline split: how much of the writer's own time is SQLite. A value near 100% means writer-side dispatch optimization can buy little (the FFI call dominates); a value well below 100% means the Dart-side wrapper is a target.
- `writer_handler / wall` is the structural ceiling on how much main-isolate wall the writer can ever explain. The remainder (`1 - handler/wall`) is main-isolate scheduling, in-flight reader fan-out, invalidation traversal, and the round-trip the request/reply messages take through Dart's isolate ports.
- `parked_total` and `max_parked` should both stay at zero post-exp-120/122. Reproducing that is a sanity check that the workload is hitting the shapes exp 119 / exp 121 measured.

## Interpretation

See `experiments/123-writer-dispatch-step-split.md` for the decision and follow-up notes attached to these numbers.
