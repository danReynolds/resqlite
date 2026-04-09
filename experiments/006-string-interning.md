# Experiment 006: String Interning for Isolate.exit Optimization

**Date:** 2026-04-06
**Status:** Rejected

## Problem

The `Isolate.exit()` MessageValidator walks every object in the transfer graph. For 20,000 rows with 4 text columns, that's ~80,000 String objects. Columns like `category` have only 10 unique values repeated 2,000 times each. Could we deduplicate these to reduce the object count?

## Hypothesis

Interning repeated string values (`intern.putIfAbsent(decoded, () => decoded)`) would reduce the number of unique String objects in the graph. The MessageValidator might skip already-visited objects, reducing the validation walk time. Even if it doesn't skip, fewer objects means less memory allocation.

## What We Tested

Two variants measured in a transfer cost benchmark:
1. **Interned keys only** — all rows share the same column name String instances
2. **Fully interned** — keys + repeated values (category, dates) interned

Compared against unique strings (no interning) and Uint8List (baseline).

## Results

### Transfer cost benchmark (data built inside worker, Isolate.exit only)

At 10,000 rows:

| Variant | Build + Transfer time |
|---|---|
| Unique strings | 17.28 ms |
| Interned keys | 6.60 ms |
| Fully interned | 5.46 ms |

Interning appeared to help dramatically. But deeper analysis revealed that most of the savings were in **build time** (map construction is faster with shared key instances), not transfer validation time.

### Full select() with interning integrated

At 5,000 rows:

| Implementation | Wall time | vs without interning |
|---|---|---|
| Without interning | 3.22 ms | — |
| **With interning** | **5.30 ms** | **+64% slower** |

The intern table (`Map<String, String>`) grew to 60,000+ entries for mostly-unique data (names, descriptions). Every string did a hash lookup in this large map. For columns with unique values per row, this added overhead with zero deduplication benefit.

## Why Rejected

The hash lookup cost on mostly-unique data exceeds the savings from deduplication. Column key interning helps (and our final implementation does intern column names by reading them once into a shared list), but value interning is a net negative for typical query data where most strings are unique.

**Key lesson:** You can't predict data cardinality at query time. An optimization that assumes repeated values will hurt when values are unique.
