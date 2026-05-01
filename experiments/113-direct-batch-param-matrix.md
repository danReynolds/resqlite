# Experiment 113: Direct batch parameter matrix encoding

**Date:** 2026-05-01T06:20:00
**Status:** In Review
**Direction:** `parameter-encoding-and-binding`, `measurement-system`
**PR:** [#70](https://github.com/danReynolds/resqlite/pull/70)

## Problem

Experiment 096 rejected direct nested batch parameter encoding because the
release suite did not show a reliable win and the implementation duplicated too
much encoder logic. Experiment 112 then narrowed the question to fixed-length
flattening, but its two-parameter batch benchmark still measured flat enough to
reject.

That left the exact future signal from experiment 112 untested: a batch workload
with much wider parameter rows. The current production path still flattens
`List<List<Object?>>` into a temporary `List<Object?>` before encoding native
parameter structs. For a 10,000-row, 20-parameter batch, that is a 200,000-entry
temporary list before the existing two-pass native buffer packer even starts.

## Hypothesis

If batch rows are wide enough, avoiding the temporary flat Dart list should
become visible. A direct matrix encoder can preserve experiment 109's inline
text/blob byte layout while writing native structs directly from the nested
`paramSets`.

Accept for PR review if a newly widened focused benchmark shows repeatable wins
on 8- and 20-parameter batch rows, while the original two-parameter shape stays
neutral. Reject if the wide-row benchmark overlaps with the baseline or the
implementation adds complexity without a clear target signal.

## Research Notes

External checks did not change the premise:

- Dart 3.11 is the current SDK in this worktree. The Dart 3.11 notes and SDK
  changelog do not expose a new collection-flattening primitive that would make
  the temporary list free; the decision needs to be empirical on this VM.
- SQLite's bind API still supports the same ownership and length contract used
  by experiment 109: callers can pass explicit byte lengths, and
  `SQLITE_STATIC` means the caller keeps the bound object valid until the
  statement is rebound or finalized.

Sources checked:

- Dart what's new / 3.11 release index: https://dart.dev/resources/whats-new
- Dart SDK changelog: https://dart.dev/changelog
- SQLite bind API: https://www.sqlite.org/c3ref/bind_blob.html

## Approach

First, widened the focused benchmark
`benchmark/experiments/batch_param_flatten.dart`:

- Keep the original 2-parameter shape.
- Add 8- and 20-parameter mixed rows.
- Prebuild `paramSets` outside the timed region.
- Time only `DELETE FROM items` followed by one `executeBatch`.

Then added `allocateBatchParams`, a batch-specific native parameter packer that:

1. Scans the nested matrix directly to encode strings and count inline
   text/blob bytes.
2. Allocates the same `[structs][bytes]` native buffer layout used by
   `allocateParams`.
3. Writes structs and inline bytes directly from each nested row.

Both top-level `executeBatchWrite` and nested transaction batch writes now use
the matrix encoder. Single-statement reads/writes continue to use the existing
`allocateParams` path.

## Results

Command for each pass:

```text
dart run benchmark/experiments/batch_param_flatten.dart --warmup=6 --iterations=24
```

Focused benchmark p50 wall time:

| Shape | Baseline 1 | Candidate 1 | Candidate 2 | Baseline 2 | Candidate range vs baseline range |
|---|---:|---:|---:|---:|---:|
| 100 rows x 2 params | 0.247 ms | 0.194 ms | 0.230 ms | 0.274 ms | mixed small-case noise |
| 1,000 rows x 2 params | 0.472 ms | 0.442 ms | 0.470 ms | 0.466 ms | neutral |
| 10,000 rows x 2 params | 3.979 ms | 3.857 ms | 3.966 ms | 3.885 ms | neutral |
| 100 rows x 8 params | 0.173 ms | 0.179 ms | 0.281 ms | 0.173 ms | noisy / small absolute |
| 1,000 rows x 8 params | 0.615 ms | 0.608 ms | 0.597 ms | 0.636 ms | -1% to -6% |
| 10,000 rows x 8 params | 8.146 ms | 6.152 ms | 6.020 ms | 8.147 ms | -24% to -26% |
| 100 rows x 20 params | 0.150 ms | 0.146 ms | 0.149 ms | 0.149 ms | neutral |
| 1,000 rows x 20 params | 1.202 ms | 1.059 ms | 1.063 ms | 1.230 ms | -12% to -14% |
| 10,000 rows x 20 params | 16.230 ms | 13.364 ms | 13.414 ms | 15.615 ms | -14% to -18% |

The original two-parameter shape stayed effectively neutral, which matches
experiment 112. The new wide shapes produce the missing signal: at 10,000 rows,
the 8-parameter case drops from ~8.15 ms to ~6.0 ms, and the 20-parameter case
drops from ~15.6-16.2 ms to ~13.4 ms.

Validation:

```text
dart analyze lib benchmark/experiments/batch_param_flatten.dart \
  test/database_test.dart test/transaction_test.dart
dart test test/database_test.dart test/transaction_test.dart
```

Both passed. A broader `dart analyze lib test benchmark/...` attempt hit an
existing generated-Drift setup issue unrelated to this change: the benchmark
Drift `*.g.dart` files were missing in the fresh worktree.

## Decision

Keep in review.

This is the changed premise that experiments 096 and 112 were missing. Direct
batch matrix encoding is still not worth accepting for the narrow two-parameter
benchmark, but it is a clear win for wider batch rows while preserving the
existing public API and experiment 109's inline native-buffer contract.

The trade-off is a second batch-specific encoder loop. That complexity is now
bounded to `executeBatch` and justified by the new workload: the implementation
removes a large temporary Dart list exactly when the matrix is wide enough for
that list to matter.

## Future Notes

Future batch-parameter work should include row width as a first-class dimension.
The two-parameter batch insert benchmark is still useful, but it is not a
sufficient proxy for ORM-style writes or generated statements that bind many
columns per row.

Do not re-open fixed-length flattening alone unless Dart's collection
implementation changes. The useful shape is avoiding the temporary flat list,
not merely constructing that list differently.

Post-merge review tightened the focused benchmark so `BLOB` columns now receive
small non-null `Uint8List` values instead of `null`. The original A/B table above
should be read as the row-width signal; future reruns of the script also cover
the blob byte-copy path directly.
