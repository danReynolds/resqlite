# Exp 226 - one-pass numeric batch packing

Focused A/B on an Apple M1 Pro with Dart 3.12.2. Baseline was
`origin/main` at `8f6a30e`; candidate was the exact prototype archived at
`archive/exp-226` (`6349cf3`). The benchmark extension was identical in both
worktrees. Negative deltas mean candidate-faster.

## Numeric `executeBatch` wall

`dart run benchmark/experiments/batch_param_flatten.dart --warmup=8
--iterations=40|60 --cell-mode=numeric --measure=execute`

| Shape | Pass 1 baseline -> candidate | Delta | Pass 2 candidate -> baseline | Delta |
|---|---:|---:|---:|---:|
| 10k rows x 8 params | 4.517 -> 4.477 ms | -0.9% | 4.562 vs 4.854 ms | -6.0% |
| 10k rows x 20 params | 7.716 -> 7.457 ms | -3.4% | 7.710 vs 7.820 ms | -1.4% |

The 20-parameter target stays candidate-faster but below the predeclared 5%
end-to-end gate in both orderings. The 8-parameter delta changes magnitude
from below 1% to 6%, so it does not provide a stable two-lane acceptance.

## Numeric marshal-only wall

`dart run benchmark/experiments/batch_param_flatten.dart --warmup=12
--iterations=80 --cell-mode=numeric --measure=marshal`

| Shape | Pass 1 candidate -> baseline | Delta | Pass 2 baseline -> candidate | Delta |
|---|---:|---:|---:|---:|
| 10k rows x 8 params | 0.278 vs 0.386 ms | -28.0% | 0.398 -> 0.288 ms | -27.6% |
| 10k rows x 20 params | 0.672 vs 0.901 ms | -25.4% | 0.903 -> 0.670 ms | -25.8% |

Removing the sizing scan is a real encoder-local win, saving about 0.11 ms at
8 parameters and 0.23 ms at 20. That work is too small a share of the full
4.5-7.8 ms batch write to clear the public-workload gate.

## Late-payload fallback guards

The candidate speculated only when row 0 contained fixed scalars. A later
TEXT/BLOB value is legal, so the prototype discarded the fixed-width arena and
retried the unchanged generic packer.

| Shape | Pass 1 baseline -> candidate | Delta | Pass 2 candidate -> baseline | Delta |
|---|---:|---:|---:|---:|
| late TEXT, 10k x 8 | 5.271 -> 5.228 ms | -0.8% | 5.405 vs 5.299 ms | +2.0% |
| late TEXT, 10k x 20 | 8.602 -> 9.206 ms | +7.0% | 9.499 vs 9.058 ms | +4.9% |

A single baseline-first pass of the 256-byte late-BLOB guard measured 10k x 8
at 4.769 -> 5.034 ms (+5.6%) and 10k x 20 at 8.773 -> 8.651 ms (-1.4%). The
TEXT guard is the decisive result: the 4.8 MB speculative struct arena on the
20-parameter shape creates a reproduced 5-7% penalty when the final row
introduces payload.

## Verdict

Rejected. Keep the existing two-pass generic packer. The marshal-only saving
does not clear the end-to-end gate, and first-row speculation creates a
material late-payload regression. The numeric and adversarial modes remain in
the focused harness so future parameter-layout changes must show both the
isolated mechanism and the public write outcome.
