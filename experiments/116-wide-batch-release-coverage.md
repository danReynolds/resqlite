# Experiment 116: Wide batch insert release coverage

**Date:** 2026-05-01
**Status:** Accepted
**Direction:** `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** none (release-suite coverage row only; the public Wide Batch Insert lane it adds is exercised by downstream exp 125/126's runs)

## Problem

Experiment 113 showed that batch parameter row width is a real write-path
dimension. The existing release write suite still only tracked the narrow
two-parameter insert shape:

```sql
INSERT INTO t(name, value) VALUES (?, ?)
```

That narrow shape is useful, but it is not a sufficient guard for generated
statements or ORM-style sync writes that bind many columns per row. Without a
wide release-suite row, future parameter-encoding regressions could land while
the public write dashboard still looked neutral.

## Hypothesis

Adding a single 10,000-row x 20-parameter mixed-type batch insert to
`Write Performance` will preserve the current narrow batch metrics while making
wide batch behavior visible in release results and on the experiments
dashboard.

Accept if the workload runs across all four peers through the existing
`BenchmarkPeer.executeBatch` path, uses identical schema and parameter values,
and adds a clear metric key without expanding the release suite into every
focused-benchmark size/width combination.

## Approach

`benchmark/suites/writes.dart` now adds one subsection:

```text
Wide Batch Insert (10000 rows x 20 params)
```

The table shape mirrors experiment 113's mixed parameter matrix:

- 20 bound parameters per row.
- Column type cycle: `TEXT`, `INTEGER`, `REAL`, `BLOB`.
- 10,000 rows per timed `executeBatch`.
- Same warmup and iteration policy as the existing write suite.

`benchmark/drift/writes_db.dart` now registers the matching `wide_batch` table
so the drift peer participates through the same `BenchmarkPeer.executeBatch`
path as the other peers. The curated metric registry tracks the resqlite row as
`wide batch 10K x20` under the write chart.

## Results

Command:

```text
/Users/dan/Coding/flutter_arm64/bin/dart run benchmark/suites/writes.dart
```

Wide batch subsection:

| Library | Wall med | Wall p90 |
|---|---:|---:|
| resqlite executeBatch() | 21.896 ms | 26.800 ms |
| sqlite3 executeBatch() | 20.969 ms | 23.331 ms |
| sqlite_async executeBatch() | 28.151 ms | 35.365 ms |
| drift executeBatch() | 30.437 ms | 36.688 ms |

The narrow batch sections still execute normally in the same run:

| Shape | resqlite median |
|---|---:|
| Batch Insert (100 rows) | 0.098 ms |
| Batch Insert (1000 rows) | 0.459 ms |
| Batch Insert (10000 rows) | 4.294 ms |
| Wide Batch Insert (10000 rows x 20 params) | 21.896 ms |

Validation:

```text
/Users/dan/Coding/flutter_arm64/bin/dart pub get
/Users/dan/Coding/flutter_arm64/bin/dart run build_runner build --delete-conflicting-outputs
/Users/dan/Coding/flutter_arm64/bin/dart analyze --fatal-infos
/Users/dan/Coding/flutter_arm64/bin/dart run benchmark/suites/writes.dart
```

## Decision

**Accepted — measurement coverage.**

This experiment intentionally adds no production optimization. Its value is
that the release suite now tracks the exact workload dimension experiment 113
proved was missing: parameter width. Future batch-parameter work can compare
both the common two-parameter insert and the generated-statement-shaped
20-parameter insert without relying on a focused script alone.

## Future Notes

Do not add the full 2 / 8 / 20 parameter-width matrix to release mode unless a
future regression needs that granularity. The release suite should stay compact;
one wide mixed-type row is enough to keep the public dashboard honest while
focused experiments remain free to sweep width and row-count combinations.
