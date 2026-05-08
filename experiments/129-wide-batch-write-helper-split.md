# Experiment 129: Wide-batch write-helper split

**Date:** 2026-05-08
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** None (measurement-only)

## Problem

Exp 125 and exp 126 removed the largest known string-allocation cost in
large wide `executeBatch` calls: temporary per-string UTF-8 lists inside the
batch matrix encoder. Exp 127 then showed that the current 10,000-row x
20-parameter wide-batch shape still spends almost the entire workload wall
inside the writer roundtrip, with the write helper accounting for roughly
71-75% of that roundtrip after warmup.

That still left the key question unresolved: **inside the write helper, how
much is Dart parameter-matrix packing versus the native `resqlite_run_batch*`
call?** Without that split, the next wide-batch idea would be guessing whether
to keep changing the Dart encoder or move down into native binding / stepping /
transaction-control work.

## Hypothesis

After the direct ASCII and direct UTF-8 packing paths, steady-state wide batches
should no longer be primarily Dart-packing-bound. Parameter packing may remain
material, but the native batch call should be the larger slice of write-helper
wall on the mixed 10k x20 shapes.

Accept this as a measurement experiment if:

- profile-mode counters split `executeBatch` write-helper wall into
  `param_pack_us` and `native_write_us`;
- the harness measures ASCII, Unicode, and emoji wide mixed rows so both direct
  text encoders are covered;
- results update `signals.json` so the next parameter experiment has a concrete
  ceiling.

## Approach

Added profile-only batch sub-counters:

```text
lib/src/native/resqlite_bindings.dart             BatchWriteProfile
lib/src/writer/write_worker.dart                  profiled batch helper path
lib/src/writer/writer.dart                        main-isolate counter copy
lib/src/profile_counters.dart                     snapshot/diff/reset fields
benchmark/profile/wide_batch_write_helper_split.dart
benchmark/profile/results/exp-129-wide-batch-helper-split.md
```

The normal production path still calls `executeBatchWrite` /
`executeNestedBatchWrite`. In profile mode only, `_handleBatch` calls the
profiled equivalent, which measures:

- `param_pack_us`: `allocateBatchParams(paramSets)` wall;
- `native_write_us`: `resqlite_run_batch*` wall after params are packed;
- `write_residual_us`: helper remainder, mostly wrapper overhead and freeing the
  packed native buffer.

These values are carried through the existing profiled writer response and
accumulated in `ProfileCounters`. No public API changes.

The focused harness runs three 10,000-row x 20-parameter mixed shapes:

- ASCII text, exercising exp 125's direct ASCII path;
- Unicode text, exercising exp 126's direct UTF-8 path;
- emoji text, exercising surrogate-pair handling in the same UTF-8 path.

Rows are built before the measured window so row generation is not counted.

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/wide_batch_write_helper_split.dart --markdown --repeats=5
```

The first pass is warmup-heavy, especially in parameter packing. Passes 2-5 are
the useful steady-state band.

| workload | steady wall_ms | param pack / write call | native write / write call | param pack / wall | native write / wall |
|---|---:|---:|---:|---:|---:|
| mixed ASCII text | 14.37-21.91 | 25.15-30.41% | 69.11-74.27% | 11.67-21.25% | 34.47-53.80% |
| mixed Unicode text | 16.48-18.28 | 31.90-36.83% | 62.62-67.75% | 24.08-27.15% | 46.15-51.14% |
| mixed emoji text | 23.77-42.55 | 27.54-35.74% | 63.93-72.27% | 18.36-24.66% | 32.85-60.98% |

Raw committed output:

```text
benchmark/profile/results/exp-129-wide-batch-helper-split.md
```

## Decision

**Accept for review - measurement.**

The missing wide-batch signal is now resolved: after exp 125 / exp 126,
steady-state wide mixed batches are **native-call dominated**, not
parameter-packing dominated. Dart packing is still material, roughly
25-37% of write-helper wall after warmup, but the larger slice is now
`resqlite_run_batch*` at roughly 63-74%.

That changes the next-experiment bar:

- another broad Dart encoder tweak is likely ceiling-bound unless it removes a
  larger structural cost than the direct ASCII / UTF-8 paths already removed;
- a new packing idea should first prove a shape where `param_pack_us` is much
  larger than the measured 25-37% steady-state band;
- the next native-side measurement should split `resqlite_run_batch*` into
  binding, stepping, reset, and transaction-control work before changing the C
  loop.

This does not make parameter work uninteresting. A perfect packing elimination
would still remove several milliseconds from a 10k x20 batch. It does mean the
old open signal, "split Dart parameter packing from the native write call before
another encoder change," is answered: the next broad win is more likely below
the Dart matrix encoder than inside it.

## Future Notes

- If a production workload is much wider than 20 params, blob-heavy, or carries
  larger text payloads, rerun this harness with that shape before generalizing
  this result.
- Keep the counters profile-only. They are useful for future batch work but
  should not widen the user API.
- Treat exact SQLite statement timing as a separate native-profile experiment;
  this split stops at the boundary of `resqlite_run_batch*`.
