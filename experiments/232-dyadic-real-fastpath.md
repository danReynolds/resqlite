# Experiment 232: Reject exact quarter-step REAL JSON fast path

**Date:** 2026-07-16
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  The exact tested harness and runtime are preserved at
  [`archive/exp-232`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-232),
  with order-flipped measurements recorded in
  [`benchmark/results/2026-07-16T11-07-07Z-exp232-dyadic-real-fastpath.md`](../benchmark/results/2026-07-16T11-07-07Z-exp232-dyadic-real-fastpath.md).
  No release-suite run was used because no release lane isolates exact
  quarter-step REAL formatting.
**Archive:** [`archive/exp-232`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-232)

## Problem

[Exp 194](194-real-integer-fastpath.md) removed `snprintf("%.17g")` from
`selectBytes()` for REAL cells that are exactly integral. Its future note was
deliberately stricter about fractional work: pursue another specialization only
if a real production profile shows fractional REAL formatting dominates.

This run skipped that prerequisite. It reasoned that exact `.25`, `.5`, and
`.75` values occur in domains such as ratings and prices, then moved directly
to an all-quarter focused benchmark. That made the mechanism easy to isolate,
but it did not establish how often the value lattice occurs in representative
`selectBytes()` traffic.

## Hypothesis

For a finite, non-integral REAL value with `abs(value) < 1e15`, if `value * 4`
is exactly integral and not divisible by four, the historical
`snprintf("%.17g")` spelling can be emitted by reusing the native i64 formatter
and appending `.25`, `.5`, or `.75`.

The original acceptance gate required at least 20% improvement on synthetic
10k × 8 and 10k × 20 quarter-step lanes in both orderings, at least 5% on a
synthetic 50%-quarter mixed row, and integral/general-fractional controls inside
±3%. That gate could prove a fast formatter. It was insufficient to prove that
permanent specialization of the generic REAL path was worth shipping because
it omitted activation prevalence, expected aggregate impact, and a persistent
complexity budget.

## Approach

The archived prototype placed exp 194's zero and exact-integral checks first,
then:

1. multiplied other REAL values by four and admitted exact non-integral quarter
   units inside a strict `abs(value) < 1e15` bound;
2. called an out-of-line fixed-point writer that reused the i64 formatter and
   appended the exact suffix;
3. sent every miss to the historical `snprintf("%.17g")` fallback.

Correctness required special handling for negative sub-unit values, the strict
magnitude boundary, a portable no-inline wrapper, and two exported native test
hooks, including one exposing production-path admission. The candidate added
114 lines across `native/` and the build hook, plus quarter-specific tests and
benchmark lanes. The behavior was byte-identical, but the maintenance surface
was permanent and every non-integral REAL miss still evaluated the new
recognizer.

The focused harness used 100%-quarter target lanes and a mixed row with four
quarter cells out of eight. Those rows measure the ceiling cleanly; they are not
representative-incidence evidence. During final review, the candidate was
reassessed against the product-value question rather than only its preset
mechanism gate.

## Results

Medians in microseconds per query; full raw tables and shared-host control
traces are in the linked result file.

| Lane | Candidate-first Δ | Baseline-first Δ | Read |
|---|---:|---:|---|
| 10k × 8 integral REAL control | -2.67% | +0.38% | neutral/mixed |
| 10k × 20 integral REAL control | +1.63% | -0.35% | neutral/mixed |
| 10k × 8 quarter-step REAL | **-85.44%** | **-77.95%** | mechanism reproduced |
| 10k × 20 quarter-step REAL | **-87.23%** | **-86.82%** | mechanism reproduced |
| 10k × 20 non-quarter fractional REAL | +1.35% | +1.95% | miss path leans slower |
| 10k × 8 synthetic 50%-quarter mixed | **-52.90%** | **-50.22%** | expected synthetic mix |
| 1k × 2 quarter-step REAL | -80.41% | -76.83% | supporting mechanism win |

The quarter formatter itself is roughly **4.5× to 7.8× faster**. Correctness
coverage also proved exact byte identity across dense signed quarters,
bound-adjacent magnitudes, and 100k deterministic random quarter values.

That is not the same as product value. All three summaries of the non-quarter
fractional control lean candidate-slower: +1.35%, +1.95%, and +0.65% for the
repeat-sequence median. They remain below the noise floor, but the direction is
mechanistically plausible because every miss performs extra classification.
Using the 20-column target/control deltas as a rough linear estimate, exact
quarters would need to comprise about **1.6% to 2.6%** of non-integral REAL
cells merely to offset that miss tax. No production or representative
distribution established even that incidence, and no evidence showed
fractional REAL formatting materially affects end-to-end application wall time.

## Decision

**Rejected.** Keep exp 194's exact-integral specialization and remove the
quarter-step runtime path.

The mechanism cleared its synthetic speed and correctness gates, but the run
did not prove a common workload, representative activation rate, or aggregate
user benefit large enough to repay a value-specific branch in the generic REAL
formatter. The exact candidate is preserved at `archive/exp-232`; runtime,
quarter-specific test exports, and quarter-only harness lanes are removed from
the publication branch. The only retained harness change is a generic untimed
assertion that exp 194's integral and fractional fixtures remain SQLite `REAL`
and exercise their intended formatter paths.

Reopen only with a production/downstream trace or representative application
showing both that fractional REAL formatting is material and that exact quarter
steps occur often enough to produce a meaningful aggregate win. A smaller
implementation or a broad fractional mechanism would lower the evidence burden.
Do not generalize this result to eighths or another synthetic value lattice.

## Selection lesson

The failure happened before benchmarking: the runner optimized an easy-to-test
subdomain without first ranking its expected product value against other live
directions. The exploit-selection rubric now requires representative incidence,
expected aggregate value after miss tax, an explicit persistent-complexity
budget, and a cross-direction shortlist. Moonshots may still probe meaningful
ceilings, but a narrow runtime result needs the product-value evidence before it
ships. Synthetic 100%-eligible lanes are mechanism evidence only.

## Validation

- Archived prototype: strict Clang C11 warning build, full analysis, direct
  native differential 9/9, selectBytes 9/9, benchmark pipeline 20/20, and full
  serial suite 328/328.
- Final publication branch: runtime and quarter-specific test/harness changes
  removed; generic REAL fixture invariant retained and exercised by the focused
  harness.
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/232-dyadic-real-fastpath.md`.
- `dart run benchmark/check_experiment_dispositions.dart`.
- `dart analyze --fatal-infos`.
- `dart test test/benchmark_pipeline_test.dart`.
- Direct native differential 7/7 and full serial suite 326/326.
- JSON validation and `git diff --check`.
