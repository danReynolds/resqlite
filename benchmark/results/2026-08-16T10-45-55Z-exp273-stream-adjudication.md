# Exp 273 continuous-PGO stream adjudication

This receipt preserves the fixed-binary follow-up for the durable exp 249
`stream_rerun_latency.dart` gate. Each process measured 300 homogeneous and
300 heterogeneous single-write emission latencies. Odd pairs ran baseline then
candidate; even pairs reversed the order. The table derives p50 from the raw
samples rather than the three-decimal display line in each log.

| Pair | Order | Homogeneous baseline p50 (ms) | Homogeneous candidate p50 (ms) | Candidate delta | Heterogeneous baseline p50 (ms) | Heterogeneous candidate p50 (ms) | Candidate delta |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | B-C | 1.3445 | 1.2150 | -9.63% (-0.1295 ms) | 1.4200 | 1.3775 | -2.99% (-0.0425 ms) |
| 2 | C-B | 1.0625 | 1.1090 | +4.38% (+0.0465 ms) | 1.2885 | 1.3945 | +8.23% (+0.1060 ms) |
| 3 | B-C | 1.1145 | 0.9405 | -15.61% (-0.1740 ms) | 1.2125 | 1.3490 | +11.26% (+0.1365 ms) |
| 4 | C-B | 0.7575 | 1.0860 | +43.37% (+0.3285 ms) | 1.3860 | 1.0655 | -23.12% (-0.3205 ms) |
| 5 | B-C | 1.1250 | 1.2565 | +11.69% (+0.1315 ms) | 1.3790 | 1.3920 | +0.94% (+0.0130 ms) |

The declared adjudication rejection rule was: reject if homogeneous candidate
p50 regresses by at least 3% and at least 0.02 ms in at least three of five
independent pairs. Pairs 2, 4, and 5 meet both thresholds. **Verdict: reject the
production PGO candidate under the declared rule.** Aggregate wins elsewhere
do not override this load-bearing latency decision.

As a noise qualification, pooling all 1,500 samples per arm gives homogeneous
p50 1.1140 ms baseline versus 1.1310 ms candidate (+1.53%, +0.0170 ms). A
deterministic 10,000-resample independent-sample bootstrap (seed 273) gives a
95% median-delta interval of -0.0825 to +0.1140 ms. Heterogeneous pooled p50 is
1.3465 versus 1.2875 ms (-4.38%, -0.0590 ms), with interval -0.1145 to
+0.0180 ms. These pooled intervals span zero and ignore within-process phase
correlation, so the evidence does not establish a stable intrinsic slowdown;
it records a rejection under the predeclared pair-replication rule.

## Raw log inventory

All logs are under
`2026-08-16T10-45-55Z-exp273-stream-adjudication-raw/` and are exact copies of
the ten `/private/tmp/resqlite-exp273/logs/stream-adj-*.log` inputs.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `stream-adj-p1-baseline.log` | 3,785 | `c843567e8c6a6c43283572b3b79f2cd0bcc9fe2e4e660be9761bf5ed96efb9b5` |
| `stream-adj-p1-candidate.log` | 3,763 | `cdd186a78570617c4dc7ca4961868d73526b29fdc3e7f522408b720006035fde` |
| `stream-adj-p2-baseline.log` | 3,772 | `521480cc3e192fd92740fb946732265693efe6cfc8f9839eeba56b8c137fd462` |
| `stream-adj-p2-candidate.log` | 3,760 | `a009950e18dd2bd87689d24076f06781d69da762e48a24c6afa2178a837fa316` |
| `stream-adj-p3-baseline.log` | 3,762 | `227ca7407cc825d03bbb0185d12693bcccf7dc35ca4281b911b65a4aa0e6eab6` |
| `stream-adj-p3-candidate.log` | 3,758 | `cd707e4053b246017abbdf802cc95dfe36c56b34ccd9a55910f7190b409f2e6a` |
| `stream-adj-p4-baseline.log` | 3,780 | `5e0f3f141c1994f988ec66519caa587dfdf963f299f9b79aed8682554c9a1e87` |
| `stream-adj-p4-candidate.log` | 3,771 | `544a443fc548e5f945a64eb7ca4b75e60c0a3dab6eb7bd64aebe3aaf8b7a8393` |
| `stream-adj-p5-baseline.log` | 3,771 | `16684116a21e9b78c2501443873ea31dc07744c95e24d103323edf4559c7e2b3` |
| `stream-adj-p5-candidate.log` | 3,774 | `1a9b3c04435a8f32543bfcf5914aa24944b58ba42dcaf1b3178f87b599a8e28e` |

The archived representative profile is
`exp273-arm64-representative.profdata`: 522,568 bytes, SHA-256
`cd957c73e38b10dc04106bdd2bf056687bb0bd856209943146eca6596fd25d74`.
