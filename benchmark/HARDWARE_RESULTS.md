# resqlite Hardware Benchmark Results

Community-submitted benchmark results across different hardware.

## How to Submit

1. Run the benchmark with the hardware summary flag:
   ```bash
   cd packages/resqlite
   dart run benchmark/run_all.dart "your-device" --repeat=3 --hardware-summary
   ```

2. The output includes pre-formatted rows for each table below. Copy them in and fill in your device details.

3. Submit a PR.

## Devices

| Device | CPU | OS | Dart | Date | By |
|---|---|---|---|---|---|
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 2026-04-13 | @danReynolds |

## Select → Maps (ms)

Read throughput — building Dart `Map` objects from query results.
Wall = total time, main = time on the UI isolate, worker = time offloaded to background.

| Device | Timing | 10 rows | 100 rows | 1K rows | 10K rows |
|---|---|---:|---:|---:|---:|
| MacBook Pro 14" | wall | 0.01 | 0.06 | 0.38 | 4.89 |
| MacBook Pro 14" | main | 0.00 | 0.02 | 0.10 | 0.99 |
| MacBook Pro 14" | worker | 0.01 | 0.04 | 0.28 | 3.90 |

## Select → JSON Bytes (ms)

C-native JSON serialization — entire result as a `Uint8List`, zero Dart-side allocation.
Main isolate time is near-zero regardless of result size.

| Device | Timing | 10 rows | 100 rows | 1K rows | 10K rows |
|---|---|---:|---:|---:|---:|
| MacBook Pro 14" | wall | 0.01 | 0.06 | 0.50 | 5.57 |
| MacBook Pro 14" | main | 0.00 | 0.00 | 0.00 | 0.00 |
| MacBook Pro 14" | worker | 0.01 | 0.06 | 0.50 | 5.57 |

## Point Query Throughput

Single-row lookups by primary key — measures the async dispatch latency floor.

| Device | qps |
|---|---:|
| MacBook Pro 14" | 105K |

## Batch Insert (ms)

`executeBatch()` — all rows in one transaction via a single isolate round-trip.
Main isolate just dispatches; the writer isolate does all the work.

| Device | Timing | 100 rows | 1K rows | 10K rows |
|---|---|---:|---:|---:|
| MacBook Pro 14" | wall | 0.06 | 0.45 | 4.60 |
| MacBook Pro 14" | main | 0.00 | 0.00 | 0.00 |
| MacBook Pro 14" | worker | 0.06 | 0.45 | 4.60 |

## Concurrent Reads — 1K rows per query (ms wall)

Parallel `select()` calls via `Future.wait` — shows reader pool scaling.

| Device | 1× | 2× | 4× | 8× |
|---|---:|---:|---:|---:|
| MacBook Pro 14" | 0.29 | 0.32 | 0.37 | 0.72 |

## Transaction (ms)

Interactive transaction — insert + select + conditional delete in one `transaction()` block.

| Device | mixed |
|---|---:|
| MacBook Pro 14" | 0.06 |

## Stream Reactivity (ms)

Time from write commit to stream re-emission.

| Device | invalidation | fan-out 10× |
|---|---:|---:|
| MacBook Pro 14" | 0.04 | 0.20 |
