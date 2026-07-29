# Exp 258 — columnar result transfer A/B (focused harness)

Harness: `benchmark/experiments/columnar_result_transfer.dart`, AOT-compiled,
two order-flipped passes. Not a release-suite run (no resqlite median section);
this file is the raw receipt for the exp 258 writeup. Lanes tagged `(send)` stay
under the 32768-slot sacrifice threshold (production SendPort path); `(exit)` lanes
exceed it (production Isolate.exit zero-copy path).

```
## PASS 1 (flat-first)
# Exp 258 — columnar result transfer A/B
inner=60 samples=25 sacrificeSlots=32768 order=flat-first

| lane | fBuild | cBuild | bΔ | fHop | cHop | hopΔ | fCons | cCons | consΔ | NET(hop+cons)Δ |
|---|---|---|---|---|---|---|---|---|---|---|
| 1k x 8 INTEGER (send) | 0.016 | 0.011 | -30.4% | 0.025 | 0.016 | -36.0% | 0.043 | 0.022 | -49.5% | -44.6% |
| 1k x 8 REAL (send) | 0.021 | 0.009 | -58.5% | 0.028 | 0.013 | -53.6% | 0.042 | 0.038 | -9.0% | -26.8% |
| 1.5k x 20 REAL (send) | 0.090 | 0.034 | -62.0% | 0.238 | 0.046 | -80.7% | 0.159 | 0.146 | -8.3% | -51.7% |
| 10k x 8 INTEGER (exit) | 0.314 | 0.103 | -67.1% | 0.496 | 0.146 | -70.6% | 0.446 | 0.218 | -51.2% | -61.4% |
| 10k x 20 INTEGER (exit) | 0.745 | 0.276 | -63.0% | 1.121 | 0.327 | -70.8% | 1.113 | 0.559 | -49.8% | -60.3% |
| 10k x 8 REAL (exit) | 0.731 | 0.089 | -87.9% | 0.779 | 0.113 | -85.5% | 0.440 | 0.405 | -8.0% | -57.5% |
| 10k x 20 REAL (exit) | 1.957 | 0.204 | -89.6% | 3.001 | 0.278 | -90.7% | 1.089 | 1.029 | -5.6% | -68.1% |
| 10k x (16 REAL + 4 TEXT) mixed (exit) | 2.022 | 0.267 | -86.8% | 1.922 | 0.326 | -83.0% | 1.198 | 0.978 | -18.3% | -58.2% |

All times are ms. Δ = columnar vs flat (negative = columnar faster). Build is worker-side (off main isolate); Hop is the main-observed round trip (build+serialize+receive); Cons is main-isolate full-scan. NET = hop+cons is the main-isolate-charged decision figure.

## Memory lane (peak RSS holding 40 live result sets)

| lane | flat RSS (MB) | columnar RSS (MB) | Δ |
|---|---:|---:|---:|
| 1k x 8 INTEGER (send) | 79.8 | 79.8 | 0.0% |
| 1k x 8 REAL (send) | 85.8 | 85.8 | 0.0% |
| 1.5k x 20 REAL (send) | 101.8 | 84.0 | -17.4% |
| 10k x 8 INTEGER (exit) | 108.2 | 122.5 | 13.2% |
| 10k x 20 INTEGER (exit) | 160.6 | 112.0 | -30.2% |
| 10k x 8 REAL (exit) | 148.0 | 146.7 | -0.9% |
| 10k x 20 REAL (exit) | 265.5 | 262.4 | -1.2% |
| 10k x (16 REAL + 4 TEXT) mixed (exit) | 243.5 | 240.5 | -1.2% |

RSS is process-wide and noisy; read only large, reproduced gaps.

sink=937623679808

## PASS 2 (columnar-first)
# Exp 258 — columnar result transfer A/B
inner=60 samples=25 sacrificeSlots=32768 order=columnar-first

| lane | fBuild | cBuild | bΔ | fHop | cHop | hopΔ | fCons | cCons | consΔ | NET(hop+cons)Δ |
|---|---|---|---|---|---|---|---|---|---|---|
| 1k x 8 INTEGER (send) | 0.017 | 0.012 | -26.5% | 0.025 | 0.017 | -32.0% | 0.044 | 0.022 | -49.5% | -43.2% |
| 1k x 8 REAL (send) | 0.021 | 0.009 | -58.2% | 0.029 | 0.013 | -55.2% | 0.042 | 0.039 | -8.7% | -27.6% |
| 1.5k x 20 REAL (send) | 0.092 | 0.035 | -61.6% | 0.100 | 0.048 | -52.0% | 0.162 | 0.148 | -8.4% | -25.0% |
| 10k x 8 INTEGER (exit) | 0.333 | 0.111 | -66.6% | 0.512 | 0.141 | -72.5% | 0.447 | 0.228 | -49.1% | -61.6% |
| 10k x 20 INTEGER (exit) | 0.758 | 0.289 | -61.8% | 1.350 | 0.332 | -75.4% | 1.116 | 0.560 | -49.9% | -63.8% |
| 10k x 8 REAL (exit) | 0.826 | 0.093 | -88.8% | 0.758 | 0.116 | -84.7% | 0.431 | 0.415 | -3.6% | -55.3% |
| 10k x 20 REAL (exit) | 2.276 | 0.217 | -90.5% | 2.000 | 0.280 | -86.0% | 1.097 | 1.033 | -5.8% | -57.6% |
| 10k x (16 REAL + 4 TEXT) mixed (exit) | 1.820 | 0.260 | -85.7% | 2.058 | 0.354 | -82.8% | 1.205 | 1.000 | -17.0% | -58.5% |

All times are ms. Δ = columnar vs flat (negative = columnar faster). Build is worker-side (off main isolate); Hop is the main-observed round trip (build+serialize+receive); Cons is main-isolate full-scan. NET = hop+cons is the main-isolate-charged decision figure.

## Memory lane (peak RSS holding 40 live result sets)

| lane | flat RSS (MB) | columnar RSS (MB) | Δ |
|---|---:|---:|---:|
| 1k x 8 INTEGER (send) | 68.3 | 68.3 | 0.0% |
| 1k x 8 REAL (send) | 68.3 | 68.3 | 0.0% |
| 1.5k x 20 REAL (send) | 69.8 | 72.5 | 3.9% |
| 10k x 8 INTEGER (exit) | 96.6 | 111.1 | 15.1% |
| 10k x 20 INTEGER (exit) | 149.3 | 99.9 | -33.1% |
| 10k x 8 REAL (exit) | 139.6 | 169.7 | 21.6% |
| 10k x 20 REAL (exit) | 365.5 | 426.2 | 16.6% |
| 10k x (16 REAL + 4 TEXT) mixed (exit) | 271.1 | 164.2 | -39.4% |

RSS is process-wide and noisy; read only large, reproduced gaps.

sink=937623679808
```
