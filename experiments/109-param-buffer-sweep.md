# Experiment 109: Parameter buffer allocation sweep

**Date:** 2026-04-27
**Status:** Rejected
**Benchmark Run:** [`benchmark/profile/results/exp109-param-view-multirun.md`](../benchmark/profile/results/exp109-param-view-multirun.md)

## Problem

The current hot paths are already narrow after the accepted statement-cache,
static-bind, row-decode, transaction-control, and stream-hash experiments. The
latest external research pass did not reveal a large new public API or SQLite
feature that cleanly maps to resqlite without expanding the API:

- Dart 3.10 stabilized build hooks, which resqlite already uses through
  `hook/build.dart`. Dart 3.11 adds no new language features and focuses on
  tooling responsiveness, not runtime FFI/database primitives.
- Dart FFI `isLeaf` remains the key low-level call-overhead tool, and resqlite
  already annotates the short native calls that qualify.
- SQLite 3.53.0 adds planner work, `sqlite3_carray_bind_v2`,
  `SQLITE_UTF8_ZT`, and `SQLITE_DBCONFIG_FP_DIGITS`, but the embedded
  sqlite3mc copy is intentionally held at SQLite 3.51.3 after exp 090's bump
  audit. sqlite3mc 2.3.3 now tracks SQLite 3.53.0, but that is still the first
  3.53.x release and includes a floating-point text conversion behavior change.
- Peer libraries continue to validate the same broad themes resqlite already
  optimizes for: prepared statement reuse, WAL checkpoint hygiene, and avoiding
  worker/message abstractions that dominate small queries.

That left a smaller allocation-side question: do any of the remaining Dart
FFI marshalling allocations still show up in the benchmark floor?

## Hypothesis

Three small ideas looked plausible:

1. **Known-length text binds.** `allocateParams` currently writes text params as
   native UTF-8 plus `len = -1`, so `sqlite3_bind_text()` scans to the first
   zero terminator. SQLite's bind docs specify that the fourth argument is byte
   length and negative length means terminator scan. Passing the UTF-8 byte
   length already known during Dart encoding might remove SQLite's `strlen`.
2. **Persistent `selectBytes()` out slots.** `queryBytes` allocates two tiny
   out-parameters (`unsigned char**`, `int*`) for every call even though the
   reader worker handles one request at a time.
3. **Reusable parameter `ByteData` view.** `request_cache.dart` already reuses
   the native parameter struct buffer, but `allocateParams` and `freeParams`
   recreate typed-list / `ByteData` views over that same pointer on every call.
   Keeping those views beside the reusable buffer should remove two short-lived
   Dart objects per parameterized request.

All three keep the public API unchanged.

## Approach

### Pass 1: known-length text binds + `selectBytes()` scratch slots

Implemented:

- a Dart UTF-8 helper that returned native pointer plus byte length
- text param struct length set to the encoded byte count instead of `-1`
- persistent reader-isolate out slots for `resqlite_query_bytes`
- a regression test proving embedded NUL text params round-trip instead of
  truncating at the first zero byte

This pass was reverted after measurement. The embedded-NUL behavior is a real
correctness improvement, but it is not a performance win and changes historical
text binding semantics. It should be revisited as a correctness fix, not hidden
inside a performance PR.

### Pass 2: reusable parameter `ByteData` views

Reverted the text-length change and tested a narrower allocation optimization:

- `request_cache.dart` kept a cached `Uint8List` and `ByteData` view whenever
  the reusable param struct buffer grew
- `allocateParams` and `freeParams` reused that `ByteData` for normal
  small/medium param payloads
- oversized param buffers above `_maxReusableParamBufBytes` still allocated and
  viewed ad hoc, preserving the existing large-payload behavior

This pass was also reverted after measurement.

## Results

Validation while the candidate code was present:

```bash
dart test test/database_test.dart
dart analyze
```

Both passed.

### Profile-mode A/B

Final measured candidate: reusable parameter `ByteData` view. Baseline runs came
from a clean worktree at `3f88e24`; candidate runs came from the experiment
branch. Three runs per side were compared with
`benchmark/profile/diff_multirun.dart`.

Key rows from
[`benchmark/profile/results/exp109-param-view-multirun.md`](../benchmark/profile/results/exp109-param-view-multirun.md):

| Workload | Metric | Baseline | Candidate | Delta |
|---|---:|---:|---:|---:|
| merge_rounds executeBatch | p50 | 100 us | 103 us | +3.0% |
| merge_rounds executeBatch | work | 91 us | 94 us | +3.3% |
| merge_rounds executeBatch | p90 | 112 us | 124 us | +10.7% |
| single_insert execute | p50 | 16 us | 16 us | flat |
| single_insert execute | work | 6 us | 7 us | +16.7% |
| point_query select | work | 1 us | 1 us | flat |

The noop floor moved favorably in the final candidate run set, which makes the
unchanged/worse parameterized write rows more damning rather than less. If the
allocation-view reuse helped, merge rounds should have been the clearest signal;
instead p50/work moved backwards.

### `selectBytes()` focused check

The persistent out-slot pass did not show a reliable focused win:

| Rows | Baseline `selectBytes()` | Candidate/final `selectBytes()` | Read |
|---:|---:|---:|---|
| 10 | 0.023 ms | 0.023 ms | flat |
| 100 | 0.053 ms | 0.055 ms | flat / noise |
| 1,000 | 0.374 ms | 0.352 ms | small trend, not enough |
| 10,000 | 3.668 ms | 3.663 ms | flat |

The two-pointer allocation is below the measurement floor compared with worker
dispatch and native JSON encoding.

## Decision

Rejected. All implementation changes were reverted.

The useful result is negative: the remaining Dart-side parameter buffer view
allocations and `selectBytes()` out-param allocations are not meaningful
performance targets. Known-length text binds are also not a performance win in
the current harness; if embedded NUL support matters, handle that separately as
a behavior/correctness change with explicit compatibility notes.

Future rounds should avoid more sub-allocation sweeps in this area unless a
memory profiler points directly at these objects. Better targets are still the
larger costs called out in earlier experiments: dispatch/message scheduling,
long-text stream hashing with a benchmark that actually carries long text, and
workload-specific SQLite planner/version audits once SQLite 3.53.x has a safer
point release.
