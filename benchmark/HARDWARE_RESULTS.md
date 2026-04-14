# resqlite Hardware Benchmark Results

Community-submitted benchmark results across different hardware.

## How to Submit

1. Run the full benchmark suite:
   ```bash
   dart run benchmark/run_all.dart "your-device" --repeat=3
   ```

2. Add your device to the table below, referencing the result file that was generated in `benchmark/results/`.

3. Submit a PR. The GitHub Action will regenerate the dashboard automatically.

## Devices

| Device | CPU | OS | Dart | Date | By | Result File |
|---|---|---|---|---|---|---|
| MacBook Pro 14" | M1 Pro 10c | macOS 26.2 | 3.11 | 2026-04-13 | @danReynolds | 2026-04-14T09-32-07-fresh-run.md |
