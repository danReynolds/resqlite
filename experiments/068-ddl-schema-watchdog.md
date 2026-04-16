# Experiment 068: DDL schema_version watchdog

**Date:** 2026-04-16 (shipped), 2026-04-16 (reverted same day)
**Status:** Deferred (correctness idea valid, implementation hit a stmt-cache race that needs more design work)

## Problem

Active streams cache their read tables at registration time via the authorizer
hook. When DDL changes the schema — `CREATE TABLE`, `DROP TABLE`,
`ALTER TABLE` — the cached dependencies can go stale:

- `ALTER TABLE ADD COLUMN`: `SELECT * FROM t` streams return old column
  lists until the first unrelated write re-queries them.
- `DROP TABLE`: streams whose SQL references the dropped table return
  their last cached result forever (or error unpredictably on the next
  invalidation).
- `ALTER TABLE RENAME`: stream read-table mappings still point at the old
  name.

DDL doesn't fire the preupdate hook, so these changes go unnoticed by the
existing dirty-table tracking.

## Approach

Cache `PRAGMA schema_version` on the writer. Read it after each write
commit; if it moved, broadcast-invalidate every active stream and force
`_reDiscover` to rebuild dependencies against the new schema.

### C side

- Added `schema_version_stmt` (cached PRAGMA) and `last_schema_version`
  to `resqlite_db`.
- New FFI `resqlite_schema_changed(db)` returning 1/0/-1.

### Dart side

- Writer responses carry a `schemaChanged` flag.
- `StreamEngine.handleSchemaChange()` bumps every active entry's
  generation and dispatches `_reDiscover` — a re-run of the
  initial-query path (`selectWithDeps`) to recapture dependencies.
- `Database.execute` / `executeBatch` / commit path all check the flag.

Two correctness tests were added (`ALTER TABLE ADD COLUMN`, `DROP TABLE`)
and passed locally.

## Why Reverted

**CI revealed two failures** that didn't reproduce on the dev machine:

1. **A pre-existing test** (`re-query failure after initial success
   propagates error and recovers`) timed out. The existing test manually
   triggers `handleDirtyTables` after a column rename to simulate a
   data write landing on a DDL-affected table. With the watchdog in
   place, both `handleSchemaChange` (my code) and `handleDirtyTables`
   (the test) dispatch racing re-queries. The generation-check discards
   the older one; on CI's slower scheduling, the surviving path didn't
   complete within the 5-second test timeout.

2. **A new `ALTER TABLE ADD COLUMN` test** returned stale data — the
   second row after the new column was added showed `null` instead of
   the inserted value.

The root cause for #2 traces to an interaction between our C-level stmt
cache and SQLite's auto-reprepare:

- `decodeQuery` calls `sqlite3_column_count(stmt)` *before* the first
  `sqlite3_step`.
- SQLite auto-reprepares stale cached statements *inside*
  `sqlite3_step`, not before it.
- After DDL, a cached stmt still reports the old column count on
  `sqlite3_column_count` until it's been stepped once.
- We cache the stale count, decode N cells per row, and silently miss
  columns.

A partial fix (validate `schemaCache.names.length == colCount` and
rebuild the Dart-side schema on mismatch) helped locally but wasn't
enough — the C-level cached stmt itself was still the stale one, and
the column_count read happens before any step can trigger reprepare.

## Proper Fix (Future Work)

The clean implementation needs to invalidate the C-level stmt cache
when the schema version changes, not just the Dart-side schema cache.
Options investigated but not implemented in-session:

1. **Per-reader schema-version tracking.** Each reader records its
   last-seen schema_version. At the top of every query, compare against
   the writer's current version; if different, clear the reader's own
   stmt cache so the next prepare picks up the new schema cleanly.
2. **Explicit cache invalidation via a broadcast message.** Writer
   sends a "clear caches" request to every reader isolate on DDL. Needs
   careful coordination with in-flight queries.
3. **Use `sqlite3_stmt_busy` + defensive re-prepare.** Mark cached
   stmts stale on DDL, re-prepare lazily on next acquire.

All three need a deliberate design pass that the "quick win" framing
didn't support. Reverted to keep the rest of the round shippable and
CI green.

## Related

- Experiment 003 (C-level statement cache) — the caching design we
  need to extend
- Experiment 034 (per-worker schema cache) — the Dart-side cache that
  had its own validation gap
- Team proposal idea #1 (column-level invalidation) and #6 (row-level
  filter invalidation) — both benefit from the same infrastructure
  (reliable DDL invalidation + a stream-granularity benchmark)

## Decision

**Deferred.** The idea is sound and the need is real. Landing it
properly requires fixing the stmt-cache/auto-reprepare interaction,
which is a focused correctness effort rather than a quick win.
