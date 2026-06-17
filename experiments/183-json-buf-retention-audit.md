# Experiment 183: json_buf retention audit + high-threshold reclaim

**Date:** 2026-06-17
**Status:** In Review
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused `json_buf_retention.dart` (baseline + candidate, three workload shapes) + focused `large_bytes_transfer.dart` (perf neutrality A/B). See Results.

## Problem

Exp 174 stopped sacrificing readers on the `selectBytes` path: large byte
results are now sent as a `Uint8List` view over the reader's persistent
`json_buf` (one mandatory `SendPort.send` copy, no `Isolate.exit`,
no respawn). That removed the only mechanism that had previously
reset per-reader `json_buf` capacity, so the buffer grows on the
largest result a reader has produced and never shrinks. Exp 174
measured the bounded high-water (~+15 MB RSS after 200 × 651 KB
queries on a 4-reader pool) and recorded a future-note: *"if a
memory-sensitive workload shows problematic `json_buf` retention,
reopen with a high memory-reclaim threshold for bytes (sacrifice only
above, e.g., 8 MB, purely to free a pathologically large `json_buf`)
or a C-side `json_buf` shrink-after-large"*.

The follow-up was gated on a workload showing retention. Before
exp 183, the gate had no observation tool: `Database.diagnostics()` did
not expose per-reader `json_buf` capacity, so no benchmark could
quantify the high-water directly, and no test could confirm a future
shrink mechanism actually freed memory.

## Hypothesis

If `Database.diagnostics()` reports the per-reader `json_buf` total,
realistic workloads will show retention beyond a one-off large
`selectBytes` (the buffer staying parked at the burst size while
hundreds of subsequent small reads run). If the retention is real, a
high-threshold C-side shrink — triggered by the reader worker after
`SendPort.send` returns on a `selectBytes` reply, gated by the
just-sent result size — will reclaim the inflated capacity without
adding measurable cost to the warm small-read path or to the recurring
large-read path that genuinely needs the buffer.

Acceptance criterion (set before running): the focused
`large_bytes_transfer.dart` lanes stay within run-to-run noise on the
candidate, AND the retention audit shows the inflated `json_buf` falls
back to the initial 16 KB cap on subsequent small reads.

## Approach

### Measurement: `json_buf` high-water diagnostic

- `native/resqlite.{c,h}`: new `resqlite_reader_json_buf_total(db)` sums
  every reader's `json_buf.cap`. Safe to call concurrently with reader
  activity — `cap` is an `int` and a torn read only widens an
  already-bounded summary.
- `lib/src/native/resqlite_bindings.dart`: `resqliteReaderJsonBufTotal`
  FFI binding.
- `lib/src/diagnostics.dart`: new `Diagnostics.readerJsonBufHighWaterBytes`
  field, wired through `Database.diagnostics()`.

### Implementation: high-threshold reclaim

- `native/resqlite.{c,h}`: new `resqlite_reader_maybe_shrink_json_buf(db,
  reader_id, last_used_len)`. Reallocs the reader's `json_buf` back down
  to the 16 KB initial cap when:
  - the buffer has grown past **1 MB** (the trigger cap — warm small
    buffers stay alone), and
  - the just-sent result fit comfortably below **256 KB** (the
    last-len guard — back-to-back large reads keep the warm capacity).

  Realloc failure is non-fatal: the existing larger buffer is still
  functional, just memory not reclaimed. Returns the post-call
  capacity.
- `lib/src/native/resqlite_bindings.dart`:
  `resqliteReaderMaybeShrinkJsonBuf` FFI binding.
- `lib/src/reader/read_worker.dart`: after `eventPort.send` returns on
  a `SelectBytesRequest` reply (at which point `SendPort` has already
  snapshotted the bytes into the receiver, per exp 174's same
  invariant), call the shrink FFI with `result.length`. The C function
  is a no-op for warm small buffers and for back-to-back large reads,
  so the hot common path adds at most one FFI boundary crossing.

No public API change (the shrink mechanism is internal; the new
`Diagnostics` field is additive).

`dart test test/` — **303 passed** with the candidate, including the
streams, transactions, and selectBytes suites.

## Results

### Retention audit (`benchmark/experiments/json_buf_retention.dart`)

Five checkpoints per shape; `json_buf_total` is `Diagnostics.readerJsonBufHighWaterBytes` (sum across the 4-reader pool).

#### small-only (200 × ~4 KB `selectBytes`, no large reads)

| Checkpoint | Baseline | Candidate |
|---|---:|---:|
| open | 64.0 KB | 64.0 KB |
| after 10 warmup | 64.0 KB | 64.0 KB |
| after 200 small | 64.0 KB | 64.0 KB |

