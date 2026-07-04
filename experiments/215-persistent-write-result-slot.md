# Experiment 215: Persistent `executeWrite` result-buffer slot (revisits exp 095)

**Date:** 2026-07-04
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** focused
  [`benchmark/experiments/write_result_direct_read.dart`](../benchmark/experiments/write_result_direct_read.dart);
  raw pair tables in
  [`benchmark/results/2026-07-04T11-13-17Z-exp215-persistent-write-result-slot.md`](../benchmark/results/2026-07-04T11-13-17Z-exp215-persistent-write-result-slot.md).
**Archive:** [`archive/exp-215`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-215)

## Problem

`executeWrite()` in
[`lib/src/native/resqlite_bindings.dart`](../lib/src/native/resqlite_bindings.dart)
allocates a 16-byte native scratch buffer on every writer request so C can
return `affected_rows` and `last_insert_id`:

```dart
final resultBuf = calloc<ffi.Uint8>(_writeResultSize);
try {
  final rc = resqliteExecute(..., resultBuf);
  ...
  final view = ByteData.sublistView(
    resultBuf.asTypedList(_writeResultSize),
  );
  return WriteResult(
    view.getInt32(_writeResultOffAffected, Endian.little),
    view.getInt64(_writeResultOffLastId, Endian.little),
  );
} finally {
  calloc.free(resultBuf);
}
```

[Exp 095](095-writer-result-buffer.md) already tried removing this per-call
`calloc` / `free` pair with a persistent per-isolate buffer and rejected the
change: the release-suite comparison reported "0 wins, 14 regressions, 139
neutral" and focused dispatch shifted only a couple of microseconds. That
verdict was correct given the release-suite harness resolution — write-path
medians are in the milliseconds and cannot see a few-hundred-nanosecond
scratch.

Two things have moved since exp 095:

