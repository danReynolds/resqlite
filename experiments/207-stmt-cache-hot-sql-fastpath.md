# Experiment 207: stmt_cache hot-SQL fast-path bypass

**Date:** 2026-06-30
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** focused
  [`benchmark/experiments/stmt_cache_hot_sql.dart`](../benchmark/experiments/stmt_cache_hot_sql.dart),
  three order-flipped A/B pairs against `origin/main` at `f2c13d0`; see
  Results.
**Archive:** [`archive/exp-207`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-207)

## Problem

The per-connection C statement cache (`STMT_CACHE_MAX = 32` in
`native/resqlite.c`) looks up prepared statements by linear scan in
`stmt_cache_lookup_entry`:

```c
for (int i = 0; i < c->count; i++) {
    if (c->entries[i].sql_len == sql_len &&
        memcmp(c->entries[i].sql, sql, sql_len) == 0) {
        if (i != c->count - 1) {
            // move-to-MRU swap with entries[count - 1]
        }
        return &c->entries[c->count - 1];
    }
}
```

On a hit, the matched entry is swapped to `entries[count - 1]` (the MRU
position). The next lookup for the same SQL then walks every slot ahead of
`count - 1` again before re-finding it. For a per-reader cache fully populated
with 32 distinct SQLs and one repeated hot query, that is up to 31 wasted
`sql_len` compares (and possibly `memcmp` calls) per hot lookup.

Exp 195 / 198 / 199 / 203 / 205 have pushed per-call cost in `write_json_to_buf`
and `resqlite_step_row` down to the microsecond range; per-call FFI prep
overhead is a larger relative fraction of that wall than it used to be, so the
cache-scan-per-lookup pattern is worth re-checking.

## Hypothesis

If the cache carries a `last_lookup` pointer set after every successful match
(or insert), `stmt_cache_lookup_entry` can short-circuit the linear scan when
the requested SQL matches the most recently touched entry. That should remove
the wasted scan steps on workloads that re-execute the same prepared SQL many
times in a row — exactly the shape the per-reader cache sees during a hot loop.

The bet: cache-pressured small-rowset lanes (e.g. `cache=31 cold` plus a hot
1-row `selectBytes()`) should reproduce a same-sign candidate-faster delta
across two order-flipped passes. Cache-empty guard lanes should stay flat — the
extra check only costs one wasted compare on a miss, and the workload provides
no real misses inside a hot loop.

Reject if the cache-pressure lanes do not reproduce candidate-faster after a
warmed order flip, or if the change makes the guard lanes worse.

## Approach

The archived prototype made three small changes to
[`native/resqlite.c`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-207):

- Added `resqlite_cached_stmt* last_lookup;` to `resqlite_stmt_cache`.
- Added a fast-path branch at the top of `stmt_cache_lookup_entry`:
  ```c
  resqlite_cached_stmt* last = c->last_lookup;
  if (last && last->sql_len == sql_len &&
      memcmp(last->sql, sql, sql_len) == 0) {
      return last;
  }
  ```
  and an `c->last_lookup = &c->entries[c->count - 1];` write on every
  successful linear-scan match.
- Cleared `last_lookup` in `stmt_cache_init`, `stmt_cache_clear`, and before
  the eviction `memmove` inside `stmt_cache_insert`, then re-primed it to the
  freshly inserted entry. Eviction and clear are the only paths that can leave
  the cached pointer dangling into freed `sql` memory; the memmove case shifts
  entries down so a stale pointer would still land on a valid (but
  semantically wrong) entry, but resetting it keeps a stale hit from masking
  whatever the next lookup is actually asking for.

No public API changes, no output-format changes, no behavioural change on
correctness paths (full `dart test test/database_test.dart` plus the
`stream*`, `transaction*`, and `stream_cache_hit_reliability` suites pass
unchanged).

To exercise the path with a representative workload, the run also adds
[`benchmark/experiments/stmt_cache_hot_sql.dart`](../benchmark/experiments/stmt_cache_hot_sql.dart):
it pre-fills the per-reader cache with `coldCacheFill` distinct cold SQLs
padded to the same byte length as the hot SQL — so the scan cannot
short-circuit on `sql_len` and must `memcmp` every cold entry on every
lookup — then measures median µs per call across `_samples = 11` samples of
`_callsPerSample = 1000` hot calls each. Exp 195's
`select_bytes_repeated_calls.dart` is not the right denominator because its
cache only ever holds the one hot SQL (`count == 1` → scan already O(1)).

## Results

Three order-flipped A/B pairs against `origin/main` at `f2c13d0`. Each cell is
the median µs/call across 11 samples of 1000 calls each. Build hook recompiled
the dylib between every swap.

