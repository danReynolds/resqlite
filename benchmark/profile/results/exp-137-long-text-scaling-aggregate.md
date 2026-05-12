# Experiment 137 - Long-Text Cell-Size Scaling Audit

Profile-mode harness: `benchmark/profile/long_text_scaling_audit.dart`

Workload shape: 8 unchanged streams x 256 rows, one fixed-row barrier stream (id = 999999, outside every unchanged stream's `id < 256` predicate), 30 timed UPDATE iterations against the barrier row per cell size after 3 warmups.

Wall convention: per-iteration `Stopwatch` brackets the UPDATE plus the wait for the barrier stream to re-emit. The unchanged streams must not emit (their hash-only fast path is supposed to suppress re-delivery); the harness asserts this on every iteration. Using UPDATE against a fixed barrier row keeps every result set at constant size across iterations, so per-iteration hashed-byte work is constant and the median is not biased toward later (heavier) iterations.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/long_text_scaling_audit.dart --markdown
```

## Wall by cell size

| cell size | median_ms | p90_ms | p99_ms | min_ms | max_ms |
|---|---:|---:|---:|---:|---:|
| 4KB | 1.35 | 1.98 | 2.66 | 1.02 | 2.66 |
| 16KB | 2.46 | 2.89 | 3.94 | 2.10 | 3.94 |
| 32KB | 5.28 | 5.60 | 5.85 | 5.00 | 5.85 |
| 64KB | 9.21 | 10.88 | 15.69 | 8.80 | 15.69 |
| 128KB | 17.40 | 18.78 | 21.98 | 16.83 | 21.98 |

## Per-byte cost

The fanout wave hashes every unchanged stream's full result (256 rows x 8 unchanged streams) plus the barrier stream's single fixed row. `hashed_bytes_per_iter = cell_bytes x (2048 + 1)`. `ns_per_byte` divides the median wall by the total hashed bytes to isolate the per-byte cost from the per-iteration overhead.

| cell size | hashed_bytes_per_iter | ns_per_byte (median) |
|---|---:|---:|
| 4KB | 8392704 | 0.160 |
| 16KB | 33570816 | 0.073 |
| 32KB | 67141632 | 0.079 |
| 64KB | 134283264 | 0.069 |
| 128KB | 268566528 | 0.065 |

## Reading the table

- `median_ms` is the per-iteration wall: one UPDATE against the fixed barrier row plus the fanout wave that re-hashes every unchanged stream's result.
- `ns_per_byte` is the per-byte cost averaged across the full hashed payload. If hashing is the bottleneck, this number stays roughly flat across cell sizes.
- Drift downward as cell sizes grow points to a per-iteration overhead floor (mutex acquisition, microtask scheduling, isolate dispatch) hiding the per-byte cost at small sizes.
- Drift upward at large sizes points to a non-hash cost emerging — allocation, GC pressure, page cache misses, or SQLite text fetch stalling on disk.

## Interpretation

See `experiments/137-long-text-cell-scaling.md` for the decision and follow-up notes attached to these numbers.
