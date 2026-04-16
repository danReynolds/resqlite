# Experiment 047: Authorizer opt-out for non-stream queries

**Date:** 2026-04-15
**Status:** Rejected

## Problem

The SQLite authorizer callback fires on every column access in every query, recording read table dependencies for stream invalidation. For non-stream reads (`select()`, `selectBytes()`), this dependency tracking is wasted work — the results are never checked.

## Hypothesis

Add a `tracking_enabled` flag to the `resqlite_reader` struct. The authorizer checks this first; if 0, it returns immediately (no `read_set_add`). Dart enables tracking only around `SelectWithDepsRequest` (initial stream queries). All other query types run with tracking disabled, saving one string comparison + linear scan per column access per row.

## Approach

1. Added `int tracking_enabled` to `resqlite_reader` struct.
2. Changed authorizer callback to check `reader->tracking_enabled` before `read_set_add`.
3. Changed `sqlite3_set_authorizer` to pass `resqlite_reader*` instead of `resqlite_read_set*`.
4. Added `resqlite_set_tracking()` C function, exposed via FFI.
5. Toggled tracking on/off around `SelectWithDepsRequest` in `read_worker.dart`.

## Results

**Streaming benchmarks timed out** — stream invalidation stopped working.

Root cause: **statement cache conflict.** When a non-stream `select()` prepares a statement with tracking OFF, the cache entry stores empty read tables. If a `stream()` later queries the same SQL, it hits the cache and loads the empty dependency set — the stream never discovers which tables it reads, so invalidation never fires.

The statement cache is shared between stream and non-stream queries by design. The `read_set_load_from_cache_entry` at `get_or_prepare_reader:930` loads cached dependencies regardless of tracking state, but only if the cache entry was populated when tracking was ON during the original prepare.

## Decision

**Rejected.** The shared statement cache makes per-query authorizer toggling unsafe without significant complexity (e.g., force re-prepare when tracking state changes, or maintain separate caches for stream vs non-stream queries). The authorizer callback is already very cheap: one `action_code == SQLITE_READ` comparison + one `read_set_add` that scans 1-3 table names. The overhead is dwarfed by actual SQLite query execution.
