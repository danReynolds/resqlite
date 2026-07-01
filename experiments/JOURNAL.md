# Journal

A researcher's notebook of durable insights from Resqlite performance work.
Each entry is a lesson that earned its place by surviving more than one
experiment — write here only when you have learned something a future runner
shouldn't have to rediscover.

This file sits between two others:

- [`signals.json`](signals.json) — the structured, machine-readable research
  map (per-direction state, statuses, dependencies).
- [`../doc/stories/`](../doc/stories/) — the curated, blog-style narrative of
  how the project has evolved, updated on request rather than per experiment.

Journal entries cite the experiments they came from and end with a *Reapplies*
note describing when the lesson kicks in.

## Insights

### An optimization that measures flat may simply not be running

[Exp 099](099-fnv-8byte-bytestream.md) added an 8-byte FNV main loop — a
structurally sound win for long-text streams — and measured nothing. The cause
wasn't the implementation; the streaming benchmarks at the time only carried
≤ 8-byte cells, so the new main loop never executed. Before declaring an
optimization dead, verify the workload actually exercises its hot path.
[Exp 110](110-long-text-stream-benchmark.md) later built the long-cell workload
that exp 099 should have been measured against.

*Reapplies whenever a structurally plausible change shows a flat result. The
hypothesis to test first is "is the path running?", not "is the change wrong?".*

### Reader-pool throughput is round-trip-bound, not parallelism-bound

[Exp 105](105-reader-pool-sizing.md) raised the reader pool cap above
`clamp(numProcessors - 1, 2, 4)` and regressed A11c writer throughput. Per-write
wall closely matches `pool_round_trip × ⌈N/pool_size⌉ + ~30 µs`, so adding
workers only helps when there are enough concurrent reads to saturate them. On
writer-shaped fan-out the extra workers cost more in scheduling than they save
in latency.

*Reapplies when considering "more workers" as a remedy for fan-out latency.
Check the round-trip count first; parallelism without queue pressure is
overhead.*

### Re-running a rejected experiment requires the rejection's reason to have changed

A new workload, signal, or external change can revive a rejected idea — but the
rerun must articulate *what is different* from the original rejection.
[Exp 104](104-094-reeval-under-a11c.md) re-evaluated [exp 094](094-dirty-read-string-reuse.md)
under A11c-shaped fan-out and the maximum effect was still within MDE. Pure
replication of a bounded measurement rarely earns a slot.

*Reapplies whenever an old direction looks tempting again. The working note
should name the specific thing that changed — a new benchmark, a new compiler
release, a related accepted experiment that altered the hot path — not just
"worth another look."*

### Sub-MDE memory deltas can still be real

The benchmark harness measures RSS, but the Dart VM retains heap pages after
GC. A memory win below the per-benchmark MDE can be real — invisible because
the VM didn't return pages to the OS, not because the allocation didn't go
away.

*Reapplies whenever a change targets allocation or object reuse. Prefer
profiler/heap evidence over RSS-only claims; a flat RSS number is not a "no
change" signal.*

### Measurement is a first-class outcome

