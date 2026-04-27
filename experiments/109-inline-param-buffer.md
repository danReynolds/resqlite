# Experiment 109: Inline-packed parameter buffer

**Date:** 2026-04-27
**Status:** Accepted

## Problem

`allocateParams` (in `lib/src/native/resqlite_bindings.dart`) currently
issues one native allocation per text/blob parameter on top of the
reusable struct buffer:

```dart
} else if (value is String) {
  final encoded = value.toNativeUtf8();          // calloc(N+1) per text param
  ...
  byteData.setInt32(offset + 16, -1, ...);        // signal: SQLite must strlen
} else if (value is Uint8List) {
  final blob = calloc<ffi.Uint8>(value.length);   // calloc(N) per blob param
  ...
}
```

`freeParams` then does N `calloc.free` calls plus one buffer release.
For a query with K text params, the path is `1 + K` allocations and
`1 + K` frees per call — and SQLite separately calls `strlen` on every
text bind because `text.len` is `-1`.

The struct buffer itself has been a single reused 64 KB allocation since
exp 070 (the `_reusableParamStructBuf` in `request_cache.dart`); only
the per-string and per-blob byte buffers remain unbatched.

## Hypothesis

Pack the text/blob bytes inline at the tail of the same buffer that
holds the param structs. Layout becomes
`[struct_0 .. struct_N][text_0 bytes][blob_1 bytes][text_2 bytes] ...`,
with each struct's `text.data` / `blob.data` pointer carrying the
address of its slice inside the buffer.

Because the worker that calls `allocateParams` is single-threaded and
owns the bound stmt for the entire FFI exchange (`acquire → step* →
reset`), `SQLITE_STATIC` pointers into the buffer remain valid for as
long as SQLite needs them. The buffer is only ever reused on the
*next* call.

Two side benefits compose with the main change:

1. The actual UTF-8 byte length is known after `utf8.encode`, so it can
   be written to `text.len` directly. SQLite skips its internal
   `strlen` walk on every text bind.
2. Inline bytes don't need null termination — `sqlite3_bind_text`
   reads exactly `len` bytes when `len >= 0`.

Expected upside: 1 native allocation per query regardless of param
count, plus a per-text-param `strlen` saved inside SQLite. Pattern-
matches the family of "fewer allocations on the hot bind path" wins
that exp 028 (static-bind), exp 070 (zero-row dirty buffer), and
exp 101 (cached tx stmts) belong to.

Expected risk: same single-FFI-exchange ownership assumption that
exp 028 already relies on for SQLITE_STATIC; no new lifetime
assumption. Buffers larger than `_maxReusableParamBufBytes` (64 KB)
fall back to a per-call calloc — still one allocation instead of
`1 + N`, so behavior degrades gracefully for large blobs.

## Research Notes

- Recent rejections (exp 094, 095, 096, 102, 108) all sit in the same
  zone — micro-allocation removals on hot paths whose suite-level
  signal is below noise. Read carefully before adding more.
- SQLite docs explicitly note that passing `-1` for the length argument
  to `sqlite3_bind_text` causes an internal `strlen` walk. The doc
  comment matches the C source in 3.51.3:
  <https://www.sqlite.org/c3ref/bind_blob.html>.
- `package:ffi`'s `String.toNativeUtf8()` allocates `units.length + 1`
  bytes via `calloc`, copies the encoded UTF-8 in, and returns a
  null-terminated pointer. Replacing it with an explicit `utf8.encode`
  + range copy is the same Dart-side work, but lets us reuse the
  param-struct buffer for the bytes and keep the byte length around.
- exp 028 already converted text/blob binds to SQLITE_STATIC, so the
  ownership invariant the new layout depends on is the *same* one
  that has been live since 028 merged.

## Approach

Replaced `allocateParams` with a two-pass packer:

1. Pass 1: `utf8.encode` each string param, collect the resulting
   `Uint8List`s, sum their lengths plus blob lengths into
   `extraBytes`.
2. Pass 2: allocate `structsBytes + extraBytes` from
   `allocateReusableParamStructBuf`, write each struct, and copy
   text/blob bytes into the tail. Each struct's data pointer is
   `bufAddr + dataOffset` where `dataOffset` advances by the byte
   length of the value just written.