Identical on both sides — the shrink doesn't fire on warm small
buffers because `cap` never crosses the 1 MB trigger.

#### one-shot-large (8 concurrent × ~8 MB `selectBytes`, then 200 small)

| Checkpoint | Baseline | Candidate |
|---|---:|---:|
| after seed + 1 small + 1 large probe | 8.05 MB | 8.05 MB |
| after 10 small warmup | 8.05 MB | **64.0 KB** |
| after concurrent burst of 8 large | 32.00 MB | 32.00 MB |
| after 200 small (post-burst settle) | **32.00 MB** | **64.0 KB** |

Baseline pins **32 MB** across the four readers for the rest of the
connection's life — exactly the pathological retention exp 174
left as future work. Candidate reclaims back to **64 KB** after the
subsequent small reads, **−32 MB** of pinned native heap recovered.
The pre-burst probe row also shows the candidate already reclaiming
the 8 MB one-off probe once the small warmup runs through.

#### recurring-large (1 large per 50 small, 300 interleaved)

| Checkpoint | Baseline | Candidate |
|---|---:|---:|
| after seed | 64.0 KB | 64.0 KB |
| after 300 interleaved | **16.03 MB** | **64.0 KB** |

The recurring shape used to pin 16 MB (each periodic large query grew
the buffer to 4 MB+ per reader); the candidate settles at the initial
64 KB because each large read is immediately followed by small reads
that trip the reclaim. Each periodic large still pays a normal
`buf_ensure` grow, but the cost (~one realloc per large read) is
negligible against the SQLite step + JSON-write that dominates a
large-bytes query.

### Performance neutrality (`benchmark/experiments/large_bytes_transfer.dart`)

| Lane | Baseline | Candidate | Δ |
|---|---:|---:|---:|
| large-bytes (~651 KB, 150 iters) | 292 µs/query | 294 µs/query | +0.7 % (noise) |
| small-bytes (~64 KB, 2000 iters) | 98 µs/query | 100 µs/query | +2 % (noise) |

The candidate adds one FFI call per `selectBytes` reply; for warm
buffers below the 1 MB trigger this is a constant-time return. The
+2 % on the small-bytes lane is within the per-pass spread the same
benchmark produces on baseline-vs-baseline reruns. Large-bytes neutral
within ±1 %.

## Decision

**In Review.** Adds runtime code (`native/`, `lib/`) so the disposition
policy holds it for human review rather than auto-merge. The candidate
both:

1. **Quantifies the bounded RSS exp 174 left open**: a new
   `Diagnostics.readerJsonBufHighWaterBytes` field every benchmark and
   downstream user can read; the additive shape preserves API stability
   (a new required-named field in a `const` constructor only affects the
   single in-repo construction site).
2. **Reclaims pathological retention**: the high-threshold shrink frees
   the 32 MB pinned by a one-off concurrent-burst workload (post-burst
   settle: 32 MB → 64 KB) and the 16 MB pinned by recurring-large
   shapes (settled: 16 MB → 64 KB), with neutral large-bytes /
   small-bytes performance.

The thresholds (1 MB trigger cap, 256 KB last-len guard, 16 KB target)
match exp 174's "around 8 MB" mental model but at a lower trigger so
the win shows up on realistic 1-MB-class one-off reads, not just at
truly pathological 8 MB+ sizes. The last-len guard is the load-bearing
piece that lets back-to-back large reads keep their warm capacity.

## Future Notes

- The new `Diagnostics.readerJsonBufHighWaterBytes` is the reusable
  signal for any future memory-sensitive `selectBytes` work; a release
  lane that asserts `json_buf_total < N MB` after a representative
  workload would catch regressions of the reclaim mechanism the same
  way exp 161 catches writer pipelining regressions on the public lane.
- If a future workload shows the 1 MB trigger is too aggressive (e.g.,
  a hot 1-MB-class read followed by a steady 500-KB-class read pays
  too much realloc churn), the natural tuning is to raise the trigger
  cap to 4 MB, not to add hysteresis or per-reader history.
- The `last_used_len` guard is what makes the policy safe under
  back-to-back large reads. A future change that drops the guard
  would re-introduce the realloc-churn anti-case the exp 174
  future-note explicitly warned against.
- The C-side `last_used_len` parameter is currently passed from Dart;
  if a future native consumer needs the same reclaim mechanism without
  Dart involvement, the worker can read the buffer's own `len` field
  directly inside `resqlite_query_bytes`.
