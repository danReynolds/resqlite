# Experiment 242: TransferableTypedData for the selectBytes result buffer (rejected)

**Date:** 2026-07-22
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused A/B, `selectBytes` end-to-end under
  `--verbose_gc`. Raw table in
  [`benchmark/results/2026-07-22-exp242-selectbytes-ttd.md`](../benchmark/results/2026-07-22-exp242-selectbytes-ttd.md).
  The prototype (a one-line wrap behind a `RESQLITE_SELECTBYTES_TTD` compile
  define) is reverted; this branch keeps only the writeup, fragments, and
  measured result.

## Problem

[Exp 234](234-blob-param-transfer.md) and [exp 236](236-blob-cell-transfer.md)
both won by moving a large payload off the `SendPort` graph copy — which lands
bytes on the shared GC heap — and into malloc'd external memory via
`TransferableTypedData`. `selectBytes` returns a large `Uint8List` too (the
whole JSON result buffer), so the obvious question is whether the same wrap wins
there.

But `selectBytes` is not shaped like the blob paths. Its bytes are **not** a
heap-allocated `Uint8List`: they are `result.ptr.asTypedList(length)` — a view
directly over the reader's native `json_buf` (a per-reader malloc'd C buffer,
reused across queries). That view must be snapshotted before the next query
overwrites `json_buf`, and today that snapshot *is* the single mandatory
`SendPort.send` copy of the `(bytes, rowCount)` record. So the question is
sharper: does sending that native-backed view land its copy on main's GC heap
(then a TTD wrap would win, like the blob paths), or does the one copy already
go somewhere a wrap can't improve?

## Hypothesis

If the graph copy of the native-backed view lands on the GC heap, wrapping the
view in `TransferableTypedData` before send should reproduce the exp 234/236
win — forcing the copy into external memory the GC never traces. If it does not
help, that tells us the existing single send-copy is already the floor for this
path.

## Approach

Prototype behind a default-off `kSelectBytesTtd`
(`RESQLITE_SELECTBYTES_TTD`) define: on the reader, wrap the `json_buf` view in
`TransferableTypedData.fromList([bytes])` instead of returning it directly;
on the main isolate, materialize it back to `Uint8List` in `ReaderPool` so the
public `BytesResult` stays `Uint8List`. A/B both lanes end-to-end across JSON
sizes spanning the 256 KB new-space cap (142 KB, 362 KB, 731 KB), under
`--verbose_gc`.

## Results

Median `selectBytes` round-trip, µs:

| rows | JSON KiB | view (current) | ttd |
|---:|---:|---:|---:|
| 2000  | 142 | 297.3 | 305.3 |
| 5000  | 362 | 700.1 | 702.0 |
| 10000 | 731 | 1391.7 | 1742.3 |

The TTD lane is **neutral-to-worse at every size** — dead even in the 142–362 KB
range and ~25% *slower* at 731 KB. Main-isolate GC did not improve; both lanes
sat in the same steady stream of tiny `Scavenge(external)` collections
(sub-0.2 ms pauses), with no heap-pressure difference for the wrap to relieve.

The mechanism explains the null. Unlike a heap `Uint8List` blob param, the
`selectBytes` bytes are already a view over native external memory. The current
path pays exactly one copy — the send that snapshots the view before `json_buf`
is reused. Wrapping in TTD does **not** remove that copy; it *relocates* it to a
`fromList` memcpy into a fresh external buffer on the reader, then adds malloc +
finalizer bookkeeping and an ownership move on top. Same one copy, extra
machinery — so at large sizes it loses by the machinery, and at small sizes it
breaks even.

## Outcome

**Rejected.** `selectBytes`' single send-copy of the native-backed `json_buf`
view is already the floor for this path; forcing an external destination via
`TransferableTypedData` adds a copy's worth of machinery without removing a copy.
This is the opposite of the blob-param/blob-cell result, and the difference is
exactly the source of the bytes: a heap `Uint8List` (blobs) has a GC-heap
destination a wrap can escape; a native-backed view (`selectBytes`) does not.

Would reopen only if `selectBytes`' source representation changed — e.g. if the
JSON buffer ever became a heap `Uint8List` rather than a native `json_buf` view,
restoring the GC-heap destination that makes the wrap pay. As long as
`selectBytes` returns a native view, this direction is closed. See also the
cross-isolate transfer arch note for the "read cell vs read buffer" distinction.
