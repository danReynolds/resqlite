# Experiment 243: Shared-wrapper (table protocol) for aliased blob write params

**Date:** 2026-07-22
**Status:** Accepted
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none — focused
  [`benchmark/experiments/alias_transfer_isolated.dart`](../benchmark/experiments/alias_transfer_isolated.dart)
  (isolated transport round-trip, one 300 KB buffer referenced N times, three
  wrapping shapes); raw table in
  [`benchmark/results/2026-07-22-exp243-blob-alias-table.md`](../benchmark/results/2026-07-22-exp243-blob-alias-table.md).
  No release-suite lane isolates aliased-blob parameter transport; the focused
  harness plus the round-trip correctness tests are the durable gate.

## Problem

[Exp 234](234-blob-param-transfer.md) wraps each large blob write param in its
own `TransferableTypedData` so the main→writer hop lands in malloc'd external
memory instead of on the GC heap. But `wrapBlobParams` walked the param list
position by position, calling `TransferableTypedData.fromList([value])` at every
qualifying slot **independently**. When a caller hands the *same* `Uint8List`
object to more than one position, exp 234 duplicated that one buffer into N
separate external copies.

That is a latent regression exp 234 introduced. For an aliased buffer,
per-occurrence wrapping is strictly *worse* than the graph copy it replaced: the
VM's object-graph copy preserves reference identity and would have copied the
shared buffer once, whereas per-occurrence wrapping pays N `fromList` memcpys and
holds N live external buffers until the writer materializes them.

There are two ways one buffer reaches the writer N times in a single send:

1. **Same object in N params of one write** —
   `db.execute('INSERT INTO t(a, b) VALUES (?, ?)', [blob, blob])`.
2. **Same object reused across the writes of a coalesced burst** — the exp 180
   pump folds concurrent standalone writes into one `MultiExecuteRequest`; a
   caller looping `db.execute(sql, [sharedBlob])` feeds one buffer into many
   writes of the same envelope.

## Hypothesis

Wrap by **identity**: share one `TransferableTypedData` per unique backing
buffer, referenced at every position it occurs. Because `SendPort.send`'s graph
copy preserves identity, a shared wrapper crosses the hop exactly once; the
writer materializes it once (a second `materialize()` on the same wrapper
throws) and substitutes the resulting view at every reference.

This "table protocol" should recover the aliasing regression *and* beat both
alternatives on the table:

- the exp 234 **baseline** (per-occurrence: N wrappers, N external copies), and
- a **census** alternative that leaves aliased buffers on the graph-copy path
  (one copy, but back onto the GC heap via the chunked slow path).

## Approach

All changes are in the existing write-side transfer helper; the fast path (no
qualifying blob) still returns the input list unchanged with no allocation.

- `_wrapShared` — wrap each large blob through an identity-keyed cache
  (`HashMap(equals: identical, hashCode: identityHashCode)`):
  `out[i] = cache[value] ??= TransferableTypedData.fromList([value])`. Distinct
  buffers each get their own wrapper (unchanged common case); an aliased buffer
  reuses its single wrapper at every position.
- `wrapBlobParamsGroup` — the coalesced-envelope variant shares **one** cache
  across all the group's writes, so a buffer reused across writes crosses as a
  single wrapper referenced by every occurrence.
- `unwrapBlobParams(params, [cache])` — materialization dedups by wrapper
  identity. A single param list makes a local cache; `_handleMultiExecute`
  passes one shared cache across the envelope's writes so an envelope-shared
  wrapper is materialized **exactly once** (a second `materialize()` would
  throw).

The A/B toggle used during development (`RESQLITE_BLOB_ALIAS_SHARE`) is removed;
the accepted code does the table protocol unconditionally. The three shapes are
compared directly inside the transport harness rather than through a build flag.

## Results

Transport round-trip in microseconds, one 300 KB buffer referenced N times, on
an Apple M1 Pro / macOS box:

| N | census (1 graph copy, heap) | baseline (N TTD) | **table (1 TTD ×N)** |
|---:|---:|---:|---:|
| 1  | 196.2 | 44.4 | **32.9** |
| 2  | 179.6 | 49.6 | **27.0** |
| 4  | 171.6 | 70.8 | **28.2** |
| 8  | 190.9 | 132.0 | **33.8** |
| 32 | 209.0 | 1502.7 | **56.5** |

The table protocol is **flat and fastest at every N**. The other two each fail a
different way:

- **baseline** is fine at N=1 (44 µs) but scales linearly — one external memcpy
  per occurrence — reaching **1.5 ms at N=32** (~27× the table lane). This is the
  regression the experiment fixes.
- **census** is flat but slow (~180–210 µs regardless of N): a large *heap* blob
  aborts onto the object-graph copier's chunked slow path
  (`CopyTypedDataBaseWithSafepointChecks`), and it re-lands the payload on the GC
  heap — exactly the cost exp 234 exists to avoid. One copy, but the expensive
  kind.

Table wins because it takes the *single* copy of baseline's fast route (one
`fromList` into external memory) and the *shared-once* transport of census, with
neither downside. It even edges out baseline at N=1 (32.9 vs 44.4 µs) — the same
single wrap, so the gap is harness noise, not a real N=1 difference. Beyond
transport wall time it also collapses **peak external memory** from N live
buffers to one.

## Outcome

**Accepted.** The table protocol fixes the exp 234 aliasing regression and is the
strictly-best of the three wrapping shapes. It changes nothing for the
overwhelmingly common single-reference write (identical to exp 234 — one buffer,
one wrapper); it only helps when a caller references the same ≥256 KB buffer more
than once in a write or across a coalesced burst, where it turns a linear
per-occurrence blowup into a single shared transfer.

Would reopen the *census* direction only if a future VM change made the
heap-typed-data graph copy take a fast unchunked path for large buffers — then
"leave it on the graph copy" would stop paying the slow-path tax and could rival
table without any wrapper bookkeeping. Nothing today points that way.

## Not applicable to the read side

Reads need no equivalent. A read response's blob cells are distinct materialized
objects with no caller aliasing to collapse — there is no "same object N times"
shape to dedup. [Exp 236](236-blob-cell-transfer.md) handles read-cell transfer;
the table protocol is a write-envelope concern only.
