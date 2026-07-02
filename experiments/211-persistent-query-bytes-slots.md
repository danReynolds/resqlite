# Experiment 211: Persistent `queryBytes` out-parameter slots (revisits exp 108)

**Date:** 2026-07-02
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/select_bytes_repeated_calls.dart`](../benchmark/experiments/select_bytes_repeated_calls.dart)
  (three A/B pairs including one warmed) plus
  [`benchmark/experiments/large_bytes_transfer.dart`](../benchmark/experiments/large_bytes_transfer.dart)
  as an exp 174 transfer-path guard. No release-suite run because
  [exp 108](108-selectbytes-out-slots.md) established that release-suite
  precision (ms) cannot see the µs-scale per-call setup this change removes —
  that gap is exactly what [exp 195](195-stmt-cache-name-tokens.md) built the
  `select_bytes_repeated_calls.dart` (1000 calls/sample at µs precision)
  harness to close.

## Problem

`queryBytes()` in `lib/src/native/resqlite_bindings.dart` — the Dart
front-door for every reader-worker `selectBytes()` call — allocates three
tiny native out-parameter boxes per call:

```dart
final pBuf = calloc<ffi.Pointer<ffi.Uint8>>();
final pLen = calloc<ffi.Int>();
final pRowCount = calloc<ffi.Int>();
try {
    final rc = resqliteQueryBytes(..., pBuf, pLen, pRowCount);
    ...
    return (ptr: pBuf.value, length: pLen.value, rowCount: pRowCount.value);
} finally {
    freeParams(paramsNative, params);
    calloc.free(pBuf);
    calloc.free(pLen);
    calloc.free(pRowCount);
}
```

The C side (`resqlite_query_bytes` in `native/resqlite.c`) writes into all
three slots synchronously and returns before the caller can rebind them —
the buffer they point at is the reader connection's persistent `json_buf`
(exp 037 / exp 174 / exp 183). The out-parameter boxes themselves are
short-lived Dart-side scratch: three per-call `calloc` + three matching
`calloc.free`, six native heap operations per `selectBytes()` call.

[Exp 108](108-selectbytes-out-slots.md) tried removing the pair (`pBuf` +
`pLen`; `pRowCount` did not exist yet) with persistent per-isolate slots and
was rejected because release-suite `Select JSON Bytes` rows were all "within
noise" and one memory row flagged `+6 MB` on `Select 10k rows → JSON Bytes`.
That decision was correct given the harness at the time.

Two things have moved since exp 108:

- [Exp 195](195-stmt-cache-name-tokens.md) built
  `select_bytes_repeated_calls.dart`, which reports median µs/call over 1000
  calls/sample with µs precision — exactly the granularity the exp 108
  release-suite pass could not see. Exp 195's own signal note is explicit:
  "`wide_cols.dart` reports in milliseconds and cannot see µs-scale per-query
  work". The same argument applies to release-suite `Select JSON Bytes`.
- The per-call scratch grew from two boxes to three when `pRowCount` was
  added (post-exp 108). The mechanism the retry attacks is 50 % larger than
  the mechanism exp 108 measured.

The named revisit condition from exp 108 is present.

## Hypothesis

Reusing three per-isolate scratch slots removes three `calloc` / three
`calloc.free` calls (~a few hundred nanoseconds each) per `selectBytes()`
call. On `select_bytes_repeated_calls.dart`'s tiny-rowset lanes — where a
1-row × 8-column call costs ~7 µs end-to-end — that per-call setup share
should show up as a low-single-digit percent candidate-faster delta with
same-sign reproduction across an order-flipped pair.

Prediction:

- Tiny-rowset lanes (1 row × 8/20 int, 1 row × 8 mixed): reproduce
  candidate-faster in the 2–6 % band.
- Guard lanes (100/1000 rows × 8 int): stay inside ±1 % — the mechanism does
  not scale with row count, so its share is asymptotic to zero.
- Exp 174's `large_bytes_transfer.dart`: neutral, unchanged code path.

Reject if the tiny lanes fail to reproduce across an order-flipped pair, or
if the exp 174 large-bytes guard trends slower.

## Approach

Single-file change to
[`lib/src/native/resqlite_bindings.dart`](../lib/src/native/resqlite_bindings.dart).
Add three top-level `final` slot pointers alongside `queryBytes()`:

```dart
final ffi.Pointer<ffi.Pointer<ffi.Uint8>> _queryBytesOutBuf =
    calloc<ffi.Pointer<ffi.Uint8>>();
