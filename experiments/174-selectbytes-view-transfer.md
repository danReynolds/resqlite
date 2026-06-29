# Experiment 174: selectBytes native-view transfer (drop the bytes sacrifice)

**Date:** 2026-06-15
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused A/B (`benchmark/experiments/large_bytes_transfer.dart`), candidate vs baseline (`read_worker.dart` swap), quiet machine, order-flipped passes; the release-suite guard for this path is the exp 175 `selectBytes() large bytes` row.

## Problem

The reader pool transfers small results (`< 256 KB`) by `SendPort.send` (the VM
deep-copies) and large results by the **sacrifice** path — `Isolate.exit(port,
payload)` hands the message to the main isolate zero-copy, then the reader
isolate dies and the pool respawns it (exp 019). The 256 KB threshold trades
copy cost against respawn cost.

That trade is correct for the **rows** `select()` path: the payload is a
`ResultSet` of already-built Dart objects, so `Isolate.exit` transfers thousands
of objects with **no re-copy** — the whole point.

But the same size threshold is applied to **`selectBytes`**, and there it is
counterproductive. The JSON lives in the reader connection's persistent native
`json_buf`. To hand it to `Isolate.exit` the worker must first
`Uint8List.fromList`-copy it onto the Dart heap (native memory can't be
transferred as owned). So for bytes:

- **Sacrifice path (`> 256 KB`):** `fromList` (1 copy) + `Isolate.exit` (no copy)
  **+ a reader respawn**. The zero-copy transfer saves nothing — the `fromList`
  copy was forced — so all the sacrifice buys is the respawn cost.
- **Non-sacrifice path (`< 256 KB`):** `fromList` (copy 1) + `SendPort.send`
  (copy 2) = the bytes are copied **twice**.

## Hypothesis

For `selectBytes`, sending a `Uint8List` **view** over the native `json_buf`
directly is strictly better at every size: `SendPort.send` snapshots the bytes
once (the one mandatory copy), and the reader stays alive (no respawn). So
`selectBytes` should never sacrifice and never pre-copy.

Soundness check (load-independent): a native-backed `Uint8List` view sent across
a `SendPort`, with the native memory mutated immediately after send, arrives as
an intact isolated copy — confirming the VM copies at send time and the view is
safe to send. The reader handler is single-threaded, so `json_buf` is stable
from `queryBytes` return through the send.

## Approach

`lib/src/reader/read_worker.dart`:

