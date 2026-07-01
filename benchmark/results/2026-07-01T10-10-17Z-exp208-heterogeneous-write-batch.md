# Exp 208: Heterogeneous Write Batch

Focused benchmark:

```bash
dart run benchmark/experiments/heterogeneous_write_batch.dart --order=transaction-first
dart run benchmark/experiments/heterogeneous_write_batch.dart --order=batch-first
```

Each round applies 400 heterogeneous statements: 200 inserts into `items` and
200 counter updates, all in one transaction. The baseline lane uses the current
interactive transaction API (`db.transaction` + `await tx.execute(...)` for
each statement). The candidate lane uses the prototype
`db.executeStatements([...WriteStatement...])` request, which applies the same
statements in one transaction and one writer-isolate request.

## Transaction-First

```text
=== Heterogeneous write batch experiment (exp 208) ===
order: _Order.transactionFirst
rounds: 7; statements per round: 400

transaction loop (400 statements): median 4.895ms  rounds [14.549, 6.731, 5.780, 4.895, 4.531, 4.337, 3.613]ms
statement batch (400 statements): median 0.517ms  rounds [2.914, 1.128, 0.846, 0.505, 0.517, 0.444, 0.393]ms
```

Median delta: -89.4% (about 9.5x faster).

## Batch-First

```text
=== Heterogeneous write batch experiment (exp 208) ===
order: _Order.batchFirst
rounds: 7; statements per round: 400

transaction loop (400 statements): median 4.819ms  rounds [10.577, 6.372, 5.809, 4.819, 4.146, 3.839, 3.612]ms
statement batch (400 statements): median 0.633ms  rounds [4.380, 1.146, 0.954, 0.550, 0.497, 0.633, 0.433]ms
```

Median delta: -86.9% (about 7.6x faster).
