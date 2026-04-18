# resqlite Hardware Benchmark Results

Community-submitted benchmark results across different hardware.

## How to Submit

1. Run the full benchmark suite:
   ```bash
   dart run benchmark/run_all.dart "your-device" --repeat=3
   ```

2. Add a new row to the table below, referencing the result file that was generated in `benchmark/results/`. Re-runs on the same hardware should be appended as additional rows (not overwrites) so the dashboard can surface a history of runs per device.

3. Submit a PR. The GitHub Action will regenerate the dashboard automatically.

## Devices

| Device | CPU | OS | Dart | Date | By | Result File |
|---|---|---|---|---|---|---|
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 2026-04-17 | @danReynolds | 2026-04-17T21-35-02-MacBook Pro 14".md |
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 2026-04-17 | @danReynolds | 2026-04-17T20-39-40-MacBook Pro 14".md |
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 2026-04-17 | @danReynolds | 2026-04-17T10-16-08-precision-fix.md |
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 2026-04-16 | @danReynolds | 2026-04-16T22-30-30-rolling-history.md |
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 2026-04-13 | @danReynolds | 2026-04-14T09-32-07-fresh-run.md |
