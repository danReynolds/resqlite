# Experiment 130: Wide-batch native call split

**Date:** 2026-05-08
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** None (measurement-only)

## Problem

Exp 129 answered the first write-helper question for large wide
`executeBatch` calls: after exp 125 and exp 126, Dart parameter packing is
material but no longer the dominant steady-state slice. The measured
10,000-row x 20-parameter mixed shapes now spend roughly 63-74% of
write-helper wall inside the native `resqlite_run_batch*` call.

That still left the native call as an opaque bucket. Without splitting it, the
next implementation could easily chase a tiny loop cost such as reset or
statement-cache lookup while the actual wall sits in SQLite stepping or WAL
transaction completion.

## Hypothesis

The native batch call should be dominated by one of:

- parameter binding, which would justify another native binding/layout pass;
- `sqlite3_step`, which would shift attention to SQLite row-writing behavior;
- transaction control, which would shift attention toward WAL/commit behavior;
- reset / statement lookup, which would make small loop cleanups plausible.

Accept this as a measurement experiment if profile-mode counters can split the
native call without changing the public API or adding production-path timing
branches.

## Approach

Added profile-only native batch sub-counters:

```text
native/resqlite.h                                  resqlite_batch_profile
native/resqlite.c                                  profiled native batch path
hook/build.dart                                    profiled symbol exports
lib/src/native/resqlite_bindings.dart              FFI profile struct readback
lib/src/writer/write_worker.dart                   writer sample propagation
lib/src/writer/writer.dart                         main-isolate counter copy
lib/src/profile_counters.dart                      snapshot/diff/reset fields
benchmark/profile/wide_batch_native_call_split.dart
benchmark/profile/results/exp-130-wide-batch-native-call-split.md
```

The normal production path still calls the original `run_batch_locked` loop.
The profile-mode path calls `resqlite_run_batch_profiled` /
`resqlite_run_batch_nested_profiled`, which use a separate profiled native
loop and install the timed preupdate hook only during profiled batch execution.
No public API changes.

The native profile struct records:

- statement lookup / prepare / cache-insert wall;
- cached transaction-control statement wall for BEGIN, COMMIT, and ROLLBACK;
- per-set `bind_params` wall;
- per-set `sqlite3_step` wall;
- per-set `sqlite3_reset` wall;
- preupdate-hook wall as a subset of `sqlite3_step`;
- operation counts for sets, binds, steps, resets, and preupdate callbacks.

The focused harness reuses the exp 129 10,000-row x 20-parameter shapes:

- ASCII text, covering exp 125's direct ASCII payload path;
- Unicode text, covering exp 126's direct UTF-8 payload path;
- emoji text, covering surrogate-pair handling in the UTF-8 path.

Rows are built before the measured window.

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/wide_batch_native_call_split.dart --markdown --repeats=5
```

The first pass is warmup-heavy. Passes 2-5 are the useful steady-state band.

| workload | steady native_write_us | bind / native | step / native | tx commit / native | reset / native | stmt / native | residual / native |
|---|---:|---:|---:|---:|---:|---:|---:|
| mixed ASCII text | 9280-9800 | 13.84-14.78% | 44.98-49.43% | 25.08-29.48% | 2.49-2.60% | 0.28-0.45% | 7.80-10.95% |
| mixed Unicode text | 9898-10655 | 12.73-13.74% | 42.78-45.46% | 31.22-34.21% | 2.07-2.41% | 0.29-0.38% | 7.33-7.61% |
| mixed emoji text | 12607-13754 | 9.96-11.01% | 32.31-35.84% | 44.57-50.01% | 1.56-1.83% | 0.19-0.26% | 5.42-6.33% |

Per-set steady bands:

| workload | bind_us / set | step_us / set | reset_us / set | preupdate / step |
|---|---:|---:|---:|---:|
| mixed ASCII text | 0.130-0.143 | 0.423-0.475 | 0.024-0.025 | 6.29-7.06% |
| mixed Unicode text | 0.135-0.137 | 0.439-0.470 | 0.022-0.024 | 6.44-7.69% |
| mixed emoji text | 0.132-0.141 | 0.443-0.455 | 0.021-0.024 | 6.19-6.75% |

Raw committed output:

```text
benchmark/profile/results/exp-130-wide-batch-native-call-split.md
```

## Decision

**Accept for review - measurement.**

The native call is not reset-bound or statement-cache-bound. Those buckets are
too small to justify a broad implementation pass:

- reset is about 1.6-2.6% of native wall;
- statement lookup / prepare is about 0.2-0.5% after warmup.

Binding is real but not the dominant remaining cost. On the measured mixed
wide shapes, bind wall is roughly 9-15% of native wall, or about 0.13-0.14 us
per 20-parameter row. A perfect binding elimination would not explain the
remaining wide-batch native wall by itself.

The largest buckets are `sqlite3_step` and COMMIT:

- `sqlite3_step` is the largest loop-local bucket for ASCII and Unicode
  batches, about 32-49% of native wall across the measured shapes;
- COMMIT is large on every shape and dominates emoji, about 25-50% of native
  wall.

That shifts the next useful work away from small loop helpers and toward
SQLite row-writing / WAL transaction behavior. A future implementation should
either reduce the number/cost of steps, change transaction/commit behavior in
a workload-safe way, or add a focused harness that explains why COMMIT grows so
large on the heavier text shapes.

## Future Notes

- Do not chase reset or statement lookup for wide batches unless a different
  workload shows a radically different split.
- Treat binding micro-optimizations as limited-ceiling until a workload shows
  bind above the 9-15% steady-state band.
- The next native-wide-batch candidate should compare top-level batch commits
  against nested/in-transaction batches or WAL/checkpoint state, so COMMIT can
  be separated from row stepping and text payload size.
- `preupdate_us` is a subset of `step_us`, not an additive bucket. The measured
  6-8% of step is useful attribution but not an immediate standalone target.
