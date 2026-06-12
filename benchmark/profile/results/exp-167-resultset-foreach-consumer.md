# Exp 167 - ResultSet.forEach consumer recheck

Date: 2026-06-12

Focused benchmark:

```bash
dart run benchmark/experiments/resultset_foreach_consumer.dart \
  --rows=10000 --passes=100 --warmup=3 --iterations=N
```

The benchmark seeds a real resqlite database, runs `Database.select()` before
each sample, and then times main-isolate consumer loops over the returned
`ResultSet`. It was added because closed PR #125 / exp 141 only had a synthetic
`ResultSet` microbenchmark and was explicitly closed until a current
full-consumer-cost lane existed.

## Candidate

The discarded candidate overrode `ResultSet.forEach` to walk the flat values
buffer by row offset and construct the same lazy `Row` views as `operator []`.
No transport, `Row`, schema, or public API shape changed.

## JIT Pair A

Baseline first, then candidate. `--iterations=15`.

| Case | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| for-in lookup | 25.440 ms | 24.643 ms | -3.1% |
| forEach lookup | 30.525 ms | 28.383 ms | -7.0% |
| indexed lookup | 21.553 ms | 20.115 ms | -6.7% |
| forEach length | 9.439 ms | 8.010 ms | -15.1% |

This pass favored the candidate on the target rows, but controls also moved in
the same direction, so the run was not decisive by itself.

## JIT Pair B

Baseline first, then candidate after rebuilding from the same benchmark script.
`--iterations=25`.

| Case | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| for-in lookup | 27.531 ms | 28.311 ms | +2.8% |
| forEach lookup | 28.563 ms | 30.942 ms | +8.3% |
| indexed lookup | 20.778 ms | 21.143 ms | +1.8% |
| forEach length | 8.652 ms | 9.490 ms | +9.7% |

The order-flipped confirmation reversed the target row. The candidate does not
have a stable current win on the real SQLite-backed consumer lane.

## AOT Note

I tried to compile baseline and candidate binaries with `dart compile exe` to
remove JIT effects, but the standalone executable could not resolve resqlite's
native asset:

```text
Couldn't resolve native function 'resqlite_open' ... No available native assets.
```

For this branch, the JIT evidence is enough to reject the one-method runtime
change rather than extend the measurement system.

## Conclusion

Reject the runtime override. Keep the focused benchmark script as the reusable
full-consumer lane for future result-shape work, but do not revive the exp 141
`ResultSet.forEach` override unless a future Dart runtime or workload produces
a stable target win without moving the controls.