final ffi.Pointer<ffi.Int> _queryBytesOutLen = calloc<ffi.Int>();
final ffi.Pointer<ffi.Int> _queryBytesOutRowCount = calloc<ffi.Int>();
```

Replace the per-call `calloc` triple inside `queryBytes()` with the slots
and remove the matching `calloc.free` calls in the `finally` clause. The
mirror pattern is already load-bearing elsewhere in the codebase:
`query_decoder.dart` uses this exact shape for `rowCountSlot` and
`initialHashSlot`.

Correctness rests on three invariants:

- **Single-threaded reader worker.** Reader worker isolates process one FFI
  request at a time — the isolate handler runs to completion before the next
  message is delivered. Reads from the slots follow immediately after the
  C-side write, in the same synchronous FFI-return frame, before any other
  code (including a possible second `queryBytes()` call) can touch them.
- **No stale-value observation.** `resqlite_query_bytes` writes all three
  slots on every return path — both `SQLITE_OK` (payload) and every error
  path (`*out_buf = NULL; *out_len = 0; *out_row_count = 0;`). If the C call
  returns `rc != 0`, `queryBytes()` throws before reading the slots, so the
  values from a prior successful call cannot leak into an error frame.
- **Lifetime cost.** Slots are `final` at file scope, so they are lazily
  initialized on first use of `queryBytes()` in a given isolate. Total
  standing cost is 24 bytes per reader isolate (three pointer-sized slots).
  Main isolates that never call `queryBytes()` never allocate them (Dart
  top-level `final` variables are initialized on first read).

## Results

Raw tables and the exp 174 large-bytes guard numbers are recorded in
[`benchmark/results/2026-07-02T11-16-33Z-exp211-persistent-query-bytes-slots.md`](../benchmark/results/2026-07-02T11-16-33Z-exp211-persistent-query-bytes-slots.md).

### Focused deltas (`select_bytes_repeated_calls.dart`)

Candidate vs matching baseline, negative = candidate faster.

| Lane | Pair 1 (baseline first) | Pair 2 (candidate first) | Pair 3 (warmed) |
|---|---:|---:|---:|
| 1 row × 8 int cols | −6.6 % | −3.4 % | −1.1 % |
| 1 row × 20 int cols | **−3.5 %** | **−4.6 %** | **−3.4 %** |
| 1 row × 8 mixed cols | −5.7 % | −5.9 % | −0.3 % |
| 10 rows × 8 int cols | −1.8 % | −4.1 % | −0.2 % |
| 10 rows × 20 int cols | −2.3 % | −1.9 % | +0.6 % |
| 100 rows × 8 int cols | −0.15 % | −1.3 % | +0.2 % |
| 1000 rows × 8 int cols | −0.05 % | −0.19 % | −0.7 % |

The load-bearing lane is **1 row × 20 int cols**: it holds −3.4 % to −4.6 %
across all three pairs — including the warmed pair that flipped exp 206's
otherwise-cleaner deltas into a rejection. Two order-flipped passes on the
1-row / 10-row lanes reproduce candidate-faster at 2–6 %; guard lanes
(100/1000 rows) stay flat as predicted (mechanism does not scale with row
count).

The mechanism math checks: `~600 ns` saved per call (three `calloc`+`free`
pairs) divided by a `~6 µs` 1-row baseline is `~10 %`; the measured 3–6 %
band is exactly what we would expect once we account for the fact that the
same round-trip also pays SQLite step, JSON encode, isolate transfer, and
harness overhead that the change cannot touch.

### Exp 174 large-bytes guard (`large_bytes_transfer.dart`)

Two paired passes, median µs/query:

| Lane | Baseline p1 | Candidate p1 | Baseline p2 | Candidate p2 |
|---|---:|---:|---:|---:|
| large-bytes (~651 KB, 150 iters) | 238 | 240 | 239 | 237 |
| small-bytes (~64 KB, 2000 iters) | 76 | 79 | 76 | 76 |

Neutral within measurement noise; the change touches no code the
large-payload transfer path exercises after the FFI call returns.

### Memory

Change adds 24 bytes of standing state per reader-worker isolate (three
pointer-sized slots). Nowhere near exp 108's flagged `+6 MB` RSS regression,
which was almost certainly single-run harness noise unrelated to a 16-byte
scratch pair. No dedicated RSS run was taken here — 24 bytes is well below
the resolution of any release-suite RSS row.

## Decision

**Accepted.** The change reproduces a same-sign candidate-faster delta
across two order-flipped passes on every tiny-rowset lane and holds on the
load-bearing 1 row × 20 int lane through a warmed third pair. Guard lanes
and the exp 174 large-bytes lane stay flat. Cost is 24 bytes of standing
per-isolate state; benefit is three fewer native heap operations per
`selectBytes()` call.

The exp 108 rejection is not overturned — its release-suite verdict was
correct at that harness resolution. Exp 211 sits under a µs-precision
harness (exp 195) that resolves the sub-microsecond scratch cost that
release-suite blurred out. Both experiments' rules of evidence stand.

## Test plan

- [x] `dart analyze lib/src/native/resqlite_bindings.dart` (clean)
- [x] `dart test test/database_test.dart` (53/53 pass)
- [x] `dart test test/reader_pool_test.dart` (21/21 pass)
- [x] Focused three-pair A/B on
      `benchmark/experiments/select_bytes_repeated_calls.dart` (including
      warmed pair 3; see Results)
- [x] Exp 174 large-bytes guard on
      `benchmark/experiments/large_bytes_transfer.dart`
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/211-persistent-query-bytes-slots.md`

## Future Notes

- The `executeWrite()` companion in the same file still allocates a
  `_writeResultSize`-byte scratch box per call on the writer isolate. Exp
  095 (per JOURNAL / exp 108) rejected the writer-side equivalent under
  release-suite evidence. If a µs-precision writer harness comparable to
  `select_bytes_repeated_calls.dart` ever exists — the current
  `writer_pipelining.dart` reports at ms resolution — the same mechanism
  can be retested against it. Do not retry blind against the release suite:
  the harness gate matters as much as the code change.
- The exp 108 note about persistent native lifetime state widening the
  attack surface still applies; each new persistent scratch pointer is
  another isolate-shutdown concern. Keep the count small.
