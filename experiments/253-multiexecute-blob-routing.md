# Experiment 253: Reject identity-conditioned MultiExecute BLOB routing

**Date:** 2026-07-28T06:23:43-04:00
**Status:** Rejected
**Direction:** `parameter-encoding-and-binding`
**Benchmark Run:** focused cross-worktree, order-flipped A/B; aggregate tables,
  distributions, and raw samples in
  [`benchmark/results/2026-07-28T10-23-43Z-exp253-multiexecute-blob-routing.md`](../benchmark/results/2026-07-28T10-23-43Z-exp253-multiexecute-blob-routing.md)
**Archive:** [`archive/exp-253`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-253)

## Problem

[Exp 234](234-blob-param-transfer.md) found that wrapping BLOB parameters at or
above 256 KiB in `TransferableTypedData` improves single-write wall time by
moving the required sender-side copy into external memory rather than the
shared GC heap. [Exp 243](243-blob-alias-table-protocol.md) then made the wrapper
identity-aware: one buffer referenced N times in a coalesced envelope now gets
one shared wrapper and one materialization instead of N external copies.

The current `MultiExecuteRequest` applies that route to *every* large BLOB in a
coalesced group. But the group already crosses the writer port in one message.
[Exp 237](237-batch-blob-param-transfer.md) had reported that per-blob wrapping
regressed `executeBatch` after its many writes were collapsed into one request,
suggesting that unique buffers in a coalesced standalone-write envelope might
be better left on the direct graph-copy route. Repeated identities would still
need exp 243's shared wrapper because the graph copier's large-buffer path is
slow and wrapper sharing avoids N copies.

That inference needed a direct test. Exp 237's fixture reused one
`Uint8List` object across all 30 parameter sets, and its pre-exp-243 prototype
created a fresh wrapper for every occurrence. Its candidate therefore made 30
external copies of one logical buffer while the direct baseline preserved
identity and copied it once. `executeBatch` also runs one SQL inside one
transaction, whereas `MultiExecuteRequest` preserves an independent autocommit
and outcome for each member. One envelope is not the whole topology.

