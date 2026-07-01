# Experiment 208: Heterogeneous Write Batch

**Date:** 2026-07-01T10:10:17Z
**Status:** Accepted
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none - focused `benchmark/experiments/heterogeneous_write_batch.dart`, order-flipped pair

## Problem

[Exp 197](197-true-group-commit-moonshot.md) proved that true group commit is a
large writer frontier: wrapping a coalesced standalone write burst in one SQLite
transaction made the focused concurrent-burst lane roughly 8x faster. It was
rejected because hiding that behavior behind `db.execute()` changes independent
autocommit semantics: read visibility, crash-window durability, and failure
atomicity no longer match the API users called.

The current explicit alternatives leave a gap:

- `executeBatch()` is fast and explicit, but only for one SQL statement repeated
  across many parameter sets.
- `transaction()` is flexible and explicit, but a heterogeneous write loop still
  sends one writer-isolate request per `tx.execute(...)`.

So the live question is not whether hidden commit merging is fast. It is whether
an explicit heterogeneous batch surface can capture that same semantic class
without making ordinary `execute()` surprising.

## Hypothesis

Assumption challenged: preserving a lean API means `transaction()` must be the
only public way to express a heterogeneous atomic write group.

Prototype: add a small `WriteStatement` value and
`Database.executeStatements(List<WriteStatement>)`. The method states the
semantics up front: many SQL statements, one writer request, one SQLite
transaction, all-or-nothing commit, and one stream invalidation after commit.
Inside an existing `transaction()` body, the matching `Transaction` method runs
the same statement list inside the already-open transaction.

Expected result: a large win over the interactive transaction loop on static
heterogeneous write groups, while leaving `execute()`, `executeBatch()`, and
full interactive transactions unchanged.

## Approach

The candidate adds one public value object:

```dart
const WriteStatement('INSERT INTO items(body, n) VALUES (?, ?)', ['row_1', 1])
```

and one database method:

```dart
await db.executeStatements([
  const WriteStatement('INSERT INTO items(body, n) VALUES (?, ?)', ['row_1', 1]),
  const WriteStatement(
    'UPDATE counters SET value = value + 1 WHERE name = ?',
    ['items'],
  ),
]);
```

The writer isolate handles a new `StatementBatchRequest`. At top level it:

1. starts `BEGIN IMMEDIATE`,
2. executes each statement through the existing `executeWrite` path,
3. commits once,
4. returns every `WriteResult`,
5. harvests dirty dependencies once for stream invalidation.

If any statement throws, the handler rolls back the whole transaction and
propagates the original `ResqliteQueryException`. In an existing transaction,
the handler skips its own BEGIN/COMMIT and lets the enclosing transaction own
rollback and stream invalidation, matching `Transaction.executeBatch`.

## Results

Focused harness:

```bash
dart run benchmark/experiments/heterogeneous_write_batch.dart --order=transaction-first
dart run benchmark/experiments/heterogeneous_write_batch.dart --order=batch-first
```

Each round applies 400 heterogeneous statements: 200 inserts and 200 counter
updates. Medians below are from 7 rounds per side.

| Order | Transaction loop | Statement batch | Delta |
|---|---:|---:|---:|
| transaction first | 4.895 ms | 0.517 ms | -89.4% |
| batch first | 4.819 ms | 0.633 ms | -86.9% |

The result is large and order-stable: the explicit statement batch is about
7.6x to 9.5x faster than the current interactive transaction loop on a static
heterogeneous write group. The win is exactly the one-request shape: both lanes
use one SQLite transaction, but the baseline sends 400 writer requests and the
candidate sends one.

Validation:

```bash
dart analyze --fatal-infos lib test/execute_statements_test.dart benchmark/experiments/heterogeneous_write_batch.dart
dart test test/execute_statements_test.dart
```

## Decision

Accepted.

This keeps the exp 197 semantic boundary intact. `db.execute()` still means one
standalone autocommit write. The new API is opt-in and names the trade: callers
who already have a static list of heterogeneous statements can choose one
all-or-nothing transaction and avoid hundreds of isolate round trips.

The surface is narrow enough to fit the lean API rule because it mirrors the
existing `executeBatch()` shape rather than replacing `transaction()`:

- use `executeBatch()` for one SQL over many parameter sets,
- use `executeStatements()` for many SQL statements when no transaction reads or
  control flow are needed,
- use `transaction()` when the body needs reads, branching, savepoints, or
  statement-by-statement application logic.

## Future Notes

- Add a public release-suite lane if heterogeneous static write groups appear
  in downstream workloads. The focused harness is the current gate.
- Do not reopen hidden true group commit behind `execute()`. The accepted path
  is explicit semantics.
- If this API grows, keep the boundary strict: no implicit partial-success mode,
  no silent fallback to independent autocommits, and no replacement for
  interactive transaction reads.
