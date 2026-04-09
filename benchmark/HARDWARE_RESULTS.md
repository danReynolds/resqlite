# resqlite Hardware Benchmark Results

Community-submitted benchmark results across different hardware.

## How to Submit

1. Run the benchmark with the hardware summary flag:
   ```bash
   cd packages/resqlite
   dart run benchmark/run_all.dart "your-device" --repeat=3 --hardware-summary
   ```

2. The output includes a pre-formatted table row. Copy it and add it below.

3. Submit a PR.

## What's Measured

| Category | What it tests |
|---|---|
| **select 1K rows** | Read throughput — building Dart objects from 1,000 rows |
| **selectBytes 1K rows** | JSON serialization — C-native JSON for 1,000 rows |
| **Point query qps** | Latency floor — single-row lookups per second |
| **Batch insert 1K** | Write throughput — 1,000 rows in one transaction |
| **Stream invalidation** | Reactivity — time from write commit to stream re-emission |

These cover the five performance dimensions that matter for real apps: read throughput, serialization, point query latency, write throughput, and reactive responsiveness.

## Results

| Device | CPU | OS | Dart | select 1K | bytes 1K | Point qps | Batch 1K | Stream inv. | Date | By |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 0.43ms | 0.62ms | 68K | 0.80ms | 0.11ms | 2026-04-09 | @danReynolds |
