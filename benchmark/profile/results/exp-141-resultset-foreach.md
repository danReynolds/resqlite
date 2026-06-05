# Experiment 141: ResultSet forEach Fast Path

Focused AOT microbenchmark for `ResultSet` main-isolate iteration. The
benchmark constructs the shipped lazy `ResultSet` / `Row` shape directly and
runs 10,000 rows x 8 columns across 500 passes per sample.

Command:

```bash
dart compile exe benchmark/experiments/resultset_iteration.dart \
  -o /tmp/resqlite_exp141_resultset_iteration
/tmp/resqlite_exp141_resultset_iteration \
  --rows=10000 --columns=8 --passes=500 --warmup=3 --iterations=20
```

## Paired A/B Results

Two paired runs were used because this local machine showed occasional
scheduler spikes in p90/p99. The decision uses p50 medians and keeps indexed
loops as controls because the implementation does not touch `operator []`.

### Pair A

Baseline first, candidate second.

| Case | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| for-in length | 42.375 ms | 30.601 ms | -27.8% |
| for-in lookup | 115.825 ms | 118.902 ms | +2.7% |
| forEach length | 18.590 ms | 14.677 ms | -21.0% |
| forEach lookup | 108.888 ms | 92.158 ms | -15.4% |
| indexed length | 24.427 ms | 24.209 ms | -0.9% |
| indexed lookup | 88.082 ms | 82.873 ms | -5.9% |

### Pair B

Candidate first, baseline second.

| Case | Baseline p50 | Candidate p50 | Delta |
|---|---:|---:|---:|
| for-in length | 68.526 ms | 43.764 ms | -36.1% |
| for-in lookup | 116.556 ms | 100.362 ms | -13.9% |
| forEach length | 15.354 ms | 14.593 ms | -5.0% |
| forEach lookup | 99.837 ms | 80.093 ms | -19.8% |
| indexed length | 22.187 ms | 22.491 ms | +1.4% |
| indexed lookup | 72.613 ms | 76.715 ms | +5.6% |

## Read

Direct `ResultSet.forEach` is the accepted change. It consistently improves the
lookup-heavy `rows.forEach((row) => row['c0'])` case by 15-20% while indexed
loop controls stay within the local noise band.

The broader `ResultSet.iterator` override was tested and rejected. It helped
some `for-in` medians, but moved unrelated controls too noisily for a small
library optimization. Keep the public list/row shape unchanged and only bypass
`ListMixin.forEach` for explicit `rows.forEach` consumers.
