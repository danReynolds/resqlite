# Experiment 104: Persistent `pBuf` / `pLen` slots for `queryBytes`

**Date:** 2026-04-26
**Status:** Rejected
**Archive:** [`archive/exp-104`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-104)

## Problem

`queryBytes` in [lib/src/native/resqlite_bindings.dart](../lib/src/native/resqlite_bindings.dart)
allocated two scratch out-parameter cells per call:

```dart
final pBuf = calloc<ffi.Pointer<ffi.Uint8>>();
final pLen = calloc<ffi.Int>();
try {
  final rc = resqliteQueryBytes(..., pBuf, pLen);
  ...
} finally {
  ...
  calloc.free(pBuf);
  calloc.free(pLen);
}
```

`resqlite_query_bytes` writes the json buffer pointer and the byte
length into those slots. Both the reader and writer isolates are
single-threaded and each one serializes its `queryBytes` calls, so
the same pair of slots can be reused across every call instead of
paying a `calloc` + `free` pair per query.

This is the read-path twin of exp 095 (persistent writer result
buffer). The hypothesis was the same: small per-call native
allocations that survive the call should move to per-isolate
top-level state.

## Hypothesis

Replacing the per-call `calloc` + `free` pair with two persistent
top-level cells should remove a small, fixed bookkeeping cost on
every `selectBytes` query. The biggest signal — if any — should be
on:

- The `Select → JSON Bytes` size sweep (10 / 100 / 1000 / 10000
  rows), which exercises `selectBytes` directly.
- The `Scaling` suite's `resqlite selectBytes()` rows.
- The `Memory` suite's `Select 10k rows → JSON Bytes / resqlite
  selectBytes()` row.

Estimated saving is in the 50–150 ns range per call — same shape as
exp 095's removable 16-byte allocation. The expectation going in was
that, like exp 095, this would be **at or below** the release-mode
benchmark floor.

## Approach

Moved `pBuf` / `pLen` from per-call `calloc` to two top-level
`final` `Pointer<…>` slots in
[lib/src/native/resqlite_bindings.dart](../lib/src/native/resqlite_bindings.dart):

```dart
final ffi.Pointer<ffi.Pointer<ffi.Uint8>> _queryBytesPBuf =
    calloc<ffi.Pointer<ffi.Uint8>>();
final ffi.Pointer<ffi.Int> _queryBytesPLen = calloc<ffi.Int>();

NativeBuffer queryBytes(...) {
  ...
  final rc = resqliteQueryBytes(..., _queryBytesPBuf, _queryBytesPLen);
  ...
  return (ptr: _queryBytesPBuf.value, length: _queryBytesPLen.value);
}
```

Each Dart isolate gets its own copy of top-level statics, so the
single-threaded serialization invariant for `queryBytes` calls is
preserved without any extra coordination. The slots live for the
lifetime of the isolate.

The change is local — only the `queryBytes` helper is touched. The
C-side `resqlite_query_bytes` contract is unchanged.

All 208 tests pass (`dart test`).

## Results

Artifact:
[`benchmark/results/2026-04-26T07-28-32-exp104-querybytes-persistent-slots.md`](../benchmark/results/2026-04-26T07-28-32-exp104-querybytes-persistent-slots.md)

Baseline: `2026-04-25T14-06-42-baseline-for-exp100.md`.

Suite-level: **6 wins, 1 regression, 146 neutral.**

**Directly attributable to the change** (`selectBytes` workloads
that take the modified path):

| Workload | Baseline (ms) | Experiment (ms) | Delta | Status |
|---|---:|---:|---:|---|
| Select → JSON Bytes / 10 rows / `resqlite selectBytes()` | 0.01 | 0.01 | -0.00 | ⚪ Within noise (±85%) |
| Select → JSON Bytes / 100 rows / `resqlite selectBytes()` | 0.04 | 0.04 | +0.00 | ⚪ Within noise (±14%) |
| Select → JSON Bytes / 1000 rows / `resqlite selectBytes()` | 0.37 | 0.36 | -0.01 | ⚪ Within noise (±10%) |
| Select → JSON Bytes / 10000 rows / `resqlite selectBytes()` | 3.77 | 3.79 | +0.03 | ⚪ Within noise (±10%) |
| Scaling / 10 rows / `resqlite selectBytes()` | 0.01 | 0.01 | +0.00 | ⚪ Within noise |
| Scaling / 50 rows / `resqlite selectBytes()` | 0.03 | 0.03 | +0.00 | ⚪ Within noise |
| Scaling / 5000 rows / `resqlite selectBytes()` | 2.33 | 1.98 | -0.36 | 🟢 Win (-15%) |

The whole `Select → JSON Bytes` size sweep is **flat** within
noise. The `Scaling` suite shows one isolated -15% point at 5000
rows — but it is **not corroborated** by the four matching
`Select → JSON Bytes` row counts (10 / 100 / 1000 / 10000), which
all sit on top of baseline. A real per-call allocation saving would
shift every selectBytes size class in the same direction; this
isolated win pattern-matches run-to-run drift on a single noisy
workload rather than a structural change.

**Other suite-level deltas** (not attributable to the change):

- `Stream Subscription Rate` -19%, `Single Inserts` -28% — neither
  workload calls `queryBytes`. Run-to-run drift relative to a
  day-old baseline.
- `Select → JSON Bytes / 10000 rows / resqlite + jsonEncode` +11%.
  This is the `select()` + `jsonEncode` path on the main isolate;
  `queryBytes` is not on that path. Same class of drift as the wins
  above, with the sign flipped.

**Memory suite:** unchanged within MDE on every `selectBytes`
workload. The single 1-win row is on a `drift + jsonEncode` cell
that has no relationship to the change.

## Decision

Rejected. Code change reverted on the main branch; the
implementation is preserved at the [`archive/exp-104`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-104)
tag for re-evaluation if a future benchmark surfaces a
`selectBytes`-dominated workload at the noise floor.

The targeted `selectBytes` benchmarks across four row-count tiers
do not move; the one isolated win and the one isolated regression
are on workloads that don't take the modified path. This is the
same fingerprint as exp 095 (persistent writer result buffer) and
exp 093 (alias cache entry's read tables): a structurally sound
removal of a small per-call native-allocation pair, but the
practical signal is below the release-mode noise floor.

The savings ceiling is one `calloc(8) + calloc(4)` + matching
`free` pair per call — well under 200 ns. On workloads where a
`selectBytes` call already takes 40 µs–4 ms (the smallest
selectBytes benchmark medians), that saving is < 0.5 % of the wall
time and indistinguishable from drift in a 5-repeat release run.

The implementation is small (~10 LoC) and zero-risk, but per the
project's "if we can't measure it, we don't adopt it" rule
(established in exp 050, reaffirmed in 071/093/095), it does not
clear the bar for inclusion.

## Related

- exp 095 — persistent writer result buffer (rejected, same class).
- exp 093 — alias cache entry's read tables (rejected, same class).
- exp 076 — pre-bound stmt cache (rejected pre-implementation;
  bind cost was already 0.3 % of wall time).
- exp 037 — persistent JSON buffer per reader (accepted; that one
  *did* move benchmarks because the buffer is allocated per-call
  on a much larger size class — kilobytes, not 12 bytes).
