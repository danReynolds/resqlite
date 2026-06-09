# Experiment 150 - Writer Request Residual Split Audit

Profile-mode harness: `benchmark/profile/writer_request_residual_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

`wall_ms` is writer-side write-loop wall and stops on the last write. `drain_ms` is the post-burst quiet-window drain. Writer-side counters come from the burst-end snapshot; completion counters use the post-drain snapshot because reader replies usually finish after the write burst.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_request_residual_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | drain_ms | writer_request_us | writer_handler_us | writer_sqlite_us | writer_dirty_harvest_us | writer_local_other_us | transfer_resolution_us | invalidate_us | coordination_us | completion_handler_us | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 35.14 | 0.00 | 21584 | 15529 | 11577 | 3424 | 528 | 6055 | 0 | 13559 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 39.30 | 54.02 | 18342 | 11214 | 8108 | 2626 | 480 | 7128 | 7934 | 13023 | 0 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 89.91 | 104.64 | 40808 | 16377 | 11706 | 4225 | 446 | 24431 | 13857 | 35249 | 40132 | 0 | 0 | 29 |
| keyed PK subscriptions | 50 streams x 200 random writes | 24.47 | 203.59 | 17692 | 6636 | 5771 | 692 | 173 | 11056 | 3293 | 3488 | 8941 | 0 | 0 | 3 |

## Derived fractions

| workload | request / wall | handler / wall | SQLite / wall | dirty harvest / wall | transfer+resolution / wall | invalidation / wall | coordination / wall | completion / total |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 61.42% | 44.19% | 32.94% | 9.74% | 17.23% | 0.00% | 38.58% | 0.00% |
| A11c disjoint | 46.67% | 28.54% | 20.63% | 6.68% | 18.14% | 20.19% | 33.14% | 0.00% |
| A11c overlap | 45.39% | 18.21% | 13.02% | 4.70% | 27.17% | 15.41% | 39.20% | 20.63% |
| keyed PK subscriptions | 72.29% | 27.12% | 23.58% | 2.83% | 45.18% | 13.46% | 14.25% | 3.92% |

## Per-event costs

| workload | request_us/op | handler_us/op | dirty_harvest_us/op | completion_us/callback |
|---|---:|---:|---:|---:|
| A11c baseline | 43.17 | 31.06 | 6.85 | 0.00 |
| A11c disjoint | 36.68 | 22.43 | 5.25 | 0.00 |
| A11c overlap | 81.62 | 32.75 | 8.45 | 10.54 |
| keyed PK subscriptions | 88.46 | 33.18 | 3.46 | 7.91 |

## Reading the table

- `writer_request_us` is the main-isolate round trip to the writer isolate. It includes writer queueing, request transfer, handler work, reply transfer, and main-isolate response scheduling.
- `writer_handler_us` is writer-isolate active work before the response is sent. `writer_local_other_us` is handler work that is neither SQLite nor dirty harvest.
- `transfer_resolution_us = writer_request_us - writer_handler_us`; it contains message transfer, reply send/copy, writer queue wait, and main-isolate request resolution.
- `coordination_us = wall_us - writer_request_us - invalidate_us`; on A11c this includes the deliberate microtask yields between writes and any other write-loop scheduling outside the writer request and synchronous invalidation body.
