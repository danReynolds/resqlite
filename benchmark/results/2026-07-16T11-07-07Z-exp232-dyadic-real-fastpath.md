# Experiment 232: reject exact quarter-step REAL JSON fast path

- **Date:** 2026-07-16
- **Environment:** Apple M1 Pro, macOS 26.2, Dart 3.12.2 (`macos_arm64`)
- **Baseline:** `0ae826fe397a569e374260a80e5fa9d421bf5ff7` (`origin/main`)
- **Candidate:** [`archive/exp-232`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-232) (`4b972ebbe60aa3627c0bff9b238eb183f828c586`)
- **Harness:** [`archive/exp-232: benchmark/experiments/select_bytes_real_int_fastpath.dart`](https://github.com/danReynolds/resqlite/blob/archive/exp-232/benchmark/experiments/select_bytes_real_int_fastpath.dart)
- **Decision:** Rejected

## Original mechanism gate (insufficient)

- 10k × 8 and 10k × 20 exact quarter-step REAL lanes: at least 20%
  candidate-faster in both orderings.
- Mixed 10k × 8 lane: at least 5% candidate-faster.
- Integral-REAL and non-quarter fractional-REAL controls: individually inside
  ±3% in both selected orderings.
- Direct native differential: shipped spelling must be byte-identical to the
  historical `snprintf("%.17g")` oracle, with explicit specialization
  admission/rejection assertions.
- 1k × 2 quarter-step lane: supporting and non-regressing, not a primary gate.

This gate established mechanism speed and compatibility, but omitted the three
questions needed to ship a narrow hot-path specialization: representative
incidence, expected aggregate value after miss tax, and permanent complexity.

## Methodology

Each lane reports the median microseconds per `selectBytes()` query across six
rounds after warmup. Both worktrees used the same harness, dependencies, SQLite
fixtures, and native build settings. Untimed setup assertions proved that:

- integral controls remained SQLite `REAL` and exactly integral;
- target cells remained non-integral SQLite `REAL` values in `.25/.5/.75` steps;
- fallback controls remained SQLite `REAL` eighth steps that could not enter the
  quarter specialization.

This was a heavily shared development host. A full candidate-first pass stayed
clean and supplies the first ordering. Several later full passes were invalid
because unrelated Dart/Rust/Chrome jobs started between late lanes. For the
baseline-first confirmation, the same harness was temporarily given a lane-only
switch so each baseline/candidate control was temporally adjacent; the switch
was removed before publication. Controls used short B–C–B–C or B–C–B sequences
(with one final baseline closeout), not a different workload: row generation,
warmup, iterations, and six-round median logic were unchanged.

## Candidate-first full pass

| Lane | Candidate (µs/query) | Baseline (µs/query) | Δ |
|---|---:|---:|---:|
| 10k × 8 integral REAL control | 2,803 | 2,880 | -2.67% |
| 10k × 20 integral REAL control | 6,221 | 6,121 | +1.63% |
| 10k × 8 quarter-step REAL | 3,092 | 21,230 | **-85.44%** |
| 10k × 20 quarter-step REAL | 6,919 | 54,185 | **-87.23%** |
| 10k × 20 non-quarter fractional REAL control | 58,143 | 57,367 | +1.35% |
| 10k × 8 mixed (4 quarter + 2 fractional + 2 TEXT) | 8,392 | 17,817 | **-52.90%** |
| 1k × 2 quarter-step REAL | 115 | 587 | -80.41% |

## Baseline-first lane-adjacent confirmation

| Lane | Baseline (µs/query) | Candidate (µs/query) | Δ |
|---|---:|---:|---:|
| 10k × 8 integral REAL control | 2,867 | 2,878 | +0.38% |
| 10k × 20 integral REAL control | 6,513 | 6,490 | -0.35% |
| 10k × 8 quarter-step REAL | 23,167 | 5,108 | **-77.95%** |
| 10k × 20 quarter-step REAL | 52,743 | 6,952 | **-86.82%** |
| 10k × 20 non-quarter fractional REAL control | 61,850 | 63,056 | +1.95% |
| 10k × 8 mixed (4 quarter + 2 fractional + 2 TEXT) | 18,177 | 9,049 | **-50.22%** |
| 1k × 2 quarter-step REAL | 794 | 184 | -76.83% |

### Control repeat trace

For transparency, the short control sequences (B = baseline, C = candidate)
were: integral ×8 `B2936 → C2840 → B2867 → C2878`; integral ×20
`B6513 → C6490 → B6305`; and non-quarter fractional ×20
`B57969 → C59955 → B61850 → C63056 → B61106`. The reported baseline-first
pairs are temporally adjacent B→C readings. Sequence-median baseline/candidate
comparisons are also flat at -1.46%, +1.26%, and +0.65%, respectively. A few
individual transitions crossed the preset ±3% floor by at most 0.43 percentage
points, consistent with the host noise that required lane-adjacent confirmation.

## Interpretation

The formatter mechanism is real. The primary quarter-step widths improve by
roughly **4.5× to 7.8×** in both orderings, and the synthetic row with four
quarter cells out of eight is about **2× faster**. Dense signed/magnitude
coverage plus 100k deterministic random quarter values also proved byte
identity with the historical formatter.

Those lanes measure a ceiling, not product value. The target rows are 100%
eligible and the mixed row is 50% eligible, while no production trace,
representative application, or measured schema distribution established the
real eligible share. All three summaries of the non-quarter fractional control
lean candidate-slower: +1.35%, +1.95%, and +0.65% for the repeat-sequence
median. The differences are below the noise floor, but the direction is
mechanistically plausible because each miss performs extra classification.

Using the 20-column target/control deltas as a rough linear estimate, exact
quarters would need to represent about **1.6% to 2.6%** of non-integral REAL
cells merely to offset that possible miss tax. There is no evidence that they
clear that floor, nor that fractional REAL formatting contributes materially to
end-to-end application wall time.

## Correctness and implementation evidence

The archived prototype was correct and well placed:

- dense signed/magnitude quarters and 100k deterministic random quarters
  matched forced `snprintf("%.17g")` byte for byte;
- integral, non-quarter, non-finite, negative-zero, and magnitude-boundary
  values were explicitly rejected and matched the same oracle through fallback;
- AArch64 `-O3` assembly review found the integral predicate/encoder before
  quarter admission and instruction-equivalent to baseline;
- strict C warning builds produced no candidate-specific warning.

But preserving that behavior required 114 native/build-hook lines plus
quarter-specific tests and benchmark lanes: a value-lattice branch, strict
magnitude boundary, negative-subunit formatting, portable no-inline wrapper,
and two exported native test hooks, including one exposing production-path
admission.

## Decision

**Rejected.** The mechanism cleared its synthetic speed and correctness gates,
but its representative incidence and aggregate benefit were unproven, while
its maintenance surface would be permanent in the generic REAL formatter.

The runtime, native test exports, quarter-specific tests, and quarter-only
harness lanes are removed from the publication branch. The exact tested
prototype remains at `archive/exp-232`. The harness retains only a generic
untimed invariant that exp 194's integral and fractional fixtures remain SQLite
`REAL` and exercise their intended paths.

Reopen only with production/downstream or representative-application evidence
showing both that fractional REAL formatting is material and that exact quarter
steps occur often enough to produce meaningful aggregate value after miss tax.
Do not generalize this synthetic result to eighths or another value lattice.

## Invalidated observations

Prototype and full-script passes taken while unrelated Fleury/Flark/Foreman test
or build jobs were active were discarded before the decision. Their
code-identical controls moved by 4–100% and sometimes changed sign. One useful
prototype finding remains part of the record: making every fractional miss call
an out-of-line recognizer added a plausible per-cell fallback cost, so the final
prototype kept admission inline and crossed the helper boundary only for
admitted quarters.
