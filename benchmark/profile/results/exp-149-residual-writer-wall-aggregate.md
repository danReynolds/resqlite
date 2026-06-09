# Experiment 149 - Residual Writer/Request Wall Split

Profile-mode harness: `benchmark/profile/residual_writer_wall_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

`wall_us` is writer-side burst wall; the stopwatch stops on the last write. `writer_handle_us` is the per-request writer-isolate handler wall (SQLite + dirty harvest + writer-internal overhead). `writer_send_us = writer_handle_us - writer_sqlite_us - writer_dirty_us` approximates writer reply construction beyond SQLite/dirty. `main_writer_reply_us` is the main-isolate `Writer._request<T>` reply handler wall. `rest_us = wall_us - writer_handle_us - invalidate_us - main_writer_reply_us` covers main-isolate inter-request scheduling.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/residual_writer_wall_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | writer_sqlite_us | writer_dirty_us | writer_send_us | invalidate_us | main_reply_us | completion_us | rest_us | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 33.44 | 10804 | 3291 | 455 | 0 | 553 | 0 | 18332 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 38.13 | 8575 | 2602 | 401 | 8121 | 699 | 0 | 17735 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 87.52 | 11351 | 3437 | 691 | 13964 | 942 | 39239 | 57135 | 0 | 0 | 20 |
| keyed PK subscriptions | 50 streams x 200 random writes | 21.48 | 4818 | 437 | 147 | 3550 | 556 | 7680 | 11970 | 0 | 0 | 3 |

## Derived fractions

| workload | SQLite / wall | dirty / wall | send / wall | invalidation / wall | main_reply / wall | completion / wall | rest / wall |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 32.31% | 9.84% | 1.36% | 0.00% | 1.65% | 0.00% | 54.83% |
| A11c disjoint | 22.49% | 6.82% | 1.05% | 21.30% | 1.83% | 0.00% | 46.51% |
| A11c overlap | 12.97% | 3.93% | 0.79% | 15.96% | 1.08% | 44.83% | 65.28% |
| keyed PK subscriptions | 22.43% | 2.03% | 0.68% | 16.53% | 2.59% | 35.76% | 55.73% |

## Per-write averages

| workload | writer_handle us/write | writer_dirty us/write | main_reply us/write |
|---|---:|---:|---:|
| A11c baseline | 29.10 | 6.58 | 1.11 |
| A11c disjoint | 23.16 | 5.20 | 1.40 |
| A11c overlap | 30.96 | 6.87 | 1.88 |
| keyed PK subscriptions | 27.01 | 2.19 | 2.78 |

## Reading the table

- `writer_sqlite_us` matches exp 147 — the SQLite-facing write call on the writer isolate.
- `writer_dirty_us` is the writer-isolate dirty-set harvest call (`getDirtyTableDependencies`).
- `writer_send_us` is writer-handler residual after SQLite + dirty: response construction, internal handler bookkeeping. Excludes the SendPort send itself.
- `invalidate_us` is the main-isolate `StreamEngine.onDependencyChanges` body audited by exp 121.
- `main_reply_us` is the main-isolate `Writer._request<T>` reply handler wall — port close, exception unwrap, completer.complete. The downstream `await` continuation runs in a subsequent microtask and is not counted here.
- `completion_us` is the burst-end value of exp 136 `completion_handler_us`. On A11c overlap most reader replies fire AFTER the stopwatch stops, so this captures only the reader-completion work that ran BETWEEN writes during the burst, NOT the post-burst drain. It overlaps with `rest_us` because reader replies execute inside the same main-isolate event-loop turns that the harness `await Future<void>.delayed(Duration.zero)` pairs release.
- `rest_us` is everything else inside the writer-burst wall: writer mutex acquisition, request build/serialize, the awaits in the harness loop, in-burst reader-pool completion work, and any measurement overhead.
