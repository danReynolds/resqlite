# Exp 246 — slot-count vs byte-count sacrifice trigger (A/B)

Harness: `benchmark/experiments/slot_sacrifice_ab.dart` (temporary A/B scaffolding,
removed on landing together with the byte machinery it toggled — see
`experiments/246-slot-sacrifice-guard.md`). Apple M1 Pro.
End-to-end `select`, median µs over 9×200 iters, sacrifices/select from
`ReaderPool.debugSacrificeCount`. Lanes: default (slot trigger), and
`-DRESQLITE_SLOT_TRIGGER=false` (legacy byte trigger). Slot threshold via
`-DRESQLITE_SLOT_THRESHOLD` (default 32768).

| shape | slots | ~bytes | bytes µs | bytes sac | slot@48k µs | slot@48k sac | slot@32k µs | slot@32k sac |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| bigstr | 4 | 400 KB | 131.0 | 1.00 | 91.1 | 0.00 | 90.9 | 0.00 |
| band | 40k | 320 KB | 1462.3 | 1.00 | 1640.2 | 0.00 | 1472.5 | 1.00 |
| large | 200k | 1.6 MB | 6328.3 | 1.00 | 6196.4 | 1.00 | 6127.6 | 1.00 |
| medium | 20k | 160 KB | 800.3 | 0.00 | 804.6 | 0.00 | 785.1 | 0.00 |
| small | 400 | small | 17.6 | 0.00 | 18.5 | 0.00 | 16.4 | 0.00 |

Reading:
- bigstr (misroute): slot trigger stops sacrificing (1.00 → 0.00) and is ~31%
  faster (131 → 91 µs). This is the win.
- band (40k slots): at the 48k intrinsic threshold it sends and regresses +12%
  (1462 → 1640); at 32k it sacrifices like the byte trigger — parity. End-to-end
  crossover is below the intrinsic 48k because the send copy is on the worker's
  critical path (exp 244).
- large/medium/small: parity in both routing and latency.

Chosen threshold: 32768 slots (= 256 KB / 8 bytes-per-cell). See
`experiments/246-slot-sacrifice-guard.md`.
