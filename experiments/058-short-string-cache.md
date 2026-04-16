# Experiment 058: Short-string value cache

**Date:** 2026-04-16
**Status:** Rejected (catastrophic regression)

## Problem

The text decode path (`fastDecodeText` in `query_decoder.dart`) allocates a new Dart `String` for every text cell read from SQLite. In CRUD schemas, many text values repeat across rows: status enums ("active", "pending"), types, categories, short names, date strings. Caching short decoded strings could eliminate repeated `String.fromCharCodes` / `utf8.decode` calls.

## Hypothesis

A per-worker LRU cache keyed on the raw byte sequence (not the decoded string, to avoid decoding on cache hit) would let us return a reference to a previously-decoded String for repeated values. For 64 cache slots with strings ≤ 32 bytes, the cache fits in a few cache lines and should be faster than decoding.

## Approach

Per-worker cache:
- `List<Uint8List?>` of 64 key slots (raw bytes)
- `List<String?>` of 64 value slots (decoded strings)
- Ring buffer replacement policy (evict oldest entry)

On lookup: linear scan of 64 slots, byte-for-byte compare. On hit: return cached String. On miss: decode normally, insert into cache.

## Results

**0 wins, 19 regressions, up to +256%.**

| Benchmark | Baseline | With cache | Delta |
|---|---|---|---|
| Transaction read 1000 rows | 0.18ms | 0.64ms | **+256%** |
| Transaction read 500 rows | 0.10ms | 0.33ms | **+230%** |
| Concurrent reads 8x | 0.68ms | 1.89ms | **+178%** |
| Select maps 10000 rows | 4.70ms | 11.01ms | **+134%** |
| Parameterized queries | 14.64ms | 36.20ms | **+147%** |
| Schema wide 20 cols | 1.01ms | 2.24ms | **+122%** |

The cache made everything dramatically slower. Every column access pays the cache miss cost (linear scan of 64 slots + byte comparison) before falling through to the normal decode.

## Why It Failed

Dart's `String.fromCharCodes` (the ASCII fast path in `fastDecodeText`) is a single VM-internal `memcpy` into a pre-allocated Latin-1 backing store. On the Apple M1 benchmark hardware, this is roughly **~10-30ns** for a short string.

The cache lookup does:
- 64 iterations of length compare + byte-by-byte `memcmp`
- Each comparison accesses the `Uint8List` key's header + data

Even with early-exit on length mismatch, the expected cost of a cache miss is **~100-500ns** — more than the decode it was trying to skip. And misses are common: the cache holds 64 entries, but CRUD schemas have many distinct short strings beyond enum columns (names, emails, ids).

On cache hit, the savings (~20ns) are offset by the lookup cost. Only if hit rate were 95%+ would the cache break even, and this isn't representative of real data.

Also, each cache miss triggers `Uint8List.fromList(ptr.asTypedList(len))` to store the key — another allocation on top of the decode.

## Decision

**Rejected.** This is the same lesson as experiment 006 (string interning): Dart's VM-level string allocation is already so fast that no Dart-level cache can beat it. Any indirection (hash lookup, linear scan, byte comparison) adds more overhead than it saves.

The general principle: when the baseline operation is ~20ns, a cache must have <10ns lookup and near-perfect hit rate to be a win. Those constraints are effectively impossible in Dart user code.
