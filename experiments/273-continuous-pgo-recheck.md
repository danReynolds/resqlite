# Experiment 273: recheck continuous profile-guided optimization

**Date:** 2026-08-16
**Status:** Rejected
**Category:** Performance
**Direction:** `sqlite-version-and-build-config`
**Benchmark Run:** Resqlite-only release AOT B-C-C-B in
  [`baseline 1`](../benchmark/results/2026-08-16T06-34-24-exp273-full-baseline-1.md),
  [`candidate 1`](../benchmark/results/2026-08-16T06-34-42-exp273-full-candidate-1.md),
  [`candidate 2`](../benchmark/results/2026-08-16T06-35-00-exp273-full-candidate-2.md),
  and
  [`baseline 2`](../benchmark/results/2026-08-16T06-35-18-exp273-full-baseline-2.md).
  The profile contract is frozen in the
  [`manifest`](../benchmark/results/2026-08-16T10-45-22Z-exp273-pgo-profile-manifest.md),
  and the decisive fixed-binary follow-up is the
  [`5 x 300 stream adjudication`](../benchmark/results/2026-08-16T10-45-55Z-exp273-stream-adjudication.md).
**Archive:** `archive/exp-273` at
  `580135626619cc70164918ab06caf95a040e9eb5`

> **Rejected under the predeclared stream guard.** Counter-only continuous PGO
> produced a broad release improvement and smaller focused point-read and
> transaction wins. The homogeneous single-write stream guard nevertheless
> regressed by at least 3% and 0.02 ms in three of five independent 300-trial
> pairs: pairs 2, 4, and 5. Pooling all samples reduces the apparent regression
> below both thresholds and does not prove a stable intrinsic slowdown, but it
> cannot override the declared adjacent-pair replication rule. The shipping
> branch keeps no PGO build behavior or profile.

## Problem

[Exp 054](054-pgo.md) rejected profile-guided optimization before reaching a
profile-use build. Its instrumented Dart-loaded dylib produced no `.profraw`:
the host could use `_exit()` and bypass the profiling runtime's normal exit
flush. That was an infrastructure result, not a performance measurement.

Apple Clang 21 now supports continuous IR profiles on Darwin. Counters are
memory-mapped into `.profraw` while the process runs, so a real Resqlite dylib
can preserve them even when its Dart host calls `_exit()`. This changed the
load-bearing premise of exp 054 and made one bounded recheck warranted.

The opportunity was broad rather than tied to one speculative cache. PGO can
use measured execution counts to change native inlining, code layout, branch
placement, and hot/cold partitioning across SQLite, sqlite3mc, and Resqlite's C
transfer paths. The cost is a compiler-, target-, source-, and training-corpus
specific build artifact. A broad benchmark win was therefore necessary but not
sufficient: the candidate also had to preserve important latency paths and
support a maintainable profile lifecycle.

## Hypothesis and predeclared gates

Training the untraced native asset on representative Resqlite release, stream,
and transaction work should improve representative native wall by at least 5%
in both run orders without a repeated important-lane regression.

The experiment was accepted only if all of these conditions held:

1. representative wall time improved by at least **5% in both orders**;
2. controls and guardrails did not reproduce a candidate regression of at
   least **3%** (with a **0.02 ms** absolute floor for the stream latency
   guard);
3. profile generation and use were exact and profile-use diagnostics were
   clean; and
4. a pinned, auditable, cross-platform-safe profile lifecycle existed, with an
   explicit non-PGO fallback for unsupported targets.

The first focused stream check reproduced candidate-slower homogeneous p50
results in both orders: **+7.80% (+0.061 ms)** and
**+5.61% (+0.025 ms)**. That held the candidate for one bounded, higher-sample
adjudication. Its rule was declared before the five pairs were inspected:

> Reject if homogeneous candidate p50 regresses by at least 3% **and** at least
> 0.02 ms in at least three of five independent 300-trial pairs.

This p50 rule, not a p95 threshold or an aggregate average, is the final
decision gate.

## Approach

Both arms used source
`02592093e6b671e420a1de7b277d7c56c434627a` on macOS 26.2 arm64 with Dart
3.12.2. The candidate used Apple clang 21.0.0
(`clang-2100.1.1.101`, Xcode 26.6) and Apple LLVM `llvm-profdata` 21.0.0.

### Counter-only continuous profile

The generation build added:

```text
-fprofile-generate=<profile-directory>
-fprofile-continuous
-fprofile-update=atomic
-mllvm -disable-vp
-mllvm -static-func-full-module-prefix=false
-DRESQLITE_PGO
```

Training processes used
`LLVM_PROFILE_FILE=<lane>-%p-%m%c.profraw`. Raw profiles were merged without
sparse mode. The indexed `exp273-arm64-representative.profdata` is 522,568
bytes with SHA-256
`cd957c73e38b10dc04106bdd2bf056687bb0bd856209943146eca6596fd25d74`.
It contains IR counts for 2,406 functions, 31,934 blocks, and
2,556,436,455 counter events.

