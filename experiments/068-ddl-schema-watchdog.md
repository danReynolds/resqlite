# Experiment 068: DDL schema_version watchdog

**Date:** 2026-04-16
**Status:** Accepted (correctness fix)

## Problem

Active streams cached their read tables at registration time via the authorizer
hook. When DDL changed the schema — `CREATE TABLE`, `DROP TABLE`,
`ALTER TABLE` — the cached dependencies became stale:

- `ALTER TABLE ADD COLUMN`: `SELECT * FROM t` streams returned old column
  lists until the first unrelated write re-queried them.
- `DROP TABLE`: streams whose SQL referenced the dropped table returned
  their last cached result forever (or errored unpredictably on the next
  invalidation).
- `ALTER TABLE RENAME`: stream read-tables still pointed at the old name.

DDL doesn't fire the preupdate hook (which is what our dirty-table tracking
relies on), so these changes went unnoticed by the stream engine.

## Hypothesis

SQLite bumps the `schema_version` PRAGMA on every DDL statement that changes
the schema. Reading it after each write commit is O(1) — a single page cookie
fetch — and lets us detect schema changes at the point they land.

When the watchdog fires, broadcast-invalidate every active stream: re-run
the initial-query path (`selectWithDeps`) so they re-discover their
dependencies against the new schema, and re-emit if the result actually
changed.

## Approach

### C side

- Added `sqlite3_stmt* schema_version_stmt` (cached `PRAGMA schema_version`)
  and `int last_schema_version` to the `resqlite_db` struct.
- Initialize on open; step once to capture the baseline.
- New FFI: `int resqlite_schema_changed(resqlite_db*)` — returns `1` if
  the version moved since last call, `0` if unchanged, `-1` on error.
  Protected by the writer mutex; total cost is a single cached stmt step
  (~1μs).
- Finalize the cached stmt in `resqlite_close`.

### Writer isolate

- Each of the three commit sites (`_handleExecute`, `_handleBatch` outside-tx
  branch, `_handleCommit` outermost-tx commit) reads dirty tables *and*
  calls `resqliteSchemaChanged`, packing both into a single response.
- Skip the check inside open transactions — the schema change is reported
  on the outermost commit via `_handleCommit`.

### Stream engine

- New `handleSchemaChange()` method on `StreamEngine`. When triggered,
  bumps `reQueryGeneration` on every active entry and dispatches a new
  `_reDiscover` pass.
- `_reDiscover` calls `pool.selectWithDeps()` to re-capture read tables
  against the new schema. Re-emits only if the result hash changed
  (benign DDL like RENAME COLUMN that doesn't affect a stream's projection
  stays invisible). On failure, propagates the error to subscribers.

### Call-site wiring

`Database.execute`, `Database.executeBatch`, and `Writer.<tx-commit>` each
check `response.schemaChanged` and call `_streamEngine.handleSchemaChange()`
before `handleDirtyTables()`.

## Results

### Correctness tests (new)

Two new test cases added to `test/stream_test.dart`:

- `ALTER TABLE ADD COLUMN re-emits with new schema (experiment 068)` —
  verifies the stream re-emits with the new column present, and that a
  subsequent INSERT on the new column is picked up by the refreshed
  dependencies.
- `DROP TABLE propagates error to active stream (experiment 068)` —
  verifies `onError` receives a `ResqliteQueryException` when the stream's
  underlying table is dropped.

Both pass. All 126 pre-existing tests also pass unchanged — total 128.

### Performance

**0 wins, 0 regressions on the 63-benchmark suite** (5 repeats vs baseline).

The per-write cost of the watchdog is a single cached-statement step
(~1μs), which is below the noise floor of the benchmark suite. Writes that
fired DDL (rare) pay an extra invalidation pass, but that path was broken
before — there's no "before" baseline to compare against for correctness.

## Decision

**Accepted as a correctness fix.** Stream invalidation on DDL is expected
behavior for a reactive query engine; this closes the gap. The performance
cost is negligible and offset by the new `getDirtyTables` persistent-buffer
optimization shipped in experiment 070.

## Edge cases handled

- **Rolled-back DDL**: SQLite reverts the schema version cookie on rollback,
  so the watchdog correctly reports no change after a failed DDL transaction.
- **Encrypted DB with pending key**: `prepare_v3` for the cached stmt may
  fail at open time if the key isn't set yet. `resqlite_schema_changed`
  returns 0 when `schema_version_stmt` is NULL — watchdog degrades
  gracefully to "disabled" rather than blocking open.
- **Benign DDL** (e.g., `ALTER TABLE RENAME COLUMN` for a column not
  selected by a stream): `_reDiscover` hashes the new result and only
  emits if it changed. Silent re-discover, no spurious emission.
- **Write during DDL**: the schema-change handler runs before dirty-table
  handling, so streams re-discover dependencies first, then normal
  invalidation routes to the refreshed mappings.
