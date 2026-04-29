# Experiment 106: Column-level dependency tracking (re-attempt of 052)

**Date:** 2026-04-25
**Status:** Accepted

## Problem

The stream invalidation engine tracks dependencies at table granularity. A
stream watching `SELECT id, a, b FROM wide` re-queries on any write to
`wide`, even if the write only modifies an unrelated column like `c` that
the stream doesn't project. Under N-stream fan-out (50+ subscribed
streams on a wide table) the writer pays a per-stream re-query dispatch
even when the modified column couldn't possibly change any stream's
result.

The original [exp 052](052-column-level-dependencies.md) was deferred as
*"benchmark-invisible"* — the design was sound, but the existing
streaming benchmarks all watched every column of every table, so the
dispatch-elision win had nowhere to show up. With the
[A11c Many-Streams Writer Throughput](../benchmark/suites/many_streams_writer_throughput.dart)
benchmark in PR #39 (50 streams × 500 writes against a 20-column table,
split into disjoint and overlapping column scenarios), the gap is now
measurable.

Pre-experiment back-of-envelope on cap=4 baseline:
[`2026-04-25T19-43-21-baseline-for-exp105.md`](../benchmark/results/2026-04-25T19-43-21-baseline-for-exp105.md)

| Scenario | w/s | Notes |
|---|---|---|
| No-streams baseline | 50,110 | writer ceiling on this hardware |
| Disjoint (write to non-projected column) | 3,956 | 12.7× slower than ceiling |
| Overlap (write to projected column) | 4,477 | every stream must re-query |

The 12.7× gap between the no-streams ceiling and the 50-stream disjoint
case is the writer-side fan-out tax that exp 052 was designed to remove.

## Hypothesis

Capture each watcher's read-column dependencies at subscribe time and
each write's modified-column set at execute time. At dispatch time,
intersect the two: when no shared table has any column overlap, skip the
per-stream re-query entirely.

If column-level dispatch elision works, A11c disjoint should rise toward
the no-streams ceiling. Overlap should stay unchanged (the elision
selectively fires on disjoint writes only).

## Approach

Two authorizer-driven captures, an intersection check on dispatch.

**1. Reader side — per-stream column projection.** The existing
authorizer hook already fires `SQLITE_READ` events at prepare time with
both the table name (arg1) and column name (arg2); we were ignoring
arg2. The change extends the authorizer's user_data to a
`resqlite_authz_ctx { tables, columns, track_writes }` struct so the
reader's per-stmt cache stores both the table list and a structured
table/column dependency set. SELECT *, JOIN, subquery, view, and CTE
queries all flow through `SQLITE_READ` so they all get column-level
tracking automatically — the authorizer fires for every column SQLite
needs to evaluate (projection, WHERE, ORDER BY, etc.).

**2. Writer side — per-stmt modified columns.** The same authorizer
context, with `track_writes=1`, captures `SQLITE_UPDATE` events (table +
column being SET) at writer prepare time. INSERT and DELETE arrive
without a column from SQLite, so they emit a `"table.*"` wildcard
sentinel meaning "any column dirty for this table" — the dispatch path
then degrades to today's table-only behaviour for those writes.

The cached set lives on the writer's `resqlite_cached_stmt::dep_columns`
array. On each `sqlite3_step`, the writer sets `db->writer_active_entry`
so the **preupdate hook** (which already fires per-row to populate
`dirty_tables`) merges the active stmt's pre-captured columns into a
new `dirty_columns` accumulator. This keeps dirty-column semantics
identical to dirty-table semantics: writes that modify zero rows leave
both sets clean, and per-row hook firings only do an O(small) dedup
linear scan.

**3. Dispatch elision.** `StreamEngine.invalidate(dirtyTables,
dirtyColumns?)` performs a per-table column-intersection check before
scheduling a stream for re-query:

```dart
// Pseudo-code from lib/src/stream_engine.dart:_writeAffectsEntry
for (final table in dirtyTables) {
  if (!entryDeps.contains(table)) continue;
  final writerCols = dirtyColumns[table];
  if (writerCols == null) return true;       // wildcard — re-query
  final readerCols = entryCols[table];
  if (readerCols == null) return true;       // unknown read cols — re-query
  for (final c in writerCols) {              // both concrete: intersect
    if (readerCols.contains(c)) return true;
  }
}
return false;                                 // disjoint — skip dispatch
```

The check is O(small × small) per watcher per dirty table — typically
2-5 columns each. It runs only when both sides have concrete column
sets; either side carrying a wildcard or empty set degrades to today's
unconditional re-query, so the experiment never *reduces* invalidation
fidelity.

### Files touched

