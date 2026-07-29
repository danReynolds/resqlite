# Exp 256 — stale-then-correct vs suppress-stale initial emission

Harness: `benchmark/experiments/stream_initial_emission_ab.dart`. Apple M1 Pro.
Stream opened over a seeded table; 8 inserts fired without awaiting the first
emission so they race the initial query. 12 samples per shape after 3 warmup
observations. Lane A reproduced by replacing the poisoned-baseline branch in
`StreamEngine._createStream` with a plain `entry.emit(initialRows)`.

| lane | shape | first emit ms | correct ms (p50/p90) | emissions | stale frames |
|---|---|---:|---:|---:|---:|
| A emit-then-correct | racing · 1k | 0.3 | 0.9 / 2.0 | 2.08 | 1.08 |
| A emit-then-correct | racing · 20k | 3.1 | 8.1 / 10.0 | 2.00 | 1.00 |
| A emit-then-correct | racing · 60k | 8.1 | 18.5 / 22.9 | 2.00 | 1.00 |
| A emit-then-correct | no race · 20k (control) | 3.4 | 13.3 / 15.1 | 2.00 | 1.00 |
| B suppress-stale | racing · 1k | 0.9 | 1.1 / 2.5 | 1.42 | 0.42 |
| B suppress-stale | racing · 20k | 9.5 | 9.5 / 15.8 | 1.00 | 0.00 |
| B suppress-stale | racing · 60k | 18.9 | 18.9 / 21.4 | 1.00 | 0.00 |
| B suppress-stale | no race · 20k (control) | 2.9 | 13.3 / 19.4 | 2.00 | 1.00 |

B shipped: ~1 ms of time-to-correct-value buys the removal of every stale
frame, and the unraced control is identical. See
`experiments/256-stale-initial-emission-tradeoff.md`.
