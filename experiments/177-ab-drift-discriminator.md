# Experiment 177: Order-flipped A/B drift discriminator

**Date:** 2026-06-16
**Status:** In Review
**Direction:** `measurement-system`
**Benchmark Run:** none (methodology tooling; validation aggregate at `benchmark/profile/results/exp-177-ab-drift-check-aggregate.md`)

## Problem

The single most-reapplied lesson in [`JOURNAL.md`](JOURNAL.md) is "Phase-ordered
A/B gates confound code deltas with time-correlated drift." The Tracelite
experiment wrapper (and any baseline-then-candidate harness) collects all
baseline runs, then all candidate runs, in disjoint time blocks. When the
machine drifts during one block, the regression flag lands entirely on one
side. The documented remedy is a two-step manual check:

1. Compare the **flagged phase's within-run CV** against the clean phase's CV
   — exp 159 saw 0.20–0.46 on the contaminated phase vs 0.01–0.06 on the clean
   one.
2. **Re-run with the collection order flipped** and see whether the flag
   reproduces — exp 144's two-independent-passes rule, sharpened by exp 159 to
   "flip the order so drift has to indict the opposite side."

Every recent A/B writeup performs both steps by hand:
`exp-159-writer-pipelining-aggregate.md` ("CVs 0.20–0.46 vs 0.01–0.06" then
"order flipped … did not reproduce"), `167-resultset-foreach-consumer.md`
("order-flipped confirmation reversed the target row"),
`171-resolved-runtime-cache.md` ("two order-flipped passes … alternating-sign
deltas"), `173-long-text-32kb-hash.md` ("Pair 2 — baseline first (order flipped
per JOURNAL.md)"). The reasoning is identical each time and is reconstructed
from memory each time. Nothing in the harness encodes it, so a future runner
can forget the CV check, or read "the flag did not reproduce" inconsistently.

## Hypothesis

The CV-asymmetry + order-flip reasoning is a small, deterministic rule. Encoding
it as a checker — `cvPct` plus a `classifyDriftFlag` classifier over two
order-flipped passes — makes the call reproducible instead of eyeballed, lets
future runners cite a verdict instead of re-deriving it, and provides an
optional gate (`--fail-on-reproduced`) for harnesses that want to assert a flag
is *not* a real regression. If the rule is right, running it on the recorded
flags from prior experiments should reproduce the verdicts those runners
reached by hand.

This is methodology infrastructure, the same class as
[exp 161](161-concurrent-writes-release-coverage.md) (release coverage) and
[exp 169](169-tracelite-workload-insights.md) (insight guard): it changes no
runtime code and is not part of the release suite. Under the runner
instructions' paired-run rule it is not a "measurement that unlocks an
implementation" — it is a reusable guardrail whose deliverable is the guardrail
itself, so the "carry the implementation it unlocks" requirement does not apply
(the same exemption exp 161 and exp 169 used).

## Approach

Two pieces, both touching only `benchmark/` and `test/`:

- **`benchmark/shared/stats.dart`** gains a pure, unit-tested core:
  - `cvPct(samples)` — population coefficient of variation as a percent,
    matching the CV figures recorded in prior `*-aggregate.md` files.
  - `AbPass` — one pass's baseline/candidate per-run values, exposing
    `deltaPct` (candidate-vs-baseline median delta) and `flaggedSideCvPct`
    (the CV of whichever side carries the regression, the phase the JOURNAL
    lesson says to inspect first).
  - `classifyDriftFlag(pass1, pass2, thresholds)` -> `DriftClassification`
    with a `DriftVerdict` of `reproduced` / `driftSuspected` / `inconclusive`.
    The rule, in order: (1) if either pass's flagged side is far noisier than
    its clean side (CV ratio ≥ 4× and above an 8% clean floor), it is
    `driftSuspected` — the exp 159 signature; (2) else if the two passes
    disagree on sign with both effects above a 3% floor, the flag reversed on
    the flip — `driftSuspected` (exp 167); (3) else if both passes show a
    same-direction effect above the floor, `reproduced`; (4) otherwise
    `inconclusive` (read as neutral). All three thresholds are tunable.
- **`benchmark/ab_drift_check.dart`** — a thin CLI over the core. Reads a small
  JSON file (`{"scenarios":[{label, pass1:{baseline,candidate},
  pass2:{...}}]}`), emits a text or `--markdown` table, supports `--self-check`
  (built-in demo, no fixture needed), and `--fail-on-reproduced` to exit 1 when
  any scenario classifies as a real effect.

## Results

The checker reproduces, by rule, the verdicts prior runners reached by hand.
Input `benchmark/ab_drift_fixtures/exp-177-recorded-flags.json` reconstructs the
medians and per-side CV ranges documented in those committed aggregates;
pass1 = the standard-order pass that flagged, pass2 = the order-flipped
confirmation.

| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV | mechanism |
|---|---|---:|---:|---:|---|
| exp159 high-cardinality-fanout | drift-suspected | 19.0% | 1.0% | 23.5% | CV asymmetry |
| exp159 many-streams-writer-throughput | drift-suspected | 12.0% | 0.0% | 18.7% | CV asymmetry |
| exp167 forEach lookup | drift-suspected | −7.0% | 8.3% | 0.2% | sign reversal |

- exp 159's two stream flags resolve to `drift-suspected` via the CV-asymmetry
  rule — the checker reaches the verdict on the *first* pass alone, and the
  order flip confirms it (Δ collapses to ~1% / ~0%). That matches the runner's
  accept decision.
- exp 167's `forEach lookup` resolves to `drift-suspected` via the
  sign-reversal rule (−7% then +8% with tight CVs) — matching the runner's
  "reversed on the confirmation pair, rejected" decision.

The built-in `--self-check` adds a synthetic same-direction +12%/+12% case with
comparable low CVs, the only one that classifies `reproduced` — the shape a
real regression takes, which the historical flag record (correctly) never
produced for a flag later dismissed as drift.

Validation:

| check | result |
|---|---|
| `dart analyze` (3 changed/new files) | clean |
| `dart test test/benchmark_ab_drift_check_test.dart` | 14/14 pass |
| `--fail-on-reproduced` on recorded flags | exit 0 (none reproduced) |
| `--fail-on-reproduced` on `--self-check` | exit 1 (one reproduced) |

## Decision

Accepted as methodology tooling. It is permanent profiling/methodology code by
the runner-instructions bar: it will be reused by every future order-flipped
A/B (the dominant evaluation pattern in this repo's recent history) and it
replaces a manual, memory-dependent step with a deterministic, tested one. No
runtime behavior changes; the release suite is untouched.

## Future Notes

- The classifier consumes the per-run values an A/B already produces; the next
  natural step is to have `decide_tracelite.dart` / `run_tracelite_experiment.dart`
  emit those per-run arrays for flagged scenarios in a shape this tool reads
  directly, so the drift check becomes a single command after a flagged pass
  rather than a hand-built fixture. That wiring depends on the upstream
  tracelite decision JSON exposing per-run samples, so it is left as a
  follow-up rather than bundled here.
- Thresholds (CV-asymmetry ratio 4×, clean-CV floor 8%, effect floor 3%) are
  defaults derived from exp 144/159/167/171/173; if a future workload has a
  naturally higher noise floor, pass `--cv-asymmetry-ratio` /
  `--clean-cv-pct` / `--effect-floor-pct` rather than editing the defaults.
- This does not replace running the order-flipped second pass — it interprets
  it. A single pass can only ever reach `driftSuspected` (via CV asymmetry) or
  be left to the runner; `reproduced` requires both passes to agree.
