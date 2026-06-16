# Experiment 177 — Order-flipped A/B drift discriminator: validation aggregate

Date: 2026-06-16

This is a methodology-tooling experiment: it adds a checker, not a runtime
change, so there is no baseline/candidate wall-time A/B. The "results" are
that the checker mechanically reproduces the verdicts prior runners reached
by hand on recorded phase-ordered A/B flags.

## Tool

- `benchmark/ab_drift_check.dart` — CLI that reads two order-flipped passes
  of per-run values for each flagged scenario and classifies the flag.
- `cvPct` + `classifyDriftFlag` in `benchmark/shared/stats.dart` — the pure,
  unit-tested core.

## Recorded-flag re-classification

Input: `benchmark/ab_drift_fixtures/exp-177-recorded-flags.json`, reconstructed
to the medians and per-side CV ranges documented in the committed aggregates
(`exp-159-writer-pipelining-aggregate.md`) and rejection writeups
(`167-resultset-foreach-consumer.md`). pass1 = the standard-order pass that
flagged; pass2 = the order-flipped confirmation.

| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV | mechanism |
|---|---|---:|---:|---:|---|
| exp159 high-cardinality-fanout | drift-suspected | 19.0% | 1.0% | 23.5% | CV asymmetry |
| exp159 many-streams-writer-throughput | drift-suspected | 12.0% | 0.0% | 18.7% | CV asymmetry |
| exp167 forEach lookup | drift-suspected | -7.0% | 8.3% | 0.2% | sign reversal |

Each verdict matches the decision the original runner reached manually:

- **exp 159** flagged +19.4% / +11.9% on stream scenarios in pass 1 with
  within-run CVs of 0.20–0.46 against the clean phase's 0.01–0.06. The runner
  re-ran order-flipped, saw the flags dissolve, and accepted. The checker
  reaches `drift-suspected` on the *first* pass alone via the CV-asymmetry
  rule, and the order flip confirms it (Δ collapses to ~1% / ~0%).
- **exp 167** saw `forEach lookup` improve −7% in pair A then reverse to +8%
  in the order-flipped pair, both with tight CVs. The checker reaches
  `drift-suspected` via the sign-reversal rule.

## Self-check (built-in demo, no fixture file)

`dart run benchmark/ab_drift_check.dart --self-check --markdown`:

| scenario | verdict | pass 1 Δ | pass 2 Δ | worst flagged CV |
|---|---|---:|---:|---:|
| exp159-high-card-fanout (drift) | drift-suspected | 19.0% | 1.0% | 23.5% |
| synthetic-real-regression (reproduced) | REPRODUCED (real effect) | 12.0% | 12.0% | 0.7% |

The synthetic same-direction +12%/+12% case with comparable low CVs is the
only one that classifies as `reproduced` — the shape a real regression would
take, which the historical record (correctly) never produced for a flag that
was later dismissed as drift.

## Validation

- `dart analyze` clean on the three changed/new files.
- `dart test test/benchmark_ab_drift_check_test.dart`: 14/14 pass, covering
  `cvPct` edge cases, the three verdicts, sign reversal, CV-asymmetry
  override, and threshold tunability.
- `--fail-on-reproduced` exits 0 on the recorded-flag input (no real
  regression in the historical record) and 1 on the self-check (which
  contains a synthetic reproduced case).
