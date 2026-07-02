# Exp 210 - reused BLOB batch workload and object-identity prototype

Focused BLOB batch harness plus Tracelite profile lane against `origin/main`
at `990468a`. Prototype archived at `archive/exp-210`; final branch reverts
the runtime change and keeps only the reusable workload coverage.

## Focused marshal gate

Command:

```text
dart run benchmark/experiments/batch_param_flatten.dart \
  --measure=marshal \
  --warmup=10 \
  --iterations=60 \
  --cell-mode=blob \
  --blob-bytes=1024 \
  --blob-mode=reused
```

Median ms per `allocateBatchParams` / `freeParamBuffer` cycle. Lower is better.

| Shape | Baseline | Candidate | Delta | Read |
|---|---:|---:|---:|---|
| 100 rows x 8 params | 0.030 | 0.034 | +13.3% | guard disabled by total-count threshold; noise/tiny overhead |
| 1,000 rows x 8 params | 0.297 | 0.210 | -29.3% | repeated-BLOB marshal win |
| 10,000 rows x 8 params | 3.563 | 2.031 | -43.0% | repeated-BLOB marshal win |
| 100 rows x 20 params | 0.074 | 0.081 | +9.5% | guard disabled by total-count threshold; noise/tiny overhead |
| 1,000 rows x 20 params | 0.732 | 0.510 | -30.3% | repeated-BLOB marshal win |
| 10,000 rows x 20 params | 10.494 | 5.642 | -46.2% | repeated-BLOB marshal win |

The narrower 2-param rows are intentionally below the guard and did not use the
prototype. A 256-byte reused-BLOB sweep was also run before tightening the
threshold; it did not justify identity tracking (`10,000 x 8` moved 1.378 ms
baseline to 2.036 ms candidate), so the prototype was narrowed to 1 KB+
payloads and 8,000+ total params before the final measurements above.

## Focused execute sanity check

Command:

```text
dart run benchmark/experiments/batch_param_flatten.dart \
  --measure=execute \
  --warmup=1 \
  --iterations=3 \
  --cell-mode=blob \
  --blob-bytes=1024 \
  --blob-mode=reused
```

Median ms per `executeBatch`. Lower is better.

| Shape | Baseline | Candidate | Delta | Read |
|---|---:|---:|---:|---|
| 1,000 rows x 8 params | 14.870 | 14.982 | +0.8% | flat/slightly slower |
| 10,000 rows x 8 params | 217.580 | 197.346 | -9.3% | possible win |
| 1,000 rows x 20 params | 38.061 | 37.225 | -2.2% | small possible win |
| 10,000 rows x 20 params | 526.400 | 540.200 | +2.6% | reversed under SQLite storage work |

The end-to-end signal is not strong enough to keep the runtime change. SQLite
storage work absorbs the marshal saving on most shapes, and the widest row
reversed in this short execute pass.

## Tracelite profile lane

The profile driver gained `blob_merge_rounds`: 400 `executeBatch` samples per
run, each inserting reused 1 KB BLOB values into an 8-column BLOB table.

Commands:

```text
dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --dart=/opt/homebrew/Cellar/dart/3.12.2/libexec/bin/dart \
  --label=exp210-blob-baseline-1kb \
  --out-dir=build/tracelite-profile/exp210-blob-baseline-1kb \
  --allow-unpinned-tracelite \
  --allow-dirty-tracelite \
  --no-graph-data

dart run benchmark/profile/run_tracelite_profile.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --dart=/opt/homebrew/Cellar/dart/3.12.2/libexec/bin/dart \
  --label=exp210-blob-candidate-1kb \
  --out-dir=build/tracelite-profile/exp210-blob-candidate-1kb \
  --allow-unpinned-tracelite \
  --allow-dirty-tracelite \
  --no-graph-data
```

| Metric | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| `blob_merge_rounds` executeBatch p50 | 909 us | 1177 us | +29.5% |
| `blob_merge_rounds` executeBatch p90 | 3091 us | 3628 us | +17.4% |
| `writer_sqlite_us` during BLOB lane | 642,217 us | 792,149 us | +23.3% |

This is the decision gate. The profile lane is the missing workload evidence
that the earlier repeated-BLOB prototype lacked, and it rejects the runtime
change: object-identity reuse wins in marshal isolation but slows the traced
workload once SQLite storage and writer-side effects are included.

## Decision

Rejected. Keep the BLOB workload coverage and result record; do not keep the
runtime identity-map prototype. Reopen only if a production trace shows reused
large BLOB batches hot enough that marshal-only savings matter end-to-end, or
if a cheaper plan avoids per-cell identity-map lookup overhead.
