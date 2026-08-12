# Experiment 270: answer the repeated read from memory

**Date:** 2026-08-12
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`, `stream-rerun-dispatch`
**Benchmark Run:** Headline sweep in
  [`benchmark/results/2026-08-12T08-10-19-exp270-vs-parent.md`](../benchmark/results/2026-08-12T08-10-19-exp270-vs-parent.md),
  compared explicitly against the same-host parent-commit baseline
  [`benchmark/results/2026-08-12T07-42-23-exp270-parent-baseline.md`](../benchmark/results/2026-08-12T07-42-23-exp270-parent-baseline.md).
  The decision evidence is the focused AOT A/B and the probes below; the final
  branch ships no runtime code.

## Problem

[Exp 265](265-inline-main-isolate-select.md) priced something four earlier
experiments had argued against without measuring: for a hot point read, the
isolate round trip is most of the latency. [Exp 269](269-enforced-inline-reads.md)
tried to remove that round trip by running the statement on the calling isolate,
reproduced the win at 24–90%, and was rejected — arbitrary SQLite work cannot be
bounded on a caller that must stay responsive. Its closing instruction was
explicit: do not retry a caller-isolate policy for arbitrary `select()` with a
richer predictor or more SQLite counters.

That leaves the measured headroom on the table and forecloses the obvious way to
collect it. This experiment takes the other way: instead of running the query
somewhere cheaper, do not run it at all.

## Hypothesis

**Assumption challenged: the invalidation signal that is good enough for
`stream()` is good enough to answer `select()` from memory.**

resqlite already computes both halves of a read cache and uses them for
something else. The C authorizer records, per prepared statement, which tables
that statement reads — cached on the statement entry since exp 106, so a warm
statement can report its dependencies for free. The preupdate hook records, per
write, which tables changed, and `StreamEngine.onDependencyChanges` receives that
set on the main isolate the moment a write resolves. Streams consume both. One-shot
reads consume neither and re-execute from scratch every time.

A cache hit runs no SQLite, so it is bounded by construction — it is the one way
to collect exp 265's headroom that exp 269's rejection does not forbid. The
question is not whether it is fast. It is whether the signal underneath it is
honest, because streams and reads fail differently: a stream that misses an
invalidation re-emits late, and a `select()` that misses one returns the wrong
rows, silently.

## Approach

`ReadCache` lives on the main isolate beside the reader pool, keyed by
`(sql, parameters)`.

**What it refuses to store.** A statement is described once — on its *second*
sighting, not its first, since a statement executed once can never be hit and the
describe costs a wider reply. The description is a refusal unless all of:

- the C-side read-table capture is reliable (not `UnknownTableDependencies`);
- the statement reads at least one table, so some write could invalidate it —
  this excludes `SELECT 1` and every scalar-only query;
- every SQL function it invokes is on a new C-side deterministic allowlist. A new
  `SQLITE_FUNCTION` case in the authorizer marks the statement impure for
  anything not on that list, which is an allowlist rather than a denylist of
  `random()` because the set of functions a caller can register is open. The flag
  is stored on the cached statement entry, because a cache hit never re-runs the
  authorizer;
- the result fits the retention cap (256 rows). An oversized result also retires
  the SQL, so the next execution stops at the description lookup.

**What retires an entry.** Invalidation is a version stamp, not an index walk.
Each table carries a write counter; each retained result carries the counters its
tables were at *when the read was dispatched*, and a lookup that finds a mismatch
drops the entry. A write therefore costs one map write per dirty table and
nothing else — no index of dependent queries, no set arithmetic, no allocation —
which matters because that cost is paid by every application whether or not the
cache ever helps it. Stamping at dispatch rather than at completion is what makes
a write that races an in-flight read retire the result it produced.

Two whole-cache retirements share one epoch counter. An unknown dirty set is
obvious. The other is not: **a write reporting an empty dirty set retires
everything**, because DDL and virtual-table writes fire no preupdate hook, so
"nothing changed" and "we cannot see what changed" arrive identically (exp 068).
Streams read that as nothing to do. A read cache cannot afford to.

Reads inside a transaction never reach the pool, so they neither hit nor fill.
`selectBytes` is excluded — its result is a view over native memory the next
query overwrites — and streams keep their own last result.

## Results

### The mechanism is worth about ten times the hop

Focused AOT A/B, lane-isolated, eight alternating pairs per lane per collection,
51 samples per pass, two collections with the order flipped. Both arms are built
from one worktree and one native library, differing only in the `kReadCacheEnabled`
constant, so no per-`.so` placement offset can exist between them
(the exp 254 hazard).

| lane | collection 1 | collection 2 | verdict |
|---|---:|---:|---|
| `point1-repeat` | −90.0% | −90.1% | REPRODUCED |
| `point1-wide20` | −92.1% | −91.9% | REPRODUCED |
| `point1-params` | −90.2% | −89.6% | REPRODUCED |
| `page20-repeat` | −95.1% | −95.7% | REPRODUCED |
| `read-write-alternate` (guard) | +0.7% | +1.8% | neutral |
| `churn-unique` (guard) | +3.1% | −4.1% | drift-suspected |
| `uncacheable-fn` (guard) | −0.2% | −0.2% | neutral |
| `mixed6-1k` (guard) | −2.2% | +0.9% | neutral |
| `concurrent8` (guard) | +2.7% | +0.6% | neutral |

In absolute terms a dispatched point read costs ~4.65 µs (the `uncacheable-fn`
baseline median, 929 µs over 200 reads) and a hit ~0.48 µs (`point1-repeat`
candidate, 95 µs over 200). The `page20-repeat` lane also *lowers* peak RSS,
31.0 → 25.9 MB, because fifty repetitions per sample stop allocating fifty
result sets.

The guards are the load-bearing half. `churn-unique` — every read a SQL string
never seen before, so no cache of any size could help — is neutral only because
of the second-sighting rule; describing on first sight measured a reproduced
+21% there, which is the version of this design that should not exist.
`read-write-alternate` is neutral only because invalidation is a counter bump; the
first implementation kept a table→queries index and measured +16–19% on the same
lane. Both taxes were real, both were found by guards rather than by reasoning,
and the second one is why the shipped shape gives up the column-level elision the
stream engine uses: re-checking columns against every retained entry on every
write is exactly the walk that cost 16%.

### The premise is false at the connection boundary

[`select_cache_foreign_writer.dart`](../benchmark/experiments/select_cache_foreign_writer.dart)
opens a second `Database` on the same file, commits through it, and reads through
the first:

| arm | `select()` after the foreign commit | a fresh connection reads |
|---|---|---|
| parent `1237587` | `after` | `after` |
| candidate | **`before`** | `after` |

This is not a bookkeeping bug and no amount of care inside `ReadCache` addresses
it. resqlite's invalidation is built from *its own* preupdate hook; a connection
it does not own commits without it hearing anything. `stream()` has always had
that boundary and it is documented. `select()` has not: it re-reads the file
every time, so today it observes any committed write, whoever made it. The cache
silently narrows a guarantee callers currently have, and the failure mode is a UI
painted with superseded rows and no error anywhere.

### The fix for it is affordable, and it is exp 269's architecture again

SQLite answers precisely this question. `PRAGMA data_version` changes when the
file is modified by any connection other than the one asking. If a hit could
check it, the hazard would close. So it was measured rather than assumed —
[`select_cache_data_version.dart`](../benchmark/experiments/select_cache_data_version.dart),
AOT, stepping a cached statement on a main-isolate-owned reader connection:

| phase | p50 | p90 | p99 | max |
|---|---:|---:|---:|---:|
| idle | 2 µs | 2 µs | 3 µs | 5 µs |
| foreign writer committing continuously (1,107 commits) | 1 µs | 1 µs | 1 µs | 10 µs |

A validated hit would therefore cost roughly 0.5 + 1.5 ≈ 2 µs against the 4.65 µs
round trip — still about 2× faster, not 10×. That is the honest price, and it is
worth recording that it is a price and not a wall.

What it is not is free of exp 269's problem. Reading the pragma requires a SQLite
connection on the calling isolate, opening a read transaction, under a 5-second
busy timeout — the same structure exp 269 rejected, and the probe's contention
was a same-process writer rather than a foreign process, a checkpoint, or a
contended WAL index. The measurement says the median is cheap. It does not say
the tail is bounded, and exp 269's rule applies unchanged: a cheap median for
synchronous native work is an admission check, not a bound.

### How often it would actually hit

Every winning lane above is an all-hit lane by construction, and so — it turns
out — is most of the release suite: its read scenarios execute one statement
thousands of times with nothing writing, so a cache keyed on that statement
measures itself. `Select → Maps` at 100 rows reads 0.040 ms on the parent and
0.005 ms here, and that number is not a database result. This is the same
property exp 267 recorded about the statement caches — every benchmark in the
repo uses a handful of SQL strings — showing up on a different axis, and it means
**the release suite cannot evaluate a read cache.**

The closest thing the repo has to an application is its two workload
simulations, which at least mix reads with writes to the tables those reads
depend on.
[`select_read_cache_incidence.dart`](../benchmark/experiments/select_read_cache_incidence.dart)
runs them and counts:

| workload | `select()` calls | hits | hit rate |
|---|---:|---:|---:|
| Chat Sim (A5) — inserts, updates, a last-20 JOIN, a user-by-PK fetch | 9,006 | 1,598 | **17.7%** |
| Feed Paging (A6) — page walks plus reactive updates | 140 | 118 | **84.3%** |

At a measured 4.2 µs saved per hit, that is ~0.74 µs per `select()` in the
write-mixed workload and ~3.5 µs in the paging one. The spread is the finding:
the value of this idea is entirely a property of how much a workload writes to
what it reads, and it varies by nearly 5× between two workloads in the same
repository. Neither is a production trace, so neither settles the question —
but they do establish that the answer is workload-shaped rather than a
constant, and that the write-mixed case is the modest one.

### Collateral damage

The headline sweep ran against a same-host baseline captured from the exact
parent commit, passed explicitly — exp 269's claim 269.5 warns that the
auto-selected anchor can be a non-release artifact, and it was: the automatic
comparison picked exp 269's hand-authored opaque-work receipt and skipped itself
for missing environment metadata.

Against the parent, the candidate is **7 wins, 0 wall-time regressions, 162
neutral**, with memory **1 win, 0 regressions, 14 neutral**. The wins are the
measurement artifact described above and not a result: `Select → Maps` at 100
rows −86%, `Scaling` at 100 rows −87%, keyset pagination −100%.

One row is flagged red — `Streaming (Column Granularity) / Overlapping column
writes`, −592 re-emits. It is `sqlite_async`'s row, not resqlite's, and it moved
3,466 / 3,894 / 4,347 / 3,663 / 4,185 across the five repeats *inside this single
run*; resqlite reports 0 disjoint and 10 overlapping re-emits in all five. Peer
non-determinism, nothing to attribute.

A first sweep of the same commit against the same baseline flagged fourteen
lanes at +12% to +40% — writes, streaming fan-out, subscription rate. None had a
mechanism connecting them to a diff that adds one method call to the write path
and one map lookup to the read path, and the cause was the host rather than the
code: a separate multi-`Database` probe was running concurrently. The quiet
repeat above is the receipt. The lesson is the one already in the journal — check
the host before trusting a benchmark — applied to the release suite rather than a
focused harness.

## Decision

**Rejected.** The mechanism works and the engineering is sound — a 90–96% win on
repeated reads, every adversarial guard neutral, peak RSS flat or better — and
none of that is the question. Three things decide it:

1. **The contract change is silent.** `select()` currently reflects every
   committed write. Behind this cache it reflects only writes made through the
   same `Database`, and a caller with a second connection gets stale rows with no
   signal. Making that opt-in means new public API for a trade-off-shaped win,
   which the near-freeze rejects on its own terms.
2. **Making it honest costs most of the win** — a validated hit is ~2 µs against
   ~4.65 µs rather than ~0.5 µs — and buys it back by putting a SQLite connection
   on the calling isolate, which is the structure exp 269 rejected for reasons
   this experiment has not retired.
3. **The value is workload-shaped and, where writes are involved, modest.**
   17.7% of Chat Sim's 9,006 reads could be served from memory, against 84.3% of
   Feed Paging's — about 0.74 µs and 3.5 µs saved per `select()` respectively.
   A permanent semantic narrowing is a poor trade for the first number, and the
   second is a workload that barely writes.

The runtime is reverted from the publication branch. The exact prototype is
preserved at `archive/exp-270` (`ae60084`) for inspection, not as a base to
build on — its `SQLITE_FUNCTION` purity capture and version-stamped invalidation
are both reusable ideas, and neither is worth carrying on `main` for a design
that cannot ship. What is kept here is the evidence: the focused A/B harness,
the foreign-writer probe, and the `data_version` price. The incidence probe went
with the runtime, since it reads the cache's own counters; its numbers are above
and its shape is recoverable from the archive tag.

### What this changes for future runners

The useful result is a sharper statement of what resqlite's invalidation signal
can carry. It is *sufficient for streams and insufficient for reads*, and the gap
is not precision — table and column capture are precise where they exist — but
**scope**: it reports writes this `Database` made, and a read must be correct
against writes it did not. Any future design that remembers a result rather than
re-reading it inherits that gap, whatever it caches and wherever it caches it.

Two things fell out that are worth keeping separately from the verdict:

- **The write path must stay free.** The first invalidation design kept a
  table→queries index and cost 16–19% on a read/write-alternating lane, because
  the write pays it whether or not anything is cached. Version stamps checked at
  lookup moved the entire cost to the reader that benefits, and the same lane went
  neutral. Any invalidation scheme should be judged on the write path first.
- **The empty dirty set is the dangerous one.** DDL and virtual-table writes are
  indistinguishable from a no-op write at the Dart boundary. The stream engine
  treats that as nothing to do — correctly for its purposes — and it is exactly
  the case a read cache must treat as "drop everything". Exp 068's deferred DDL
  watchdog is still the missing piece; while it is missing, the empty set means
  "unknown".

### Reopen conditions

Do not re-propose a `select()` cache invalidated only by resqlite's own writes.
Reopen if any of these changes:

1. **The signal grows scope.** A cross-connection change detector integrated into
   the read path — `PRAGMA data_version` on a bounded main-isolate mechanism, or
   SQLite's `sqlite3_update_hook`-equivalent across connections — priced against a
   contended, cross-process writer rather than a same-process one.
2. **Better incidence evidence appears.** The two workload simulations disagree
   by nearly 5× and neither is a production trace. A downstream AOT trace giving
   the real share of `select()` calls that repeat a (sql, parameters) pair with
   no intervening write is what decides whether ~4 µs per hit is worth any
   complexity at all; `select_read_cache_incidence.dart` is the shape of the
   measurement, it just needs a workload worth measuring.
3. **A narrower target with the same mechanism.** The stream engine already holds
   `entry.lastResult` for every active stream, invalidated by the same signal and
   already accepted as stream-scoped. Serving `select()` from an *existing
   stream's* current result would carry no new staleness contract, because the
   caller has already opted into stream semantics for that query. That is a much
   smaller idea than this one and it is the one worth trying next.

## Test plan

- `dart analyze --fatal-infos` — clean
- `dart test` — 495 tests, including 22 new `test/read_cache_test.dart` cases
- three load-bearing guards verified to fail against a deliberately weakened
  cache (purity gate removed, empty-dirty-set flush removed, no-table-dependency
  refusal removed)
- focused AOT A/B, nine lanes, two order-flipped collections of eight pairs;
  `dart run benchmark/ab_drift_check.dart` over all nine lane pairs
- `benchmark/experiments/select_cache_foreign_writer.dart` on both arms
- `benchmark/experiments/select_cache_data_version.dart`, AOT
- headline release sweep, `--repeat=5 --fail-on-regression --fail-on-memory-regression`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/270-read-result-cache.md`
