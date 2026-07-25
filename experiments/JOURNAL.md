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

### A reproduced win can still be the wrong thing to ship

[Exp 213](213-tx-body-write-coalescing.md) built the buffered
`Transaction.execute` path, measured **-26 % / -31 %** on the
`Future.wait([tx.execute × N])` inside `db.transaction()` shape across two
order-flipped focused passes, `ab_drift_check.dart` returned REPRODUCED, and
every other lane (sequential-await, single-write, interleaved-select) stayed
inside the 3 % effect floor. The measurement was clean. The moonshot was
rejected anyway — because the winning shape is not one resqlite steers users
toward: same-SQL bulk atomic writes belong on `executeBatch`, different-SQL
non-atomic bursts have exp 180's standalone coalescing, and different-SQL
atomic bursts are rare in practice. The runtime change required four
load-bearing guards (`_inFlightWrites`, `hasPendingWrites` on `drainForClose`,
parameter aliasing snapshot, tracelite span parity) plus persistent
per-`Transaction` state — a maintenance floor every future writer-path change
would have to reason about, all to accelerate a workload we are not
promoting.

The prior "you cannot merge a win under noise" lessons (measurement gap,
sub-MDE memory, drift discrimination) are all about *whether the number is
real*. This one is downstream: even when the number is real and the
regressions on the important lanes are provably absent, the acceptance
question is still whether the *pattern the win depends on* is one we want to
optimize for. If it's a niche the API doesn't encourage, or one already
covered by another well-fitted primitive, the win is orthogonal to the
product direction and the complexity cost eats it.

[Exp 232](232-dyadic-real-fastpath.md) exposed the same failure through a data
distribution rather than an API pattern. Exact quarter-step REAL targets were
78-87% faster and a synthetic row with 50% quarter cells improved 50-53%, but
no production profile or representative schema established that exact
`.25`/`.5`/`.75` cells occur often enough to matter. Meanwhile every summary
of the general fractional control leaned 0.65-1.95% slower, and the candidate
added a permanent value-lattice branch, magnitude boundary, negative-subunit
formatting, and test-export surface to the generic REAL formatter. The
mechanism was real; its expected product value was not established, so the
runtime was rejected and archived.

*Reapplies at the end of any experiment where the numbers cleared the drift
check but the winning workload shape is niche or already covered by an
existing primitive, or where the win depends on a narrow data distribution.
Ask: does the API steer users toward this shape? Does another primitive cover
it? What representative evidence establishes the eligible share? What is the
expected aggregate benefit after miss-path tax? Does that benefit repay the
permanent complexity budget? If the answers do not make a product case, the
reproduced win is not the whole case — write the rejection carefully so the
evidence is what lands on main, and preserve the runtime prototype at
`archive/exp-NNN` for the case where a production signal reopens the shape.*

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

### Removing boundary crossings can still add more work than it removes

[Exp 224](224-numeric-row-batching-moonshot.md) removed nearly all per-row
leaf FFI crossings from numeric `select()` scans without repeating
[exp 018](018-multi-row-step.md) / [exp 074](074-bulk-step-many.md)'s TEXT/BLOB
copy mistake. The dynamic prototype accumulated up to 64 numeric/NULL rows but
returned immediately after a pointer-backed row, preserving SQLite's borrowed
buffer lifetime. Even then, the numeric targets stayed flat-to-slower and the
TEXT guard regressed 5-7%: the integrated batched fill/decode path cost more
than the leaf calls it removed, even without the earlier payload-copy confound.

*Reapplies whenever a batching or fusion change is justified mainly by fewer
crossings. Count the work that moves into the larger batch—buffer writes,
working-set growth, guard branches, and the larger batched fill/decode
traversal—and require the target lane to beat a control that keeps the old
locality. A smaller boundary count is not itself a smaller end-to-end path.*

### A fast-reject value is not necessarily a cacheable identity

[Exp 077](077-cheap-check-first-sweep.md) stopped hashing a growing stream
result once its row count proved the result had changed. That was a valid
one-shot rejection, but the prefix-only accumulator was then cached as the
changed result's complete hash. [Exp 228](228-canonical-stream-hash.md) exposed
the delayed cost: the next identical rerun computed the canonical full hash,
mismatched the partial baseline, and decoded and emitted every row again.
Removing the shortcut fixed the public behavior and improved the complete
grow-then-no-op sequence even though the first growth leg did slightly more
work.

