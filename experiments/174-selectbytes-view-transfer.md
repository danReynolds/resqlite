# Experiment 174: selectBytes native-view transfer (drop the bytes sacrifice)

**Date:** 2026-06-15
**Status:** In Review
**Direction:** `result-transfer-shape`
**Benchmark Run:** Focused A/B (`benchmark/experiments/large_bytes_transfer.dart`), candidate vs baseline (`read_worker.dart` swap), quiet machine, order-flipped passes.

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

- `executeQueryBytes` → `executeQueryBytesView`: returns
  `result.ptr.asTypedList(result.length)` (the native view) instead of
  `Uint8List.fromList(...)`. Documented lifetime contract: send immediately,
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