Three of the most useful experiments in the recent map ([exp 097](097-one-pass-initial-stream-hash.md),
[exp 099](099-fnv-8byte-bytestream.md)'s rejection, [exp 110](110-long-text-stream-benchmark.md))
were either pure measurement work or surfaced their main value by exposing a
gap in the existing benchmarks. When the bottleneck signal is missing, build
the signal — don't force an implementation experiment against a workload that
can't see it.

*Reapplies before any implementation experiment. If you cannot describe the
benchmark line that will move under the change, the next experiment is probably
the benchmark, not the change.*

### Filling a measurement gap can still produce a rejection — and that's a stronger result

When a prior experiment was rejected for "no workload to measure," it's
tempting to treat building the workload as a setup step before the eventual
acceptance. [Exp 111](111-nested-tx-benchmark-savepoint-cache.md) added the
missing nested-transaction benchmark that exp 102 and exp 103 had both pointed
at, then re-ran exp 102's archived savepoint string cache against it. The
shallow fan-out shape — 50 SAVEPOINTs/iteration, the worst case achievable
through the public API — moved -9 %, below the ±17 % decision threshold. The
benchmark is the lasting contribution; the implementation rejection now rests
on direct worst-case-workload evidence rather than the absence of evidence.

*Reapplies whenever a "blocked on missing measurement" rejection is being
revisited. Frame the experiment so the new measurement is the deliverable
regardless of the implementation outcome — and budget for the implementation
to fail more confidently than before.*

### A new accepted experiment can erase the workload that justifies an open one

[Exp 114](114-fifo-waiter-queue.md) opened with strong wins on streaming
fan-out (-32 % Long-Text Unchanged Fanout, -18 % Streaming Fan-out, -10 %
A11c Overlap) measured against a baseline that did not yet contain
[exp 106 polish](106-column-level-deps.md). When 106 polish merged to
main and 114 was rebased on top of it, the same change against the same
workloads collapsed entirely into noise: 106's writer-side column-level
elision skips most stream re-queries before they reach the reader pool,
so the parked-dispatcher contention 114 was waking more efficiently
simply doesn't fire anymore. The implementation was sound and the
original measurements were honest — the workload that exposed the
contention was just removed upstream while the PR was open.

*Reapplies whenever a slow-merging in-flight PR is in the same subsystem
as a freshly-merged accepted experiment. Re-baseline against current
main before claiming acceptance — and ask, before opening, whether the
contention path the change targets is still reachable on current main
or whether some recently-accepted experiment now elides it.*

### Wall-convention and counter-snapshot timing must match the work being measured

[Exp 121](121-invalidation-traversal-audit.md) established a strict
writer-side burst-wall convention — stopwatch stops on the last write —
so `invalidate_us / wall_us` was a stable denominator for invalidation
traversal, which fires entirely inside the writer-reply handler chain
during the burst.

[Exp 136](136-completion-microtask-counter.md) initially inherited the
same audit harness verbatim and read **zero** for its completion-side
counter — even though the instrumentation was correct and `kProfileMode`
was on. The cause: reader-pool replies on the same A11c overlap workload
mostly land on the main isolate AFTER the last write, during the drain.
The audit's counter snapshot ran at burst-end, so it missed almost all
of the work the counter was designed to measure. Adding a second
post-drain snapshot (`countersAfterDrain`) brought the counter to life
and produced the 22–27% completion-fraction reading.

The wall denominator itself doesn't need to change between writer-side
and completion-side audits — keep `wall_us` writer-burst wall so
fractions stay directly comparable across experiments — but the
*counter snapshot timing* must match where the measured work actually
fires. For drain-phase counters (reader-pool completion, post-burst
subscriber delivery, anything driven by Future resolution of an async
I/O), snapshot after the quiet-window drain finishes and report it as
a fraction of total (burst + drain) wall, not as a fraction of burst
wall alone.

*Reapplies whenever instrumenting an event-loop-driven path. Before
running the audit, predict which phase the counter increments fire in
— if any meaningful fraction lands in the drain, the harness needs a
post-drain snapshot or the result will look like the counter is dead.*

### A worktree's `dart pub get` is mandatory before edited library code is observable

A scheduled-experiment worktree under `.claude/worktrees/` shares the
parent repo's `.dart_tool/package_config.json` by default. That config
resolves the `resqlite` package to `..` (the parent repo's `lib/`),
*not* the worktree's. [Exp 136](136-completion-microtask-counter.md)
hit this directly: a counter added to `lib/src/profile_counters.dart`
in the worktree was invisible because the audit harness compiled
against the parent repo's older copy of that file — which happened to
already contain a different in-flight branch's counters (exp 135's
writer-handler counters), making the symptom look like wrong-branch
contamination rather than a path-resolution issue.

The first sign is the `ProfileCounters.snapshot()` output disagreeing
with the static field list in the code you just edited. Running
`dart pub get` from inside the worktree creates a worktree-local
`.dart_tool/` that binds the toolchain to the worktree's `lib/`.

*Reapplies any time a scheduled experiment runs inside a fresh
worktree and instruments library code. Run `dart pub get` once
before the first profile-mode invocation. If a counter shows zeros
that you expected to be nonzero, check the snapshot map for
unexpected keys from a different branch.*

### Admission loops need concrete resources before checking capacity

[Exp 122](122-concrete-reader-pool-stream-admission.md) found a subtle async admission
boundary: `StreamEngine._flushQueue` was trying to make reader-capacity
decisions while the engine still held a `Future<ReaderPool>`. Even after the
future had resolved, the stream path still crossed an async handoff before a
re-query reached `ReaderPool._dispatch`. Constructing `StreamEngine` only after
the reader pool has spawned makes the capacity check and re-query admission
part of the same synchronous path.

*Reapplies whenever a loop gates work on a scarce resource such as reader
slots, writer locks, or native buffers. Prefer giving the admission owner a
concrete handle to the resource over layering a second queue around a future;
otherwise the check is only advisory.*

### Mirroring a rejected experiment on the symmetric path does not reopen its rejection

[Exp 151](151-sync-writer-response.md) rejected the response-side
request-resolution tweak: switching writer reply futures to
`Completer<T>.sync()`. [Exp 170](170-uncontended-mutex-fastpath.md)
tried the symmetric request-side variant: `Mutex.tryLock()` plus a
non-`async` `Writer.execute` to drop the uncontended `await
_mutex.lock()` microtask hop and the wrapping async function's
implicit reply await. Both attempts pointed at the same exp 147
residual writer/request bucket, used the same mental model
("scheduling overhead", not "execution work"), and produced the same
verdict (primary lane within ±2 %, wrong direction).

A scheduling-shape rejection generalises across the request and
response sides. The candidate that follows it should change the
mechanism, not the side. Exp 159 already proved this: it cleared
the same residual by restructuring (persistent reply port + cached
SendPort + send-gated locking) rather than micro-tweaking the
existing structure on the opposite side.

*Reapplies whenever a recently-rejected scheduling change has an
obvious mirror on the other end of the same round-trip. The mirror
is not "a different experiment" — it is the same experiment in a
different file. Look for a structural change instead, or pick a
different direction.*

### Phase-ordered A/B gates confound code deltas with time-correlated drift

The Tracelite experiment wrapper collects all baseline runs, then all
candidate runs. [Exp 159](159-writer-pipelining.md)'s first gate pass flagged
+12–19% regressions on stream scenarios whose write loops never execute the
changed code path — and the flagged phase's within-run CVs were 0.20–0.46
against the other phase's 0.01–0.06. A second pass with collection order
flipped (candidate first) measured all three scenarios neutral with CVs of
0.01–0.03. The flag was machine drift that landed entirely on one side
because the sides were collected in disjoint time blocks. This extends
[exp 144](144-sqlite3mc-bump-2-3-5.md)'s two-independent-passes rule: the
second pass discriminates most when it *flips the collection order*, because
drift then has to indict the opposite side to reproduce.

*Reapplies whenever a phase-ordered A/B flags a regression. Check the
flagged phase's within-run CVs against the other phase first; if they are
elevated, re-run order-flipped before treating the flag as real — and
before burning an ablation pass on a mechanism the workload may not even
exercise.*

[Exp 177](177-ab-drift-discriminator.md) turned this check into a tool:
`benchmark/ab_drift_check.dart` (over `cvPct` + `classifyDriftFlag` in
`benchmark/shared/stats.dart`) takes two order-flipped passes of per-run
values and classifies the flag as `reproduced` / `drift-suspected` /
`inconclusive` by exactly this rule (CV asymmetry, then sign reversal).
Prefer citing its verdict over re-deriving the reasoning by hand; it
reproduces the manual exp 159 (CV asymmetry) and exp 167 (sign reversal)
decisions. It interprets the order-flipped pass — it does not replace
running it.

### A guard against the wrong value often leaves the missing value silent

The experiment->chart pipeline had a build-time guard for the *wrong-file*
case — [exp 109](109-inline-param-buffer.md)'s chart mixup, where an Accepted
experiment linked a baseline-shaped run while a candidate existed, caught by
`_assertAcceptedExperimentsLinkToCandidates`. But the more common
*missing-file* case — an experiment with **no** linked run and no declaration
of that absence — passed silently, even though the skill warns it makes the
experiment "invisible on the chart." [Exp 178](178-missing-run-declaration-guard.md)
found that ~17 of 23 chartable null-run experiments were silently unmapped, and
added the symmetric guard: an absence is only acceptable if it is *declared*
(here, a `**Benchmark Run:**` opt-out header), otherwise it is a forgotten
artifact and fails the build.

*Reapplies whenever a guardrail validates that a present value is correct.
Ask the symmetric question: what happens when the value is absent entirely? If
"absent" and "deliberately none" look identical to the checker, a forgotten
artifact is indistinguishable from an intentional opt-out — add a required
declaration so the two diverge.*

### Parallelism and round-trip batching are complementary at the reader-pool round-trip floor

[Exp 148](148-reader-reply-batching.md) rejected worker→main reader-reply
batching under the load-bearing measured-elapsed gates. It was tempting to
generalize that rejection into "batching along the reader path is not a real
win." [Exp 209](209-heterogeneous-read-batch.md) proved the symmetric side of
the story: main→worker *request* batching (`db.selectAll([...])`) reproduces
same-direction wins on the shape where per-query SQLite work sits below the
reader-pool round-trip floor (point-query lane ≈ 3× faster, medium-list lane
≈ 1.8× faster), while its large-payload guard reproduces the *expected*
regression (≈ 3× slower on 4×10 000-row selects). The regression is
load-bearing, not a bug: it proves the batch path is not a hidden universal
substitute for `Future.wait([db.select(...)])`, and the two APIs are
complementary rather than competing at the reader-pool round-trip floor.

*Reapplies whenever an idea batches work along a scarce-resource path. Ask
which side is being batched (request vs reply, request vs completion), what
the round-trip cost is on that side, and where the boundary lies at which
parallelism starts to win. A single "batching does/does not work here"
rejection rarely generalizes across the boundary.*

## How to add to this file

Add an entry when an experiment surfaces a transferable lesson — something a
future runner could reapply to a different direction, or could waste time
relearning. Each entry should:

- Lead with the lesson, not the experiment
- Cite the experiment(s) where it was learned
- End with a *Reapplies* note describing when the lesson kicks in
- Be short enough that the next reader actually reads it

Don't add entries for facts already captured in `signals.json` (that file
covers per-direction state, not transferable lessons). Don't add process
guidance (that lives in `RUNNER_INSTRUCTIONS.md`). Don't add narrative
stories (those live in `../doc/stories/`).
