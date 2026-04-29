# Experiment 111: Nested-transaction benchmark + revisit savepoint string cache

**Date:** 2026-04-28
**Status:** Rejected
**Direction:** `transaction-control-paths`, `measurement-system`

## Problem

Two prior experiments rejected work in the savepoint codepath solely because
the benchmark suite couldn't see the modified path:

- [Exp 102](102-savepoint-string-cache.md) cached the
  `'SAVEPOINT sN'` / `'RELEASE sN'` / `'ROLLBACK TO sN'` UTF-8 byte
  allocations on `_WriterState`. It explicitly noted: "The benchmark
  suite has no nested-transaction workload. The single Interactive
  Transaction benchmark uses a top-level BEGIN/COMMIT only, which goes
  through exp 101's cached prepared stmts and never hits the savepoint
  code path."
- [Exp 103](103-native-nested-tx-depth-control.md) attempted a native
  nested-transaction depth control API and was rejected because the
  realistic nested-write cases were flat or worse.

The `signals.json` `transaction-control-paths` direction calls this
out directly: "A nested-transaction benchmark would make this area
much easier to reason about." [`JOURNAL.md`](JOURNAL.md)'s
"Measurement is a first-class outcome" entry codifies the same lesson.

## Hypothesis

Adding a representative nested-transaction workload to the release suite
should make the savepoint codepath visible. With the workload in place,
revisiting exp 102's archived savepoint string cache should produce a
measurable win on the new workload — or, if it stays flat even there,
prune the direction more confidently than the original "no signal"
rejection could.

## Approach

### Part 1 — Nested-transaction benchmark

Added a "Nested Transactions (savepoints)" section to
[`benchmark/suites/writes.dart`](../benchmark/suites/writes.dart) with
two shapes:

- **Shallow fan-out**: 1 outer `db.transaction(...)` containing 50
  sequential `tx.transaction(...)` blocks, each inserting one row and
  releasing. Each iteration fires `BEGIN IMMEDIATE` + 50 ×
  (`SAVEPOINT s1` / `RELEASE s1`) + `COMMIT`. Worst case for the
  per-call `'SAVEPOINT sN'.toNativeUtf8()` + `calloc.free` pair, since
  the same depth fires 50× per iteration.
- **Deep chain**: 5 levels of nesting deep with the insert at the
  innermost level. Each iteration fires `SAVEPOINT s1..s5` + `RELEASE
  s5..s1`. Worst case for unique-depth savepoint strings.

Resqlite-only (no peer comparison): `sqlite_async`'s nested transaction
semantics don't map cleanly enough for an apples-to-apples single-row
picture, and the goal here is a baseline for resqlite-vs-resqlite
experiment comparisons.

### Part 2 — Revisit savepoint string cache

Re-implemented exp 102's pattern from the documented description:

```dart
final List<ffi.Pointer<Utf8>> _savepointEnter = [];
final List<ffi.Pointer<Utf8>> _savepointRelease = [];
final List<ffi.Pointer<Utf8>> _savepointRollbackTo = [];

ffi.Pointer<Utf8> savepointEnter(int depth) =>
    _cachedSavepoint(_savepointEnter, depth, 'SAVEPOINT s');
// + savepointRelease, savepointRollbackTo

static ffi.Pointer<Utf8> _cachedSavepoint(
  List<ffi.Pointer<Utf8>> cache,
  int depth,
  String prefix,
) {
  while (cache.length <= depth) {
    cache.add('$prefix${cache.length}'.toNativeUtf8());
  }
  return cache[depth];
}
```

Replaced the six `'…'.toNativeUtf8()` + `calloc.free` call sites in
`_handleBegin`, `_handleCommit`, and `_handleRollback`
([`lib/src/writer/write_worker.dart`](../lib/src/writer/write_worker.dart))
with the cached-pointer helpers. Native footprint: ~12 bytes per
depth per list × 3 lists ≈ 36 bytes per realised depth, persisting for
the writer isolate's lifetime.

