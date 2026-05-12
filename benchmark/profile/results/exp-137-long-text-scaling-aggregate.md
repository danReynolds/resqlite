# Experiment 137 - Long-Text Cell-Size Scaling Audit

Profile-mode harness: `benchmark/profile/long_text_scaling_audit.dart`

Workload shape: 8 unchanged streams x 256 rows, one barrier stream, 30 timed INSERT iterations per cell size after 3 warmups.

Wall convention: per-iteration `Stopwatch` brackets the INSERT plus the wait for the barrier stream to re-emit. The unchanged streams must not emit (their hash-only fast path is supposed to suppress re-delivery); the harness asserts this on every iteration. The hash-loop work the unchanged streams do during each iteration is the cost the scaling sweep is targeting.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/long_text_scaling_audit.dart --markdown
```

## Wall by cell size

| cell size | median_ms | p90_ms | p99_ms | min_ms | max_ms |
|---|---:|---:|---:|---:|---:|
| 4KB | 2.11 | 3.09 | 3.23 | 1.82 | 3.23 |
| 16KB | 4.50 | 5.53 | 6.98 | 4.00 | 6.98 |
| 32KB | 9.49 | 10.67 | 12.87 | 8.40 | 12.87 |
| 64KB | 27.52 | 33.72 | 34.72 | 16.01 | 34.72 |
| 128KB | 44.51 | 53.92 | 55.84 | 35.07 | 55.84 |

## Per-byte cost

The fanout wave hashes every unchanged stream's full result (256 rows x 8 unchanged streams) plus the barrier stream's full result (257 rows after the INSERT lands). `hashed_bytes_per_iter ≈ cell_bytes x (2048 + 257)`. `ns_per_byte` divides the median wall by the total hashed bytes to isolate the per-byte cost from the per-iteration overhead.

| cell size | hashed_bytes_per_iter | ns_per_byte (median) |
|---|---:|---:|
| 4KB | 9441280 | 0.224 |
| 16KB | 37765120 | 0.119 |
| 32KB | 75530240 | 0.126 |
| 64KB | 151060480 | 0.182 |
| 128KB | 302120960 | 0.147 |

## Reading the table

- `median_ms` is the per-iteration wall: one INSERT plus the fanout wave that re-hashes every unchanged stream's result.
- `ns_per_byte` is the per-byte cost averaged across the full hashed payload. If hashing is the bottleneck, this number stays roughly flat across cell sizes.
- Drift downward as cell sizes grow points to a per-iteration overhead floor (mutex acquisition, microtask scheduling, isolate dispatch) hiding the per-byte cost at small sizes.
- Drift upward at large sizes points to a non-hash cost emerging — allocation, GC pressure, page cache misses, or SQLite text fetch stalling on disk.

## Interpretation

See `experiments/137-long-text-cell-scaling.md` for the decision and follow-up notes attached to these numbers.
