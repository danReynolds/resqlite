# Experiment 232: exact quarter-step REAL JSON fast path

- **Date:** 2026-07-16
- **Environment:** Apple M1 Pro, macOS 26.2, Dart 3.12.2 (`macos_arm64`)
- **Baseline:** `0ae826fe397a569e374260a80e5fa9d421bf5ff7` (`origin/main`)
- **Candidate:** `exp-232-dyadic-real-fastpath`
- **Harness:** `benchmark/experiments/select_bytes_real_int_fastpath.dart`

## Decision gate

- 10k × 8 and 10k × 20 exact quarter-step REAL lanes: at least 20%
  candidate-faster in both orderings.
- Mixed 10k × 8 lane: at least 5% candidate-faster.
- Integral-REAL and non-quarter fractional-REAL controls: individually inside
  ±3% in both selected orderings.
- Direct native differential: shipped spelling must be byte-identical to the
  historical `snprintf("%.17g")` oracle, with explicit specialization
  admission/rejection assertions.
- 1k × 2 quarter-step lane: supporting and non-regressing, not a primary gate.

## Methodology

Each lane reports the median microseconds per `selectBytes()` query across six
rounds after warmup. Both worktrees used the same harness, dependencies, SQLite
fixtures, and native build settings. Untimed setup assertions prove that:

- integral controls remain SQLite `REAL` and are exactly integral;
- target cells remain non-integral SQLite `REAL` values in `.25/.5/.75` steps;
- fallback controls remain SQLite `REAL` eighth steps that cannot enter the
  quarter specialization.

This was a heavily shared development host. A full candidate-first pass stayed
clean and supplies the first ordering. Several later full passes were invalid
because unrelated Dart/Rust/Chrome jobs started between late lanes. For the
baseline-first confirmation, the same harness was temporarily given a
lane-only switch so each baseline/candidate control was temporally adjacent;
the switch was removed before publication. Controls used short B–C–B–C or
B–C–B sequences (with one final baseline closeout), not a different workload:
row generation, warmup, iterations, and six-round median logic were unchanged.

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

The two primary quarter-step widths improve by roughly **4.5× to 7.8×** in
both orderings, far beyond the 20% gate. The mixed lane is about **2× faster**,
matching its four specialized cells. Every load-bearing control comparison is
inside ±2.7% in the reported decision pairs, and each control sequence median
is inside ±1.5%. Exp 194's integral path and the general `snprintf` fallback
therefore remain inside the preset effect floor. The small lane confirms the
fixed-cost case still benefits.

The result applies to exact `.25`, `.5`, and `.75` REAL values below the
conservative `abs(value) < 1e15` bound. It does not claim a general float
formatter win.

## Correctness and placement evidence

- Dense signed/magnitude quarter coverage plus 100k deterministic random
  quarter values matches forced `snprintf("%.17g")` byte for byte. Its path
  assertion runs the shared production dispatch implementation, so a removed
  or dead specialization cannot pass vacuously through fallback.
- Integral, non-quarter, non-finite, negative-zero, and magnitude-boundary
  values are explicitly rejected by the specialization and match the same
  oracle through the shipped formatter.
- AArch64 `-O3` assembly review found the integral per-cell predicate/encoder
  instruction-equivalent to baseline and branching before quarter admission.
  The final hybrid adds only once-per-query FP register preservation to the
  caller; ordinary fractional cells keep exactly one `snprintf` call, while
  admitted quarters alone call the out-of-line fixed-point writer.
- Strict C warning builds produced no candidate-specific warning. The portable
  `RESQLITE_NOINLINE` macro covers MSVC, GCC, and Clang spelling.

## Invalidated observations

Prototype and full-script passes taken while unrelated Fleury/Flark/Foreman
test or build jobs were active were discarded before the decision. Their
code-identical controls moved by 4–100% and sometimes changed sign. One useful
prototype finding was retained in the implementation: making every fractional
miss call an out-of-line recognizer added a plausible per-cell fallback cost,
so the final shape keeps admission inline and crosses the helper boundary only
for admitted quarters.