Validation before benchmarking:

```text
dart test test/database_test.dart test/transaction_test.dart
```

All 76 tests passed both with and without the cache.

## Results

Artifacts:

- Baseline: [`benchmark/results/2026-04-28T13-13-50-baseline-for-exp111.md`](../benchmark/results/2026-04-28T13-13-50-baseline-for-exp111.md)
- Candidate: [`benchmark/results/2026-04-28T13-24-34-exp111-savepoint-cache.md`](../benchmark/results/2026-04-28T13-24-34-exp111-savepoint-cache.md)

Command:

```text
dart run benchmark/run_release.dart exp111-savepoint-cache --repeat=5 \
  --compare-to=benchmark/results/2026-04-28T13-13-50-baseline-for-exp111.md
```

**Suite-level: 8 wins, 0 regressions, 151 neutral.**

Target rows (the new nested-tx workload):

| Benchmark | Baseline ms | Candidate ms | Delta | Threshold | Status |
|---|---:|---:|---:|---:|---|
| Nested Transactions (savepoints) / 50× shallow fan-out | 0.87 | 0.79 | -0.08 (-9%) | ±17% / ±0.15 ms | ⚪ Within noise |
| Nested Transactions (savepoints) / depth=5 deep chain | 0.08 | 0.08 | ±0.00 | ±19% / ±0.02 ms | ⚪ Within noise |

The shallow fan-out trended in the right direction, but at -9% it
falls below the per-benchmark decision threshold of ±17%
(MDE_ci-driven). Even on a workload designed specifically to maximize
the savepoint-allocation savings — 50 SAVEPOINT/RELEASE pairs at the
same depth per iteration — the per-call savings (~one `toNativeUtf8`
+ `calloc.free`) is small relative to the fixed cost of an isolate
round-trip per nested transaction. The deep-chain shape is too short
to expose any savings.

The 8 suite-level wins are on workloads that **don't fire user-level
SAVEPOINT/RELEASE statements at all** — Concurrent Reads, Stream
Subscription Rate, Batched Write Inside Transaction (`tx.executeBatch`
opens a top-level tx via cached BEGIN/COMMIT prepared stmts; no
savepoint code runs). They pattern-match run-to-run drift on
write/read paths and are not structurally attributable to this change.

Memory comparison reported **2 wins, 0 regressions, 13 neutral** — no
flags, all neutral on target paths.

## Decision

**Rejected** — same outcome as exp 102, now with explicit worst-case
workload evidence.

The nested-tx benchmark itself is the durable contribution: it ships
to main as a measurement-system improvement and prevents future
experimenters from being blocked by the same gap. Future experiments
in `transaction-control-paths` (e.g. revisiting exp 103's native
nested-tx depth control, or any SAVEPOINT-related work) should
compare against this benchmark before claiming a win.

The savepoint string cache code is reverted. The implementation
pattern remains documented in exp 102's writeup for cherry-pick if a
future workload (e.g. a deeply-nested-tx hot loop with N >> 50 inner
saves per outer tx, or a profile mode showing a measurable allocator
spike on this path) ever surfaces signal that the release suite
cannot.

## Future Notes

Two complementary observations from this run:

1. **Per-isolate-round-trip costs dominate** the savepoint string
   allocation cost on a worst-case savepoint workload. A future
   nested-tx optimization that *batches* multiple savepoint
   open/close operations into one isolate hop (cf. exp 009 for the
   read-side batching pattern) is more likely to show signal than any
   per-savepoint allocation tweak. This is a different shape from
   exp 103's "native nested-tx depth control" — that one tried to add
   one C entry point per savepoint operation, which still kept N hops.
2. The shallow fan-out variant is the most savepoint-allocation-
   stressing shape achievable through the public `tx.transaction(...)`
   API. If a change is invisible at 50× repeat, it's effectively
   invisible everywhere a real app could exercise.