*Reapplies whenever an early exit returns a value that crosses a state boundary.
Separate “enough to decide this call” from “safe to persist for the next call”;
only a canonical value can silently serve both roles.*

### A SIMD kernel co-located with a scalar hot path must be `noinline`

[Exp 229](229-simd-base64-neon.md)'s first prototype placed the AArch64/NEON
`vqtbl4q_u8` base64 body directly inside `json_write_base64`, gated by
`if (len >= 48)`. Even though small-blob calls (`len < 48`) never entered
the SIMD branch, the 3 B tiny-cell lanes reproduced +3-9 % candidate-slower
across order-flipped passes. The scalar body was byte-textually unchanged;
the compiler's register allocation and code layout around it were not.
On a lane that runs ~80,000 base64 calls per query, a ~5-10 cycle
scalar-path overhead per call maps to ~400 µs / query — matching the
observed regression exactly.

Moving the NEON body into a separate `__attribute__((noinline))` function
and calling it from `json_write_base64` (`if (len >= 48) { i = simd(...); }`)
collapsed the 3 B regression back into noise while preserving the 4 KB /
128 B wins in full. The scalar path's `.text` layout matched exp 225's
byte-for-byte.

*Reapplies to every future SIMD kernel added to a hot-path C function.
Place the SIMD body in its own `__attribute__((noinline))` function; the
caller dispatches with one length check. Don't let the compiler decide to
inline it "back" — even when the SIMD branch is not taken, an inlined
kernel body reshapes the scalar path's register allocation and code
layout around it. The dispatch check is cheap; the layout cost isn't.*

### The smallest workload admitted to an optimized path is its adoption gate

[Exp 230](230-neon-json-scan-copy.md) fused AArch64/NEON escape
classification with copying for JSON TEXT values at least 256 bytes long.
The mechanism was strong at the far end: safe 1 KiB ASCII improved
33.6-34.1% and long CJK improved 25.2-25.5% across an order-flipped pair.
But the 256-byte cutoff lane moved 17.7% and then 12.6%, missing the preset
15% bar in the second ordering.

The cutoff row is where the implementation first starts paying its dispatcher,
extra encoder body, platform-specific correctness surface, and future
maintenance cost. A much larger payload can confirm the mechanism, but it
cannot substitute for the first admitted workload clearing the declared bar.
Moving the cutoff after seeing the results would merely select the winning row
post hoc.

*Reapplies whenever an optimization is guarded by a size, width, or count
threshold. Declare the first admitted workload before measuring and treat it as
the load-bearing acceptance row; larger workloads are confirmation. If the
boundary misses, archive the far-end potential and wait for production evidence
rather than moving the threshold around noisy guards.*

### A SIMD kernel needs bulk *per call*, not just a hot path — amortisation, not the algorithm, decides

[Exp 229](229-simd-base64-neon.md) landed the first AArch64/NEON kernel by
encoding base64 over whole BLOBs, and suggested out-of-lined ISA kernels are
broadly viable. [Exp 231](231-neon-i64-decimal.md) tried the same mechanism on
the integer arm — a byte-identical NEON i64→decimal kernel that breaks the
scalar two-digit loop's serial `/100` chain — and it never beat the scalar itoa
on the deep-magnitude BIGINT lane, across 11 A/B passes in three methodologies.

The difference is *what one call processes*. Base64 amortises SIMD register
setup and the out-of-line call over tens-to-thousands of bytes per invocation.
The integer formatter converts exactly one scalar value per call, so the same
fixed setup is paid per cell with nothing to spread it over, and it loses to a
fully-inlined scalar loop the CPU already pipelines. Integer encoding *is* a
material share of integer-heavy `selectBytes` wall (exp 192 won −25% there), so
the path is hot — but a hot path is not a batched call. Inlining the kernel to
kill the call boundary is the wrong escape: it bloats the per-cell hot loop and
regresses the common small case, the code-gen regression exp 229/230 both hit
when SIMD state leaked into a scalar path.

