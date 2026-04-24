# Experiment 097: One-pass initial stream decode and hash

**Date:** 2026-04-23
**Status:** In Review

## Problem

Initial stream registration decodes the query result for subscribers, then
replays the same SQLite statement through `resqlite_query_hash` to establish
the baseline result hash used by later `selectIfChanged` calls.

That two-pass setup is correct, but it is wasteful for workloads that create
many streams or frequently subscribe/cancel.

## Hypothesis

If the initial stream path fills the existing cell buffer and folds the native
FNV result hash during the same SQLite step pass, stream setup should improve
without changing public API behavior or the unchanged-result fast path.

## Approach

Added a native `resqlite_step_row_hash` helper used only by initial stream
registration. It mirrors `resqlite_step_row`, but also updates the same masked
FNV accumulator used by `resqlite_query_hash`.

Dart now uses a dedicated `decodeQueryWithInitialHash` path for
`selectWithDeps`. Normal `select()` still uses the existing decoder, and later
stream re-queries still use the hash-only `resqlite_query_hash` path so
unchanged results can skip Dart decoding entirely.

## Results

Artifacts:

- `benchmark/results/2026-04-23T19-38-11-exp097-one-pass-initial-stream-hash.md`
- `benchmark/results/2026-04-23T19-38-11-exp097-one-pass-initial-stream-hash.json`

Release benchmark summary: **6 wins, 0 regressions, 147 neutral**.

Key stream metrics:

| Benchmark | Previous | Current | Result |
|---|---:|---:|---|
| Fan-out (10 streams) | 0.24 ms | 0.21 ms | 14% faster |
| Stream subscription rate (500 subscribe+cancel) | 7.22 ms | 6.06 ms | 16% faster |
| Stream churn (100 cycles) | 2.06 ms | 1.53 ms | faster, but below threshold |
| Initial emission | 0.03 ms | 0.03 ms | tiny absolute delta, within noise |

The structured artifact also showed the expected direction on the targeted
setup-heavy paths:

| Benchmark | Baseline artifact | Experiment artifact |
|---|---:|---:|
| Initial emission | 0.036 ms | 0.025 ms |
| Fan-out (10 streams) | 0.267 ms | 0.211 ms |
| Stream churn (100 cycles) | 1.898 ms | 1.535 ms |
| Stream subscription rate (500 cycles) | 7.646 ms | 6.063 ms |

Correctness checks passed:

- `dart test test/stream_test.dart test/stream_invalidation_coalescing_test.dart test/stream_dependency_shapes_test.dart test/reader_pool_test.dart`

## Decision

Keep in review.

This is the only candidate from the sweep with a clean, targeted signal and no
reported release regressions. The main trade-off is code complexity: the
initial stream path now has a second decode loop that must stay hash-compatible
with `resqlite_query_hash`. The win is concentrated exactly where expected,
which makes it worth carrying to PR review.
