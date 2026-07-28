# Exp 253 identity-conditioned MultiExecute BLOB routing A/B

**Date:** 2026-07-28
**Base:** `origin/main` at `292a60246bca`
**Candidate:** `a03d017237cd` (`archive/exp-253`)
**Host:** Darwin arm64
**Dart:** 3.12.2 stable, macOS arm64

## Method

The unchanged focused harness ran as separate baseline and candidate
processes/worktrees:

```text
dart run benchmark/experiments/multiexecute_blob_routing.dart \
  --shape=SHAPE --size-kb=SIZE --samples=SAMPLES \
  --bursts=3 --writes=12 --warmup-bursts=WARMUPS
```

Each process warmed the path before sampling. Each timed sample performs three
public `Future.wait([db.execute(...), ...])` bursts of 12 writes. The first
write in a burst is sent alone; writes queued behind it are coalesced into the
following `MultiExecuteRequest`. Every write remains an independent autocommit.

The baseline wraps every qualifying large BLOB identity in one shared
`TransferableTypedData` per coalesced envelope. The candidate first counts BLOB
identities, keeps unique large buffers on the direct object-graph-copy route,
and wraps only identities that repeat inside the envelope. The single-request
`ExecuteRequest` route is byte-for-byte unchanged.

Payloads are deterministic and constructed outside the timed region. Each
process/run uses one fresh WAL database and deletes its rows between samples.
Every sample verifies row count, total bytes, and aggregate checksums outside
the stopwatch; the final sample also reads every payload and recomputes its
length and checksum. Two comparisons ran in opposite order: baseline then
candidate, followed by candidate then baseline. Lower is better; delta is
`(candidate - baseline) / baseline`.

The predeclared decision shape was:

- distinct 256 KiB and 512 KiB buffers are the primary lanes;
- shared 300 KiB buffers guard exp 243's one-wrapper alias behavior;
- mixed 300 KiB buffers exercise shared and unique identities in one envelope;
- distinct 128 KiB buffers are a sub-threshold routing control; and
- the unchanged single-request path must retain its existing correctness
  guards.

Acceptance required a same-direction distinct-buffer improvement at the
existing 256 KiB admission floor and at 512 KiB, without a shared/mixed
regression. A result only at the larger endpoint could not move the threshold
after measurement.

## Decision summary

| Pair | Shape | Samples | Baseline p50 µs/write | Candidate p50 µs/write | Delta |
|---|---|---:|---:|---:|---:|
| baseline first | **distinct 256 KiB** | 9 | 548.472 | 604.194 | **+10.2%** |
| candidate first | **distinct 256 KiB** | 9 | 572.389 | 613.583 | **+7.2%** |
| baseline first | distinct 512 KiB | 9 | 1314.944 | 1182.028 | -10.1% |
| candidate first | distinct 512 KiB | 9 | 1243.556 | 1185.889 | -4.6% |
| baseline first | shared 300 KiB | 7 | 691.833 | 610.083 | -11.8% |
| candidate first | shared 300 KiB | 7 | 614.056 | 679.167 | +10.6% |
| baseline first | mixed 300 KiB | 9 | 672.222 | 651.806 | -3.0% |
| candidate first | mixed 300 KiB | 9 | 607.833 | 650.972 | +7.1% |
| baseline first | control 128 KiB | 7 | 364.167 | 303.111 | -16.8% |
| candidate first | control 128 KiB | 7 | 298.222 | 303.139 | +1.6% |

The load-bearing 256 KiB lane is candidate-slower in both orderings, by 10.2%
and 7.2%. That rejects the combined identity-census/direct-routing policy at
the first size where it would change production routing. The end-to-end run
does not isolate the census cost from the transfer-route cost.

The 512 KiB lane is candidate-faster in both comparisons, but the repository's
order-flipped drift checker classifies it as drift-suspected. It cannot rescue
the candidate: moving or splitting the threshold around that observed endpoint
would be a new, post-hoc hypothesis. One baseline 512 KiB sample in the second
comparison is a 2531.806 µs/write outlier; the median remains 1243.556, but its
31.5% sample coefficient of variation is another reason not to promote the
larger endpoint alone.

Shared, mixed, and sub-threshold controls change sign across the order flip.
The shared route remains one wrapper in both builds but the candidate adds an
identity census; the control remains direct in both builds; and the mixed route
changes only its unique identities. Their alternating deltas expose
process/order drift rather than a stable guardrail benefit.

The repository classifier was run directly over the raw arrays:

| Shape | Pass deltas | `ab_drift_check.dart` verdict |
|---|---:|---|
| distinct 256 KiB | +10.2% / +7.2% | **REPRODUCED (real regression)** |
| distinct 512 KiB | -10.1% / -4.6% | drift-suspected |
| shared 300 KiB | -11.8% / +10.6% | drift-suspected |
| mixed 300 KiB | -3.0% / +7.1% | drift-suspected |
| control 128 KiB | -16.8% / +1.6% | inconclusive / neutral |

## Distribution summary

MAD is the median absolute deviation. CV is sample standard deviation divided
by the sample mean.

