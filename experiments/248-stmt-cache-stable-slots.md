# Experiment 248: stable stmt-cache slots — removing the move-to-back struct swap

**Date:** 2026-07-25
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** focused
  [`benchmark/experiments/stmt_cache_interleaved.dart`](../benchmark/experiments/stmt_cache_interleaved.dart),
  two order-flipped A/B passes against `origin/main` at `56331a5`, plus an
  isolated C mechanism measurement; see Results.
**Archive:** [`archive/exp-248`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-248)

## Problem

The per-connection C statement cache (`STMT_CACHE_MAX = 32` in
[`native/resqlite.c`](../native/resqlite.c)) keeps its most-recently-used entry
at `entries[count - 1]`. A lookup that matches any other slot promotes it by
swapping whole structs:

```c
if (i != c->count - 1) {
    resqlite_cached_stmt tmp = c->entries[i];
    c->entries[i] = c->entries[c->count - 1];
    c->entries[c->count - 1] = tmp;
}
```

`resqlite_cached_stmt` is not small. It embeds two fixed-size arrays —
`read_tables[64]` (512 B) and `dep_columns[64]` (1 KB) — from exp 106's
column-level dependency tracking, so **one entry is 1,632 bytes** and each
promotion moves **4,896 bytes** through three full-struct copies. Eviction pays
a matching cost: `stmt_cache_insert` disposes `entries[0]` and `memmove`s the
remaining 31 entries down, ~50 KB of copying.

Two prior experiments looked at this function and both measured the *scan* half
of it on a single repeated SQL: exp 071 (MRU-first scan + precomputed SQL hash)
and exp 207 (a `last_lookup` fast-path pointer). Both were rejected. But that
workload shape never pays the swap at all — with one hot SQL the entry is
already parked at the MRU tail, `i == count - 1`, and the promotion branch is
skipped every time.

The swap only fires when a workload **alternates** between two or more hot
statements. Then every lookup finds its entry away from the tail and pays a full
promotion. That is not an exotic shape: it is what several active streams
re-querying, or DML touching more than one table, looks like from the cache's
point of view. So the swap was an unmeasured cost sitting behind two rejections
that had structurally excluded it.

## Hypothesis

LRU *ordering* does not require moving the *storage*. If each entry carries a
recency stamp from a monotonic per-cache counter, a lookup can stamp in place
and eviction can pick the smallest stamp — identical policy, zero struct
movement.

The bet: on an interleaved-statement workload the candidate reproduces a
same-sign candidate-faster delta across two order-flipped passes, while the
single-SQL control lanes (where no swap ever fires) stay flat.

Reject if the interleaved lanes do not reproduce candidate-faster, or if the
mechanism turns out to be too small a fraction of per-call wall to matter.

## Approach

The archived prototype makes three changes to
[`native/resqlite.c`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-248):

- Added `uint64_t lru_seq` to `resqlite_cached_stmt` and `uint64_t lru_clock` to
  `resqlite_stmt_cache`.
- `stmt_cache_lookup_entry` stamps `entries[i].lru_seq = ++c->lru_clock` and
  returns `&c->entries[i]` — no swap, slots never move.
- `stmt_cache_insert` scans for the smallest `lru_seq` and reuses that slot in
  place instead of disposing `entries[0]` and `memmove`-ing the tail down. The
  `sql` copy is also allocated *before* the cache is touched, so an OOM there no
  longer evicts an entry for nothing.

The eviction policy is unchanged: move-to-back kept the LRU entry at index 0,
which is exactly the entry a min-stamp scan selects.

Stable slots are also strictly safer for the two raw entry pointers the codebase
already holds — `reader->last_entry` and `db->writer_active_entry`. Under the
baseline those point at a *slot* whose occupant changes on the next promotion;
they are correct today only because a reader's operations are serialized between
acquire and dependency read. Under stable slots they refer to the same entry
until it is evicted.

To exercise the path, the run adds
[`benchmark/experiments/stmt_cache_interleaved.dart`](../benchmark/experiments/stmt_cache_interleaved.dart):
`distinct` byte-length-identical hot SQLs executed round-robin on one pinned
reader, with cold filler parked in the cache to lengthen the promotion distance.
`distinct = 1` reproduces the exp 207 shape as a control.

## Results

### Mechanism, isolated (C microbenchmark, 2M iterations/lane)

Both lookup implementations over the real struct layout, no SQLite, no isolates:

