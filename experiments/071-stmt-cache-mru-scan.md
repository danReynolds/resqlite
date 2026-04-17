# Experiment 071: MRU-first stmt cache scan + precomputed SQL hash

**Date:** 2026-04-16
**Status:** Rejected (no measurable impact)

## Problem

Scanning `stmt_cache_lookup_entry` in `native/resqlite.c`:

```c
for (int i = 0; i < c->count; i++) {
    if (c->entries[i].sql_len == sql_len &&
        memcmp(c->entries[i].sql, sql, sql_len) == 0) {
        if (i != c->count - 1) { /* MRU-promote by swap with tail */ }
        return &c->entries[c->count - 1];
    }
}
```

The MRU entry lives at the tail (new inserts append, hit promotions swap
to the tail). But the scan walks head-to-tail, so a hot query — the very
thing the cache is designed to accelerate — must traverse every other
entry before finding itself.

## Hypothesis

Two changes would speed up the common hot-loop case:

1. **Reverse scan direction** (tail → head). The MRU now hits in one
   iteration.
2. **Precomputed `sql_hash`** stored on each entry. Compare the 32-bit
   hash before the `memcmp`, so cache misses on differently-shaped SQL
   pay ~1 ns instead of ~tens of ns.

Originally framed as "SQL fingerprint for stmt cache" in the Round 1
plan, which I rejected during pre-implementation analysis — the literal-
normalization version has a correctness issue because prepared
statements bake in literal values and can't be reused across different
literal bindings. The hash+MRU variant is the honest, implementable
version of the same goal: reduce cache lookup cost.

## Approach

Added `uint32_t sql_hash` field to `resqlite_cached_stmt`, populated
via `fnv1a_32()` at insert time. Rewrote `stmt_cache_lookup_entry` to
scan `count-1` down to `0`, comparing `sql_hash` first as a fast
reject, then `sql_len`, then `memcmp` only on hash+length match.

MRU promotion preserved: matched non-tail entries are swapped with the
tail as before.

129 tests pass.

## Results

`--repeat=5` against `noise-2.md` baseline:

| Benchmark | Baseline | exp048 | Verdict |
|---|---:|---:|---|
| Point Query Throughput | 118,259 qps | 114,548 qps | within noise (±14%) |
| Select → Maps / 1000 rows | 0.40 ms | 0.39 ms | within noise |
| Parameterized Queries | 14.79 ms | 14.79 ms | within noise |
| All 63 benchmarks | — | — | 0 wins, 0 regressions* |

\* Two regression entries for Stream Churn, which uses a single SQL and
is dominated by stream lifecycle overhead rather than cache lookup cost
— previously observed noise-band variance.

## Why It Didn't Move the Needle

Each benchmark suite uses ≤ 10 distinct SQL strings. At that size:

- The head-to-tail scan visits 2-5 entries before finding the MRU —
  cheap enough that reversing to tail-first saves only single-digit ns.
- The `sql_len` fast-reject in the original code already avoids most
  `memcmp` calls, since SQL lengths differ. The `sql_hash` filter
  almost never triggers because the `sql_len` filter got there first.

The improvement would show when the cache is near its 32-entry capacity
*and* the workload cycles through many similar-length SQLs (where
`sql_len` fails to reject and `memcmp` does most of the work).

## Decision

Rejected on the same methodology as 050: if we can't measure it, we
don't adopt it. The change was structurally sound and zero-risk, but
the default benchmark suite has no workload that stresses the cache
lookup path.

## Follow-ups

- Round 2 should include a "high-diversity SQL" benchmark (e.g. 64
  rotating query shapes, cache at capacity) before revisiting either
  this or any cache-capacity experiment.
- If that benchmark lands a real win, the same experiment becomes
  trivially re-runnable against it.