*Reapplies before vectorising any per-element formatter/encoder. Ask how many
elements one kernel call consumes, not whether the path is hot. If a call
handles a single scalar value (one int, one small cell), the setup + call cost
will not amortise no matter how good the vector body is — reopen only when the
architecture can hand the kernel a batch (columnar/bulk transfer), not a stream
of one-value calls.*

### Asynchronous maintenance needs a re-arm rule, not just coalescing

[Exp 233](233-async-checkpoint-worker.md) moved the writer hook's 500-frame
PASSIVE checkpoint to a dedicated connection and isolate. The first crossing
became 46-56% faster, proving the I/O was removed from the reply path. Under a
sustained burst, however, write p50 became 2.7-3.4x slower and the WAL grew to
12,377 frames. The inline trigger was a level check (`pages_in_wal >= 500`)
whose work naturally completed before another commit. Once execution became
asynchronous, the writer kept observing the same true level and requesting or
rerunning checkpoints. A four-state coalescer bounded messages but did not
bound maintenance work.

*Reapplies whenever inline cleanup, refresh, compaction, or checkpoint work is
moved to a background worker. Define what new generation or high-water delta
re-arms the trigger, and benchmark sustained foreground contention; suppressing
duplicate wakeups does not make a continuously true trigger edge-like.*

### Cross-isolate transport costs live in the copy's destination, not its count

[Exp 234](234-blob-param-transfer.md) initially shipped with the intuitive
mechanism story — "`TransferableTypedData` avoids `SendPort.send`'s deep
copy" — and a source-level dig proved it wrong twice over. Since Dart 2.15,
same-group sends do a single object-graph copy **on the sender**
(`runtime/vm/object_graph_copy.cc`); there is no receive-side rebuild, and
the wrapped route (`fromList` memcpy + constant-time ownership move + ~1 µs
`materialize()` view) copies the payload exactly as many times as the direct
route: once, on main. The reproduced ~15–20% win on 256 KB–512 KB blob
INSERTs comes from *where* that one copy lands: the direct route parks every
in-flight payload on the shared GC heap, where scavenges must evacuate it as
live young-generation data and every collection safepoints the whole isolate
group — including the writer mid-step, which a serialized request/reply
protocol converts straight into latency. The wrapped buffer is malloc'd
external memory the GC never traces (real-path attribution: 8.6 ms vs 1.2 ms
of GC pause per 300 × 256 KB inserts). The bounds are mechanistic: below
~256 KB the graph copy's fast path is near-free and wrap bookkeeping loses;
at ≥ 1 MB the WAL write dominates and huge payloads skip new space anyway.

*Reapplies whenever comparing transports or attributing a transport win.
Count where the bytes land, not just how many times they move — a GC-visible
allocation carries deferred collection and group-safepoint costs that
per-call timing never shows. And verify mechanism claims with per-claim
measurement (a synchronous call's wall vs size proves where a copy runs;
flat-vs-linear scaling proves view-vs-copy) rather than inferring the
mechanism from an end-to-end delta.*

## A transport win measured on many round-trips need not survive coalescing — round-trip topology is the load-bearing variable, not payload size

Exp 234 accepted a ~15–20% win from wrapping ≥ 256 KB blob params in
`TransferableTypedData` on the single-row write path, and its own signal
predicted the win would "reproduce the same transfer fraction" on a blob-heavy
`executeBatch`. Exp 237 tested exactly that and found the opposite: a
*reproduced regression* (256 KB candidate-slower on 8/8 order-flipped legs,
+7.6% to +18.1%; no size wins). The reason is that exp 234's win was never
about payload size in the abstract — it came from the interaction between
*per-round-trip* heap churn and the writer being safepointed **mid-step**:
across N single-row INSERTs, each `SendPort.send` parks a blob on the
young-generation heap, and a scavenge triggered while the writer is
mid-`sqlite3_step` on the previous blob stalls it, a cost that compounds over N
round-trips. `executeBatch` carries all N sets across **one** send and runs
them in **one** writer round-trip inside one transaction, so that interleaving
is gone — leaving only the wrap's per-blob `fromList`/`materialize` tax with
nothing to reclaim. Batching is a form of round-trip coalescing (cf. exp 180),
and coalescing removes precisely the churn the wrap reclaimed.