- [Exp 214](214-write-result-direct-read.md) built
  `benchmark/experiments/write_result_direct_read.dart`, a focused writer
  harness that reports median microseconds per `Database.execute()` call over
  2000 calls/sample on three shapes (no-op update, point update, param
  update). That is exactly the µs-precision writer harness
  [exp 211's Future Notes](211-persistent-query-bytes-slots.md#future-notes)
  named as the revisit condition for exp 095.
- [Exp 211](211-persistent-query-bytes-slots.md) accepted the exact mirror
  change on the reader side: persistent per-isolate slots for `queryBytes()`
  reproduced −3.4 % to −6.6 % on tiny-rowset lanes across two order-flipped
  passes of `select_bytes_repeated_calls.dart` after exp 108 had rejected the
  same mechanism under the ms-precision release suite.

The named revisit condition from exp 095 is present.

## Hypothesis

Reusing one persistent 16-byte per-isolate slot removes one `calloc` + one
matching `calloc.free` (~a few hundred nanoseconds each) per
`Database.execute()` call. On `write_result_direct_read.dart`'s ~6.5 µs
no-op-update floor the mechanism should land in a low-single-digit
candidate-faster band; on the ~14 µs point/param lanes the same fixed
mechanism should be about half as big.

Prediction:

- All three shapes reproduce candidate-faster in the 1-4 % band across two
  order-flipped passes.
- The no-op-update lane (lowest baseline) shows the largest relative delta;
  the point/param lanes show smaller-but-same-sign wins because the
  mechanism is a per-call fixed cost.

Reject if the deltas do not reproduce same-sign across the order-flipped
pair, or if the mechanism sits at or below the harness noise floor.

## Approach

Single-file change to
[`lib/src/native/resqlite_bindings.dart`](../lib/src/native/resqlite_bindings.dart).
Add one top-level `final` slot pointer near `executeWrite()`:

```dart
final ffi.Pointer<ffi.Uint8> _writeResultBuf =
    calloc<ffi.Uint8>(_writeResultSize);
```

Replace the per-call `calloc<ffi.Uint8>(_writeResultSize)` inside
`executeWrite()` with `_writeResultBuf` and remove the matching
`calloc.free(resultBuf)` in the `finally` clause. The ByteData decode stays
byte-for-byte identical (exp 214 already rejected changing that half of the
path). This mirrors exp 211's pattern: `queryBytes` uses `_queryBytesOutBuf`
/ `_queryBytesOutLen` / `_queryBytesOutRowCount` at file scope, shared
across all reader-worker `selectBytes()` calls on the same isolate.

Correctness rests on three invariants:

- **Single-threaded writer isolate.** The writer isolate's message handler
  runs to completion before the next request is delivered
  ([`write_worker.dart`](../lib/src/writer/write_worker.dart)). `executeWrite`
  reads both scalar fields inside the same synchronous FFI-return frame
  before the handler yields, so a second `executeWrite` call cannot race the
  slot.
- **No stale-value observation.** On `rc == 0`, `resqlite_execute` writes
  both `affected_rows` and `last_insert_id` before returning; on `rc != 0`
  the Dart caller throws before reading the slot, so a previous successful
  call's values cannot leak into an error frame. The `_handleMultiExecute`
  loop reads the `WriteResult` into an `outcomes` list before the next
  `executeWrite` call runs, so back-to-back invocations are equally safe.
- **Lifetime cost.** The slot is a top-level `final` initialized on first
  read, so isolates that never call `executeWrite` never allocate it. The
  standing cost is 16 bytes per writer isolate.

## Results

Raw pair tables (four A/B passes, medians and mins/maxes) are recorded in
[`benchmark/results/2026-07-04T11-13-17Z-exp215-persistent-write-result-slot.md`](../benchmark/results/2026-07-04T11-13-17Z-exp215-persistent-write-result-slot.md).

Candidate vs matching-pair baseline, negative = candidate faster:

| Shape | P1 (b -> c) | P2 (c -> b) | P3* (b -> c drifted) | P4 (b -> c rerun) |
|---|---:|---:|---:|---:|
| noop update  | +1.5 % | -0.9 % | -25.4 %* | -4.2 % |
| point update | -0.5 % | -2.2 % | -12.1 %* | -4.1 % |
| param update | -0.1 % | -3.3 % |  -5.3 %* | -5.2 % |

*Pair 3's baseline pass shifted well above the other three baseline
passes (noop median 9.115 vs 6.5-6.8 elsewhere), so pair 3 is a
system-drift outlier and does not enter the verdict.*

The candidate `us/call` medians are stable across all four pairs (noop
6.54-6.80, point 13.94-14.30, param 13.99-14.19); it is the baseline that
jitters. Pairs 2 and 4 both show all three shapes candidate-faster in a
coherent 0.9-5.2 % band — the pattern a real ~200 ns per-call mechanism
should produce. Pair 1 does not reproduce that pattern: the no-op-update
lane goes the *wrong* direction (+1.5 % candidate-slower), which is exactly
the shape a fixed-cost mechanism should show its **largest** relative win
on. When the lane most sensitive to the mechanism cannot reproduce
same-sign across the primary order-flipped pair, the mechanism has not
cleared the harness floor.

## Decision

**Rejected.** Do not keep the persistent 16-byte writer-result buffer.

The mechanism removes one native heap `calloc` / `free` pair per
`Database.execute()` call — structurally sound and analogous to exp 211 —
but the deltas do not reproduce same-sign across the primary order-flipped
pair (P1 + P2). Cleaner-condition passes (P2, P4) each show a coherent
candidate-faster shape, but P1 flips the sign on the lowest-baseline lane;
that inconsistency is the exp 214 pattern on this same harness.

Together with exp 214 — which rejected the mirror change on the *other*
half of the path (direct pointer read instead of the ByteData decode) — this
closes both Dart-side writer-result micro-optimizations on
`write_result_direct_read.dart`. The 6.5-14 µs writer floor is not
calloc-limited or view-limited on the shapes this harness measures; the
remaining wall is SQLite step, isolate transport, and Dart-side param
handling.

**Would reopen if:** (a) a lower-noise writer harness surfaces where
the ~200 ns per-call mechanism cleanly clears the floor, or (b) a workload
appears where writer-result decode is a larger share of wall time
(long-lived hot single-writer paths where the exp 159 pipelining has already
compressed everything else). Exp 095's release-suite verdict, exp 214's
decode rejection, and exp 215's scratch rejection now form a consistent
`writer-result path is not the next lever` signal — future runners should
look up-stream at param encoding or isolate dispatch rather than at another
`executeWrite` micro-change.

## Test plan

- [x] `dart pub get`
- [x] `dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart`
- [x] `dart test test/database_test.dart` (53/53 pass)
- [x] `dart test test/database_test.dart --name 'execute INSERT returns affected rows and last insert ID|execute UPDATE returns affected rows|execute DELETE returns affected rows|execute DDL returns zero affected rows'` (4/4 pass)
- [x] `dart test test/transaction_test.dart --name 'db.execute without parameters returns accurate affectedRows and lastInsertId'` (1/1 pass)
- [x] Focused order-flipped A/B with
      `benchmark/experiments/write_result_direct_read.dart` (four passes; see
      Results)
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/215-persistent-write-result-slot.md`
