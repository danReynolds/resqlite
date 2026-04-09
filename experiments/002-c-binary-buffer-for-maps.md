# Experiment 002: C Binary Buffer for Maps

**Date:** 2026-04-06
**Status:** Rejected (for maps path; kept for selectBytes infrastructure)

## Problem

The sqlite3 Dart package crosses the FFI boundary per-column per-row when reading results. For 5,000 rows × 6 columns, that's 30,000+ FFI calls. Each call has ~10-20ns overhead. Could a C function that bulk-reads all rows into a binary buffer and returns it in one FFI call be faster?

## Hypothesis

One FFI call replacing 30,000 should save ~0.3-0.6ms from reduced FFI boundary crossing overhead. The binary buffer would then be decoded to maps in Dart.

## What We Built

`resqlite_query_to_rows` — a C function that packs all rows into a compact binary format:
```
Header: [row_count][col_count][column_names...]
Per row, per column: [type_tag][value_bytes]
```

Dart decodes this buffer into `List<Map<String, Object?>>` by reading sequentially from a `ByteData` view.

## Results

At 5,000 rows:

| Path | Wall time |
|---|---|
| resqlite C bulk read → Dart decode | 4.95 ms |
| resqlite per-cell FFI → maps directly | **4.92 ms** |
| sqlite3 per-cell FFI → maps | 3.90 ms |

The binary buffer approach was **not faster** for maps. The C-side encoding saved FFI overhead, but the Dart-side decoding (reading ByteData, utf8.decode per string, Map construction) added it right back. Two passes over the data (encode in C + decode in Dart) was slower than one pass (read via FFI + build maps directly).

At 20,000 rows, the binary buffer was marginally faster (26.21ms vs 26.61ms), but within noise.

## Why Rejected

The double-pass overhead (C encodes → Dart decodes) negates the FFI savings for the maps path. Direct per-cell FFI with one-pass map construction is faster at all practical sizes.

The binary buffer infrastructure was kept for `selectBytes()` (where C writes JSON directly — no Dart decode needed) and later reused in the ByteBackedResultSet experiment.