- `executeQueryBytes`: returns `result.ptr.asTypedList(result.length)` (a view
  over the connection's persistent `json_buf`) instead of
  `Uint8List.fromList(...)`. Doc'd as a transient view — send immediately,
  never retain.
- `SelectBytesRequest` case: `sacrifice = false` unconditionally; `result` is the
  view. The sacrifice machinery is untouched and still serves the rows path.

Net code removal; no public API change; no main-isolate work added (consistent
with the library's "minimize main-isolate work" principle — decode still never
happens on main for bytes; the bytes are the result).

## Results

Focused A/B (`large_bytes_transfer.dart`), order-flipped passes on a quiet box:

| lane | candidate (view-send) | baseline (sacrifice / 2-copy) | delta |
|---|---:|---:|---:|
| **large bytes (651 KB result)** | 269 / 269 / 271 µs/query | 487 / 482 / 480 µs/query | **−44 % (~1.8×)** |
| small bytes (64 KB result, < 256 KB) | 93 / 94 / 93 µs/query | 96 / 97 / 97 µs/query | **−4 %** |

(Three order-flipped passes each; per-pass medians shown.) The large-bytes win
is structural — an eliminated isolate respawn (ms-scale) — and reproduces to
within ±1 % across flipped passes, so it survives a loaded machine unlike a
sub-noise micro-opt (the same A/B run earlier at load ~5 still showed −47 %). The
small-bytes path drops one ~64 KB memcpy of two; that is a small fraction of the
~95 µs/query JSON-gen + round-trip, but on a quiet box it shows a consistent
−4 % across all three passes (no regression, modest win).

### Honest cost — bounded memory high-water

Not sacrificing means readers are no longer respawned, so each reader's heap and
`json_buf` reach a steady-state high-water instead of being reset. Measured
~+15 MB RSS vs baseline after 200 × 651 KB queries (4-reader pool). This is a
**bounded high-water, not a leak** — `json_buf` is reused (reset, not
reallocated) and the remainder is reclaimable GC high-water; it plateaus at the
working set of the largest concurrent byte results.

## Decision

In Review — touches `lib/`, so it gets a human glance per the disposition policy.
Strong win on large byte payloads (the workload `selectBytes` exists for:
forwarding large JSON without materializing rows), neutral on small, net code
simplification, no API change.

## Considered and rejected: true zero-copy transfer

The natural "go further" is to copy zero bytes across the port: `malloc` a
**fresh** native buffer per query, send only `(address, len)`, and wrap it on
main with a `NativeFinalizer` (GC frees the native memory) — the manual
native-memory analogue of what `Isolate.exit` does for Dart objects.

Measured it (`benchmark/experiments/transfer_mechanism_ab.dart`, 651 KB,
round-trip per query, three order-flipped passes, B given its **best** case of
explicit `free` rather than a finalizer):

| pass | A: current (one copy) | B: zero-copy (address + free) | B/A |
|---|---:|---:|---:|
| 1 | 362.7 µs | 337.3 µs | 93 % |
| 2 | 305.8 µs | 367.3 µs | 120 % |
| 3 | 318.7 µs | 335.4 µs | 105 % |

**Worse than the current one-copy path, at every size — no crossover.** A size
sweep (256 KB → 64 MB) had B **14–24 % slower** throughout, widening at the
extremes:

| payload | A: copy (reused buf) | B: zero-copy (fresh buf) | B/A |
|---|---:|---:|---:|
| 256 KB | 140.7 µs | 173.4 µs | 123 % |
| 1 MB | 578.8 µs | 661.8 µs | 114 % |
| 4 MB | 2302.7 µs | 2629.0 µs | 114 % |
| 16 MB | 8728.9 µs | 10484.8 µs | 120 % |
| 64 MB | 33841.1 µs | 42095.1 µs | 124 % |

The decisive factor is **buffer reuse, not the copy.** A reuses one warm
`json_buf` (pages already faulted, no allocator calls); B must `malloc` a
**fresh** buffer per query — per-query `mmap`/`munmap` syscalls + cold-page
faults that scale with size — and that costs *more* than the `memcpy` it saves.
And reuse is fundamentally incompatible with zero-copy: handing the buffer to
main means it can't be reused, and it can't be safely recycled either, because
the caller can retain the returned `Uint8List` indefinitely (a recycled buffer
would corrupt a held reference). So **the copy is the price of keeping the
buffer reusable, and reuse wins at every size** — the single copy is the floor,
structurally. (Real B is worse still: `NativeFinalizer` GC overhead, GC-timed
native memory pressure, and a cross-isolate raw-pointer ownership protocol.)
**Do not reopen** without a fundamentally different mechanism (e.g. a recycled
*warm* native transfer-buffer pool with cross-isolate finalizer recycling —
complex, GC-timing-dependent, and unbounded under load).

## Future Notes

- The existing release lane "Select → JSON Bytes / 1000 rows" is a small result
  (< 256 KB) → it will show this as neutral. A **large-byte release lane** should
  be promoted (exp 161 pattern) so the win is visible and guarded in CI.
- If a memory-sensitive workload shows problematic `json_buf` retention, reopen
  with a **high memory-reclaim threshold** for bytes (sacrifice only above, e.g.,
  8 MB, purely to free a pathologically large `json_buf`) or a C-side `json_buf`
  shrink-after-large — preserving the view-send win for the realistic large
  range while bounding retention.
- The rows `select()` path intentionally keeps sacrifice — there the zero-copy
  object transfer is real.