| Shape | Pair | Base p50 | Base MAD | Base CV | Cand p50 | Cand MAD | Cand CV |
|---|---|---:|---:|---:|---:|---:|---:|
| distinct 256 | baseline first | 548.472 | 12.528 | 3.5% | 604.194 | 22.833 | 6.2% |
| distinct 256 | candidate first | 572.389 | 24.278 | 5.1% | 613.583 | 28.667 | 9.5% |
| distinct 512 | baseline first | 1314.944 | 34.278 | 5.7% | 1182.028 | 19.694 | 5.5% |
| distinct 512 | candidate first | 1243.556 | 17.889 | 31.5% | 1185.889 | 14.417 | 6.4% |
| shared 300 | baseline first | 691.833 | 45.250 | 8.0% | 610.083 | 13.667 | 3.3% |
| shared 300 | candidate first | 614.056 | 4.972 | 3.8% | 679.167 | 73.028 | 18.2% |
| mixed 300 | baseline first | 672.222 | 12.333 | 6.1% | 651.806 | 31.972 | 14.1% |
| mixed 300 | candidate first | 607.833 | 12.639 | 3.4% | 650.972 | 40.194 | 7.4% |
| control 128 | baseline first | 364.167 | 14.528 | 11.8% | 303.111 | 26.278 | 12.3% |
| control 128 | candidate first | 298.222 | 25.750 | 12.2% | 303.139 | 28.278 | 12.7% |

## Raw samples

Values are µs/write.

### Distinct 256 KiB

```text
pass 1 baseline:
561.000, 558.000, 516.944, 551.194, 525.222, 560.167, 519.583, 548.472, 520.222

pass 1 candidate:
567.500, 581.361, 604.194, 634.972, 590.667, 620.500, 580.722, 612.972, 692.583

pass 2 candidate:
573.722, 584.917, 619.139, 613.583, 588.278, 615.167, 579.944, 650.861, 764.278

pass 2 baseline:
572.389, 608.222, 576.917, 591.333, 548.111, 600.667, 539.583, 555.222, 523.694
```

### Distinct 512 KiB

```text
pass 1 baseline:
1249.944, 1320.806, 1346.722, 1349.222, 1314.944, 1336.917, 1199.611, 1180.972, 1183.694

pass 1 candidate:
1176.278, 1162.333, 1157.861, 1188.361, 1155.861, 1218.250, 1197.000, 1182.028, 1368.306

pass 2 candidate:
1171.472, 1176.528, 1179.639, 1171.306, 1185.889, 1205.028, 1189.750, 1202.083, 1413.861

pass 2 baseline:
2531.806, 1343.333, 1261.444, 1242.861, 1148.556, 1175.528, 1236.167, 1243.556, 1254.417
```

### Shared 300 KiB

```text
pass 1 baseline:
737.083, 734.111, 691.833, 751.194, 681.056, 622.361, 614.778

pass 1 candidate:
626.139, 602.278, 608.056, 655.472, 610.083, 596.417, 627.361

pass 2 candidate:
679.167, 789.694, 980.361, 737.750, 661.500, 605.250, 606.139

pass 2 baseline:
656.333, 614.167, 614.056, 661.750, 609.083, 608.083, 611.278
```

### Mixed 300 KiB

```text
pass 1 baseline:
632.778, 598.028, 652.833, 659.889, 679.278, 747.250, 673.583, 679.778, 672.222

pass 1 candidate:
629.889, 619.833, 612.333, 629.778, 651.806, 730.111, 656.667, 744.111, 912.389

pass 2 candidate:
655.944, 610.778, 610.083, 607.278, 659.944, 718.111, 628.111, 650.972, 743.778

pass 2 baseline:
622.583, 596.500, 593.472, 603.750, 621.278, 664.000, 606.500, 607.833, 620.472
```

### Control 128 KiB

```text
pass 1 baseline:
439.000, 350.111, 364.167, 313.861, 378.500, 378.694, 317.278

pass 1 candidate:
369.500, 276.833, 303.111, 266.361, 320.889, 317.028, 265.750

pass 2 candidate:
376.194, 273.667, 303.139, 265.139, 320.306, 315.528, 274.861

pass 2 baseline:
364.028, 272.472, 298.222, 263.222, 317.111, 316.750, 265.722
```

## Outcome

Rejected. The exact runtime prototype remains at `archive/exp-253`; the
publication branch restores runtime and tests to `origin/main` and retains this
harness.

The result is narrower than “one message makes direct BLOB copies cheaper.”
At 256 KiB, one coalesced message still benefits from the existing external
wrapper even for distinct identities. Message count alone does not decide the
route.

It also qualifies, rather than invalidates, exp 237. That experiment measured
one BLOB object reused across all 30 `executeBatch` rows using the pre-exp-243
prototype, which created 30 independent wrappers for that one identity. Its
measured regression is valid for that implementation and fixture, but it does
not establish the cost of today's shared-wrapper protocol or of distinct
identities. `executeBatch` also runs one transaction, whereas
`MultiExecuteRequest` preserves one autocommit per member. Any future batch
revisit must separate alias cardinality from transaction topology and requires
fresh production incidence.