| cache | distinct hot SQL | swap ns/lookup | stamp ns/lookup | delta |
|---|---|---:|---:|---:|
| 8 | 1 (control) | 22.42 | 22.01 | −1.8% |
| 8 | 2 | 85.47 | 20.97 | **−75.5%** |
| 8 | 4 | 90.14 | 18.11 | **−79.9%** |
| 8 | 8 | 83.98 | 15.14 | **−82.0%** |
| 32 | 1 (control) | 83.01 | 79.56 | −4.2% |
| 32 | 2 | 144.28 | 88.98 | **−38.3%** |
| 32 | 4 | 146.77 | 82.38 | −43.9% |

The mechanism is exactly as predicted: when the swap fires it costs **~60–65 ns
per lookup**, and the controls confirm the branch is inert on single-SQL
workloads. The change removes real work.

### End-to-end (two order-flipped passes, median µs/call)

| Shape | P1 base | P1 cand | P1 Δ | P2 base | P2 cand | P2 Δ |
|---|---:|---:|---:|---:|---:|---:|
| 1 SQL control, cache=8 | 13.158 | 16.344 | +24.2% | 8.854 | 17.989 | +103.2% |
| 1 SQL control, cache=31 | 9.339 | 11.911 | +27.5% | 7.178 | 10.212 | +42.3% |
| 2 SQL round-robin, cache=8 | 9.136 | 8.942 | −2.1% | 6.874 | 10.229 | +48.8% |
| 2 SQL round-robin, cache=31 | 9.073 | 9.350 | +3.1% | 6.794 | 10.148 | +49.4% |
| 4 SQL round-robin, cache=31 | 9.745 | 9.823 | +0.8% | 6.689 | 10.435 | +56.0% |
| 8 SQL round-robin, cache=31 | 12.149 | 9.463 | −22.1% | 8.649 | 9.213 | +6.5% |
| 4 SQL, cache=31, 100 rows | 28.203 | 18.417 | −34.7% | 20.054 | 21.538 | +7.4% |

No lane reproduces a same-sign candidate-faster delta; every apparent pass-1 win
reverses in pass 2. The decisive evidence is the **control lanes**: with one
distinct SQL the promotion branch is mechanically unreachable, so the candidate
and baseline execute identical code — yet those lanes move +24%, +27%, +103%,
and +42%. Whatever this harness is measuring at that magnitude, it is not the
change.

## Why It Didn't Move the Needle

The arithmetic closes it. A `selectBytes()` call costs ~7–10 µs of wall,
essentially all of it isolate round-trip and decode. The swap the experiment
removes is ~65 ns. That is **~0.7% of per-call wall** — an order of magnitude
below this harness's run-to-run drift and below the repo's decision floor.

The mechanism measurement is real and the code is strictly less work, but the
cost was never a material fraction of anything a public API call does. The
per-call floor is the isolate round trip, and the cache promotion is bookkeeping
that rounds to nothing against it. This is exp 226's shape — an isolated win
that cannot clear the end-to-end gate — not exp 240's, where the mechanism
disappeared on the real path. Here the mechanism survives integration; it is
just too small to see.

## Decision

**Rejected.** The change is structurally sound, zero-risk, and removes work, but
it is unmeasurable through the public API — the same methodology exp 071 applied
to this exact function: if we can't measure it, we don't adopt it. Runtime
reverted; the prototype is preserved at `archive/exp-248`.

The lasting contribution is the bound. Future runners now have a number for this
path: **the stmt-cache promotion swap is ~65 ns, ~0.7% of a `selectBytes()` round
trip.** Together with exp 071 (scan direction + SQL hash) and exp 207
(`last_lookup` fast path), all three components of `stmt_cache_lookup_entry` —
scan order, scan short-circuit, and promotion cost — have now been measured and
found immaterial. Treat the function as closed.

**Would reopen if** the per-call round-trip floor drops by roughly an order of
magnitude (making a 65 ns term material), or if a workload appears that performs
many cache lookups *without* a round trip per lookup — the only shape in which
this cost could aggregate. Absent one of those, do not spend another pass here.

## Future Notes

The stable-slot property has a non-performance argument that this experiment does
not settle: `reader->last_entry` and `db->writer_active_entry` currently point at
slots whose occupant a later promotion can change, which is safe only by
serialization. If that invariant is ever weakened — a second statement lookup
between acquire and dependency read, on either the reader or writer path — the
baseline aliasing becomes a live bug and `archive/exp-248` is the fix, already
written. That would be a correctness change, not a performance one, and should
be justified as such.
