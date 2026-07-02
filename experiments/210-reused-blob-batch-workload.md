# Experiment 210: Reused BLOB batch workload and object-identity prototype

**Date:** 2026-07-02T10:17:08Z
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`, `measurement-system`
**Benchmark Run:** focused
  [`benchmark/experiments/batch_param_flatten.dart`](../benchmark/experiments/batch_param_flatten.dart)
  BLOB modes plus
  [`benchmark/profile/run_tracelite_profile.dart`](../benchmark/profile/run_tracelite_profile.dart)
  `blob_merge_rounds`; see Results.
**Archive:** [`archive/exp-210`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-210)

## Problem

The current batch encoder already writes `Uint8List` values directly into the
single native parameter arena. That means ordinary BLOB params do not have the
same removable temporary `utf8.encode()` allocation that made the wide-text
packing wins in exp 125, exp 126, exp 149, and exp 150 worthwhile.

One narrower case still looked plausible: large `executeBatch` matrices that
reuse the same `Uint8List` object many times. The baseline copies that payload
into the native arena once per BLOB parameter even though the batch runner binds
and steps synchronously while the arena remains alive. A duplicate parameter
could safely point at the first native copy for the lifetime of that batch.

This idea had prior local evidence, but it was closed unmerged because it was
marshal-only and lacked a workload/profile lane proving the shape mattered
end-to-end. This run revisits it with the missing workload evidence.

## Hypothesis

For repeated large-BLOB batches, object-identity reuse should reduce
parameter-marshalling time enough to improve a traced `executeBatch` workload
without changing public API semantics.

Reject if identity tracking only wins in marshal isolation, if 256-byte payloads
are below the tracking threshold, or if the Tracelite profile lane does not
improve once SQLite storage work is included.

## Approach

The final branch keeps the measurement surface and rejects the runtime
prototype. The archived prototype changed `allocateBatchParams` only:

- sample large batches for repeated `Uint8List` object identity;
- only consider `paramCount >= 8`, `totalCount >= 8000`, 1 KB+ BLOB values, and
  at least 4096 saved bytes;
- build an identity map from each unique BLOB object to its first payload
  offset;
- copy the first occurrence once and point duplicate BLOB structs at the same
  native arena bytes.

The final branch adds durable workload coverage:

- `batch_param_flatten.dart` now supports `--cell-mode=blob`,
  `--blob-bytes`, `--blob-mode=fresh|reused`, and
  `--measure=execute|marshal`;
- the Tracelite profile driver now includes `blob_merge_rounds`, a reused
  1 KB BLOB `executeBatch` lane.

## Results

Full numbers are recorded in
[`benchmark/results/2026-07-02T10-17-08Z-exp210-reused-blob-batch-workload.md`](../benchmark/results/2026-07-02T10-17-08Z-exp210-reused-blob-batch-workload.md).

### Marshal isolation

Median ms per `allocateBatchParams` / `freeParamBuffer` cycle, 1 KB reused
BLOB payloads:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 1,000 rows x 8 params | 0.297 | 0.211 | -29.0% |
| 10,000 rows x 8 params | 3.544 | 2.049 | -42.2% |
| 1,000 rows x 20 params | 0.727 | 0.515 | -29.2% |
| 10,000 rows x 20 params | 10.496 | 5.562 | -47.0% |

The implementation does remove marshal work when the payload is large enough.
The threshold matters: a 256-byte sweep before narrowing the guard made the
candidate slower on the target `10,000 x 8` lane, so the broad 64-byte version
is not viable.

### Execute sanity check

The same 1 KB reused-BLOB workload with SQLite execution included was mixed:

| Shape | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| 1,000 rows x 8 params | 14.870 | 14.982 | +0.8% |
| 10,000 rows x 8 params | 217.580 | 197.346 | -9.3% |
| 1,000 rows x 20 params | 38.061 | 37.225 | -2.2% |
| 10,000 rows x 20 params | 526.400 | 540.200 | +2.6% |

Once SQLite storage work is included, the marshal win is no longer a clean
end-to-end win.

### Tracelite profile

The new `blob_merge_rounds` profile lane rejects the runtime prototype:

| Metric | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| `blob_merge_rounds` executeBatch p50 | 909 us | 1177 us | +29.5% |
| `blob_merge_rounds` executeBatch p90 | 3091 us | 3628 us | +17.4% |
| `writer_sqlite_us` during BLOB lane | 642,217 us | 792,149 us | +23.3% |

The trace lane is the load-bearing result because it was the missing evidence
from the earlier local prototype. The candidate gets faster only when the
benchmark isolates marshalling; the workload that includes writer and SQLite
costs gets slower.

## Decision

**Rejected.** Do not keep the runtime identity-map prototype.

The reusable contribution is the workload coverage. Future BLOB parameter
experiments can now separate marshal-only wins from traced workload wins:
`batch_param_flatten.dart --cell-mode=blob --blob-mode=reused` isolates the
encoder, and `blob_merge_rounds` shows whether that encoder signal survives the
writer/SQLite path.

Reopen only if a production trace shows reused large-BLOB batches hot enough
that marshal-only savings matter end-to-end, or if a cheaper plan avoids the
per-cell identity-map lookup overhead.

## Test plan

- [x] `dart analyze --fatal-infos lib/src/native/resqlite_bindings.dart
      benchmark/experiments/batch_param_flatten.dart
      benchmark/profile/workloads.dart
      benchmark/profile/run_tracelite_workloads.dart test/database_test.dart`
- [x] prototype-only `dart test test/database_test.dart --name
      'wide executeBatch reuses repeated large blob parameters'`
- [x] focused marshal A/B on 1 KB reused BLOBs
- [x] focused execute sanity A/B on 1 KB reused BLOBs
- [x] Tracelite profile baseline/candidate with `blob_merge_rounds`