- `native/resqlite.c` — `resqlite_column_set` ADT, authorizer extension,
  per-stmt `dep_columns` cache, writer authorizer install,
  `writer_active_entry` tagging, preupdate-hook column merging,
  `resqlite_get_read_columns` / `resqlite_get_dirty_columns` exports.
- `native/resqlite_deps.c`, `native/resqlite_deps.h` — bounded
  dependency-set primitives shared by read tables, dirty tables, and
  structured table/column pairs.
- `native/resqlite.h` — public FFI surface for the two new getters and
  `RESQLITE_MAX_DEP_COLUMNS = 64`.
- `lib/src/native/resqlite_bindings.dart` — `getReadColumns()` and
  `getDirtyColumns()` returning `Map<String, Set<String>?>` (null per
  table = wildcard).
- `lib/src/reader/read_worker.dart` — `executeQueryWithDeps` now returns
  the column map alongside table list.
- `lib/src/reader/reader_pool.dart` — `selectWithDeps` tuple shape
  extended.
- `lib/src/writer/write_worker.dart` — `ExecuteResponse` /
  `BatchResponse` carry `dirtyColumns`; rollback paths drain the column
  accumulator.
- `lib/src/writer/writer.dart`, `lib/src/database.dart` — thread
  `dirtyColumns` into `_streamEngine.invalidate`.
- `lib/src/stream_engine.dart` — `StreamEntry.columnDependencies`,
  `invalidate(dirtyTables, dirtyColumns)` performs the intersection,
  graceful degradation to table-only when either side is unknown.

## Results

Benchmark: [`benchmark/results/2026-04-25T22-10-11-exp106-column-level-deps.md`](../benchmark/results/2026-04-25T22-10-11-exp106-column-level-deps.md)
(compared explicitly against the cap=4 baseline at
[`2026-04-25T19-43-21-baseline-for-exp105.md`](../benchmark/results/2026-04-25T19-43-21-baseline-for-exp105.md)).

### A11c (50 streams × 500 writes)

| Scenario | Cap=4 baseline | exp106 | Delta |
|---|---|---|---|
| No-streams (writer ceiling) | 50,110 w/s | run-to-run noise (noisy) | — |
| **Disjoint column writes** | **3,956 w/s** | **7,201 w/s** | **+82%** |
| Overlap column writes | 4,477 w/s | 4,581 w/s | +2.3% (within noise) |
| Overlap/disjoint ratio | 1.132 | **0.636** | exactly the signal exp 052 was designed to deliver |

The no-streams baseline column has high run-to-run variance (the
benchmark stability column flags it as "noisy", CV ~23%) because it's a
pure write loop with no streaming work and dominates short total wall
time. Median run-to-run drift on a no-stream workload is not
attributable to this change — the no-streams path doesn't exercise
`StreamEngine.invalidate` at all.

The disjoint w/s lift (+82%) clears the ≥+50% target threshold in the
experiment scope. The overlap-vs-disjoint ratio dropping from 1.132 to
0.636 is the direct measurement of writer-side dispatch elision —
overlap writes still pay the per-stream dispatch cost, but disjoint
writes now skip the re-query entirely.

The disjoint case still doesn't reach the no-streams ceiling because the
writer mutex, FFI crossing, and dirty-set drain all stay on the per-write
path. Reaching the ceiling would require also eliding the
`getDirtyColumns` / `getDirtyTables` round-trip when no stream watches
the dirtied table — a follow-up experiment.

### Other A11/A11b workloads

- **A11b High-Cardinality Stream Fan-out (100 streams × 200 writes):**
  ~244 ms (cap=4 baseline 240 ms) — **flat**. The fan-out workload has
  all 100 streams watching the same column (`name`) and writes touch
  that column, so column-level elision does not apply. Confirms the
  elision is selective rather than wholesale.
- **Disjoint Columns Stream Suite:** re-emit ratio for resqlite stays
  at 0.000 on disjoint scenarios — same as before. The stream-side hash
  short-circuit (exp 075) was already at 0 emissions; this experiment
  adds the writer-side dispatch elision on top, so the *cost* of getting
  to that 0-emission state is what dropped, not the emission count
  itself.

### Suite-wide

**24 wins, 2 regressions, 144 neutral** against the cap=4 baseline.

The two flagged "regressions" are:
- `Many-Streams Writer Throughput / Overlap-vs-disjoint ratio` flagged
  +82% — this is the diff tool reading the raw disjoint w/s value
  (higher = "regression" in its sign convention); in fact disjoint w/s
  rose from 3,956 to 7,201, which is the experiment's primary win. The
  ratio-row entry on the next line correctly classifies the
  1.13 → 0.63 ratio drop as a Win (-44%).
