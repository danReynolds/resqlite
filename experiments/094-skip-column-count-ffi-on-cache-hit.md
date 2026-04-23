# Experiment 094: Skip sqlite3_column_count FFI call on schema-cache hit

**Date:** 2026-04-23
**Status:** Rejected
**Archive:** [`archive/exp-094`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-094)

## Problem

`decodeQuery` (shared by every reader query and every transaction read)
opens with an unconditional FFI call:

```dart
final colCount = sqlite3ColumnCount(stmt);
var schema = schemaCache.remove(sql);
```

On a schema-cache **hit** — the common case once a SQL string has been
seen once — that FFI call is redundant: the cached `RowSchema` already
carries the column names, and `names.length` is the authoritative column
count.

Leaf FFI is cheap (~20–30 ns on AOT), but it fires on every decoded
query. The experiment asked whether the schema-cache branch could skip
it entirely, in the spirit of exp 077 ("cheap-check-first sweep").

## Hypothesis

Move `sqlite3_column_count` into the cache-miss branch and derive
`colCount` from `schema.names.length` on the hit branch. Savings
ceiling: one leaf FFI call per decoded query.

Rough back-of-envelope:

- Point query wall: ~11 µs per query
- Leaf FFI call: ~20–30 ns
- Savings: ~0.2 % per point query

That's smaller than single-run release-mode MDE (~10 %), which means
the a-priori expectation was "correct refactor, likely below noise
floor."

## Approach

Single-file edit in `lib/src/query_decoder.dart`:

```dart
var schema = schemaCache.remove(sql);
final int colCount;
if (schema != null) {
  colCount = schema.names.length;
  schemaCache[sql] = schema;
} else {
  colCount = sqlite3ColumnCount(stmt);
  schema = RowSchema(...);
  schemaCache[sql] = schema;
  if (schemaCache.length > _schemaCacheMax) { ... }
}
```

No C change, no FFI signature change, no API change. Pure
correctness-neutral re-order: the hit branch avoids the FFI call; the
miss branch pays it exactly once (same as before).

Safety: the RowSchema stored in the cache is constructed with exactly
`colCount` names from the same bound statement that will be stepped,
so `names.length` and the stmt's actual column count are equal by
construction. Re-prepare-on-schema-change invalidates the whole stmt
cache in C (caller re-enters the miss branch), so stale-colCount
cannot occur any more than it already could for the cached names list
itself (cf. exp 068).

## Results

Release-mode single-run A/B on the comprehensive benchmark suite:

- Baseline: `benchmark/results/2026-04-23T11-05-03-round6-baseline.md`
- Candidate: `benchmark/results/2026-04-23T11-08-49-exp094-skip-column-count.md`

Representative `resqlite select()` medians (ms):

| Rows | Baseline | Candidate | Δ% |
|---:|---:|---:|---:|
| 10 | 0.104 | 0.101 | −3 % |
| 100 | 0.158 | 0.071 | −55 % |
| 1000 | 0.702 | 0.439 | −37 % |
| 10000 | 8.867 | 5.686 | −36 % |

At face value the candidate "wins" by 36–55 % on the larger result sets.
That cannot be attributable to this change: the savings ceiling is
one ~25 ns FFI call per query, which is 0.0003 % of an 8.8 ms 10k-row
decode. A 36 % delta on a multi-millisecond wall is three orders of
magnitude larger than the theoretical headroom.

Cross-checking against a workload that **cannot** exercise the changed
code — `resqlite selectBytes()` goes through `executeQueryBytes`, not
`decodeQuery`, so it shares zero lines with the candidate:

| Rows | Baseline | Candidate | Δ% |
|---:|---:|---:|---:|
| 10 | 0.021 | 0.020 | −5 % |
| 100 | 0.058 | 0.058 | 0 % |
| 1000 | 0.386 | 0.367 | −5 % |
| 10000 | 4.394 | 4.668 | +6 % |

selectBytes also swings ±5–6 %, and 10k-row selectBytes went the
other way (+6 %). The swings on both sides line up with the release-
mode MDE (±10 %) rather than with the 25 ns theoretical savings.

Other non-decode workloads also swung in both directions:

- Point Query Throughput: 99 493 qps → 87 827 qps (−12 %) —
  cannot be caused by removing an FFI call.
- Concurrent Reads 2× concurrency: −60 % "win".
- Concurrent Reads 1× / 4× / 8×: +33 % to +98 % "regression".
- Parameterized Queries: +26 % "regression".

These are mutually inconsistent — you can't both regress 98 % at
8× concurrency and win 60 % at 2× from a single-line Dart re-order.
The picture is run-to-run noise, not signal.

## Decision

Rejected. The change is correctness-neutral and measurably safe, but
the theoretical savings ceiling (~25 ns per decoded query) is two to
three orders of magnitude below the release-mode single-run MDE. A
multi-run profile-mode A/B could plausibly resolve a sub-percent
effect, but at 0.2 % the payoff does not justify the extra local
complexity of a split `if/else`-bound `colCount` variable (currently
one straight-line FFI call).

Same class as:

- Exp 076 — pre-bound stmt cache, rejected in pre-analysis
  ("bind is ~0.3 % of re-query wall time").
- Exp 093 — alias cache entry read-tables, rejected after measurement
  ("work medians unchanged, tail regressions attributable to run-
  to-run variance").

The FFI call elision is a legitimate future micro-opt if it rides in
on a broader refactor of the decode entry-point (e.g. returning
colCount alongside the stmt pointer from `resqlite_stmt_acquire_*`
in a single FFI call that already exists). Standalone, it's not worth
the split.

## What this tells us

- **Single-run release-mode A/B cannot resolve sub-percent changes.**
  MDE sits around ±10 %. For a candidate whose ceiling is 0.2 %, we
  need either (a) a focused microbenchmark that strips away
  everything else the decode path measures, or (b) a profile-mode
  multi-run A/B with ≥ 7 runs per side to get tail metrics to settle.
- **FFI call count on the cached hot path is not a productive
  optimization target at current release-mode measurement precision.**
  Bundle changes like this into broader refactors where they can
  amortize their own measurement cost.

## Archive

The single-file implementation is preserved at `archive/exp-094`
for future re-evaluation if the decode-path entry signature changes
(e.g. a combined acquire-and-colCount FFI entry point) or a
microbenchmark harness becomes available that can resolve FFI-call-
count differences below the benchmark-suite noise floor.
