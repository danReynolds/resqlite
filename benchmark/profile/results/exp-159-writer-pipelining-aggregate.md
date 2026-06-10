# Experiment 150 — Writer pipelining + persistent reply port: profile aggregate

Date: 2026-06-09

Harnesses:

- `benchmark/profile/writer_sqlite_wall_audit.dart` (exp 147 harness),
  single pass per side, run back-to-back baseline → candidate with the
  machine otherwise idle. `dart run -DRESQLITE_PROFILE=true ... --markdown`.
- `benchmark/experiments/writer_pipelining.dart` (new focused benchmark),
  7 rounds per shape, medians reported; two full passes per side.
- `benchmark/run_tracelite_experiment.dart --direction=stream-rerun-dispatch`,
  two passes (standard order, then order-flipped).

## Writer wall split audit (single pass per side)

Baseline (main @ 841e362):

| workload | wall_ms | writer_sqlite_us | invalidate_us | residual_us |
|---|---:|---:|---:|---:|
| A11c baseline (0 streams x 500 writes) | 96.39 | 25,659 | 0 | 70,729 |
| A11c disjoint (50 streams x 500 writes) | 100.98 | 18,478 | 26,315 | 56,185 |
| A11c overlap (50 streams x 500 writes) | 202.47 | 25,177 | 33,766 | 143,527 |
| keyed PK subscriptions (50 streams x 200 writes) | 45.83 | 10,176 | 7,358 | 28,296 |

Candidate (exp-150):

| workload | wall_ms | writer_sqlite_us | invalidate_us | residual_us |
|---|---:|---:|---:|---:|
| A11c baseline (0 streams x 500 writes) | 78.18 | 22,794 | 0 | 55,385 |
| A11c disjoint (50 streams x 500 writes) | 83.77 | 17,615 | 20,424 | 45,729 |
| A11c overlap (50 streams x 500 writes) | 192.10 | 20,309 | 32,238 | 139,549 |
| keyed PK subscriptions (50 streams x 200 writes) | 39.14 | 8,803 | 7,758 | 22,583 |

`residual_us` (wall − writer_sqlite − invalidate, the exp 147 bucket this
experiment targets) drops on every workload; largest relative drop on the
0-stream pure round-trip shape (−22%). Single-pass — direction signal,
not an acceptance gate.

## Focused benchmark (7 rounds, medians, two passes per side)

| shape | baseline | candidate | delta |
|---|---:|---:|---:|
| concurrent-burst 10×200, pass 1 | 113.2 ms | 72.6 ms | −36% |
| concurrent-burst 10×200, pass 2 | 100.5 ms | 55.3 ms | −45% |
| sequential-awaited 2000, pass 1 | 77.1 ms | 98.3 ms | noisy (contaminated rounds) |
| sequential-awaited 2000, pass 2 | 72.7 ms | 74.5 ms | neutral |
| transaction-guardrail 50×10, pass 2 | 13.0 ms | 12.2 ms | neutral |

## Tracelite decision summary

Pass 1 (baseline phase first, candidate phase second; candidate phase
contaminated — within-run CVs 0.20–0.46 vs 0.01–0.06):

| scenario | delta | 95% CI | status |
|---|---:|---|---|
| high-cardinality-fanout | +19.4% | 21.0..122 ms | neutral (flagged) |
| many-streams-writer-throughput | +11.9% | 22.1..120 ms | neutral (flagged) |
| keyed-pk-subscriptions | +19.5% | −23.2..160 ms | too_noisy |

Pass 2 (order flipped: exp-159 collected first; CVs 0.01–0.03):

| scenario | delta (main vs exp-150) | 95% CI | status |
|---|---:|---|---|
| high-cardinality-fanout | +1.02% | −1.73..9.11 ms | neutral |
| many-streams-writer-throughput | −0.26% | −12.9..9.89 ms | neutral |
| keyed-pk-subscriptions | +4.00% | −9.88..34.5 ms | neutral |

The pass-1 flags did not reproduce with collection order flipped; the
clean pass shows all guardrail scenarios neutral. Raw per-run JSONs and
tracelite artifacts are local-only under `build/tracelite-experiments/`.
