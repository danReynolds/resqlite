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

### Admission loops must consume scarce resources before checking capacity again

[Exp 120](120-stream-flush-single-flight.md) found a subtle async admission
bug: `StreamEngine._flushQueue` checked reader availability, called `_requery`,
and then `_requery` awaited the already-resolved pool before it reached
`ReaderPool._dispatch`. That await split let the flush loop check stale
availability and admit more re-queries than the pool could take, recreating
dispatch parking even after exp 118 fixed wake retries. Passing the resolved
pool into `_requery` made each admitted re-query consume a reader before the
next capacity check.

*Reapplies whenever a loop gates work on a scarce resource such as reader
slots, writer locks, or native buffers. The operation that consumes the
resource needs to happen in the same synchronous turn as the capacity check, or
the check is only advisory.*

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
