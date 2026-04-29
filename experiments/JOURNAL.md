# Journal

A researcher's notebook of durable insights from Resqlite performance work.
Most experiment runs should leave at least one entry behind: a transferable
lesson, a surprise during measurement, a finding that didn't fit the
experiment writeup, an external change worth flagging for future runners, a
hunch that deserves a future experiment, or a "huh, that wasn't what I
expected" moment. Free-form is fine — a paragraph, a short list, a single
sentence with a link. Keep it short enough that the next reader actually
reads it.

This file sits between two others:

- [`signals.json`](signals.json) — the structured, machine-readable research
  map (per-direction state, statuses, dependencies).
- [`MILESTONES.md`](MILESTONES.md) — the curated, blog-style narrative of how
  the project has evolved, updated on request rather than per experiment.

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

### Per-call cost removals need a compounding effect to clear the dispatch floor

The recent run of micro-allocation and micro-computation rejections — exps
[071](071-stmt-cache-mru-scan.md),
[094](094-dirty-read-string-reuse.md),
[095](095-writer-result-buffer.md),
[102](102-savepoint-string-cache.md),
[108](108-selectbytes-out-slots.md), the savepoint-cache half of
[111](111-nested-tx-benchmark-savepoint-cache.md), and the pre-implementation
[112](112-sql-len-passthrough-analysis.md) — all targeted a single
~tens-of-nanoseconds per-call saving on a hot path. None registered. The
one acceptance in the same family, [exp 109](109-inline-param-buffer.md),
landed because it combined *two* independent effects on the same path
(per-text/blob `calloc` removal **plus** SQLite-internal `strlen` skip).
The dispatch noise floor on the release suite swallows a single small
saving even when it is structurally clean and applied across every entry
point.

*Reapplies whenever a candidate is "remove this small repeated thing." If
the per-call ceiling is bounded at sub-percent of the [exp 080](080-dispatch-budget.md)
dispatch wall, the experiment is either a pre-implementation rejection
(like exp 076 / 112) or it needs a second compounding lever on the same
path before it is worth running.*

## How to add to this file

Most runs should add at least one entry. The journal is a notebook — the
bar is "would I want to read this if I were the next runner?", not "is
this a polished theorem?".

For a **transferable lesson** (the highest-value entry type):

- Lead with the lesson, not the experiment
- Cite the experiment(s) where it was learned
- End with a *Reapplies* note describing when the lesson kicks in

For **shorter notes** (surprises, hunches, external changes, things that
didn't fit the experiment writeup): a paragraph or a sentence with a link
is enough. No fixed structure. If the note grows into a transferable
lesson over time, edit it into that shape.

Don't add entries for facts already captured in `signals.json` (that
file covers per-direction state). Don't add process guidance (that
lives in `RUNNER_INSTRUCTIONS.md`). Don't add narrative milestones
(those live in `MILESTONES.md`). When in doubt about which file a
piece of information belongs in, the journal is the right default —
it's easier to move a note into structured state later than to
re-derive a lost observation.
