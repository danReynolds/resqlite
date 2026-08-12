# Experiment 268: leave empty statement caches virtual

**Date:** 2026-08-11
**Status:** Accepted
**Direction:** `result-transfer-shape`, `measurement-system`
**Benchmark Run:** none (focused AOT A/B only). This is a connection-open and
  resident-memory change, while the release suite reports steady-state query
  rates and its process floor cannot isolate one native cache clear. The
  focused harness is
  [`benchmark/experiments/stmt_cache_init.dart`](../benchmark/experiments/stmt_cache_init.dart),
  run against `origin/main` at `96e6730` in twelve alternating-order RSS passes
  and six alternating-order wall passes; see
  [`benchmark/results/2026-08-11T10-25-54Z-exp268-stmt-cache-lazy-init.md`](../benchmark/results/2026-08-11T10-25-54Z-exp268-stmt-cache-lazy-init.md).

## Problem

[Exp 267](267-stmt-cache-capacity.md) raised the per-connection statement cache
from 32 to 128 entries and measured a 0.8-1.2 MB peak-RSS increase across the
pool. It attributed that price to the larger fixed arrays inside
`resqlite_cached_stmt` and named exact-sized dependency metadata as the next
experiment.

That attribution skipped one line. [`stmt_cache_init`](../native/resqlite.c)
sets `count = 0` and then `memset`s the complete 128-entry array. The database
object containing the writer and reader caches was already allocated with
`calloc`, so this is a second zeroing pass over memory no statement has used.
More importantly, the compiler can see through the writer initialization next
to `calloc` but not through the reader-open loop. Optimized arm64 assembly keeps
one 273,408-byte `bzero` per successfully opened reader.

The actual entry is 2,136 bytes, not exp 267's approximate 1.6 KB: its
`resqlite_column_dep` members are 24 bytes each. One cache is therefore
`128 × 2,136 = 273,408` bytes. `Database.open` chooses two to four readers and
normally selects four on this host, so open eagerly writes 546,816 to
1,093,632 bytes before the first statement reaches a cache. That range nearly
equals the memory increase exp 267 observed.

Dynamic metadata would reduce the footprint of a *populated* cache, but it
would add allocation, failure, fragmentation and disposal paths on every
prepare. The redundant clear has broader incidence — every open, even a
database that prepares nothing — and no ownership cost.

## Hypothesis

Initializing a fresh statement cache by setting only `count = 0` should leave
unused cache pages virtual and recover roughly one cache's resident bytes per
reader. It should not change behavior because lookup and cleanup inspect only
entries below `count`, and every insertion fully zeroes its chosen slot before
incrementing `count`.

The acceptance gate was at least 0.5 MB lower peak RSS, scaling from two to
four readers, with no repeated open-time regression above 3%, neutral full-cache
and eviction controls, and the 400-statement correctness suite green.

## Approach

`stmt_cache_init` now sets `count = 0` and does not touch `entries`. The safety
argument has four parts:

1. `resqlite_db` is a fresh `calloc` allocation at the only open path.
2. `stmt_cache_lookup_entry` and `stmt_cache_clear` iterate only `[0, count)`.
3. `stmt_cache_insert` calls `stmt_cache_entry_init`, whose first operation is
   `memset(entry, 0, sizeof(*entry))`, before publishing the slot by raising
   `count`.
4. The only two `stmt_cache_init` call sites initialize the fresh writer cache
   and each freshly opened reader cache.

The new AOT harness calls the native open/close API directly so a spawned Dart
reader pool cannot obscure native connection initialization. `rss2` and `rss4`
open once in a fresh process and report both lifetime max RSS and growth from
immediately before open. `wall2` and `wall4` time 16 opens per sample, with
close outside the stopwatch. Twelve RSS passes and six wall passes alternate
arm order; lane order flips for wall time as well.

The existing
[`stmt_cache_pressure.dart`](../benchmark/experiments/stmt_cache_pressure.dart)
supplies three steady-state controls: `point1` initializes and repeatedly hits
the first slot, `rotate128` fills the cache exactly, and `churn-unique` evicts
on every prepare. Its four-pass AOT A/B is an equivalence gate because the
candidate changes none of those paths.

## Results

### Resident memory

All twelve fresh-process passes put the candidate below baseline in both RSS
metrics at both reader counts.

