# Experiment 246: Slot-count sacrifice trigger — fix the string misroute

**Date:** 2026-07-23
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused end-to-end A/B; raw table in
  [`benchmark/results/2026-07-23-exp246-slot-sacrifice.md`](../benchmark/results/2026-07-23-exp246-slot-sacrifice.md).
  The A/B was driven by a temporary byte-vs-slot compile toggle and a sacrifice
  counter; both were removed with the byte machinery once the result settled, so
  the shipped tree carries only the slot-count path (see Outcome).

## Problem

The reader sacrifices a row result (`Isolate.exit`, zero-copy, at the cost of a
reader respawn) when its **estimated bytes** exceed 256 KB.
[Exp 245](245-prepared-result-handoff.md) measured the intrinsic transfer and
showed the byte trigger asks the wrong question: `SendPort.send`'s cost tracks
the **mutable flat-list slot count** (rows × columns), not payload bytes —
strings and other immutable leaves are *shared* on send for free. So a result
that is large in *bytes* but small in *slots* — a handful of rows with a big
`TEXT`/`BLOB` column (base64 blobs, large JSON/text documents) — is cheap to send
yet gets **sacrificed**, paying a reader respawn for a copy that never happens.

## Hypothesis

Route the sacrifice decision on **mutable slot count** (`raw.values.length`)
instead of estimated bytes. A slot threshold of `32 * 1024` is the exact
all-integer equivalent of the old 256 KB byte threshold (8 bytes/cell), so
numeric/structural results keep their prior routing, while string-heavy results
stop being misrouted. Slot count is also *free* — it is the flat list's length,
no per-cell accounting.

## Approach

A single `_shouldSacrifice(raw)` helper backs all three row-result decision
sites, routing on `raw.values.length > sacrificeSlotThreshold`
(`32 * 1024`, a compile-time define so a benchmark can force either lane).
`selectBytes` still never sacrifices (unchanged).

During the A/B the byte path was kept behind a `RESQLITE_SLOT_TRIGGER` toggle and
a `ReaderPool.debugSacrificeCount` counter proved the routing flipped. Both were
**removed** once the result settled, along with the byte machinery they existed
to serve: `sacrificeByteThreshold`, `RawQueryResult.estimatedBytes`, and the
decoder's per-cell `byteEstimate` accumulation — which had no remaining readers
once routing moved to slot count. The net change is a **simplification**: the
decision is one comparison against a value the flat list already knows
(`values.length`), and the decode loop no longer maintains a byte tally.

The threshold is **end-to-end** ~32k, deliberately *below* exp 245's ~48k
*intrinsic* crossover: exp 244 showed the send-side copy sits on the worker's
critical path, so at the production pool the crossover where sacrifice becomes
favorable arrives earlier. 32k reconciles both — it matches the byte trigger for
numeric results (validated below) and fixes strings.

## Results

Median end-to-end `select` latency and sacrifices per select (M1 Pro):

| shape (slots / bytes) | bytes trigger | slot trigger @32k | routing |
|---|---|---|---|
| bigstr — 4 slots / ~400 KB | 131.0 µs · **1.00 sac** | **91.3 µs · 0.00 sac** | **fixed → send** |
| band — 40k slots / ~320 KB | 1462 µs · 1.00 | 1467 µs · 1.00 | parity (sacrifice) |
| large — 200k slots / ~1.6 MB | 6328 µs · 1.00 | 6089 µs · 1.00 | parity (sacrifice) |
| medium — 20k slots / ~160 KB | 800 µs · 0.00 | 780 µs · 0.00 | parity (send) |
| small — 400 slots | 17.6 µs · 0.00 | 16.3 µs · 0.00 | parity (send) |

The **bigstr misroute is fixed**: a 4-row × 100 KB-string result stopped
sacrificing (1.00 → 0.00 per select) and got **31% faster** (131 → 91 µs) — every
such read previously killed and respawned a reader for nothing. Every other shape
is byte-for-byte the same routing at parity latency.

Threshold choice is measured, not guessed. A first pass at the ~48k intrinsic
crossover **regressed the band** (40k slots sent → +12%, 1462 → 1640 µs), because
end-to-end the send copy is on the worker's critical path (exp 244) so sacrifice
wins below 48k. Dropping to 32k = the byte trigger's all-int equivalent restores
band parity while keeping the string fix — the best of both.

## Outcome

**Accepted.** This is the one shippable win of the send-vs-sacrifice arc
(exp 241 confound → exp 244 pool → exp 245 intrinsic → this). Routing on slot
count fixes the string/shared-leaf misroute — large-`TEXT`/`BLOB` reads no longer
sacrifice and respawn a reader on every call, eliminating that reader churn (and
its connection re-open / WAL-pin churn) for a 31% latency win on those reads —
while leaving numeric/structural routing exactly where the (well-tuned) byte
threshold had it. The byte machinery is **deleted**, not deprecated — routing on
slot count leaves it with no readers, so the change removes more code than it
adds.

Interaction: [exp 236](236-blob-cell-transfer.md) (#253) subtracts
`transferableBytes` from the byte estimate so TTD-wrapped blob cells don't force a
sacrifice. Under slot-count routing that subtraction is moot — blob *size* no
longer influences the decision at all. Exp 236's blob-cell TTD wrapping stands on
its own merits; its sacrifice-decision arithmetic is superseded here. Whichever
lands second should drop the byte-based decision rather than maintain two notions
of result size.