Current Dart 3.12.2 retains the documented transfer contract:
[`TransferableTypedData.fromList`](https://api.dart.dev/dart-isolate/TransferableTypedData/TransferableTypedData.fromList.html)
is linear in the supplied byte count, while sending the resulting object is
constant-time. The route still decides where resqlite pays that linear copy;
there is no new runtime primitive that removes it.

## Hypothesis

Count qualifying BLOB identities across each coalesced group:

- keep a unique large buffer direct, so all unique buffers ride the group's one
  object-graph copy; and
- wrap only identities that occur more than once, sharing one
  `TransferableTypedData` across every occurrence.

The predeclared primary lanes were distinct 256 KiB and 512 KiB buffers in
public `Future.wait([db.execute(...), ...])` bursts, measured from separate
baseline and candidate worktrees in both execution orders. Acceptance required
a same-direction improvement at the existing 256 KiB admission floor and at
512 KiB. Shared and mixed 300 KiB guardrails could not regress, the
sub-threshold 128 KiB route had to stay neutral, and the single-request route
had to remain unchanged and correct. An apparent win only at the larger
endpoint could not move the threshold after measurement.

## Approach

The exact prototype at
[`archive/exp-253`](https://github.com/danReynolds/resqlite/tree/archive/exp-253)
(`a03d017`) changes only the coalesced-group wrapper:

1. lazily build identity-keyed `seen` and `repeated` sets while scanning
   qualifying BLOB params;
2. return the original group unchanged when no qualifying identity repeats;
3. otherwise wrap only members of the repeated set through one
   envelope-scoped identity cache; and
4. retain the existing envelope-scoped `BlobUnwrapper`, so each shared wrapper
   is materialized once and its aliasing is restored.

`wrapParams` for a single `ExecuteRequest` is untouched. The no-large-BLOB
group path remains allocation-free.

The retained harness constructs deterministic distinct, shared, mixed, and
sub-threshold BLOB shapes. Each timed sample performs three public
`Future.wait` bursts of 12 standalone writes. The pump sends the first request
alone and coalesces writes waiting behind it into the next
`MultiExecuteRequest`; every member remains its own autocommit. Setup, payload
construction, warmup, aggregate verification, per-row length and checksum
verification, and deletion stay outside the timed region.

## Results

Two cross-worktree comparisons ran in opposite order. Lower is better; delta is
candidate relative to baseline.

| Pair | Shape | Baseline p50 µs/write | Candidate p50 µs/write | Delta |
|---|---|---:|---:|---:|
| baseline first | **distinct 256 KiB** | 548.472 | 604.194 | **+10.2%** |
| candidate first | **distinct 256 KiB** | 572.389 | 613.583 | **+7.2%** |
| baseline first | distinct 512 KiB | 1314.944 | 1182.028 | -10.1% |
| candidate first | distinct 512 KiB | 1243.556 | 1185.889 | -4.6% |
| baseline first | shared 300 KiB | 691.833 | 610.083 | -11.8% |
| candidate first | shared 300 KiB | 614.056 | 679.167 | +10.6% |
| baseline first | mixed 300 KiB | 672.222 | 651.806 | -3.0% |
| candidate first | mixed 300 KiB | 607.833 | 650.972 | +7.1% |
| baseline first | control 128 KiB | 364.167 | 303.111 | -16.8% |
| candidate first | control 128 KiB | 298.222 | 303.139 | +1.6% |

The load-bearing 256 KiB lane fails in both orderings. The combined identity
census plus direct routing makes the first production-admitted size 10.2% and
7.2% slower. MultiExecute's one envelope does **not** justify removing the
external wrapper. This end-to-end benchmark decides the implementation policy;
it does not profile how much of the regression comes from the census versus the
changed transfer route.

The 512 KiB endpoint is candidate-faster in both comparisons, but the
repository drift checker classifies it as drift-suspected. It cannot rescue the
policy. Splitting or moving the threshold around an observed endpoint would be
a new hypothesis, and the candidate already fails where the existing
production rule first engages. Its second baseline comparison also has one
large outlier (31.5% sample CV), further weakening a post-hoc crossover claim.

The shared, mixed, and control lanes change sign across the order flip.
Shared identities still use one wrapper in both builds but the candidate adds
the census; 128 KiB remains direct in both; mixed changes only unique
identities. Their alternating deltas expose process/order drift rather than a
stable secondary win. The primary 256 KiB regression keeps the same sign
despite that drift.

## Decision

**Rejected.** Keep the current rule: every qualifying large BLOB in a
`MultiExecuteRequest` uses the envelope-shared wrapper cache, whether its
identity occurs once or many times. The runtime and tests are restored to
`origin/main`; the exact measured prototype remains at `archive/exp-253`, and
the public-path harness remains as the durable gate.

Do not infer BLOB transfer policy from message count alone. At 256 KiB,
the current envelope-shared wrapping implementation remains faster than the
tested identity-census/direct policy even though both cross in one group send.
Reopen a larger-size-only MultiExecute route only with a representative
production distribution concentrated above 512 KiB and a predeclared crossover
sweep that reproduces on more than this host.

Exp 253 qualifies, rather than invalidates, exp 237. Exp 237 correctly rejected
its archived per-occurrence wrapper on an all-aliased `executeBatch` workload,
but that result does not establish that graph copy wins for distinct BLOBs or
for every one-envelope topology. A future `BatchRequest` revisit would need the
current alias-preserving table protocol, separate distinct and repeated
identity lanes, and fresh production incidence. Exp 253 is not that retest:
MultiExecute members are independent autocommits rather than one transactional
C batch.

## Transferable lesson

Alias cardinality is part of a transfer workload, not a fixture detail.
Envelope count, object identity, and writer transaction/execution topology
together determine the cost. A benchmark that reuses one object N times cannot
support a routing rule for N distinct objects when the candidate and baseline
preserve identity differently.

## Validation

Archived prototype:

- exact candidate analyzed with no issues
- full `test/blob_alias_table_test.dart`: 14/14
- focused coalesced/BLOB database tests: 18/18
- distinct, shared, mixed, and sub-threshold payload lengths and checksums
  verified after transport
- separate baseline/candidate worktrees and processes
- two order-flipped comparisons at each decision lane
- `ab_drift_check.dart`: distinct 256 KiB reproduced regression; distinct
  512 KiB, shared, and mixed drift-suspected; control inconclusive
- exact commit pushed to `archive/exp-253`

Final publication branch:

- runtime and tests restored byte-for-byte to `origin/main`
- focused public-path benchmark retained
- experiment finalizer and terminal-disposition check
- `dart run build_runner build --delete-conflicting-outputs`
- `dart analyze --fatal-infos`
- full serial test suite: 354/354
- JSON validation and `git diff --check`
