# Experiment 133: Multi-row INSERT chunking

**Date:** 2026-05-08
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** None (focused profile/public guard harnesses)

## Problem

Exp 130 split the native wide-batch call and showed that reset and statement
lookup are no longer meaningful targets. The large remaining write-side bucket
is SQLite row stepping plus transaction finish. Exp 131 ruled out top-level
batch-wrapper reshaping, and exp 132 handled the narrow WAL-checkpoint part of
COMMIT.

The open question was whether the current `executeBatch` shape itself leaves
row-step work on the table: one user row is bound and executed with one
`sqlite3_step`, even when the SQL is a simple `INSERT ... VALUES (?, ...)` that
SQLite can execute as a multi-row VALUES statement.

## Hypothesis

For large simple insert batches, internally rewriting:

```sql
INSERT INTO t(a, b) VALUES (?, ?)
```

to:

```sql
INSERT INTO t(a, b) VALUES (?, ?), (?, ?), ...
```

can reduce `sqlite3_step` count without changing the public API. The rewrite
should only ship if it is narrowly guarded enough to avoid SQL parser risk and
small-batch regressions.

## Approach

Added `benchmark/profile/multi_row_insert_ceiling.dart` to measure the direct
native ceiling across rows-per-step values.

Then added a guarded writer-side implementation in
`lib/src/writer/batch_insert_chunker.dart`:

- only simple positional `INSERT ... VALUES (?, ...)` SQL;
- double-quoted, backtick, and bracketed identifiers are supported, with the
  `VALUES` keyword scan ignoring identifier contents;
- comments, string literals, trailing clauses, named parameters, expressions,
  and nested parentheses still fall back to the old path;
- only batches with at least 2,000 rows;
- non-divisible batch lengths split into full chunks plus one tail segment;
  small tails keep the caller's original SQL while larger tails get a generated
  multi-row statement;
- target 100 user rows per SQLite step, bounded by the bundled
  SQLite/sqlite3mc variable ceiling;
- all unsupported shapes fall back to the existing one-row-per-step path.

Added `benchmark/profile/multi_row_insert_public_guard.dart` to compare the
public optimized path against the same public API with a comment-forced
fallback. Quoted identifiers are measured as a separate optimized mode.

The first broadening attempt used only `ListBase` views over the original row
matrix. That removed temporary chunk-list copies, but the indexed view overhead
flattened the wide-batch signal. The retained version adds
`lib/src/native/batch_param_source.dart`: the writer still passes a list-shaped
chunk source, but the native parameter encoder recognizes it and walks the
original row matrix directly.

Top-level multi-segment plans run inside one explicit writer transaction, so a
tail failure rolls back earlier full chunks. Inside an existing transaction,
segments use the nested batch helper and rely on the outer transaction rollback
path. Both paths keep generated-SQL failures remapped to the caller's original
SQL.

## Results

Ceiling command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/multi_row_insert_ceiling.dart \
  --markdown --repeats=5 --rows=10000
```

Raw output:

```text
benchmark/profile/results/exp-133-multi-row-insert-ceiling.md
```

Best direct-native ceiling by workload:

| workload | baseline wall | best rows/step | best wall | wall delta | effective delta |
|---|---:|---:|---:|---:|---:|
| narrow 2 params | 4.44 ms | 200 | 2.07 ms | -53.4% | -50.1% |
| wide mixed ASCII | 12.28 ms | 100 | 10.30 ms | -16.1% | -9.6% |
| wide mixed Unicode | 14.10 ms | 100 | 11.94 ms | -15.3% | -8.7% |
| wide mixed emoji | 16.30 ms | 50 | 14.18 ms | -13.0% | -8.2% |
| blob-heavy 8 params | 6.57 ms | 100 | 4.57 ms | -30.5% | -23.2% |

The prototype chunk-building cost matters, so the effective delta is the
decision number. Narrow and blob-heavy batches have clear headroom; wide text
batches have smaller but still positive ceiling once chunk cost is included.

Public guard command:

```text
dart run benchmark/profile/multi_row_insert_public_guard.dart \
  --markdown --repeats=21 --rows=10000
```

Raw output:

```text
benchmark/profile/results/exp-133-multi-row-insert-public-guard.md
```

Public `executeBatch` A/B medians:

| workload | fallback wall | optimized wall | quoted optimized wall | optimized delta | quoted delta |
|---|---:|---:|---:|---:|---:|
| narrow 2 params | 4.48 ms | 3.22 ms | 3.07 ms | -28.1% | -31.5% |
| wide mixed ASCII | 18.11 ms | 17.30 ms | 17.54 ms | -4.4% | -3.2% |
| blob-heavy 8 params | 12.33 ms | 10.93 ms | 10.37 ms | -11.3% | -15.9% |

The wider 21-pass guard shows why this should not be oversold: narrow and blob
remain clear wins, while wide ASCII is positive but much smaller than the first
7-pass result. The direct matrix packer is still better than the view-only
attempt, which flattened the wide result into noise.

Release write-suite spot check before/after the guarded implementation:

| workload | before | after | note |
|---|---:|---:|---|
| Batch Insert 100 rows | 0.098 ms | 0.099 ms | below rewrite threshold |
| Batch Insert 1000 rows | 0.406 ms | 0.412 ms | below rewrite threshold |
| Batch Insert 10000 rows | 3.987 ms | 3.017 ms | optimized |
| Tx executeBatch 100 rows | 0.099 ms | 0.114 ms | below rewrite threshold / run noise |
| Tx executeBatch 1000 rows | 0.465 ms | 0.503 ms | below rewrite threshold / run noise |

The first implementation attempted to rewrite 100-row and 1000-row batches.
That exposed the cutoff: 100-row batches regressed because Dart chunking and
longer SQL were too much overhead for the tiny absolute workload, and 1000-row
batches were near the noise floor. The final guard starts at 2,000 rows.

## Decision

**Accept for local branch.**

This is the first post-exp-132 path that changes the actual step count rather
than shaving around the write helper. The useful improvement is not universal:
it applies to large, simple positional INSERT batches, now including common
quoted-identifier ORM output and odd batch lengths. The guard is intentionally
narrow so complex SQL and small batches keep the old behavior.

## Future Notes

- Keep the parser conservative. A broader SQL recognizer should earn its way
  with production workload evidence, not speculative coverage.
- Do not reintroduce generic `ListBase` view packing on this hot path. The
  retained direct matrix packer exists because view indexing erased the wide
  signal.
- Do not reuse this result to justify multi-row rewrites for UPDATE/DELETE or
  general SQL. The value comes from SQLite's native multi-row INSERT grammar.
- If this survives soak, watch the wide-batch signal specifically; it is
  positive but much less decisive than the narrow/blob results.