*Reapplies whenever a transport/scheduling win is proposed for a
coalesced, batched, or pipelined path on the strength of a per-item result.
The number of isolate round-trips — not the total payload moved — is what
determines whether a GC/safepoint-interaction win survives. Re-measure on the
collapsed path; do not extend by payload similarity. (Two adjacent runs on the
same shared file: exp 235 also touches JOURNAL.md — keep both entries on
merge.)*

### A batch can preserve aggregate throughput and still destroy independent completion latency

Exp 239 transparently grouped only plain SELECTs already parked behind a full
reader pool. The mechanism looked unusually well bounded: homogeneous
twenty-way point and short-list bursts improved 21-33%, the first four-way wave
was untouched, and even twenty large reads stayed neutral-to-faster because
the overflow remained sharded across workers. Yet alternating large and point
queries exposed the semantic scheduling cost. A point query sharing one worker
envelope with large reads could not resolve until the whole envelope returned;
point-completion p95 regressed 11-17% and total median 13-26% in both
orderings. Queue pressure says work is waiting, not whether it is equally
costly or equally latency-sensitive.

*Reapplies whenever an internal scheduler coalesces independently completable
work. Aggregate throughput and pool utilisation are insufficient guards: add a
heterogeneous lane and measure each latency-sensitive member's completion,
because an indivisible reply can create head-of-line blocking even when total
work stays parallel. Hidden batching needs a cost/priority signal or
independently deliverable member results; queue depth alone is not policy.*

## A cross-value pipelining win measured on a packed array dies when the real path fetches the inputs serially

Exp 240 built exp 231's named reopen — hand the integer formatter an *array* of
i64 cells so per-value latency amortises. In a pure-conversion microbench (values
already sitting in a contiguous `int64` array) a 2-way software-pipelined scalar
formatter overlapped two values' independent divide chains and won −6 to −13% on
mid/big magnitudes. Wired into `write_json_to_buf`, the same code was uniformly
+1 to +12% *slower* — worst on the exact lane the microbench won most. The
premise that made the microbench win — two independent conversions in flight at
once — silently evaporated on the real path, because each cell's value is fetched
through its own `sqlite3_value_int64` call, so the two "parallel" chains are
actually gated behind serial source reads. The overlap the batch was built to
exploit never existed once the inputs came from SQLite one at a time, leaving
only the lookahead machinery's added hot-loop cost.

*Reapplies whenever an ILP/pipelining/SIMD-over-array optimisation is validated
on a pre-materialised buffer of inputs. Before integrating, check how the inputs
arrive on the real path: if each is produced by a separate upstream call
(an FFI/value accessor, a decode step, a cursor advance), the cross-item overlap
the benchmark measured will not occur, and the batching scaffold becomes pure
overhead. The array-in-hand microbench must feed from the same source the hot
path does, or its win is an artefact of the packed fixture. Distinct from exp
226's "isolated win below the end-to-end gate" (a magnitude gap): here the sign
flips, because the mechanism itself is absent in production.*

## A configuration where the candidate is mechanically inert is the cheapest noise gauge you can build

Exp 248 removed a struct swap from the statement cache's MRU promotion. Its
harness cycled N distinct hot SQLs, and `N = 1` was included as a control —
with one SQL the matched entry already sits at the MRU tail, so the promotion
branch is unreachable and candidate and baseline execute *the same
instructions*. Those control lanes moved +24% and +27% on the first pass and
+103% and +42% on the order flip. Since the delta there is definitionally zero,
that swing is a direct reading of the harness's own floor — and it instantly
disqualified the primary lanes' apparent −22% and −35% "wins," which reversed
sign on the flip anyway.

*Reapplies whenever a candidate is gated by a branch, threshold, size class, or
type check. Pick inputs that provably cannot reach the changed code and run them
as a labelled lane beside the real ones. Unlike a general control workload, this
one is exactly comparable — same harness, same call shape, same allocation
pattern — so its delta measures nothing but noise, and it converts "is this
drift?" from a judgement call into an observation. It costs one array entry and
is far cheaper than the extra confirmation passes it replaces. It is also the
one control that stays valid when a rejected experiment's numbers look good:
exp 248's primary lanes looked like a win until the inert lanes moved more.*

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