- `Large Working Set (Cold cache, 3 rounds with shrink_memory)`:
  0.10 → 0.13 ms (+25 % on a 0.02 ms absolute delta, MDE ±17 %). This
  is the cold-cache shrink_memory probe — high run-to-run variance
  (the stability column flags it as "moderate") and the change to the
  authorizer hook does not run on this code path. Reads as run noise.

A first iteration of this experiment kept the per-reader column scratch
hot — every cache hit re-strdup'd up to 64 column strings — and that
showed up as ~12-50% regressions on Schema Shapes (1000 rows) wide /
numeric / text and Scaling (10–20k rows) [main]. The fix was to skip
the per-reader scratch on cache hits entirely: `last_entry` records the
most-recent acquire and the FFI getters serve directly from the
cached stmt entry. After that fix the Schema Shape / Scaling regressions
all disappeared (they're now neutral against cap=4).

Memory: a small regression on 10k-row workloads (~3–5 MB on
`Memory / Batch insert 10k rows / resqlite executeBatch()` and
`Memory / Select 10k rows → Maps / resqlite select()`). Each cached
stmt entry now also stores its captured column set (up to 64 strings
per entry, capped at 32 cached entries per connection). The 95% CI on
the regressions includes 0 MB on the lower bound — these are RSS
outliers driven by p90 rather than a tight median. Acceptable for the
+82% writer-throughput win on the workloads exp 052 was designed for.

## Decision

**Accepted.** The change ships measurable writer-side dispatch elision
on the workloads exp 052 was originally designed for, with no functional
regressions to the invalidation contract:

- `dart test` — 209/209 tests pass (no test had to change).
- Ad-hoc smoke test confirmed the elision: with a stream watching
  `SELECT id, a, b FROM wide`, an `UPDATE wide SET c = …` produces 0
  emissions while `UPDATE wide SET a = …` produces 1.
- Suite shows the predicted shape: A11c disjoint up significantly,
  overlap unchanged, A11b unchanged (single-column projection), other
  paths neutral.

The ≥+50% disjoint threshold is met (+82%). The overlap-vs-disjoint
ratio dropping from 1.132 to 0.636 is the experiment's clearest
signature — it's exactly the writer-side dispatch elision that the A11c
benchmark was added to PR #39 to make visible.

## Notes for follow-ups

- **All-cols sentinel for INSERT/DELETE** is conservative — it forces a
  re-query for any stream watching the inserted/deleted table, even if
  the WHERE clause means no row could enter or exit that stream's
  result. Tighter handling would need preupdate-hook per-column diffing
  (which exp 057 rejected as below-noise on bulk writes) or a custom
  SQL parser. Out of scope here.
- **Dirty-set drain elision** could push disjoint w/s closer to the
  no-streams ceiling: if `_streamEngine` knows no stream watches any of
  the dirtied tables, the writer could skip `getDirtyColumns` /
  `getDirtyTables` entirely. The current code always drains both sets
  for every write.
- **Wildcard column reads** for triggers / views: the authorizer fires
  inside trigger bodies and view evaluations with concrete column
  names, so this case is already handled — but if SQLite ever emits a
  `SQLITE_READ` with a NULL column (compile-flag dependent), the
  reader-side wildcard path picks it up.

## Polish (post-2026-04)

Two rounds of design review on the original commit (PR #42) surfaced
three correctness gaps and three code-quality gaps in the column-level
tracking code. The polish landed as a stacked branch
(`exp-106-polish`); the design plan is at
`.claude/plans/exp-106-polish-design.md` (v4) and the rationale below
summarises what changed and why.

### Gaps fixed

* **C1 — silent overflow at 64 columns.**
  `column_set_add` returned without signal when the cap was hit;
  writers that touched a column past the cap had it silently dropped
  from `dirty_columns`, and readers' `dep_columns` truncated their
  projection set. The intersection check then saw "disjoint" and
  silently elided dispatch — a stuck stream.
* **C2 — silent failures in `column_set_compose` / `strdup`.**
  An OOM-fallback path in `column_set_compose` returned `-1` and the
  caller no-oped. `stmt_cache_entry_set_dep_columns` incremented
  `dep_column_count` even when `strdup` returned NULL, leaving a NULL
  entry that subsequent dedup scans would dereference.
* **C3 — same silent failures in `read_set_add` and `dirty_set_add`.**
  Worse than C1: a stream whose `read_set` overflowed got *zero*
  table dependencies (the cap-truncated set had no overflow signal);
  it never invalidated. A writer whose `dirty_set` overflowed
  reported an under-set of dirty tables; real invalidations were
  silently missed.
* **C4 — no reliability signal at the FFI boundary.**
  Even if the C side knew a set was unreliable, the Dart side
  couldn't tell — both unreliable and reliable-empty returned 0.

The fix is a uniform reliability discipline: each set carries an
`int reliable` flag, init 1, set to 0 on first overflow / OOM /
strdup failure during a capture cycle. Add functions become no-ops
once unreliable. Cache entries inherit reliability from the source
sets. The asymmetric FFI boundary is the load-bearing piece:

* **column getters** (`resqlite_get_read_columns`,
  `resqlite_get_dirty_columns`) return 0 on unreliable. Zero entries
  is interpreted by `_writeAffectsEntry` as "absent column map for
  this table" and falls through to table-level re-query.
* **table getters** (`resqlite_get_read_tables`,
  `resqlite_get_dirty_tables`) return -1 on unreliable. Zero would
  mean "no deps" / "no dirty tables" — both result in stuck streams;
  -1 is the explicit unknown sentinel that forces the Dart side to
  route into the `_allTableEntries` bucket (subscribe path) or
  invalidate every active entry (write path).

A follow-up cleanup split the dependency tracking primitives out of
`native/resqlite.c` into `native/resqlite_deps.{c,h}` and changed
column metadata from packed `"table.column"` strings to structured
table/column pairs backed by one compact allocation. This removes
delimiter parsing at the FFI boundary and preserves table or column
names that contain dots.

The Dart layer captures the asymmetry in two types:
`TableDependencies` (`TableDependencies.fixed(tables)` vs
`TableDependencies.all`) at the FFI boundary, and `_allTableEntries`
at the StreamEngine level. The
contract is documented at the top of `lib/src/stream_engine.dart`:
*tables = correctness, columns = optimization*. The dispatch
elision policy is extracted into a `@visibleForTesting`
`ColumnInvalidationPolicy.affects` so direct unit tests can prove
the dispatch decision regardless of result-change-detection
confounds.

### Trigger / FK cascade verification (Phase 0)

The polish design hinged on whether SQLite's authorizer captures
column writes from triggers and FK cascades at the calling stmt's
prepare time. Three black-box tests were written *first*
(`test/stream_trigger_cascade_test.dart`) to discover this:

1. Cross-table `AFTER UPDATE` trigger.
2. Same-table `AFTER UPDATE OF col_a` trigger writing `col_b`. The
   dangerous case — preupdate-hook merge can only see the calling
   stmt's `dep_columns`, so unless the authorizer captured `col_b`
   at prepare time, the trigger-induced write is silently lost.
3. FK `ON DELETE CASCADE` from parent to child.

All three pass on the original exp-106 implementation. SQLite's
authorizer fires `SQLITE_UPDATE` events during prepare for every
column the calling stmt's bytecode could write (including those
generated from compiled trigger bodies and FK cascade actions). The
captured set is the correct dependency set; no additional
"trigger-touched stmt → unreliable column" fallback is needed. The
tests are locked in as regression protection.

### Performance check

Three workloads, vs `main` (the cap=4 baseline before exp 106):

| Workload | Main | Polish | Δ |
|---|---|---|---|
| A11c disjoint w/s | 4044 | 6976 | **+72.5 %** |
| A11c overlap w/s | 4431 | 4513 | +1.9 % (noise) |
| A11c overlap/disjoint ratio | 1.095 | 0.647 | -41 % (elision proof) |
| Schema Wide wall median | 1.153 ms | 0.934 ms | -19 % |
| Schema Numeric wall median | 0.364 ms | 0.330 ms | -9 % |
| Schema Nullable wall median | 0.386 ms | 0.319 ms | -17 % |
| A11b wall median | 245.51 ms | 241.86 ms | -1.5 % (noise) |

The +72.5 % on A11c disjoint is within run-to-run noise of the
+82 % originally reported for the unpolished exp 106 code (single-
iteration runs; the doc's three-iteration medians were tighter).
Crucially, the overlap/disjoint ratio drops to 0.647 — the
dispatch-elision signature — confirming the column elision still
works on the reliable path. Schema-shape reads stay flat or
improved (no read-path regression). A11b high-cardinality fan-out
stays flat.

### Out of scope

* **Schema watchdog / DDL invalidation.** A pre-existing hazard
  tracked by deferred [exp 068](068-ddl-schema-watchdog.md): when
  `ALTER TABLE` adds or drops columns, cached column metadata goes
  stale, but the cache is keyed on SQL text so the next prepare hits
  the cache and re-uses stale metadata. exp 106 inherits but does
  not introduce this. Documented here so future revisitors don't
  re-discover it as new.
* **Full SQLite-level OOM simulation.** The expanded cleanup added a
  small C-side fault-injection harness for the dependency primitives,
  so overflow and allocation-failure paths are covered directly.
  Simulating allocation failure across SQLite itself remains out of
  scope.
