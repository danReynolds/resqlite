# Experiment 236: Reader blob-cell TransferableTypedData transfer

**Date:** 2026-07-21
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/blob_read_transfer_ab.dart`](../benchmark/experiments/blob_read_transfer_ab.dart);
  three order-flipped per-process passes in
  [`benchmark/results/2026-07-21T14-05-00Z-exp236-blob-cell-transfer.md`](../benchmark/results/2026-07-21T14-05-00Z-exp236-blob-cell-transfer.md).
  No release-suite run because no release lane isolates large-blob row reads;
  the focused harness is the durable gate.

## Problem

Exp 234 proved the isolate-hop mechanism for write params: a payload's one
mandatory copy is cheap, but *landing it on the shared GC heap* is not, and
`TransferableTypedData` (TTD) moves malloc'd bytes by ownership transfer. A
survey of the remaining hops found the read side pays worse costs for blob
cells:

- `decodeQuery` copies every blob cell native → heap (`Uint8List.fromList`);
- a result estimated > 256 KB then **sacrifices** the reader isolate
  (`Isolate.exit`): zero-copy, but the worker dies — ~2–5 ms respawn plus
  statement-cache and schema-cache loss, *on every large read*;
- `tx.select` runs on the writer, which can never sacrifice, so large blob
  rows pay the full graph copy back to main with no mitigation at all.

(The survey also established that `selectBytes` is already optimal: it sends
a native-backed view, and the VM copies external typed data into malloc'd
memory — the good destination — which retroactively explains part of
exp 174's win.)

## Hypothesis

Decoding blob cells ≥ 256 KB directly into `TransferableTypedData` — one
native → malloc'd-external copy, skipping the heap copy entirely — lets
blob-dominated results cross the hop by ownership move: no sacrifice, no
respawn, no cache loss, and nothing for the GC to trace. The sacrifice
decision then weighs only the residual (non-transferable) bytes, so
text-heavy results keep sacrificing unchanged.

## Approach

- [`query_decoder.dart`](../lib/src/query_decoder.dart): blob cells ≥
  `blobCellTransferThreshold` (256 KB, matching exp 234's param threshold and
  the sacrifice threshold) decode into TTD in both decode loops;
  `RawQueryResult` carries `transferableBytes`. The threshold is a
  compile-time define (`-DRESQLITE_BLOB_CELL_TRANSFER_THRESHOLD`) because the
  decode loop runs on worker isolates, where a main-isolate runtime toggle
  cannot reach — a const define reaches every isolate identically.
- [`read_worker.dart`](../lib/src/reader/read_worker.dart): sacrifice fires
  on `estimatedBytes - transferableBytes > sacrificeByteThreshold`.
- [`row.dart`](../lib/src/row.dart): internal (unexported)
  `materializeTransferableBlobCells` rewrites TTD cells to `Uint8List` views
  in place at every main-isolate receive boundary —
  [`reader_pool.dart`](../lib/src/reader/reader_pool.dart) `select` /
  `selectWithDeps` / `selectIfChanged` (streams ride these) and
  [`writer.dart`](../lib/src/writer/writer.dart) `selectLocked` (tx.select) —
  so the public surface only ever exposes `Uint8List`. The sacrifice path's
  `Isolate.exit` message may also carry TTDs; the same boundary materializes
  them.
- `selectBytes` untouched (already optimal); no public API change.

## Results

Median µs/select across three order-flipped per-process passes:

| Shape | Δ range | Read |
|---|---|---|
| 1×512 KB blob select | **−80% to −83%** | sacrifice avoided — ~5× faster |
| 1×1 MB blob select | **−70% to −81%** | reproduced |
| 4×300 KB blobs select | **−67% to −82%** | multi-cell shape reproduced |
| tx.select 1×512 KB | **−84% to −87%** | writer hop, ~6–7× faster |
| 200 KB control (direct both lanes) | +2% clean-order | noise |
| 400 KB text control (sacrifices both) | 0% to −11% | unchanged path |
| 20×512 B control | sub-resolution | 24–47 µs lane |

Mechanism attribution (temporary reader-spawn counter, removed before merge,
270 blob reads/lane): baseline **270 spawns**, candidate **0** — the baseline
sacrifices and respawns a reader isolate on every large-blob read, 1:1; the
candidate never does. Interspersing a trivial query between blob reads still
produced 270 baseline spawns, so the respawns do not hide: they outrun the
~4-worker pool's respawn capacity (~2-5 ms each). Each avoided sacrifice is
worth ~410 us even with pool overlap. The magnitude scales with how
blob-read-heavy the workload is relative to pool size.

The 200 KB control initially read +14–20% candidate-slower until pass 3
reordered controls before any wrapped shape: the baseline's sacrifices hand
its later lanes freshly-respawned readers, a cross-lane contamination worth
knowing about when a lane changes worker lifecycle.

Blob-dominated reads ≥ 256 KB are **3–6× faster** because the per-query
isolate death is gone; `tx.select` improves **~6–7×** because it previously
paid the full unmitigated graph copy. Sub-threshold, text-heavy, and small
reads are structurally unchanged.

## Decision

**Accepted (in review).** A contained ~3–7× win on large-blob row reads
across `select()`, streams, and `tx.select`, delivered under the existing
public surface (rows still expose plain `Uint8List`). Correctness covered at
every receive boundary: threshold-edge round-trips, repeated reads on a
long-lived worker, tx.select, mixed text+blob results that still sacrifice
(TTD riding `Isolate.exit`), and stream initial/change emissions.

Would extend to `executeBatch` blob params (exp 234's recorded follow-up) and
revisit the shared 256 KB floor if a production blob-size profile differs;
the multi-medium-blob shape (many cells each < 256 KB summing large) still
sacrifices and is recorded as the next candidate in this lane.

## Test plan

- [x] `dart analyze --fatal-infos` on `lib/` + harness + tests (clean)
- [x] `dart test test/database_test.dart test/stream_test.dart test/transaction_test.dart -j 1` (127/127, incl. 4 new: threshold-edge select round-trip ×3 passes, tx.select, text+blob sacrifice survival, stream initial/change blob emissions)
- [x] Focused A/B, three order-flipped per-process passes with clean-order controls
- [x] `dart run benchmark/finalize_experiment.dart --experiment=experiments/236-blob-cell-transfer.md`