`freeParams` collapses to `freeReusableParamStructBuf(buf)` — the
inline layout has nothing left to free per param.

Validation before benchmarking:

```text
dart analyze lib/
dart test test/database_test.dart test/reader_pool_test.dart
```

Both passed.

## Results

Artifacts:

- Baseline: [`benchmark/results/2026-04-27T07-29-26-baseline-for-exp109.md`](../benchmark/results/2026-04-27T07-29-26-baseline-for-exp109.md)
- Candidate: [`benchmark/results/2026-04-27T07-40-26-exp109-inline-param-buffer.md`](../benchmark/results/2026-04-27T07-40-26-exp109-inline-param-buffer.md)

Command:

```text
dart run benchmark/run_release.dart exp109-inline-param-buffer --repeat=5 \
  --compare-to=benchmark/results/2026-04-27T07-29-26-baseline-for-exp109.md
```

**Suite-level: 15 wins, 0 regressions, 138 neutral.**

The wins concentrate on bind-heavy paths exactly where the change
should matter — text-param INSERT workloads:

| Benchmark | Baseline ms | Candidate ms | Delta | Status |
|---|---:|---:|---:|---|
| Write Performance / Single Inserts (100 sequential) | 1.88 | 1.61 | **-14%** | 🟢 Stable win |
| Write Performance / Batch Insert (10000 rows) | 4.21 | 3.68 | **-13%** | 🟢 Stable win |
| Write Performance / Batched Write Inside Transaction | 0.43 | 0.39 | **-10%** | 🟢 Stable win |
| Streaming / No-Streams Write Throughput (200 inserts) | 4.03 | 3.40 | **-16%** | 🟢 Stable win |
| Scaling / 20000 rows / resqlite | 12.24 | 10.88 | **-11%** | 🟢 Stable win |
| Scaling / 10000 rows / resqlite + jsonEncode | 23.92 | 20.78 | **-13%** | 🟢 Stable win |

The Single-Inserts and Batch-Insert wins are the clearest signal: the
INSERT statement binds two parameters per row (`name TEXT`, `value
REAL`), so the per-call savings from one allocation instead of two
(plus `strlen` skipped for the text param) compound across the hot
loop. The Streaming / No-Streams variant routes through the same
`executeWrite` path, which is why it tracks the single-insert delta.

Two non-target wins worth flagging:

- `Concurrent Reads / 4× concurrency`: -66% on a stable run. This
  workload binds an int param only (`SELECT WHERE id = ?`), so the
  bind path itself is not what moved — most likely run-to-run
  variance amplified by the 4× concurrency contention. Reported here
  for completeness; the experiment doesn't claim credit for it.
- `Streaming / Stream Churn (100 cycles)`: -48% but flagged "noisy"
  by the harness (MDE_ci 26%). Same caveat — not a bind-path effect.

**Memory comparison: 1 win, 0 regressions, 14 neutral.** No memory
flags on the target paths. (One drift batch-insert win was incidental,
unrelated to the change.)

`Parameterized Queries / 100 queries × ~500 rows each` moved from
15.15 → 14.48 ms (−4.4%, MDE_ci 3.1%). Below the 10% decision
threshold so the harness reports neutral, but the direction matches
the rest of the bind-path wins. Each parameterized query binds a
single text param, so the per-call savings are smaller than on a
two-text-param INSERT.

## Decision

**Accepted.**

The bind-heavy paths show consistent ~10-16% wall-clock wins with
zero regressions and no memory flags. The wins are exactly where the
hypothesis predicted — `executeWrite` and `executeBatchWrite` paths
that bind text params on every call. The changes are localized to
two functions (`allocateParams` / `freeParams`) in
`lib/src/native/resqlite_bindings.dart`, do not change any FFI
contract, and rely on the same single-FFI-exchange ownership
invariant that exp 028 already established for SQLITE_STATIC binds.

This breaks the recent string of micro-allocation rejections (94, 95,
96, 102, 108) by combining two compounding effects in a single change:
fewer native allocations *and* a `strlen` skip per text bind. Either
in isolation would have been at the noise floor; together they're
above it.

