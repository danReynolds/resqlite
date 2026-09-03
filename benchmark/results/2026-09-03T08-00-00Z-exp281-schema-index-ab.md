# Exp 281 — schema index transfer, focused A/B receipt

**Date:** 2026-09-03
**Host:** M1 Pro · macOS 26.2 · Dart 3.12.2 · AOT
**Experiment:** [281 — the lookup table that rides on every read](../../experiments/281-schema-index-transfer.md)

The decision evidence for exp 281. Two harnesses:

- `benchmark/experiments/schema_index_transfer.dart` prices the mechanism with
  no database and no resqlite code — one echo isolate, lanes differing only in
  whether the reply's schema carries a `HashMap`.
- `benchmark/experiments/schema_index_read_ab.dart` is the end-to-end A/B: two
  AOT bundles (`dart build cli`) from separate worktrees, one process per lane,
  41 samples after 8 warmup, three collections of order-flipped passes.

**Host caveat.** Every figure below was captured under sustained OS indexing
load (load average 11–21 throughout). The order-flipped, lane-isolated design
and the two zero-ceiling control lanes are what make the result readable; the
controls put this collection's floor at −10% to +29% on individual processes,
which is why the wide lanes carry the verdict and the point lanes are priced
from the mechanism harness instead.

## 1. Mechanism — what the schema's index costs to send

Two order-flipped passes, 11 samples × 2,000 round trips.

| lane | pass A | pass B |
|---|---:|---:|
| `wire-6` (schema with map) | 3.428 µs | 3.330 µs |
| `nowire-6` (no map) | 3.124 µs | 3.092 µs |
| **the map, 6 columns** | **+0.304 µs** | **+0.238 µs** |
| `wire-21` | 4.363 µs | 4.316 µs |
| `nowire-21` | 3.192 µs | 3.144 µs |
| **the map, 21 columns** | **+1.171 µs** | **+1.172 µs** |
| `wire-40` | 4.974 µs | 4.945 µs |
| `nowire-40` | 3.187 µs | 3.133 µs |
| **the map, 40 columns** | **+1.787 µs** | **+1.812 µs** |
| `digest-6` / `-21` / `-40` (Uint32List of hashes instead) | 3.204 / 3.208 / 3.240 µs | 3.132 / 3.178 / 3.144 µs |

The no-map lanes are flat across all three widths: the column-name list is free
to send, because strings cross a same-group boundary by reference. The whole
cost of transferring a schema is its index. The `digest` lanes match the no-map
lanes, so a flat typed array of the same information would also ship for free —
that design lost on lookup cost, not transfer (see §3).

### What one index costs to build instead

| lane | pass A | pass B |
|---|---:|---:|
| `build-6` | 94.55 ns | 96.50 ns |
| `build-21` | 321.50 ns | 322.65 ns |
| `build-40` | 616.65 ns | 618.70 ns |

Between a third and a quarter of what shipping it costs, once per result set
rather than once per read.

## 2. End to end — candidate against base, six passes

Percentages are candidate vs base within the same pass. c1/c2/c3 are separate
collections; p1 runs base first, p2 candidate first.

### Read lanes (µs per read)

| lane | role | c1p1 | c1p2 | c2p1 | c2p2 | c3p1 | c3p2 | median |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `point1` | primary, discarded | +5.9% | -4.3% | +32.3% | -3.6% | -2.4% | -4.2% | **-3.0%** |
| `point1-literal` | primary, by-literal consumption | -2.8% | -4.2% | -1.3% | -1.5% | -10.2% | -0.5% | **-2.2%** |
| `point1-interned` | primary, by-interned-key consumption | -2.1% | -2.3% | -5.0% | -3.1% | -9.3% | -3.2% | **-3.2%** |
| `wide21` | 21 columns | -9.5% | -5.4% | -12.4% | -11.9% | -13.2% | -13.0% | **-12.1%** |
| `wide21-literal` | 21 columns, by-literal | -6.8% | -4.2% | -2.6% | -4.9% | +0.3% | -6.4% | **-4.6%** |
| `wide40` | 40 columns | -22.2% | -14.8% | -22.8% | -22.0% | -23.9% | -22.6% | **-22.4%** |
| `rows1k-literal` | amortization check | +1.3% | +0.1% | -1.0% | -1.6% | +0.2% | -1.6% | **-0.5%** |
| `bytes1` | CONTROL — no schema on this path | -3.2% | -0.4% | +28.6% | +2.2% | -3.2% | +3.9% | **+0.9%** |
| `writes` | CONTROL — never crosses a schema | -1.9% | -1.7% | -10.1% | -8.2% | +6.2% | -1.8% | **-1.9%** |

### Lookup lanes (ns per `RowSchema.indexOf`, in process)

| lane | role | c1p1 | c1p2 | c2p1 | c2p2 | c3p1 | c3p2 | median |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `lookup-literal-6` | guard on the lazy field | +1.5% | +1.2% | +2.1% | +1.5% | +1.5% | +1.6% | **+1.5%** |
| `lookup-interned-6` | guard on the lazy field | +0.0% | -2.8% | +0.4% | -0.2% | -2.8% | +0.0% | **-0.1%** |
| `lookup-miss-6` | guard on the lazy field | -1.1% | +0.8% | +0.7% | +0.9% | -0.9% | +0.8% | **+0.8%** |
| `lookup-literal-21` | guard on the lazy field | +3.5% | +2.4% | +2.2% | +2.2% | +3.6% | +3.9% | **+3.0%** |
| `lookup-interned-21` | guard on the lazy field | -2.3% | -1.3% | -0.3% | +0.4% | +0.1% | +0.1% | **-0.1%** |
| `lookup-literal-40` | guard on the lazy field | -2.0% | -1.4% | +0.1% | +0.1% | -0.5% | -0.1% | **-0.3%** |

## 3. Why the map was kept rather than replaced

Three designs were compared in `schema_index_transfer.dart` before one was
written. Steady-state lookup cost, ns, 11 samples × 200,000 lookups:

| key | shipped (eager map) | equality scan only | lazy map | hash digest |
|---|---:|---:|---:|---:|
| literal, 6 cols | 19.8 | 16.4 | 28.4 | 20.1 |
| literal, 40 cols | 40.1 | 59.3 | 45.4 | 51.7 |
| interned, 6 cols | 6.2 | 16.7 | 9.5 | 9.5 |
| interned, 40 cols | 13.1 | 57.5 | 16.4 | 16.3 |
| miss, 40 cols | 30.9 | 79.6 | 35.2 | 54.9 |

(These lanes live in one class, so the absolute gaps between forms carry some
harness artifact; the shape is what they are for.) Deleting the map in favour of
an equality scan gives back exps 158 and 176 on the interned path — 16.7 ns
against 6.2 at six columns, 57.5 against 13.1 at forty. The digest replaces it
cleanly on transfer but loses on every lookup the identity scan does not catch.
Keeping the map and moving *when* it is built changes no lookup's behaviour at
all, which is why it is the shipped design. The real per-lookup cost of that
choice is §2's lookup lanes, measured against the shipped implementation: +0.28
ns at six columns, +0.83 ns at 21, nothing at 40 or on the identity path.
