# Experiment 232: Exact quarter-step REAL JSON fast path

**Date:** 2026-07-16
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_real_int_fastpath.dart`](../benchmark/experiments/select_bytes_real_int_fastpath.dart);
  order-flipped measurements recorded in
  [`benchmark/results/2026-07-16T11-07-07Z-exp232-dyadic-real-fastpath.md`](../benchmark/results/2026-07-16T11-07-07Z-exp232-dyadic-real-fastpath.md).
  No release-suite run because the focused harness directly isolates
  quarter-step REAL formatting, integral/fractional guards, mixed rows, and the
  small fixed-cost case.

## Problem

[Exp 194](194-real-integer-fastpath.md) removed `snprintf("%.17g")` from
`selectBytes()` for REAL cells that are exactly integral, producing roughly
5× faster integral-REAL encoding while leaving genuine fractionals on the
general formatter. Its future note explicitly allowed a much smaller
fractional specialization than the broad Ryu/Grisu formatter rejected by
[exp 041](041-ryu-double-to-string.md), provided a focused workload and exact
compatibility gate justified it.

The narrowest useful next domain is exact quarter steps: `.25`, `.5`, and
`.75`. They are common in ratings, prices, percentages, and bucketed metrics;
binary doubles represent them exactly; multiplying by four produces an exact
integer; and their canonical `%.17g` spelling is a whole-number prefix plus one
of three fixed suffixes. Paying a general decimal formatter per cell removes
work that this bounded domain does not need.

This Thursday run is an **exploit** pass: a contained extension of exp 194's
known REAL-cell hot path, not a retry of exp 041's general formatter.

## Hypothesis

For a finite, non-integral REAL value with `abs(value) < 1e15`, if `value * 4`
is exactly integral and not divisible by four, the historical
`snprintf("%.17g")` output can be emitted byte-identically by reusing the native
i64 formatter for the whole part and appending `.25`, `.5`, or `.75`.

Accept only if both 10k × 8 and 10k × 20 quarter-step lanes improve at least
20% in both orderings, mixed rows improve at least 5%, and every integral plus
general-fractional control stays inside ±3%. The shipped and forced-historical
formatters must also agree byte for byte, with tests proving intended values
are admitted and fallback values are rejected.

## Approach

The native REAL formatter now performs three ordered decisions:

1. Exp 194's zero and exact-integral checks run first and are unchanged.
2. `resqlite_json_quarter_units` admits only finite values strictly inside
   `[-1e15, 1e15]` whose four-times-scaled value converts exactly to
   `long long` and has a non-zero remainder modulo four.
3. Admitted values call the out-of-line `resqlite_json_write_quarter`, which
   formats the whole part with `resqlite_json_i64_to_str` and appends the exact
   suffix. Every miss falls directly through to the historical
   `snprintf("%.17g")` call.

The strict magnitude bound keeps the scaled cast far inside `long long` and
keeps fixed notation at no more than 17 significant digits. Negative sub-unit
values receive an explicit `-0` prefix because C integer division truncates
toward zero. The specialization shares the formatter's existing C-locale
assumption; no public API or JSON framing changes.

Admission is inline but spelling is out of line. That placement was selected
after prototyping: calling an out-of-line recognizer on every fractional miss
made fallback overhead plausible, while fully inlining the spelling body
unnecessarily reshaped the caller. In the kept hybrid, exp 194's integral
per-cell instructions branch before admission, ordinary fractionals retain one
`snprintf` call, and only admitted quarters cross the helper boundary. A new
portable `RESQLITE_NOINLINE` macro uses `__declspec(noinline)` on MSVC and the
GCC/Clang attribute elsewhere.

The existing REAL focused harness now includes quarter-step ×8/×20 lanes, a
mixed lane, and a small confirmation lane. Untimed SQL invariants prove every
integral, target, and fallback fixture retains the intended SQLite `REAL`
storage class and exact numeric subdomain before timing. The native differential
test exposes both the shipped formatter and forced `snprintf` oracle. Its path
diagnostic runs the shared production dispatch implementation, while production
passes a null diagnostic pointer that compiles away.

## Results

Medians in microseconds per query; full raw tables and the shared-host
lane-adjacent methodology are in the linked result file.

| Lane | Candidate-first Δ | Baseline-first Δ | Verdict |
|---|---:|---:|---|
| 10k × 8 integral REAL control | -2.67% | +0.38% | inside ±3% |
| 10k × 20 integral REAL control | +1.63% | -0.35% | inside ±3% |
| 10k × 8 quarter-step REAL | **-85.44%** | **-77.95%** | primary gate passed |
| 10k × 20 quarter-step REAL | **-87.23%** | **-86.82%** | primary gate passed |
| 10k × 20 non-quarter fractional REAL control | +1.35% | +1.95% | inside ±3% |
| 10k × 8 mixed | **-52.90%** | **-50.22%** | confirmation passed |
| 1k × 2 quarter-step REAL | -80.41% | -76.83% | supporting win |

Quarter-heavy REAL encoding is roughly **4.5× to 7.8× faster** at the primary
widths. The mixed rowset is about **2× faster**, moving in proportion to its
four specialized cells. Integral and genuine-fractional controls stay inside
the preset effect floor in both selected orderings, confirming that the win is
confined to the intended decimal lattice.

Direct differential coverage agrees with forced `snprintf("%.17g")` across
dense signed quarters, bound-adjacent magnitudes, and 100k deterministic random
quarter values. A diagnostic on the shared production dispatch separately
proves quarter values enter the specialization and non-quarter, integral,
non-finite, negative-zero, and out-of-bound values do not.

## Decision

**Accepted.** Keep the exact quarter-step specialization. It is a conservative,
behavior-preserving extension of exp 194 with a very large reproduced target
win, flat load-bearing controls, no public API change, and a direct byte oracle.

The release suite is not the useful denominator: no current public lane
isolates quarter-heavy REAL JSON formatting. The expanded
`select_bytes_real_int_fastpath.dart` harness and native REAL differential are
the durable gates.

## Future Notes

- Keep the exact-integral check before quarter admission and preserve the
  strict `abs(value) < 1e15` boundary. Values at or above it can require a
  different `%.17g` rounded spelling.
- Any further fractional lattice (for example exact eighths) needs its own
  representative workload, at least the same target bar, the non-quarter
  fallback guard, and forced-historical byte comparison. Do not infer a broad
  float-formatting mandate from this narrow win.
- The `native REAL formatter differential` group is now the compatibility gate
  for future number spelling changes. Tests must assert path admission as well
  as final bytes so a dead specialization cannot pass vacuously.

## Validation

- `dart pub get` in candidate and baseline worktrees.
- `dart run build_runner build --delete-conflicting-outputs`.
- Strict Clang C11 syntax/warning build of `native/resqlite_json.c`.
- `dart analyze --fatal-infos` — full repository, no issues.
- `dart test test/native_encoder_diff_test.dart` — 9/9 pass.
- `dart test test/database_test.dart --plain-name selectBytes` — 9/9 pass.
- `dart test test/benchmark_pipeline_test.dart` — 20/20 pass.
- `dart run benchmark/check_experiment_dispositions.dart` — no stranded
  in-review sources.
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/232-dyadic-real-fastpath.md`
  — generated-source and signal checks pass.
- `dart test -j 1` — full serial suite, 328/328 pass.
- Full candidate-first benchmark plus lane-adjacent baseline-first confirmation;
  every target and control fixture invariant passed.
- Independent AArch64/x86_64 code-generation, arithmetic, portability, and
  warning audit; no correctness or platform blocker found.