| Training input | Counter events | Share |
|---|---:|---:|
| Resqlite-only release work | 2,292,291,187 | 89.7% |
| `stream_rerun_latency.dart` | 244,612,184 | 9.6% |
| `tx_body_write_coalescing.dart` | 19,533,084 | 0.8% |

Concurrent worker isolates can enter the dylib at the same time, so generation
used `-fprofile-update=atomic`. A focused probe recorded the exact expected
1,000/1,000 calls with continuous, atomic counters; the default single-update
mode was not accepted as a concurrent training contract.

Darwin continuous mode does not collect LLVM value profiles. A naive profile
produced 184 missing-value-site warnings at use time. Passing
`-mllvm -disable-vp` in **both** phases creates a clean counter-only contract
instead of silently consuming incomplete value data.

### Strict profile-use build

The candidate replaced generation flags with:

```text
-fprofile-use=<indexed-profile>
-mllvm -disable-vp
-mllvm -static-func-full-module-prefix=false
-Werror=profile-instr-out-of-date
-Werror=profile-instr-unprofiled
-Werror=backend-plugin
-DRESQLITE_PGO
```

The strict AOT candidate built without warnings. `RESQLITE_PGO` suppressed the
manual `hot` attributes so the measured profile, rather than two competing
sources of hotness, owned compiler placement. Baseline and candidate bundles
were then run in independent B-C-C-B processes.

## Results

### Broad release A/B cleared the aggregate value bar

The table uses direction-normalized candidate deltas: negative is faster for
both wall-time and QPS lanes.

| Scope | Pair 1 B -> C | Pair 2 C -> B | Combined | Repeated wins >=5% | Repeated regressions >=3% |
|---|---:|---:|---:|---:|---:|
| 65 release wall/QPS lanes | **-7.11%** | **-4.17%** | **-5.65%** | 31 | 0 |
| 44 native/floor-filtered lanes | **-8.95%** | **-6.10%** | **-7.54%** | 29 | 0 |

The broad result is a real positive signal: the combined 65-lane result clears
5%, and no lane reproduced a regression of at least 3%. The stricter
native/floor-filtered subset is stronger in both orders.

Pair 2's raw aggregate was pulled down by one candidate-2 point-read sample at
116,035 QPS despite a 3.7% MDE. A fixed-binary focused B-C-C-B check did not
reproduce that result:

| Pair | Baseline | Candidate | Candidate delta |
|---|---:|---:|---:|
| 1, B -> C | 209,524 QPS | 220,936 QPS | **+5.45%** |
| 2, C -> B | 209,286 QPS | 221,223 QPS | **+5.70%** |

### Focused transaction checks were neutral-to-faster

Negative deltas are lower candidate wall time.

| Transaction lane | Pair 1 | Pair 2 |
|---|---:|---:|
| sequential await | **-5.2%** | **-4.0%** |
| burst `Future.wait` | **-6.3%** | **-4.9%** |
| single write | **-3.5%** | **-2.7%** |
| interleaved select | **-4.8%** | **-0.4%** |

No focused transaction lane regressed. These checks reinforce the broad win;
they do not erase a separate stream-latency guard.

### Homogeneous stream latency failed three of five pairs

The same baseline and candidate binaries ran five independent pairs. Each
process measured 300 homogeneous single-write emissions; odd pairs ran B-C and
even pairs C-B.

| Pair | Order | Baseline p50 | Candidate p50 | Candidate delta | Gate |
|---|---|---:|---:|---:|---|
| 1 | B-C | 1.3445 ms | 1.2150 ms | -9.63% (-0.1295 ms) | pass |
| 2 | C-B | 1.0625 ms | 1.1090 ms | **+4.38% (+0.0465 ms)** | **fail** |
| 3 | B-C | 1.1145 ms | 0.9405 ms | -15.61% (-0.1740 ms) | pass |
| 4 | C-B | 0.7575 ms | 1.0860 ms | **+43.37% (+0.3285 ms)** | **fail** |
| 5 | B-C | 1.1250 ms | 1.2565 ms | **+11.69% (+0.1315 ms)** | **fail** |

Pairs **2, 4, and 5** each cross both rejection thresholds. The failure spans
both run orders, so the candidate fails the declared 3-of-5 rule.

### Pooled nuance does not change the paired decision

Pooling all 1,500 homogeneous samples per arm yields 1.1140 ms baseline versus
1.1310 ms candidate: **+1.53% and +0.0170 ms**, below both decision thresholds.
A deterministic 10,000-resample independent-sample bootstrap gives a 95%
median-delta interval of -0.0825 to +0.1140 ms.

The pooled heterogeneous p50 moves in the favorable direction, 1.3465 to
1.2875 ms (**-4.38%, -0.0590 ms**), with a -0.1145 to +0.0180 ms bootstrap
interval. Both intervals cross zero. Pooling also discards adjacent-process
phase and order structure, so this evidence does **not** establish a stable
intrinsic PGO slowdown. It likewise cannot retroactively replace the
predeclared replication rule. Exp 273 is a policy rejection under that paired
guard, not a claim that every PGO stream sample is slower.

