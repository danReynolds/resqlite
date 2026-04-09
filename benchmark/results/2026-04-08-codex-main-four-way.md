# resqlite Main-Only Four-Way Benchmark

Generated from the `main` branch on 2026-04-08.

Inputs:

- [`packages/resqlite/benchmark/head_to_head_worker.dart`](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/head_to_head_worker.dart)
- [`packages/sqlite_reactive_verifier/bin/sqlite_reactive_benchmark.dart`](/Users/dan/Coding/dune_gemini/packages/sqlite_reactive_verifier/bin/sqlite_reactive_benchmark.dart)

Artifacts:

- `/tmp/resqlite_main_h2h.json`
- `/tmp/resqlite_main_rebench_core.json`
- `/tmp/resqlite_main_rebench_reactive.json`

## Results

| Case | Metric | resqlite | sqlite_reactive | sqlite_async | sqlite3 | Winner |
|---|---|---:|---:|---:|---:|---|
| `open_only` | `p50_ms` | 1.26 | 3.69 | 1.46 | 0.46 | `sqlite3` |
| `cold_open` | `p50_ms` | 1.56 | 7.73 | 6.22 | 4.10 | `resqlite` |
| `single_row_crud` | `ops/s` | 22,127 | 6,811 | 4,976 | 29,887 | `sqlite3` |
| `batch_write_transaction` | `rows/s` | 347,947 | 255,624 | 275,103 | 296,121 | `resqlite` |
| `read_under_write` | `mean_ms` | 0.31 | 0.50 | 0.98 | 0.56 | `resqlite` |
| `stream_invalidation_latency` | `mean_ms` | 0.13 | 0.91 | 0.77 | N/A | `resqlite` |
| `burst_coalescing` | `emissions_after_burst` | 1 | 1 | 1 | N/A | tie |
| `burst_coalescing` | `time_to_quiet_ms` | 219.81 | 224.53 | 227.07 | N/A | `resqlite` |
| `reactive_fanout_shared_query` | `fanout_ms` | 0.50 | 0.83 | 4.26 | N/A | `resqlite` |
| `reactive_fanout_unique_queries` | `fanout_ms` | N/A | 3.54 | 7.83 | N/A | `sqlite_reactive` |
| `large_result_read` | `mean_ms` | 2.61 | 2.54 | 5.75 | 5.70 | `sqlite_reactive` |
| `large_result_read_large` | `mean_ms` | 8.64 | 29.02 | 37.80 | 40.74 | `resqlite` |
| `repeated_point_query` | `qps` | 53,622 | 33,796 | 18,154 | 105,619 | `sqlite3` |

## Notes

- This is a true `main` baseline: no benchmark worktree code was used.
- `resqlite` was run in its own process to avoid native SQLite symbol conflicts with `sqlite_reactive`.
- The `resqlite` worker and the verifier use different harness implementations, so this is a directional comparison, not one fully unified runner.
- `resqlite` currently times out on `reactive_fanout_unique_queries` in this checked-in worker, so that row is intentionally `N/A`.