| readers / metric | baseline median | candidate median | delta | paired savings range |
|---|---:|---:|---:|---:|
| 2 / max RSS | 18,923,520 B | 18,333,696 B | **−589,824 B (−3.12%)** | 507,904-720,896 B |
| 2 / open growth | 4,210,688 B | 3,670,016 B | **−540,672 B (−12.84%)** | 491,520-573,440 B |
| 4 / max RSS | 21,012,480 B | 19,955,712 B | **−1,056,768 B (−5.03%)** | 933,888-1,228,800 B |
| 4 / open growth | 6,316,032 B | 5,341,184 B | **−974,848 B (−15.44%)** | 933,888-1,114,112 B |

Adding two readers adds 461-474 KB of mean savings, or 231-237 KB per reader.
That is 84-87% of the 273,408-byte assembly prediction. The scaling supports
the mechanism, but max RSS is page-granular and process-wide, so the defensible
statement is “broadly consistent,” not byte-exact attribution. The exact code
prediction lies inside the observed pass ranges.

This also revises exp 267's memory reading. Its measured 0.8-1.2 MB increase
was real, but most of it was not retained prepared statements or live
dependency metadata: four reader initializers eagerly touched 1.04 MiB of
otherwise-unused cache pages. This experiment recovers 1.06 MB of max RSS on
the same four-reader shape.

### Open time and cache controls

| lane | baseline | candidate | delta | pass signs |
|---|---:|---:|---:|---|
| native open, 2 readers | 602.0 µs | 587.4 µs | **−2.42%** | candidate faster 4/6 |
| native open, 4 readers | 757.6 µs | 736.9 µs | **−2.73%** | candidate faster 5/6 |
| `point1` pressure control | 1361.0 µs | 1354.5 µs | −0.48% | neutral, sign-flipped |
| `rotate128` full-cache control | 1553.0 µs | 1543.5 µs | −0.61% | neutral, sign-flipped |
| `churn-unique` eviction control | 3067.0 µs | 3051.5 µs | −0.51% | neutral, sign-flipped |

Open time has a small aggregate win; the only three candidate-slower pass
comparisons are +1.15%, +0.46% and +1.57%, so no regression reaches the 3%
gate or reproduces after the order flip. The pressure controls all aggregate
within 0.7%, with individual movements bounded to ±3.04%. They confirm the
change ends at initialization rather than moving lookup, fill or eviction.

### Optimized code and correctness

The baseline AOT bundle's reader loop loads `0x42c00` into the second argument
and calls `_bzero`; the candidate loop does neither. Neither bundle clears the
writer array after `calloc`, confirming the compiler had already removed that
copy and that the measured reader scaling is the changed code.

Twenty-three focused serial tests pass: empty close and first writer/reader
use, 400-statement cache fill and eviction, SQL/projection/parameter identity,
stream dependency reliability, overflow fallback, trigger cascades, native
allocation-fault behavior, and basic cached JSON token use. One existing gap
remains: no test combines `selectBytes` JSON-name tokens with an over-capacity
statement cycle. It is not a new ownership seam here because every slot is
still zeroed immediately before first use and reuse.

## Outcome

**Accepted.** One count store replaces up to four 273,408-byte reader clears.
Four-reader native open saves 1.06 MB of peak RSS and 0.97 MB of measured open
growth, while open time improves 2.7% and the full-cache and eviction paths are
neutral. The runtime change is deletion-sized, adds no allocation or failure
path, and is mechanically unreachable after a slot becomes live.

The result is more general than this cache. A `calloc`-backed parent does not
keep large inline capacity lazy when a nested initializer writes it again, and
the compiler's dead-store elimination can differ between the adjacent field
and the same field inside a loop. The durable gate is optimized assembly plus
reader-count-scaled fresh-process RSS, not source-level intuition about zeroes.

## What would reopen this

- Evidence that any statement-cache consumer can inspect an entry at or above
  `count`. That would invalidate the live-range proof and require explicit
  initialization at that consumer.
- A populated-cache footprint showing the fixed `read_tables[64]` and
  `dep_columns[64]` metadata remains material after the eager-clear removal.
  Exact-sized metadata is still a possible follow-up, but it now needs a
  representative filled-cache or >128-statement trace to justify its extra
  allocation and OOM semantics; empty-open RSS no longer supports it.
- A platform where optimized code retains the writer-side clear or lowers the
  reader clear differently. The source is portable, but the exact byte and
  wall figures are arm64/macOS measurements.