| Shape | Baseline p1 | Cand p1 | Baseline p2 | Cand p2 | Baseline p3 | Cand p3 |
|---|---|---|---|---|---|---|
| cache=31 cold \| 1 row × 8 cols | 6.880 | 7.285 | 7.057 | 9.439 | 7.580 | 9.102 |
| cache=31 cold \| 1 row × 20 cols | 5.833 | 5.888 | 5.921 | 6.834 | 6.294 | 7.595 |
| cache=31 cold \| 10 rows × 8 cols | 7.293 | 7.810 | 7.401 | 8.138 | 7.919 | 9.188 |
| cache=15 cold \| 1 row × 8 cols | 5.392 | 5.454 | 5.520 | 5.729 | 5.500 | 5.553 |
| cache=0 cold \| 1 row × 8 cols | 5.376 | 5.527 | 5.474 | 5.496 | 5.580 | 5.479 |
| cache=0 cold \| 100 rows × 8 cols | 26.780 | 26.859 | 27.082 | 26.679 | 26.680 | 26.955 |

No lane reproduces a candidate-faster median. The cache-pressure lanes
(`cache=31`) trend consistently candidate-slower across all three pairs — by 6%
on the first pair and up to 20–30% on the third — while the guard lanes
(`cache=0` and `cache=15`) sit within ±2%. The direction is reproduced, not a
single-pair drift artifact (per the exp 177 / `ab_drift_check.dart` rule on
sign reversal), so this is a real-shaped regression on the very lanes the
fast-path was meant to help.

Mechanically, the fast-path probably *does* fire on most calls — after warmup,
each per-reader cache's `last_lookup` should point at the hot entry — so the
slowdown is not "extra compare on every miss." Two more likely causes,
neither addressable by tuning the candidate:

- The 8-byte `last_lookup` field shifts the layout of `resqlite_stmt_cache`
  and any struct it is embedded in (`resqlite_db`, `resqlite_reader`), which
  in turn shifts the alignment of hotter neighbouring fields. Per-call cost
  in the µs range is sensitive to cache-line placement of the bind / step
  state next to `entries[]`.
- The `sql_len` short-circuit already makes the linear scan very cheap in
  practice: most cached SQLs differ in length, so the scan body never reaches
  `memcmp` for most entries. The harness deliberately defeats this with
  length-matched cold SQLs, but real workloads enjoy the short-circuit. Even
  then, the scan walks at most 8–9 entries per reader (31 cold rotated across
  4 readers ≈ 7–8 per reader), so the absolute work being skipped is small.

The cost of the *added* branch + memcmp on every call therefore eats whatever
the fast-path saves — the candidate ends up doing comparable or more work on
the hot loop, plus paying a layout penalty on the surrounding reader state.

## Decision

**Rejected.** The implementation is correct (all
`dart test test/database_test.dart` cases pass) but the focused harness shows
no reproducible win on the very lanes the fast-path was designed for, and a
reproduced direction of regression on the cache-pressure lanes. The runtime
prototype is reverted; only the new focused harness is kept.

The harness is the lasting contribution. It is the right gate for any future
stmt-cache layer change (eviction policy, hash key, MRU placement, branch
prediction hints): pre-fills the per-reader cache with length-matched cold
SQLs and reports µs/call, so a cache-layer win can no longer hide behind the
`sql_len` short-circuit or the `count == 1` scan that exp 195's harness
exposes.

Reopen the direction only with:

- a workload where the per-call stmt-cache scan is *measurably* dominant on
  the focused harness — e.g. a CPU profile showing `stmt_cache_lookup_entry`
  hot, or a release-suite lane where it appears as a top-N entry; **or**
- a structurally cheaper lookup (e.g. precomputed 64-bit SQL hash matched
  before any `memcmp`, or a separate per-cache linear-probe hash table) whose
  hot-path cost does not depend on cache-line shifts in `resqlite_db`. A
  pointer-bump fast-path on top of the existing struct is not the right
  shape.

## Test plan

- [x] `dart test test/database_test.dart -j 1` (53 cases) — pass on candidate.
- [x] `dart test test/database_test.dart test/stream_test.dart
       test/transaction_test.dart
       test/stream_cache_hit_reliability_test.dart -j 1` (121 cases) — pass
       on candidate.
- [x] Three order-flipped A/B pairs of
       `benchmark/experiments/stmt_cache_hot_sql.dart` — recorded above; no
       lane reproduces a candidate-faster median.
- [x] Final tree at HEAD is `origin/main` + the new harness only; no
       runtime change kept.
