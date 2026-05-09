# Experiment 134: Keyed PK dirty rowid elision

**Date:** 2026-05-09
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`
**Archive:** [`archive/exp-134`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-134)

## Problem

The keyed-PK subscription workload has 50 streams shaped like:

```sql
SELECT id, body, updated_at FROM items WHERE id = ?
```

Only 3 of the 200 deterministic writes hit watched rowids, but current
table/column invalidation still visits every stream for every write. The
hash-based `selectIfChanged` path suppresses visible emissions for misses, so
correctness is already good, but the library still pays per-stream
intersection and re-query scheduling work on the 197 miss writes.

Exp 122's future notes called this out as the next useful stream precision
target after reader-pool admission was closed: reduce keyed-PK miss-path work
without adding a new public observer API.

## Hypothesis

If the writer publishes dirty rowids alongside dirty tables/columns, and
`StreamEngine` attaches rowid precision only to verified simple
`WHERE id = ?` INTEGER PRIMARY KEY streams, then miss writes can skip before
column intersection and reader-pool re-query admission.

The implementation would be worth revisiting if:

- keyed-PK profile writer-burst wall drops materially;
- only observed hit writes reach per-stream intersection/re-query scheduling;
- A11c many-streams column-elision guardrails stay neutral;
- all uncertainty falls back to existing table/column invalidation;
- the row-level dependency model is explicit enough that the production code
  does not depend on a growing SQL-shape recognizer.

## Approach

The archived implementation accumulates dirty `(table, rowid)` pairs in a
bounded native set. It borrows the already-stable dirty-table name storage, so
single-row writes do not allocate another table string for rowid precision.
Overflow or allocation uncertainty returns zero rowid details and keeps the
existing table/column invalidation path.

Dart bindings decode those rowids into `TableRowDependency`. Row precision is
an optimization layer: when both stream and write sides have rowids, a
non-overlap skips immediately; when either side lacks rowids, the existing
column/table logic decides.

`StreamEngine` attaches read-side rowids only for narrow SQL it can prove:

- one positional parameter;
- a simple `FROM table WHERE id = ?` or intrinsic `rowid = ?` shape;
- exactly one tracked dependency table;
- for `id = ?`, `PRAGMA table_info(table)` confirms `id INTEGER PRIMARY KEY`;
- `SELECT rowid FROM table LIMIT 0` succeeds, excluding `WITHOUT ROWID`
  tables and views.

Everything else stays conservative.

## Results

Focused profile:
[`benchmark/profile/results/exp-134-keyed-pk-dirty-elision.md`](../benchmark/profile/results/exp-134-keyed-pk-dirty-elision.md)

| workload | baseline wall_ms | candidate wall_ms | delta | baseline intersection_entries | candidate intersection_entries |
|---|---:|---:|---:|---:|---:|
| keyed PK subscriptions | 25.54 | 12.45 | -51.3% | 10000 | 3 |

Release guardrails:

| workload | baseline | candidate | delta |
|---|---:|---:|---:|
| many-streams disjoint | 23,946 w/s | 24,618 w/s | +2.8% |
| many-streams overlap | 9,297 w/s | 8,763 w/s | -5.7% |
| public keyed-PK wall | 223.32 ms | 217.75 ms | -2.5% |

The public keyed-PK suite includes a quiet-window drain, so its 200 ms floor
hides most of the writer-burst improvement. The profile harness uses the exp
121 wall convention and stops at the final write, which isolates the cost this
experiment changes.

## Decision

**Rejected, but recorded as future evidence.**

This is a real keyed-PK miss-path optimization: 10,000 per-stream
intersection probes collapse to the 3 actual watched-row hits. The result is
strong enough to keep as evidence that row-level invalidation can matter for
keyed subscriptions.

The implementation shape is the problem. Making this an internal optimization
requires `StreamEngine` to recognize and prove more SQL text shapes over time.
That is too fragile for the value captured here, especially because aliases,
joins, composite keys, non-`id` aliases, views, and `WITHOUT ROWID` tables all
need conservative escape hatches. The production implementation has been
removed from the PR; the implementation commit is preserved by the archive tag
for future reference.

## Future Notes

- Do not revive this by broadening the SQL recognizer. The next viable version
  should start from an explicit row-observer API, trace metadata, or another
  stronger dependency model.
- If a real workload spends material wall time on keyed-PK miss writes, use
  this profile result as the evidence that row-level precision is worth
  designing deliberately.
- If the public keyed-PK benchmark is used as the headline in the future,
  consider adding a writer-burst variant without the quiet-window drain; the
  current public suite is intentionally emission-stability oriented.
