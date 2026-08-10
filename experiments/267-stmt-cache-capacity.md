# Experiment 267: how many statements a connection can hold

**Date:** 2026-08-10
**Status:** Accepted
**Direction:** `result-transfer-shape`
**Benchmark Run:** none (focused AOT A/B only). Every release scenario executes
  one statement thousands of times, so not one of them holds more than a
  handful of distinct SQL strings and none can reach a cache-capacity cliff —
  the same structural blindness exps 071 and 073 named. The focused harness is
  [`benchmark/experiments/stmt_cache_pressure.dart`](../benchmark/experiments/stmt_cache_pressure.dart),
  run as four order-flipped lane-isolated AOT passes against `origin/main` at
  `3e4a6ad`; see
  [`benchmark/results/2026-08-10T11-15-00Z-exp267-stmt-cache-capacity.md`](../benchmark/results/2026-08-10T11-15-00Z-exp267-stmt-cache-capacity.md).

## Problem

Three caches on the read path are keyed by SQL text and capped at 32 entries:
the C per-connection prepared-statement cache (`STMT_CACHE_MAX` in
[`native/resqlite.c`](../native/resqlite.c)), the per-worker Dart `schemaCache`
in [`lib/src/query_decoder.dart`](../lib/src/query_decoder.dart), and the
pool's row-size memory in
[`lib/src/reader/reader_pool.dart`](../lib/src/reader/reader_pool.dart). Each
one's comment says it matches the other two, and none of the three numbers has
ever been measured.

They have not been measured because nothing in the repo can reach them. Every
benchmark, release and focused alike, uses under ten distinct SQL strings, so
no suite has ever put a single one of these caches under pressure. That is not
a new observation: [exp 071](071-stmt-cache-mru-scan.md) rejected a statement
cache change in 2026 and closed by asking for "64 rotating query shapes, cache
at capacity" *before any cache-capacity experiment*, and
[exp 073](073-schema-cache-fast-path.md) rejected a schema cache change the
same way and asked for the same workload. Neither was ever built. Two later
experiments — [exp 207](207-stmt-cache-hot-sql-fastpath.md) and
[exp 248](248-stmt-cache-stable-slots.md) — went at the *lookup* path instead
and were both rejected on measurement grounds. So the cache's scan has been
attacked twice and its size never once.

What makes the gap load-bearing now is [exp 266](266-sticky-reader-dispatch.md),
merged two days ago. Under the round-robin dispatch it replaced, a sequential
loop over D distinct statements was *partitioned* across four reader workers:
each connection's cache saw roughly D/4 of them, so a 128-statement application
still fit inside 32 per connection. Sticky dispatch sends that same loop to one
worker. The cap did not move; the workload that reaches it did, by a factor of
four.

The access pattern makes it a cliff rather than a slope. These caches evict at
the front and promote on hit, which is approximately LRU — the worst possible
policy for a cyclic scan. At D ≤ 32 every read hits. At D = 33 the entry each
read needs is the one the previous miss just evicted, so the hit rate does not
degrade, it collapses.

## Hypothesis

An application with more distinct statements than a connection can cache pays
a full `sqlite3_prepare_v3`, authorizer run and dependency capture on *every*
read, and the cap that decides this is a compile-time constant that nobody has
ever tried moving. Raising all three caps together should be worth a large
fraction of a read past the cliff and nothing at all below it.

## Approach

Two changes, the second forced by the first.

**The caps.** `STMT_CACHE_MAX`, `_schemaCacheMax` and the pool's row-size
memory all go from 32 to 128. They are raised together because they are keyed
by the same string and documented as matching; splitting them would leave a
workload that fits one and thrashes another.

**The eviction.** `stmt_cache_insert` used to reclaim a slot by disposing
`entries[0]` and `memmove`-ing the remaining entries down one, so the new entry
landed at the tail. `resqlite_cached_stmt` is ~1.6 KB — `read_tables[64]` at
512 B plus `dep_columns[64]` at 1 KB, both fixed-size arrays, as
[exp 248](248-stmt-cache-stable-slots.md) documented — so that shift moves
`(STMT_CACHE_MAX - 1) × 1.6 KB` of memory on every prepare: 50 KB at 32
entries, and 203 KB at 128. The first measurement pass raised only the caps and
measured a reproduced **+42%** on the never-reused-SQL guard lane; the
arithmetic matched (39 MB of extra `memmove` per sample against a measured
1.5 ms) and identified the cost before the second pass was run.

The fix is to dispose `entries[0]` and build the new entry in place. Entry
order is already only approximate — `stmt_cache_lookup_entry` promotes a hit by
*swapping* it with the tail rather than shifting — so compacting the array
preserves no ordering guarantee that the swap has not already given up. The new
entry starts at the front, where the next eviction takes it if nothing looks it
up first, which is the right default for the only workload that reaches this
branch: a statement nobody reuses is exactly the one worth dropping, and one
that is reused is promoted to the tail by its next lookup.

Nothing else changes. No public API, no dispatch policy, no decode path.

### The instrument

[`benchmark/experiments/stmt_cache_pressure.dart`](../benchmark/experiments/stmt_cache_pressure.dart)
is the workload exps 071 and 073 asked for. It cycles D distinct statements
that differ only by a trailing comment, so the parse, the plan, the schema and
the row count are identical across lanes and D is the only variable. Every
sample performs the same 256 reads regardless of D, so a sample is ~2 ms in
every lane and no lane is decided by stopwatch resolution
([exp 264](264-initial-alloc-size-memory.md)).

