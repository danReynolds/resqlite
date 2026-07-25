# Exp 248 — stmt-cache stable slots vs move-to-back swap (rejected)

Harness: [`benchmark/experiments/stmt_cache_interleaved.dart`](../experiments/stmt_cache_interleaved.dart)
(kept) plus an isolated C mechanism microbenchmark. Prototype reverted on the
branch; re-apply from `archive/exp-248`. Median µs/call over 11 samples × 1000
calls, one pinned reader, Apple M1 Pro / macOS.

## Mechanism, isolated (2M iterations/lane, ns per cache lookup)

`resqlite_cached_stmt` is 1,632 B; one promotion moves 4,896 B.

| cache | distinct hot SQL | swap (baseline) | stamp (candidate) | delta |
|---|---|---:|---:|---:|
| 8 | 1 (control) | 22.42 | 22.01 | −1.8% |
| 8 | 2 | 85.47 | 20.97 | −75.5% |
| 8 | 4 | 90.14 | 18.11 | −79.9% |
| 8 | 8 | 83.98 | 15.14 | −82.0% |
| 32 | 1 (control) | 83.01 | 79.56 | −4.2% |
| 32 | 2 | 144.28 | 88.98 | −38.3% |
| 32 | 4 | 146.77 | 82.38 | −43.9% |

The swap costs ~60–65 ns per lookup when it fires; controls confirm it is inert
on single-SQL workloads.

## End-to-end, two order-flipped passes (median µs/call)

| Shape | P1 base | P1 cand | P1 Δ | P2 base | P2 cand | P2 Δ |
|---|---:|---:|---:|---:|---:|---:|
| 1 SQL control, cache=8 | 13.158 | 16.344 | +24.2% | 8.854 | 17.989 | +103.2% |
| 1 SQL control, cache=31 | 9.339 | 11.911 | +27.5% | 7.178 | 10.212 | +42.3% |
| 2 SQL round-robin, cache=8 | 9.136 | 8.942 | −2.1% | 6.874 | 10.229 | +48.8% |
| 2 SQL round-robin, cache=31 | 9.073 | 9.350 | +3.1% | 6.794 | 10.148 | +49.4% |
| 4 SQL round-robin, cache=31 | 9.745 | 9.823 | +0.8% | 6.689 | 10.435 | +56.0% |
| 8 SQL round-robin, cache=31 | 12.149 | 9.463 | −22.1% | 8.649 | 9.213 | +6.5% |
| 4 SQL, cache=31, 100 rows | 28.203 | 18.417 | −34.7% | 20.054 | 21.538 | +7.4% |

No lane reproduces a same-sign candidate-faster delta. The control lanes, where
the promotion branch is mechanically unreachable and both sides run identical
code, move +24% / +27% / +103% / +42% — so the harness floor is far above
anything the change can contribute.

~65 ns against a ~7–10 µs round trip is ~0.7% of per-call wall: real work
removed, immaterial through the public API. Rejected — see
`experiments/248-stmt-cache-stable-slots.md`.
