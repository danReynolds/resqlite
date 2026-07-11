# Experiment 222: Reject `malloc` for large one-shot parameter arenas

**Date:** 2026-07-11
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none — focused
  [`benchmark/experiments/single_row_large_text_bind.dart`](../benchmark/experiments/single_row_large_text_bind.dart);
  raw order-flipped tables in
  [`benchmark/results/2026-07-11T10-15-21Z-exp222-param-arena-malloc.md`](../benchmark/results/2026-07-11T10-15-21Z-exp222-param-arena-malloc.md).
**Archive:** [`archive/exp-222`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-222)

## Problem

[`allocateParams`](../lib/src/native/resqlite_bindings.dart) packs parameter
structs and their TEXT/BLOB payloads into one native arena. Arenas at or below
64 KiB reuse one persistent allocation; larger arenas are allocated and freed
for every call by
[`allocateReusableParamStructBuf`](../lib/src/native/request_cache.dart).

The one-shot branch uses `calloc`, even though the packer immediately writes
every struct field and payload byte that [`bind_params`](../native/resqlite.c)
reads. Only C struct padding and inactive union fields need no value at all.
The reusable branch already proves that zero-filled memory is not an invariant:
after its first call, later parameter sets overwrite a buffer carrying bytes
from the prior request.

[Exp 109](109-inline-param-buffer.md) established this single-arena layout.
[Exp 186](186-single-row-large-text-bind-encoder.md) and
[exp 187](187-single-row-utf8-bind-encoder.md) then made 64 KiB through 1 MiB
single-row ASCII/CJK binds first-class workloads. Those rows allocate a fresh
arena per write, making them the right place to test whether zero-fill remains
material after the direct text encoders removed the intermediate Dart byte
list.

## Hypothesis

Using `malloc` instead of `calloc` for arenas above the 64 KiB reuse cap should
skip zero-filling memory that the parameter packer immediately overwrites. The
largest ASCII and CJK rows should improve most because every sample performs
100 fresh 256 KiB or 1 MiB allocations before binding and stepping SQLite.

Accept only if at least one 256 KiB or 1 MiB row improves by more than 5% in the
same direction across an order-flipped pair, with the other large rows neutral
or faster. Reject if the target rows flip sign, remain below the effect floor,
or reproduce a regression.

## Approach

The archived prototype changes only
[`lib/src/native/request_cache.dart`](../lib/src/native/request_cache.dart):

```dart
if (byteCount > _maxReusableParamBufBytes) {
  return malloc<ffi.Uint8>(byteCount);
}
```

`freeReusableParamStructBuf` correspondingly uses `malloc.free` for one-shot
buffers. The reusable `calloc` allocation and its 64 KiB cap stay unchanged, so
small parameter sets retain exactly the existing ownership and retention
policy.

The change is behavior-preserving because `resqlite_param.type` is always
written, `bind_params` switches on that type, and the active integer, float,
TEXT, or BLOB union members are written before the FFI call. Padding and
inactive members are never read. `dart test test/database_test.dart -j 1`
passes all 53 cases on the candidate, including nulls, integers, doubles,
Unicode and embedded-NUL TEXT, BLOBs, batches, cached statements, and
transactions.

The runtime prototype is preserved at `archive/exp-222` and reverted from the
publication branch.

## Results

The focused harness reports median milliseconds per 100 sequential inserts.
Both worktrees used `origin/main` at `44a6d39` and ran with local dependencies
resolved. The 64 KiB payload rows cross the allocator threshold because their
arena also includes one 24-byte parameter struct.

| Payload | Pair 1 (base -> cand) | Pair 2 (cand -> base) |
|---|---:|---:|
| ASCII 64 KiB | +6.4% | -2.1% |
| ASCII 256 KiB | +5.9% | +0.2% |
| ASCII 1 MiB | +0.8% | -2.4% |
| CJK 64 KiB | +0.1% | -7.8% |
| CJK 256 KiB | +1.5% | -6.0% |
| CJK 1 MiB | +2.2% | -2.5% |

The result does not reproduce. ASCII 256 KiB is candidate-slower in both
orderings and never shows the predicted win. The other five allocator-targeted
rows flip from neutral/slower in Pair 1 to candidate-faster in Pair 2, with the
1 MiB rows staying within roughly 2.5% either way. Unchanged 1 KiB and 16 KiB
controls also swing widely, including opposite-direction 20-30% movements on
the sub-4 ms CJK row, which identifies machine drift rather than a stable
allocator mechanism.

Full medians for every row are in the linked result artifact.

Focused validation on the prototype:

```text
dart analyze --fatal-infos \
  lib/src/native/request_cache.dart \
  lib/src/native/resqlite_bindings.dart
dart test test/database_test.dart -j 1
```

Both passed before the runtime change was reverted.

## Decision

**Rejected.** Keep `calloc` for large one-shot parameter arenas.

Skipping zero-fill is logically safe, but it does not remove a stable,
material part of end-to-end large-bind wall on this machine. The packer writes
nearly the whole arena immediately, and modern allocator behavior makes the
remaining `calloc` cost too small or inconsistent to clear the existing public
workload. An allocator-policy difference without a reproduced workload win is
not worth carrying, even when the code diff is small.

Would reopen only if a platform-specific allocator profile attributes material
write wall directly to `calloc`, or if a future arena layout leaves a large
fraction of allocated pages intentionally untouched. Do not retry by raising
the reusable buffer cap: exp 125 already rejected that separate retention
tradeoff after an unstable small win.

## Future Notes

- Large single-row parameter work should continue to use both ASCII and CJK
  rows in `single_row_large_text_bind.dart`; allocator changes are not exempt
  from the encoder guardrails.
- The exact tested prototype is available at `archive/exp-222`.
- The next parameter experiment should remove a real copy/scan or consume
  workload evidence, rather than swapping equivalent allocator entry points.

## Test plan

- [x] `dart pub get` in baseline and candidate worktrees
- [x] focused order-flipped A/B with
      `benchmark/experiments/single_row_large_text_bind.dart`
- [x] `dart analyze --fatal-infos` on the touched allocator/bind files
- [x] `dart test test/database_test.dart -j 1` (53/53 pass)
- [x] `dart run benchmark/finalize_experiment.dart \
      --experiment=experiments/222-param-arena-malloc.md`
- [x] `dart run benchmark/check_experiment_dispositions.dart`
- [x] `dart test test/benchmark_pipeline_test.dart`
- [x] `git diff --check`
