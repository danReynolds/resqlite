# Experiment 031: Worker-Side Result Hash for Stream Re-queries

**Date:** 2026-04-08
**Status:** Accepted

## Hypothesis

Stream re-queries transfer the full ResultSet from worker to main, then hash it
on the main isolate for change detection. For unchanged results (common in fanout
scenarios where many streams watch tables not directly affected by a write), this
wastes both SendPort transfer cost and main-isolate hash computation time.

Moving the hash to the worker avoids both: unchanged results send only a hash
(single int) instead of a full ResultSet, and the main isolate skips hashing
entirely.

## Design

New `QueryType.selectIfChanged`:
- Request includes `lastResultHash` as a 5th element
- Worker executes query, hashes the raw flat values list, compares
- If unchanged: sends `[hash, false]` — no ResultSet transfer
- If changed: sends `[[ResultSet, newHash], false]` — includes new hash

Pool adds `selectIfChanged()` that returns `(rows?, newHash)`.
StreamEngine's `_reQuery` uses this instead of `select()` + `_emitResult`.

The `hashRawResult()` function hashes the flat values list directly, producing
the same hash as `_hashResult` (which iterates via Row.values → MapMixin).

## Results

3-run comparison:

| Metric | Before | After (best of 3) | sqlite_reactive |
|---|---|---|---|
| **Fanout shared (25 watchers)** | 0.48ms | **0.32ms** (-33%) | 0.37ms |
| Fanout unique (25 queries) | 0.94ms | 0.84ms (~noise) | 0.58ms |
| Invalidation latency | 0.11ms | 0.11ms (unchanged) | 0.38ms |

The shared fanout improvement is clear: with 25 watchers on the same query, only
one re-query runs. If the result is unchanged (common), the worker sends a 1-int
hash instead of a full ResultSet with 25 subscribers iterating it.

The unique fanout improvement is marginal because each of 25 different queries
still needs to execute and transfer results. The bottleneck there is serial
dispatch through 4 workers, not hash computation.

## Decision

**Accepted** — shared fanout now beats sqlite_reactive (0.32ms vs 0.37ms).
Clean implementation, no downside (worker already has the flat values list,
hashing it is trivial).
