# Experiment 226: Reject one-pass numeric batch packing

**Date:** 2026-07-13
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** none — focused
  [`benchmark/experiments/batch_param_flatten.dart`](../benchmark/experiments/batch_param_flatten.dart);
  two order-flipped numeric execute/marshal pairs plus late-payload guards in
  [`benchmark/results/2026-07-13T10-19-38Z-exp226-one-pass-numeric-batch.md`](../benchmark/results/2026-07-13T10-19-38Z-exp226-one-pass-numeric-batch.md).
**Archive:** [`archive/exp-226`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-226)

## Problem

[Exp 109](109-inline-param-buffer.md) established the native
`[resqlite_param structs][TEXT/BLOB payload]` arena, and
[exp 113](113-direct-batch-param-matrix.md) removed the temporary flattened
Dart list for wide batches. The generic matrix packer still walks every value
twice:

1. scan for TEXT/BLOB payload bytes (and encode strings), then
2. allocate the arena and write every parameter struct plus payload.

For a NULL/INTEGER/FLOAT-only matrix, the first pass discovers
`extraBytes == 0`. Its final size was already known from
`24 * rowCount * paramCount`, so the full sizing scan looked removable. This
is distinct from exp 113's list-flattening win and from exp 125/126's direct
TEXT encoding: it targets the remaining scan on fixed-width numeric batches.

The run used Dart 3.12.2. The official
[Dart 3.12 announcement](https://dart.dev/blog/announcing-dart-3-12) describes
language and tooling additions, but no collection or FFI primitive that makes
this matrix scan free; the question still needed a workload A/B.

## Hypothesis

If the first row contains only INTEGER/FLOAT values, allocate the exact struct
arena and pack once. Continue accepting NULL later in the matrix. If a later
TEXT/BLOB appears, free the speculative arena and retry through the unchanged
generic packer so SQLite's dynamic parameter types remain fully supported.

Accept only if 10k x 8 and 10k x 20 numeric `executeBatch` rows both reproduce
at least 5% candidate-faster across an order flip. Marshal-only improvement is
supporting evidence, not acceptance. Reject if either public row stays below
the gate or the adversarial late-payload path regresses by more than 3-5%.

## Approach

The archived prototype changed only private parameter packing:

- reuse the existing six-parameter / 600-total-cell admission floor;
- require row 0 to contain only `int`/`double` before speculating;
- allocate exactly `_paramStructSize * totalCount` and write NULL, INTEGER,
  FLOAT, and unsupported-as-NULL values in one pass;
- if any later `String` or `Uint8List` appears, release that arena and call the
  unchanged generic packer.

There is no stable-column cache, declared-type assumption, or API change.
SQLite parameters are dynamically typed, so the fallback is load-bearing, not
an edge that can be optimized away.

The focused batch harness gained `numeric`, `numeric-late-text`, and
`numeric-late-blob` cell modes. Numeric rows mix INTEGER/FLOAT/NULL. The late
modes put one payload in the final row, directly measuring the speculation
cost. A public correctness test covers a numeric first row followed by NULL,
TEXT, and BLOB values.

## Results

Full tables are in the linked result artifact. Decision rows:

| Workload | Pass 1 | Pass 2 | Read |
|---|---:|---:|---|
| numeric marshal 10k x 8 | -28.0% | -27.6% | mechanism reproduced |
| numeric marshal 10k x 20 | -25.4% | -25.8% | mechanism reproduced |
| numeric execute 10k x 8 | -0.9% | -6.0% | unstable magnitude |
| numeric execute 10k x 20 | -3.4% | -1.4% | below 5% both passes |
| late TEXT execute 10k x 8 | -0.8% | +2.0% | neutral/mixed |
| late TEXT execute 10k x 20 | +7.0% | +4.9% | reproduced regression |

The isolated saving is real: one-pass packing removes about 0.11 ms at 10k x
8 and 0.23 ms at 10k x 20. The public operation still spends roughly
4.5-7.8 ms binding and stepping 10,000 rows, so the removed scan is only a few
percent of end-to-end wall.

The dynamic fallback is worse. On 10k x 20 the candidate zeroes and fills a
4.8 MB struct arena, sees the final TEXT value, releases it, then performs the
original generic allocation and pack. That penalty reproduces at 5-7%.

## Decision

**Rejected.** Keep the existing two-pass generic batch packer.

This is the same decision boundary exp 210 established for repeated BLOBs:
marshal-only gains are not enough when the writer/SQLite workload does not
carry them. Here, the end-to-end numeric result misses the predeclared gate and
the necessary dynamic fallback adds a real regression.

The exact runtime prototype is preserved at `archive/exp-226` and removed from
the publication branch. The focused numeric/late-payload modes and correctness
guard remain because they are reusable for any future parameter-layout or
type-specialization proposal.

Reopen one-pass fixed-width packing only if a future internal representation
can preserve first-pass struct writes when payload appears, without allocating
and discarding the full arena, and a production/profile workload shows numeric
parameter packing above 5% of batch wall. Do not infer stable types from row 0
or declared SQLite affinity.

## Validation

- `dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart benchmark/experiments/batch_param_flatten.dart test/database_test.dart`
- focused dynamic fallback database test on the prototype and reverted branch
- two order-flipped numeric execute pairs
- two order-flipped numeric marshal-only pairs
- two order-flipped late-TEXT execute pairs and a late-BLOB guard pass
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/226-one-pass-numeric-batch.md`
- full repository analysis/tests and disposition checks before publication