`rotate8` and `rotate24` fit inside the old cap and are controls. `rotate32`
sits exactly on it. `rotate40`, `rotate64` and `rotate128` are the primaries.
`point1` holds a one-entry cache through 256 executions and is the control for
the *candidate's* cost rather than the baseline's, since raising a cap
lengthens the linear scan. `churn-unique` mints a never-repeated statement for
every read: no cache of any size can help, so the candidate can only add scan
length and eviction work. That lane is what rejected the first version.

## Results

Four order-flipped lane-isolated AOT passes, 51 samples per lane, on arm64
macOS 26.2 (Apple M1 Pro), Dart 3.12.2. Medians are per sample of 256 reads.
Verdicts are `benchmark/ab_drift_check.dart`'s, run over passes 1+2 and again
over passes 3+4.

| lane | role | base µs | cand µs | p1 | p2 | p3 | p4 | mean | verdict |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| `rotate40` | primary | 3385 | 1460 | −55.3% | −51.2% | −58.6% | −57.1% | **−55.5%** | reproduced ×2 |
| `rotate64` | primary | 3591 | 1568 | −55.2% | −57.4% | −56.4% | −51.1% | **−55.1%** | reproduced ×2 |
| `rotate128` | primary | 3572 | 1594 | −55.1% | −55.5% | −56.3% | −46.1% | **−53.3%** | reproduced ×2 |
| `churn-unique` | guard | 3688 | 3252 | −12.4% | −14.5% | −10.8% | −9.7% | **−11.9%** | reproduced ×2 |
| `rotate32` | boundary | 1491 | 1475 | +0.8% | −14.8% | −2.6% | +2.1% | −3.6% | neutral ×2 |
| `rotate24` | control | 1374 | 1374 | +0.9% | +1.6% | −0.1% | −0.9% | +0.4% | neutral ×2 |
| `rotate8` | control | 1464 | 1504 | +10.4% | +2.3% | −11.7% | +3.8% | +1.2% | neutral / drift-suspected |
| `point1` | control | 1409 | 1360 | −2.9% | −2.9% | −4.9% | −0.7% | −2.8% | neutral ×2 |

Past the cliff a read costs **less than half** what it did — 14.0 µs per read
down to 6.1 µs on `rotate64` — and the win is flat from 40 statements to 128,
which is what a cliff predicts and a gradual cache-pressure curve would not.
The three lanes that fit inside the old cap run byte-identical code in both
arms and move in both directions inside the noise floor, so nothing here is a
whole-binary layout effect ([exp 254](254-text-value-blob-decode.md)).
`rotate8` is the least trustworthy lane in the set: it is the shortest and its
four passes span 22 points, so it reads drift-suspected on the second
collection and should not be quoted as a small win or a small loss.

`churn-unique` is the load-bearing negative-turned-positive result. Its first
version measured **+42.1%**, reproduced across all four passes, and would have
rejected the capacity raise on its own. With the eviction shift removed the
same lane is a reproduced **−11.9%**, because the baseline was also paying the
`memmove` — 31 entries × 1.6 KB on every prepare, ~640 µs of its 3688 µs
sample. Removing an O(capacity)-bytes operation from the eviction path is worth
more than the larger cache costs on a workload where the cache cannot help at
all.

**Memory.** Peak RSS rises 0.8-1.2 MB on every lane, against a ~30 MB floor.
That is the cache arrays themselves: 128 × 1.6 KB per connection across the
writer, four readers and the reserved reader. SQLite's own accounting agrees
from the other side — the release suite's `sqlite_diagnostics` section, which
already ran 48 distinct SELECT texts and was therefore already past the old
cliff without anyone noticing, reports `Stmt` memory at 70.5 KiB baseline
against 103.4 KiB candidate, since more prepared statements are now retained.
The `JSON buffer reclaim` guard is unchanged at 64.0 KiB, as expected — this
run touches no dispatch policy, so exp 266's traffic-driven reclaim hazard does
not apply.

**Correctness.** [`test/stmt_cache_pressure_test.dart`](../test/stmt_cache_pressure_test.dart)
gates the new eviction path with five tests that push 400 distinct statements
through every cache. A cache that returns the *wrong* entry is silent — the
caller gets a well-formed result belonging to a different statement — so each
test makes a statement's identity checkable from its result: the row it
selects, the columns it projects, or its parameter arity. Verified to fail:
against a deliberately mismatched entry (new `sqlite3_stmt` installed under the
evicted entry's old SQL text) four of the five fail.

## Outcome

**Accepted.** A workload with more distinct statements than a connection can
cache is worth ~2× on every read, from 40 statements to at least 128, for
~1 MB of peak RSS. Below the old cap nothing changes. The never-reused-SQL
shape, which a bigger cache cannot help, improves 12% anyway because the
eviction shift it removed was already being paid at 32 entries.

The direction is not closed at 128. The cliff moves, it does not disappear: an
application with more than 128 hot statements lands in exactly the state this
experiment found at 33. What bounds the next raise is memory, and the term that
dominates it is the fixed-size `read_tables[64]` and `dep_columns[64]` arrays
that make an entry 1.6 KB when a typical statement reads one table and a
handful of columns. Sizing those from what the authorizer actually captured
would shrink a common entry by an order of magnitude and make the cap a
question about hit rate rather than about footprint. That is the named
follow-up, and it is also what would make the remaining `churn-unique` scan
cost cheap.

## What would reopen this

- A statement mix measured in a real application that exceeds 128. The
  discriminating measurement is still the one [exp 264](264-initial-alloc-size-memory.md)
  named — count distinct SQL strings per second in a representative trace — and
  it now bounds a cliff worth 2× rather than a hint worth 40%.
- Evidence that the front-insert eviction hurts a shape this run did not build.
  It was chosen because it removes an O(capacity) cost, not because its hit
  rate was measured against the compacting version at equal capacity; the two
  are indistinguishable on every lane here, since below the cap neither evicts
  and above it a cyclic workload defeats both.
