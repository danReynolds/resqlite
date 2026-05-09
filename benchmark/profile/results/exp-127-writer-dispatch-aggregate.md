# Experiment 127 - Writer Dispatch Wall Audit

Profile-mode harness: `benchmark/profile/writer_dispatch_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention: `wall_us` is writer-side burst wall — the stopwatch stops on the last write. Writer counters are snapshotted via `Database.writerProfileCounters()` immediately around the burst, so `writer_handle_us` and `writer_step_us` cover the same window as `wall_us`.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_dispatch_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | writer_handle_us | writer_step_us | writer_handle_count | invalidate_count | parked_total |
|---|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 37.06 | 17757 | 8850 | 500 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 46.32 | 16098 | 7197 | 500 | 500 | 0 |
| A11c overlap | 50 streams x 500 writes | 98.92 | 24104 | 10546 | 500 | 500 | 0 |
| keyed PK subscriptions | 50 streams x 200 random writes | 29.47 | 10558 | 6642 | 200 | 200 | 0 |

## Derived fractions

| workload | handle / wall | step / wall | dispatch / wall | us per write (handle) | us per write (step) | us per write (dispatch) |
|---|---:|---:|---:|---:|---:|---:|
| A11c baseline | 47.91% | 23.88% | 24.03% | 35.51 | 17.70 | 17.81 |
| A11c disjoint | 34.75% | 15.54% | 19.22% | 32.20 | 14.39 | 17.80 |
| A11c overlap | 24.37% | 10.66% | 13.71% | 48.21 | 21.09 | 27.12 |
| keyed PK subscriptions | 35.82% | 22.54% | 13.29% | 52.79 | 33.21 | 19.58 |

## Reading the table

- `writer_handle_us` is cumulative wall in the writer isolate's `_handleExecute` / `_handleBatch` body. It includes param encoding, the SQLite step itself, dirty-tables gather, and response build.
- `writer_step_us` is the subset spent inside the FFI call (`resqlite_execute` / `resqlite_run_batch`). The C side is not instrumented; treat this as the closest available approximation to "real SQLite work" without modifying the C amalgamation.
- `dispatch / wall` = `(writer_handle_us - writer_step_us) / wall_us`. It is the fraction of writer-side burst wall attributable to Dart-side dispatch overhead — param encoding, dirty-tables gather, isolate IPC framing, response construction. A small share argues that the next dispatch experiment should branch onto completion-side scheduling instead.
- `parked_total` should stay at zero post-exp-120/122. If it ticks above zero, treat the run as a regression of the dispatch-admission invariant before reading the writer fractions.

## Interpretation

See `experiments/127-writer-dispatch-wall-audit.md` for the decision and follow-up notes attached to these numbers.