### Profile composition explains a plausible miss

Release work supplied 89.7% of the profile's counter mass, while stream work
supplied 9.6%. `resqlite_step_row_hash`, a stream-only hot function, reached a
maximum count near 78,000, below the merged profile's approximately 102,700
99%-hot cutoff. At the same time, `RESQLITE_PGO` removed its existing manual
`hot` attribute.

Doubling stream training weight in a diagnostic would put that function near
156,000 against an approximately 105,400 cutoff. That is a mechanism clue, not
ship evidence: changing corpus weights after reading a failed guard would be
post-hoc tuning unless representative product incidence independently
justified the new mix.

### Binary size improved

The PGO dylib fell from 1,869,776 to 1,588,624 bytes, a **15.04% reduction**.
This is useful supporting evidence for code-layout specialization, but binary
size was not allowed to override a latency guard.

## Lifecycle and portability blockers

The stream failure is sufficient to reject the candidate. The build lifecycle
also did not clear the product gate:

- continuous mode requires the hidden `-mllvm -disable-vp` setting in both
  phases; omitting it produced 184 incomplete-value-profile warnings;
- correct concurrent training requires atomic counters, making
  `-fprofile-update=atomic` part of the generation contract;
- LLVM static-function keys originally embedded absolute checkout paths.
  `-ffile-prefix-map` did not repair them. The hidden
  `-mllvm -static-func-full-module-prefix=false` setting normalized keys to
  basenames, but a checked-in profile still needs an explicit cross-worktree
  use receipt;
- profiles are target-, architecture-, compiler-, and source-specific. Using
  the x86_64 profile for arm64 emitted 54 hash mismatches; this experiment
  froze only a macOS arm64 Apple Clang 21 profile;
- every supported target therefore needs a trained profile or a tested normal
  optimization fallback, plus a retraining and provenance policy for source or
  toolchain changes; and
- the checked-in profile is 522,568 bytes and the candidate adds build-hook
  conditionals, strict diagnostic policy, hidden LLVM flags, and manual-hotness
  interaction for a benefit that has already failed one important path.

These are solvable engineering problems, but they are persistent product and
release complexity. A result that fails a predeclared latency guard does not
justify paying that cost.

## Decision

**Rejected.** Continuous counter-only PGO retires exp 054's process-exit flush
blocker and shows broad native headroom: -5.65% across all 65 release lanes,
-7.54% on the native/floor-filtered subset, approximately +5.5% focused point
QPS, neutral-to-faster transaction checks, and a 15.04% smaller dylib. Those
positives are preserved because a later toolchain or better-founded training
corpus may legitimately reopen the direction.

They do not satisfy the complete product gate. Homogeneous stream p50 crossed
the exact 3% and 0.02 ms thresholds in three of five independent pairs. The
candidate also lacks a finished, cross-target and cross-worktree profile
lifecycle.

The exact tested hook/native prototype and representative profile are preserved
on `archive/exp-273` at
`580135626619cc70164918ab06caf95a040e9eb5`.
The publication branch reverts the PGO hook, native manual-hot suppression,
and temporary release-suite filters. It retains the generalized
`stream_rerun_latency.dart` `--trials` / `--raw` measurement support plus the
profile manifest and stream adjudication evidence. No runtime, native ABI,
public API, or default build behavior changes.

### Reopen conditions

Do not ship the present profile, hide the stream result inside an aggregate, or
simply double stream training weight from this post-hoc diagnosis. Reopen only
if all of the following are available:

1. representative downstream incidence independently justifies a revised
   training mix or a compiler strategy that preserves the proven stream-hot
   function without undermining profile ownership;
2. the revised candidate passes the same five-pair, 300-trial homogeneous p50
   rule, with fewer than three pairs regressing by both 3% and 0.02 ms;
3. representative release wall again improves at least 5% in both orders, with
   no reproduced important-lane regression of 3% or more;
4. strict profile-use diagnostics remain clean and cross-worktree consumption
   of the exact archived profile is proven; and
5. every supported target has a source/compiler/architecture-matched profile
   or an explicitly tested non-PGO fallback, with reproducible training,
   hashes, provenance, and bounded binary/package-size cost.

## Test plan

- [x] prove continuous dylib counters survive the Dart host's `_exit()` path
- [x] require atomic counter updates for concurrent native workers
- [x] freeze and hash the representative macOS arm64 counter-only profile
- [x] build the PGO-use AOT candidate with strict profile diagnostics
- [x] run independent Resqlite-only release B-C-C-B bundles
- [x] rerun the anomalous point-read lane with fixed binaries in B-C-C-B order
- [x] run focused transaction lanes in both orders
- [x] adjudicate homogeneous stream p50 in five independent 300-trial pairs
- [x] preserve pooled/bootstrap nuance without changing the declared rule
- [x] record profile portability and target-specific lifecycle blockers
- [x] archive the exact prototype/profile and record the final archive commit
- [x] revert temporary PGO and release-filter changes on the publication branch
