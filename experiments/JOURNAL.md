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
[Exp 110](110-long-text-fnv-8byte.md) later built the long-cell workload
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
[exp 099](099-fnv-8byte-bytestream.md)'s rejection, [exp 110](110-long-text-fnv-8byte.md))
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

## Envelope count alone does not define a transfer workload

Exp 237 validly rejected its per-occurrence `TransferableTypedData` prototype:
its 30-row `executeBatch` candidate regressed 7.6–18.1% at 256 KB. But the
fixture reused one `Uint8List` identity in every row while the pre-exp-243
candidate created 30 independent wrappers. The direct baseline preserved that
identity and copied the buffer once. The result therefore measured alias
multiplicity as well as its one-message, one-transaction batch topology. Exp
243 later fixed precisely that N-wrapper aliasing defect with one shared
wrapper per identity.

Exp 253 tested the missing distinct-identity case on the neighboring coalesced
standalone-write path. An identity census that left unique 256 KB
`MultiExecuteRequest` buffers direct regressed 10.2% and 7.2% across the order
flip versus today's envelope-shared wrappers, even though both sides used one
message. The larger 512 KB endpoint moved the other way, but could not rescue
the policy after the first admitted size failed. MultiExecute also preserves
one autocommit and outcome per member; it is not exp 237's one transactional C
batch. Exp 237's measured rejection stands, but the broader inference that
coalescing itself removes the wrapper benefit does not.

*Reapplies whenever benchmarking ownership or cross-isolate routing. Record
total bytes, occurrences, unique object identities, envelope count, wrapper
dedup semantics, and receiver transaction/execution boundaries. Exercise
distinct, repeated, and mixed identities explicitly. An end-to-end policy A/B
can reject an implementation, but do not assign the delta to one mechanism
without a focused attribution probe.*

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

## An in-process A/B toggle can manufacture a reproduced-looking win that a cross-worktree comparison reverses

Exp 249 compared two rerun-dispatch paths by flipping a `batchRerunsEnabled`
static inside one long-lived process, order-flipped, and `ab_drift_check.dart`
classified the homogeneous-fan-out emission latency as REPRODUCED at −25.8% /
−27.9%. It looked like a clean win. Then the same code, measured as two separate
binaries (baseline `origin/main` worktree vs candidate worktree, alternated over
three rounds), came out **+22% to +66% slower** on every lane. The sign flipped.

The toggle's two arms were not independent: they shared warm JIT and inline
caches, a reader pool warmed by the other arm's traffic, and a drain probe that
kept the main isolate spinning. Order-flipping cancels cross-*phase* ordering
bias but not shared-warm-state bias, so the drift classifier — which only sees
per-run values — certified an artifact. Only two cold, separate processes
isolate the change from the state it rides on.

*Reapplies to any dispatch, scheduling, isolate-message, or pool change, where
the effect is a few microseconds against warm-state noise. Do not A/B such a
change with a single-process toggle, however rigorous the order-flip and
drift-check look; use two worktrees (or the tracelite two-root wrapper). Treat a
single-process toggle delta as a hypothesis, not a result.*

## Bounded admission is not bounded completion

Exp 250 fixed exp 233's continuously true asynchronous checkpoint trigger by
rearming only after an observed WAL reset or another 500-page high-water
advance. That removed the read-side checkpoint storm and preserved the
first-crossing win, but it did not make the maintenance operation complete:
SQLite PASSIVE can return `SQLITE_OK` with `checkpointed < log` when a reader
pins frames. Consuming the request on that return stranded 9,165 and 10,316
frames in two repeats; immediately retrying would instead spin against a
long-lived reader. The request trigger and the unfinished-work retry policy are
separate state machines. Page count is also only a reset proxy: an equal-or-
larger first commit in a new WAL generation is indistinguishable without a real
generation signal.

*Reapplies whenever background maintenance can make partial progress under
contention — checkpointing, compaction, cache eviction, cleanup, or replication.
Do not equate a successful call with completed work. Declare how partial
progress is detected, backed off, retried, cancelled, and drained at shutdown;
if generation matters, carry a generation rather than inferring one from a
monotonic-looking counter.*

### Judge a candidate's novelty against `origin/main`, not the worktree you start in

[Exp 254](254-text-value-blob-decode.md) began by reading `native/resqlite.c`
in the scheduled runner's *starting* worktree, which sat on a branch behind
`origin/main`. The TEXT decode path there still showed the pre-hoist shape, so
the plan — mirror exp 203's `sqlite3_column_value` hoist onto the decode/hash
paths — looked novel. It was already shipped as the **accepted**
[exp 205](205-step-row-value-cache.md); only the stale checkout hid it. Caught
by checking `git show origin/main:native/resqlite.c` before writing code. This
is the code-reading analogue of the numbering rule ("pick highest+1 from
`origin/main`, not the local tree"): a stale worktree makes a done optimization
look undone.

*Reapplies at the start of every scheduled run. Before believing a hot path is
un-optimized, confirm it against `origin/main` (`git show origin/main:<file>`),
not the tree you happen to be checked out on — and read the adjacent accepted
experiments' index rows, which name what already landed.*

### A two-worktree A/B can carry a per-worktree offset that isn't drift

The order-flipped-pass rule (exp 159/177) catches *time-correlated* drift — a
regression that lands on whichever phase ran in the slow time block and flips
when you flip collection order. [Exp 254](254-text-value-blob-decode.md) hit a
different artifact: comparing a baseline worktree against a candidate worktree,
the byte-identical integer control lane moved ~-4.8% *the same direction in both
order-flipped passes*. A same-sign control delta that survives order-flip is not
drift — it is a systematic per-binary offset (layout/placement between two
separately built `.so`s) that silently biases every lane. The fix is to A/B a
**single binary** with a runtime toggle (env-gated, removed before merge) so
both arms run in one process; the offset cannot exist. Under that isolation
exp 254's apparent -5% text win collapsed to noise.

*Reapplies to any focused C-level A/B built from two worktrees. Put an
identical-code control lane in the harness; if it moves same-sign across the
order-flip, distrust the whole comparison and re-run both arms from one binary
behind a toggle before believing any lane.*

### One native envelope can lose by materializing the whole group

[Exp 257](257-native-autocommit-envelope.md) collapsed a homogeneous
`MultiExecuteRequest` from one Dart/native execute call per member to one
native interpreter call while retaining every independent SQLite autocommit.
That sounds like pure call amortization, but the new boundary first flattened
all parameters and allocated all results. The public insert gate missed its
reproduced bar, and the integer-only no-op control regressed in both orders
(claim 257.1): bulk materialization cost more than the calls it removed.
Variable-width groups also changed peak lifetime from one row to the whole
burst.

*Reapplies whenever an FFI, IPC, codec, or database loop is collapsed into one
envelope. Account for the aggregate input/output representation and peak live
bytes before crediting the removed calls. Compare against the actual scalar
encoder, which may already have narrow fast paths, and include a no-payload
lane: if that lane regresses, the envelope machinery itself has failed.*

### A cross-isolate transfer A/B must model the sacrifice path, or it over-credits the candidate

[Exp 258](258-columnar-result-store.md) measured a columnar typed-array result
store and found its transfer 73–91% cheaper than the boxed flat `List<Object?>`
on a `SendPort` A/B — a headline that evaporated on contact with production.
Reads large enough for transfer cost to matter (> `sacrificeSlotThreshold`,
32 K structural slots) never take `SendPort` at all: they zero-copy via
`Isolate.exit` (the sacrifice path), so the candidate's `memcpy` competes with
*free*, not with a boxed deep-copy. Where `SendPort` genuinely runs — results
under the threshold — the absolute saving was tens of microseconds, below the
`select()` round-trip floor. A naive A/B that sends every size over `SendPort`
credits the candidate on exactly the large results production already transfers
for nothing. The fix is to tag lanes by the slot threshold and compare the
`(exit)` lanes against a zero-copy baseline, not a `SendPort` one. Two smaller
traps rode along: Dart `Smi` integers live *inline* in a `List<Object?>` (tagged,
no heap box), so a typed `Int64List` column costs *more* memory, not less — the
"unbox saves memory" intuition only holds for doubles; and moving decode work
off the boxed list shifts it between isolates, so always separate worker-wall
build cost from the main-isolate `hop + consume` that resqlite's contract keys on.

*Reapplies to any result-transfer or IPC-shape experiment. Before crediting a
transfer win, ask which production path each result size actually takes — if the
large ones already zero-copy, the win only lives in the small-result regime,
where the round-trip floor usually swallows it. Model the sacrifice/`Isolate.exit`
threshold in the harness itself.*

### A fast-scan that abandons itself on the first miss penalises sparse-miss inputs across the whole tail

[Exp 235](235-json-escape-swar-resume.md) found that `json_write_string`'s SWAR
escape scan skipped 8 safe bytes at a time but `break`d to a byte-by-byte loop
on the *first* escapable byte and never resumed. A single newline near the start
of a 256-byte TEXT value therefore dragged almost the whole value through the
one-byte path. Re-entering the SWAR skip after each dirty chunk won −23% on
realistic multi-line text (−44% on the one-early-escape extreme) with the
escape-free common path byte-identical, at a bounded +6% on pathological
dense-escape text (one extra SWAR probe per all-dirty chunk).

The trap is that the abandon-on-first-miss structure is invisible on the two
obvious test shapes — all-safe (never misses) and all-dirty (misses
immediately) — and only bites the *sparse-miss* middle, which is the common
real distribution. Guard lanes with an escape at the very end (`lateEscape`)
also hide it, because the fast scan has already covered the whole value.

*Reapplies to any SWAR/SIMD/table fast-scan over variable-length input
(escape scans, delimiter/whitespace skips, validation walks). Check what happens
after the first miss: if the scan drops to a slow path for the entire remainder,
add a sparse-miss lane (one miss early, long clean tail) and resume the fast
path after the miss region. Keep the resume cheap — re-enter the original tight
inner loop and downgrade only the missing chunk, so the all-safe and all-dirty
cases stay at parity.*

### A large residual bucket is not an optimization target until it is decomposed

[Exp 251](251-step-vs-decode.md) started from a persuasive subtraction:
result handoff was only 6-12% of a large `select()`, leaving roughly 90% in
"SQLite stepping plus Dart object-graph build." But measuring those terms
directly showed no general dominant remainder. Depending on row shape, stepping
and native cell fill consumed 37-60% of worker wall while Dart value
materialization consumed 40-63%. The residual was large because it combined two
different costs, not because either one was automatically the next bottleneck.

*Reapplies whenever profiling names a large remainder after subtracting known
costs. A remainder is an accounting bucket, not a mechanism: split it on the
real path and representative shapes before designing against it. Otherwise a
large aggregate ceiling can over-credit a rewrite whose eligible sub-cost is
smaller, shape-dependent, or on the wrong thread/isolate.*

### Ask which side of a boundary already holds the inputs

Most of this program's rejected candidates tried to make an expensive step
cheaper, or to move it somewhere with better locality — and lost, because the
work still had to happen. [Exp 259](259-native-ascii-text-flag.md) won a
reproduced 10-24% on text-bearing `select()` by asking a different question: the
Dart decoder was *classifying* every TEXT cell as ASCII-or-not before it could
build the `String`, at the cost of an extra `ExternalTypedData` view plus a
bounds-checked scan (byte-by-byte under 16 bytes). `resqlite_step_row` had the
same pointer and length one frame earlier, with the bytes already in cache, where
the answer is a branch-free SWAR pass. Nothing got faster; a question moved to the
side that could already answer it for free.

The tell is a *classification* — a predicate, a length, a type discriminator, a
"does this need the slow path?" — computed by a consumer over data a producer just
touched. That is different from moving the work itself, which is what exps 081,
251 and 258 kept finding does not pay.

Two riders. The predicate's answer needs somewhere to go: exp 259 spent an unused
cell type code (SQLite's are 1-5, so 6 was free), which cost nothing; if it had
needed a wider struct or a second array, the accounting changes. And a producer-side
predicate is a new correctness surface — a wrong `true` here is silent mojibake,
not a crash — so it wants a direct byte-level differential test, not just the
end-to-end round trip.

*Reapplies wherever a decode, encode, or transfer consumer computes something
about bytes another layer just walked: escape scans, length/width probes, type
or affinity discrimination, "is this the common case" guards. Check whether the
producer can hand the answer over instead of the consumer re-deriving it.*

### A full scan can beat an early-exit scan when the miss path re-reads anyway

[Exp 235](235-json-escape-swar-resume.md) established that abandoning a fast scan
on the first miss penalises sparse-miss inputs. [Exp 259](259-native-ascii-text-flag.md)
is the complementary case and lands on the opposite structure: its ASCII classifier
ORs every 8-byte word into an accumulator and tests once at the end, so a non-ASCII
value is walked to completion even though the answer was settled at byte 3. That
looks wasteful and measured neutral — CJK guard -2.4% / -1.7%, and the shape
built to expose the trade (400 B whose one multibyte character sits at byte 0)
+1.1% / -1.0% — for two reasons:
it buys a single branch instead of one per word on the all-ASCII common path, and
the value that fails the test is immediately handed to `utf8.decode`, which
re-reads all of it regardless at roughly ten times the per-byte cost.

*Reapplies to any predicate scan. Early exit only pays when the miss path is
cheaper than the scan you saved. If the miss leads into a second, more expensive
pass over the same bytes, prefer the branch-free accumulate-and-test shape and put
a miss-heavy guard lane in the harness to prove it.*

### Amortised O(1) is not free when the elements are pointers

`decodeQuery` grew its result buffer with `values.length = values.length * 2`, the
textbook amortised-append, and [exp 059](059-row-count-hint.md) had already ruled
that "list growth is already cheap." [Exp 260](260-result-list-presize.md) measured
it: on a 200,000-slot result the doubling path costs 2318 µs against 865 µs
pre-sized, while the loads, the `switch` and the stores it exists to serve total
under 500 µs. Growing a `List<Object?>` is not a `memcpy` — it copies every live
element individually with a store barrier into a freshly allocated array the process
has never faulted in, and the doubling sequence moves about 1.6× the final result
through ~5 MB of immediate garbage. Exp 059's arithmetic ("only ~3-4 growths") counted
the wrong thing: the cost is slots copied, not growths taken.

The trap is that the amortised-O(1) framing is *correct* and still tells you nothing
about whether the constant matters. It hid a cost that turned out to be most of what
[exp 251](251-step-vs-decode.md) had already measured and labelled "Dart result
construction" — a bucket a later runner would have attacked as decode work.

*Reapplies to any geometrically-grown buffer on a hot path whose elements are
pointers or boxed values. Before accepting "amortised, therefore negligible", compute
the bytes moved, not the number of resizes, and check whether the copy is a barriered
element-wise walk or a raw block move. Typed-data buffers are usually fine; `List<T>`
of heap objects usually is not.*

### A worker that can be sacrificed cannot be trusted to remember anything

[Exp 260](260-result-list-presize.md)'s first implementation put its per-SQL size hint
in the per-worker schema cache, the obvious home — and won 30-35% on mid-sized reads
and ~1% on the largest ones, exactly backwards. Results over `sacrificeSlotThreshold`
return through `Isolate.exit`, which **ends the reader isolate**, so a hint learned
from a large result dies with the isolate that learned it and every large read is
decoded by a worker that has never seen the SQL. Sub-threshold, the same cache is
still only a quarter-view, because it describes the executions that happened to land
on one of four pool workers. Moving the memory to `ReaderPool` and stamping it on the
request took the 200k-slot lane from ~1% to −25%.

[Exp 258](258-columnar-result-store.md) already showed the sacrifice path silently
*over*-crediting a transfer candidate. This is the mirror: it silently steals a
worker-side optimisation's win, and it does so on precisely the results big enough to
care about. The pool's own schema cache has the same shape and is rebuilt from
`sqlite3_column_name` after every sacrifice.

*Reapplies to any caching, learning, adaptive, or amortising state a reader worker
accumulates. Ask what destroys the isolate and how correlated that is with the state
being valuable — if the two coincide, the state belongs on the main isolate or on the
request, not in the worker.*

### Put an adaptive hint where a wrong answer costs nothing

A size, capacity, or strategy hint learned from history will eventually be wrong, so
the design question is not "how accurate can we make it" but "where can it be wrong
for free". [Exp 260](260-result-list-presize.md) first applied its row-count hint to
`decodeQuery`'s initial allocation — the placement [exp 059](059-row-count-hint.md)
had used — and a `SELECT ... LIMIT ?` alternating between 8,000 and 50 rows made the
50-row execution **2.8× slower** (68 µs → 198 µs): zero-filling 60,000 slots it would
never touch cost far more than the doubling the hint removed. Moving the hint to the
*growth* step fixed it structurally rather than statistically. By the time a buffer
overflows, the result has already proven it is large; a small result never reaches the
code at all and runs byte-identical instructions to a build with no hint compiled in.

Note what this is *not*: a floor, a clamp, or a smoothing rule. Those make a bad hint
smaller. Relocating the decision to a point the bad case cannot reach makes it
impossible — and it gives the harness a control lane that is inert by construction
(the [exp 248](248-stmt-cache-stable-slots.md) pattern) for free.

*Reapplies whenever a heuristic predicts a size, a capacity, a strategy, or a fast
path. Write down what the prediction costs when it is wrong, then look for a place
later in the flow where the wrong case has already been excluded by something the code
has since learned. Prefer that placement over any amount of tuning on the prediction
itself.*

### Pick the memory number before you read it, because they disagree

[Exp 261](261-focused-memory-guard.md) added a memory lane to the focused
harnesses and immediately hit a fork: on a lane whose results cross
`sacrificeSlotThreshold`, a sampled `ProcessInfo.currentRss` peak reported
**+75%** for the same change that `ProcessInfo.maxRss` reported as **−1.7%**.
Both readings are correct. `maxRss` is the process high-water. A sampled
`currentRss` curve is a *retention* signal — how much is resident at the instants
you looked — and on this codebase retention is dominated by something unrelated
to the change under test: sacrificed reader isolates dying and handing their
pages back. Within one isolate the VM keeps pages after GC, so a candidate that
frees more of its own garbage reads as "no change"; a whole isolate exiting does
return memory, which is why a sacrificing lane's `currentRss` falls and a
non-sacrificing one's does not.

Had exp 261 gated on the intuitive number, it would have opened a regression
investigation into [exp 260](260-result-list-presize.md), which the high-water
shows *lowered* peak memory on every lane.

*Reapplies to any memory, cache-occupancy, handle-count or pool-depth guard.
Before comparing two arms, write down which of "peak", "resident now" and
"allocated total" you are reading and what else in the system moves it. Prefer
the high-water for a regression gate, and require one process per lane, since a
process-lifetime high-water is meaningless when several lanes share a process.*

### A guard's own flatness tells you what it can never catch

Exp 261 swept eight checkpoints from v0.3.0 to today and found peak read-path
memory flat within ~1 MB for three months, across roughly forty merged
experiments, while wall time on the same runs fell 25-40%. The reassuring reading
is "no regression accumulated". The useful reading is the second one: an
instrument that four months of real change could not move by 1% cannot resolve a
5% drift either. It is a tripwire for a doubling.

The dilution is worth measuring too. `mixed6-10k` sits at 89.5 MB before its
measured reads begin and the reads add ~18 MB, so gating that lane on peak RSS
mostly gates its seeding — which is identical in both arms.

*Reapplies whenever a guard comes back clean. A flat result is evidence about the
instrument as well as the code: check what the guard did during a period when the
system demonstrably changed, and state the smallest effect it could have caught.
A guard whose sensitivity is unknown is not yet a guard. If setup dominates the
measured quantity, say what fraction, or the number reads as more protective than
it is.*

### Run drift codegen in a fresh worktree before reading any failure as pre-existing

`benchmark/drift/*.g.dart` is gitignored and produced by `dart run build_runner
build --delete-conflicting-outputs`, which CI runs before analyze and test. A
worktree that has only had `dart pub get` is missing them, and the symptom is
alarming and misleading: `dart analyze` reports ~77 issues and nine
`benchmark_*_test.dart` files fail to load, all of it in peer drift scaffolding
that looks like it has drifted out of sync with the pinned `drift` version.
[Exp 264](264-initial-alloc-size-memory.md) read that as a pre-existing repo
breakage, checked it reproduced on `origin/main` — it did, for the same reason —
and wrote it up as a blocker before noticing the CI step that generates them. With
codegen run, `dart analyze --fatal-infos` is clean and all 450 tests pass.

*Reapplies to every new experiment worktree: run codegen immediately after
`dart pub get`. More generally, "it reproduces on `origin/main`" only rules out
your diff; it does not establish that the repo is broken, because a missing
build step reproduces everywhere. Before reporting infrastructure as broken,
check what CI does that you did not.*

### Check the host before trusting a focused benchmark

`run_release.dart` stamps `gitDirty` and the experiments chart drops a dirty or
single-sample run, but a focused AOT harness records nothing about the machine it
ran on. [Exp 264](264-initial-alloc-size-memory.md) collected an entire
experiment — four order-flipped passes, twelve lanes — on a host at **0.0% CPU
idle**, with an unrelated VM at 190% CPU, under 500 MB free on a 460 GB volume,
and six `run_release.dart` processes from earlier sessions wedged 1-4 days at 0.0%
CPU. Nothing surfaced it until a late confirmation pass read +50.6% on a lane the
candidate provably cannot reach.

What survived: the direction and mechanism, because the design was order-flipped,
the controls held to ±2%, the effect scaled with column count as predicted, and a
standalone probe with no isolates and no SQLite measured the same magnitudes. What
did not: the percentages.

*Reapplies before every focused run. `top -l 1 | grep "CPU usage"` and `df -h` cost
nothing. Treat a same-signed move in a mechanically-inert lane as a host problem
first and a code-layout offset second — the layout reading is the one exp 254
established, and it quietly assumes the host is idle. Also reap wedged
`run_release.dart` processes first: the #282 crash leaves the parent blocked
forever rather than exiting, they accumulate across sessions, and they sit at 0.0%
CPU so they never look like contention.*

### Fixing the eviction order is not fixing the capacity

Exp 264 gave the reader pool's 32-entry per-SQL memory a second consumer, so point
reads began competing for slots that had belonged exclusively to the large-result
statements exp 260's growth hint serves. A hot report query then lost its hint to
point-read churn, measured at +40-46% on a 5,000-row read.

The obvious fix — promote on use, so a hot entry is not aged out — measured **no
improvement at all**, and cost the main isolate a map remove-and-reinsert per read.
Raising the capacity did fix it, which located the mechanism: once more distinct hot
statements are in play than the map holds, no ordering keeps the one that matters.
What shipped was an eviction *preference* (drop an entry that has never returned a
large result before one that has), which restores the original tenure without
choosing a new magic number and costs nothing per read.

*Reapplies to any bounded cache that gains a second population of keys. Ask what
fraction of capacity the new population will occupy before reaching for a smarter
replacement policy — LRU, LFU and CLOCK all reorder the same too-small set. And
when a cache serves two consumers with different value densities, priority by value
beats recency.*

### A per-slot cost is not a per-call cost

[Exp 067](067-shrink-initial-allocation.md) rejected shrinking `decodeQuery`'s
fixed 256-row initial allocation and explained the rejection with a real VM
property: `List.filled(n, null)` is cheaper *per slot* when `n` is large.
[Exp 264](264-initial-alloc-size-memory.md) measured the same shape per call —
423 ns for 1,536 slots against 21.5 ns for 12 — so the large allocation is about
six times cheaper per slot and twenty times more expensive per query. The stated
mechanism was true; the decision it supported was not.

This is the second rejection in this direction closed by a locally-true
mechanism claim. [Exp 059](059-row-count-hint.md) counted *growths* rather than
slots copied and concluded list growth was already cheap; exp 260 found the same
defect there.

*Reapplies whenever a rejection's reasoning is a rate — per slot, per byte, per
row, per call. Multiply it back out by the count the caller actually pays before
treating it as a reason. And when a rejection tested an unconditional change,
what it establishes is that the change is wrong unconditionally; a later
experiment with per-case knowledge is not repeating it.*

### An inert lane is only a noise gauge once it can resolve the effect

A lane where the candidate is mechanically inert reads the harness floor, so a
same-signed move across the order flip means no lane is trustworthy (exp 254).
[Exp 264](264-initial-alloc-size-memory.md) found the precondition that rule
needs. Its `mixed6-200` control timed one 200-row read per sample at ~50 us,
where a single stopwatch tick is 2%, and reported +11.3% then +9.8% — a
reproduced, same-signed regression in a lane the candidate provably could not
reach. Batching 20 executions per sample took the same lane to -1.4% / +2.4%.

*Reapplies before trusting any control lane. Check that its resolution exceeds
the effect being hunted; below that threshold a floor gauge manufactures exactly
the signal it exists to detect. The same run also needed four alternating-order
passes rather than two, because a lane whose per-read cost was dominated by other
allocation agreed with itself twice and then reversed.*

### Re-run the guard after the fix, even when the fix is obviously right

[Exp 264](264-initial-alloc-size-memory.md)'s guard lane fired at +40%. The first
diagnosis was that the size memory was worker-local and a four-worker pool gives
each worker a biased sample — which is true, is a real defect, and was worth
fixing on its own. It moved the memory to the main isolate and the lane read
+40% again, in all four passes. The actual cause was the statistic, not its
location.

*Reapplies whenever a plausible defect is found while chasing a measured one. A
correct fix for a real problem is not evidence that it was the problem you
measured; the guard is. If the writeup had shipped after the reasoning instead of
after the re-run, it would have documented a mechanism the numbers never
supported — and shipped the +40%.*

### A hint that can under-predict needs a high-water mark, not a window

Exp 260 sized result-buffer *growth* from the smaller of a SQL's last two row
counts, because over-sizing is the expensive mistake there.
[Exp 264](264-initial-alloc-size-memory.md) sized the *initial* allocation and
inherited the window by symmetry, taking the larger of the last two — and
measured +40% in all four order-flipped passes on a statement returning 3,300
rows behind bursts of eight 20-row reads. A window of length k is defeated by any
burst longer than k: every observation before the large execution is small, so
the penalty recurs instead of amortising. A high-water mark is raised once and
never falls, which converts a periodic cost into a one-time one (measured at
+1.6%).

*Reapplies to any adaptive sizing, capacity or threshold whose two error
directions are not symmetric. Identify which direction is the expensive mistake,
then pick a statistic that cannot be talked out of guarding against it by a run
of cheap observations. Pair it with the exp 260 lesson above: put the hint where
a wrong answer costs nothing, and where it cannot, make the wrong answer
unrepeatable.*

### A benchmark built to resolve a rate cannot see a fixed cost

[Exp 266](266-sticky-reader-dispatch.md) found that the reader pool's
round-robin dispatch made all four reader isolates independently pay the
prepare, schema build and page warm for the same statement. Preferring the
worker that served the previous read is worth 33% of a statement's first four
executions — and 0% of its eight-thousandth. Every lane in the repo, release and
focused alike, executes one statement from tens to thousands of times per
sample, because that is what it takes to resolve a per-read effect at microsecond
scale. That repeat count is also the divisor a once-per-statement cost is
reported through, so a suite tuned to see rates is *structurally* blind to fixed
costs, and the blindness gets worse exactly as the measurement gets more precise.
The instrument is a lane that mints a fresh SQL string per sample — a trailing
comment leaves the plan identical — and times its first N executions, at two or
three values of N.

*Reapplies whenever a candidate's saving is paid once per statement, per
connection, per schema or per worker rather than once per row or per call: cache
capacity, prepare cost, connection setup, dispatch policy. Ask what the sample's
repeat count divides away before reading a neutral result, and make the decay
across two or three values of N part of the acceptance gate — a fixed cost must
shrink with N, and one that does not is a different mechanism.*

### A routing change can starve a reclaim path that runs on traffic

[Exp 266](266-sticky-reader-dispatch.md) made reader dispatch prefer the worker
that served the previous read. `benchmark/suites/sqlite_diagnostics.dart`'s
`JSON buffer reclaim` guard failed immediately: exp 183's `json_buf` shrink only
fires when a later, *smaller* read lands on the connection that grew it, so a
burst that inflated all four readers' buffers was reclaimed by the rotation
bringing the settle reads back round. Sticking meant three of the four were
never visited again and kept 6.2 MB against a 512 KB budget. The wall-time
harness could not see it — no lane got slower — and no test of the routing
change itself would have either.

*Reapplies to any change in which worker, connection, isolate or slot serves a
request: pooling, affinity, sharding, admission order, or a fast path that skips
a tier. Before measuring anything, enumerate the per-instance state that is only
reclaimed when that instance is used again, and run the retention guards first
rather than last. The general shape is that lazy cleanup is a hidden dependency
on the very traffic pattern a routing change exists to alter.*

### An O(capacity) maintenance cost makes the capacity look well-tuned

[Exp 267](267-stmt-cache-capacity.md) raised three 32-entry SQL-keyed caches to
128 and measured a reproduced **+42%** on the one lane where no cache size can
help. The cause was not the larger cache: `stmt_cache_insert` reclaimed a slot
by compacting the array, moving `(capacity − 1) × 1.6 KB` on *every* insert, so
quadrupling the capacity quadrupled a cost paid per prepare. Removing the
compaction — which preserved no ordering the lookup's promote-by-swap had not
already given up — turned that lane into a −12% win *against the 32-entry
baseline*, because the old capacity was paying the same tax at a quarter scale.
Two earlier experiments had probed this cache's lookup path and neither had
looked at what insertion cost.

*Reapplies to any bounded structure whose maintenance — eviction, compaction,
rehash, defragment, scan-on-insert — is O(capacity) rather than O(1): caches,
pools, free lists, ring buffers, interning tables. The tell is that growing it
makes things worse, which reads as "the current size is optimal" and is
actually "the size is bounded by a bug." Price one maintenance operation in
bytes moved before concluding a capacity is well-chosen, and re-run the sizing
question after the cost is O(1).*

### A follow-up nobody owns is never built, and it silently blocks a direction

[Exp 071](071-stmt-cache-mru-scan.md) and
[exp 073](073-schema-cache-fast-path.md) were each rejected because no
benchmark could reach the cache they changed, and each closed by asking for the
same workload — many rotating SQL shapes, cache at capacity — *before any
cache-sizing experiment*. Neither built it. Roughly 190 experiments later
[exp 267](267-stmt-cache-capacity.md) built it in an afternoon and found a
reproduced 2× cliff behind it. Two experiments in between
([207](207-stmt-cache-hot-sql-fastpath.md),
[248](248-stmt-cache-stable-slots.md)) worked on the same cache and went after
its lookup path instead, because that was the part the existing lanes could
see.

*Reapplies whenever a rejection's stated reason is "no workload can measure
this." That sentence names a prerequisite, and a prerequisite attached to a
closed experiment has no owner — later runners inherit the conclusion without
the condition and optimise whatever the current suite happens to illuminate.
When picking work, grep old rejections for the instrument they asked for, and
treat "we could not measure it" as a live candidate rather than a settled
verdict.*

### A "floor" that has never been measured is a decision, not a floor

"Below the round-trip floor" closed candidates in this repo for months — exp
258's sub-threshold columnar transfer, exp 264's remaining point-read cost, the
premise behind exps 209 and 239 both trying to *amortise* the hop across several
queries. [Exp 265](265-inline-main-isolate-select.md) priced it by removing it:
on a six-column point read the isolate round trip was 6.3 us of an 8.4 us read.
The floor was real and it was most of the operation — so every candidate
rejected against it had been compared to a denominator four times larger than
the work it was actually competing with. The candidate that produced the number
was itself rejected; the number outlived it.

*Reapplies whenever a rejection cites a fixed cost the experiment did not itself
measure. Two questions separate a floor from an unexamined assumption: how large
is it against the thing being optimised, and what makes it fixed? A cost that is
fixed only because nobody has tried to remove it is a candidate — and pricing it
is worth doing even when the thing that prices it does not ship.*

### A progress counter is not a preemption boundary

[Exp 265](265-inline-main-isolate-select.md) rejected caller-isolate reads
because row history could not bound their work. [Exp 269](269-enforced-inline-reads.md)
replaced prediction with row, payload-byte and SQLite VM-opcode caps plus a
per-turn stopwatch, then found the same safety hole one layer deeper. After two
tiny reads armed the route, `SELECT length(randomblob(?))` returned one INTEGER
but spent 26–28 ms inside one SQLite function opcode. It crossed no cap, and the
stopwatch was checked only before entering the synchronous call. Main let a
1 ms timer run while a worker did the database work; the candidate held the
calling isolate until the whole operation finished. Busy/VFS waits, callbacks,
cold preparation and native value scans have the same shape.

*Reapplies whenever a safety claim is expressed as a counter, timeout or
stopwatch around opaque synchronous work. Ask where control can actually be
regained. A budget checked only before the call is admission; a callback between
VM operations is cancellation; neither is preemption inside one operation. If
the property is wall time, run an adversarial single-operation stall before
optimising the happy path.*

### A guard set built from the lanes you have tests the hypothesis you believe

[Exp 265](265-inline-main-isolate-select.md) wrote nine lanes, declared kill
conditions, and met all of them — then was rejected on failure modes no lane
could see. Every lane was small integers and short TEXT, indexed lookups, a hot
page cache, because those were the shapes the surrounding experiments had built
harnesses for. Every kill condition tested whether the row-count hint was
*wrong*, which was the one failure mode the row cap already handled. The three
that mattered needed lanes that did not exist — a one-row 5 MB blob read, a
`count(*)` over a large table, a frame-shaped workload — and nobody builds those
while the happy path is reading −75%.

*Reapplies before declaring kill conditions, not after. Write them from the
mechanism's failure modes rather than from the available lanes, and if a failure
mode has no lane, that is the next thing to build — a guard set inherited from
the previous experiment measures the previous experiment's risk.*

### Measure a scheduling change under contention, or measure half of it

Exps 244, 245 and 246 measured cross-isolate transfer carefully — a prepared-
result barrier for the intrinsic cost, an 8-request/4-worker burst for pool
capacity — and every lane held the request population constant.
[Exp 265](265-inline-main-isolate-select.md) found the other half: a point read
issued while four large reads occupy the pool costs 533-1169 us against 37-52 us
for one that skips the queue, a 19x difference that is entirely admission and
nothing to do with transfer. The same run's guard lane inverted the expected
trade — eight concurrent point reads are 70% *faster* run serially on one
isolate than four-wide across the pool, because parallelism cannot recover a
per-request overhead larger than the request.

*Reapplies to any dispatch, queueing, batching or pool-sizing change. A lane
that has the resource to itself measures latency; a lane that contends for it
measures what a caller actually waits for. Run both, and expect them to disagree
about how large the effect is.*

### `calloc` does not keep a structure lazy if initialization writes it again

[Exp 268](268-stmt-cache-lazy-init.md) found that the 128-entry statement
cache was already inside one `calloc`-backed database allocation, but its
initializer immediately zeroed the complete array again. The compiler removed
that second write for the writer cache and retained a 273,408-byte `bzero` for
every reader, so a normal four-reader open eagerly made about 1 MiB resident
before any statement used a slot. Setting only `count = 0` recovered 1.06 MiB
of peak RSS. The proof was not that zeroes are unnecessary: lookup and cleanup
inspect only `[0, count)`, and insertion fully initializes one slot before
raising the count.

*Reapplies to large inline arrays and fixed-capacity pools inside a zero-filled
parent allocation. Inspect optimized assembly before assuming the compiler
eliminates a nested clear, then prove the live-range boundary and initialize an
element at publication time instead of faulting every page at construction.*

### A signal good enough to correct late is not good enough to answer with

[Exp 270](270-read-result-cache.md) built a `select()` result cache on
resqlite's existing write-invalidation signal — the same table dependencies and
dirty sets the stream engine has consumed since exp 106 — and it worked: −90% to
−96% on repeated reads, every adversarial guard neutral. It was rejected because
that signal reports *writes made through this `Database`*, and a second
connection to the same file commits without it hearing anything. Streams
tolerate that because a missed invalidation only delays a re-emit, and
`stream()` documents the limitation. A read cannot: it returns the wrong rows,
silently, with no error anywhere.

*Reapplies whenever an existing mechanism is reused for a stricter consumer.
Before adopting a signal, ask what its failure mode costs the current consumer
and what it would cost the new one. "Precise enough" and "complete enough" are
different questions, and a signal can be exactly precise within a scope that is
too small.*

### Put the cost of invalidation on the reader, not the writer

Exp 270's first invalidation design mirrored the stream engine: a
table→queries index, walked on every write, with column-level intersection to
elide. It measured +16–19% on a lane alternating one write and one read, because
a write pays that walk whether or not the cache ever helps. Replacing it with
per-table version counters — stamped onto a result when its read is dispatched,
compared when the result is looked up — took the same lane to neutral. The
reader that benefits now pays, and stale entries simply lose on their next
lookup.

*Reapplies to any cache, memo, or dependent-invalidation scheme. Judge it on the
path that gets no benefit first. Eager invalidation buys promptness nobody
needed and charges it to the writer; lazy validation charges the beneficiary.*

### A workload that never exercises the miss path cannot evaluate a cache

Exp 270's release sweep reported `Select → Maps` at 100 rows improving 0.040 →
0.005 ms, and the number was the benchmark measuring itself: every read scenario
in the suite executes one statement thousands of times with nothing writing, so
a cache keyed on statement identity hits every time after the first. This is
exp 267's observation — the whole repo's benchmarks use under ten distinct SQL
strings — arriving on a different axis. The honest numbers came from the two
workload simulations, which mix reads with writes to what they read: 17.7% hit
rate on Chat Sim against 84.3% on Feed Paging.

*Reapplies to any candidate keyed on statement or request identity. Before
believing a suite result, check whether the suite ever produces a miss. If the
eligible share is 100% by construction, the lane measures the ceiling and the
adoption question is still unanswered.*

### A profile-guided win includes the profile's lifecycle in its cost

[Exp 273](273-continuous-pgo-recheck.md) made continuous PGO work inside a Dart-loaded
macOS dylib and measured broad 9-19% native-path wins. It still did not produce
a product exploit: the source/compiler/target-matched profile needs permanent
retraining and provenance machinery, and homogeneous stream p50 crossed the
declared >=3% and >=0.02 ms boundary in three of five 300-trial pairs. The
pooled delta was only +1.53% with a confidence interval spanning zero, so this
is a replicated-gate failure amid phase variance, not proof of a stable
slowdown. The candidate was not just `-fprofile-use`; it was the training
corpus, generated artifact, compatibility contract, fallback policy, and every
narrow regression guard together.

*Reapplies to PGO, BOLT, generated tuning tables, and other build-time
optimization artifacts. Count generation, versioning, validation, and fallback
as implementation complexity, honor the declared replicated guard, and report
pooled uncertainty so a kill decision is not overstated as a stable effect.*

### Count the queue before you schedule it

[Exp 275](275-cost-aware-read-admission.md) gave `ReaderPool` a cost-aware
admission policy and measured it working: a point read issued into a saturated
pool went from 256-374 us to 52-65 us, and cheap reads queued behind large ones
finished 37-42% sooner from reordering alone. Then one counter over one release
suite pass ended it — 335,221 reader dispatches, 312 of which parked for a
worker at all, and **zero** cheap reads parked behind a costly one. The policy
was correct, reproduced in every pass, and scheduled a queue that does not form.
The counter cost ten minutes; the two arms, three AOT binaries and two
collections that preceded it cost the rest of the run.

*Reapplies to anything that changes an ORDER rather than a cost — priority,
fairness, cost classes, sharding, reservation, work stealing, batching by
queue depth. The eligible population is not "operations of this kind", it is
"operations that actually contend", and those are usually far rarer. One
counter on the contention path, run first, is cheaper than an A/B that can only
tell you the reordering works.*

### A lane that saturates a pool must time the first request alone

Exp 265's `point-under-load` lane issues four large reads to fill the pool, then
times ten point reads and reports their sum. Only the first of the ten waits:
sticky dispatch ([exp 266](266-sticky-reader-dispatch.md)) sends the whole
sequential run back to whichever worker freed first, so reads two through ten
measure an idle pool in every arm. That was right for exp 265, whose candidate
took all ten off the pool. It was wrong for [exp 275](275-cost-aware-read-admission.md),
which changed only who waits: on identical binaries the summed lane read -13%
and the first-read-only lane read -75%.

*Reapplies whenever a lane establishes a contended condition and then measures
repeatedly inside it. Check whether the condition survives the first
measurement. If the treatment consumes the contention it was measuring, every
later repeat is a control being averaged into the result.*

### Price the machinery before you build the candidate that removes it

[Exp 171](171-resolved-runtime-cache.md) proposed skipping an `await` on an
already-resolved future, estimated that hop at "~1–2 µs per call", derived
6–12% of headroom from the estimate, built the change and measured nothing.
[Exp 278](278-sync-read-prologue.md) went back for the larger version of the
same idea — three `async` frames off the read path, not one hop — and started
by measuring what a frame is worth. In a 90-line harness with no SQLite, no
isolates and no resqlite code, an `await` on a resolved future prices at ~71 ns
and an `async` function that only forwards a future at ~35 ns. Exp 171's
estimate was 14–28× too large; the headroom it computed never existed, and its
empty result was the correct one for a reason it could not see.

Divide the unit price by the wall time of the operation the machinery wraps and
the verdict falls out before any code is written: ~108 ns against resqlite's
~5.5 µs point read is 2.0%, against a 1,000-row read 0.05%, and the decision
gate is 5%. That arithmetic is the whole experiment.

*Reapplies to any candidate whose saving is "remove a layer" — async frames,
closures, a boxing, a virtual dispatch, a map lookup, a defensive copy. Write
the microbenchmark that prices one unit, divide by the operation it wraps, and
compare that to the gate first. It is the unit-price twin of exp 275's "count
the queue before you schedule it": that lesson says measure how often the
mechanism is reached, this one says measure what one occurrence is worth, and
either number can close a candidate for the cost of ten minutes.*

### A stand-in payload must match the real one's representation, not just its size

[Exp 279](279-native-thread-dispatch.md) built a synthetic lane to ask whether a
native thread could hand 256 KB to the main isolate more cheaply than a reader
isolate can. The lane sent a heap `Uint8List` of the right size, and the
candidate came back 6× ahead — 76.8 µs for the isolate send against 12.7 µs for
the native post. That number was an artifact. `selectBytes` does not send a heap
list; it sends a *view over native memory* (exp 174), and the VM's message copy
charges very differently for the two: the same 256 KB costs 9.0 µs as a view and
43.1 µs on the heap. Swapping the lane to a native-backed view turned a 6× win
into a 32% loss, and the end-to-end pair then agreed with the corrected lane to
within a percent.

The tell was available before the correction: the synthetic said the candidate
should win by ~60 µs on a 1,000-row read, and the end-to-end pair — run first as
a smoke test — read dead even. When a stand-in and the real path disagree by
that much, the stand-in is wrong, and the thing to check first is what the real
path actually puts on the wire.

*Reapplies whenever a harness substitutes a constructed payload for a real one:
bytes, strings, lists, maps. Size is the obvious dimension to match and usually
not the expensive one — backing (heap vs external), mutability, and whether
leaves are shared all move the cost by multiples. Build the stand-in by copying
what the shipped path constructs, and if a cheap end-to-end probe exists, run it
early enough to catch the synthetic lying.*

### A cost between two components usually belongs to one of them

[Exp 280](280-caller-side-param-arena.md) proposed moving `executeBatch`'s
parameter packing from the writer isolate to the caller, so the
`List<List<Object?>>` graph copy on the main->writer hop would disappear. The
graph copy is real — 1.29 ms for the release suite's 10k x 20 matrix, 5.6% of
that write, and 17.0% of a 10k x 8 integer one — and removing it made every
batch shape 4-24% faster in both run orders.

It was still the wrong candidate, and one lane in the pricing harness said so
before the A/B ran. Timing `SendPort.send` on its own, separately from the
round trip, showed the *sender* pays 91-99% of the copy; the receiving isolate
rebuilds the graph almost for free. So the hop was never a cost sitting between
the two isolates waiting to be collected. It was main-isolate work already, and
the candidate did not remove it — it swapped a serialize walk for a packing
walk, at 4-5x on any matrix holding text. Measured as event-loop blocking, the
main isolate went from 1.2 ms to 5.7 ms unavailable on the same shape the wall
column said improved 7.8%.

*Reapplies to any boundary — isolate, thread, process, network — where a
candidate proposes to move work across it. Before costing what the boundary
charges, find out which side is charged. A one-line lane that times the send
without the reply, or the request without the response, answers it, and it can
invert the verdict: work that looks like it lives in the gap often lives on the
side you were trying to protect. It pairs with exp 278's unit-price lesson —
that one asks what one occurrence is worth, this one asks whose budget it comes
out of.*

### Wall time is not the contract

Same experiment. The candidate improved the release suite's own Wide Batch
Insert and Batch Insert shapes, reproduced across an order flip, from separate
AOT bundles — everything the suite can see said accept. What said reject was a
metric no release lane reports: the longest gap a self-rescheduling event-queue
probe sees during the awaited call, which is how long the main isolate is
unavailable to anything else. resqlite's stated promise is that its work runs
"with zero main-isolate jank", and that promise has no column in the suite.

*Reapplies whenever a candidate moves work between isolates rather than
removing it. Wall time is conserved across such a move and jank is not, so a
wall-only gate cannot see the trade at all. The probe is about twenty lines
(`benchmark/experiments/batch_param_arena_ab.dart`); run it beside the wall
number. More generally: when a library's headline claim is about something the
benchmark suite does not measure, a candidate can pass every lane and still
break the thing people chose the library for.*

### A synthetic harness can be wrong by a microsecond, robustly

Exp 282. An echo-isolate transport ladder reported that a `SendPort` message
containing a record costs about a microsecond more than the same message built
from ordinary objects — reproducibly, with no scaling in field count, and
surviving five attempts to break it: pre-built against freshly-allocated
payloads, canonical against freshly-decoded strings, a canonical against a
run-time-built schema, nesting, and a worker made busy before it replied. Every
reader reply carried such a record, so the candidate predicted −17% to −27% of a
point read. End to end it measured −0.84% against a control at −0.42%, and the
lane that lost *two* records came out positive. A `Stopwatch` around the real
worker's own `send`, in both worktrees, said the two shapes cost the same.

The tell was in the ladder's own output and nobody looked: its most faithful
one-way reply lane priced at 3.92 µs, more than the entire 3.27 µs round trip it
was modelling. A model that charges more for half a thing than the whole thing
costs is not calibrated, however stable its lanes are.

*Reapplies to every harness that stands in for a real path — echo isolates,
mock transports, replayed traces. Two habits fall out. First, before believing
an absolute figure from one, check it against the whole operation it lives
inside; a part that exceeds the total is a calibration failure, not a finding.
Second, when a synthetic harness and an A/B disagree by more than the A/B's
control span, do not build a sixth harness variation — put twenty lines of
`Stopwatch` in the real path in both worktrees and print it from the worker on
shutdown. Four variations failed to resolve this; the in-situ counter took one
run. Remove it in the same session: it belongs in the receipt, not in `lib/`.*

### If the work you are timing overlaps the work you are waiting on, you are timing the wrong thing

Exp 283. A reactive fan-out A/B issued its write burst one awaited write at a
time — the shape the release suite itself uses — and read the candidate as
neutral, ±2%, on the lane its mechanism was worth 39% of a changed rerun on.
The reason is structural: each write's latency covers the reruns the previous
write scheduled, so the reruns never appear in the wall. The wall is the write
burst, and the write burst does not change.

The fix was to stop waiting on the writes and start waiting on the backlog.
Issue the whole burst concurrently, then issue one sentinel write that must
change one specific stream, and time until that stream emits. Everything the
burst scheduled has to clear the queue first, so the sentinel prices it. Same
code, same collection size: −12.5%, reproduced across an order flip.

*Reapplies whenever the cost you are chasing runs concurrently with something
you await anyway — background reruns, prefetches, invalidation sweeps, any
work a queue absorbs. Ask what the wall is actually bounded by before trusting
a neutral result; if it is bounded by the thing you await rather than the thing
you changed, no number of samples will help. The general move is to find an
observable event that can only happen after the invisible work has drained, and
time to that. It matters most when the invisible work produces no output of its
own — an unchanged stream rerun emits nothing and can never be waited on
directly, which is exactly why it needs a sentinel behind it.*

### Before removing a redundant pass, ask what it re-reads

Exp 283. A changed stream rerun walked its SQLite statement twice — hash to
completion, then decode from the top — and the second walk looked like pure
overhead: 35–45% of the rerun's work, removable by a decoder that had been
shipping for months and produced the identical digest. Eight order-flipped A/B
passes said 12–16% faster, guards neutral, correctness tests green.

The release suite then flagged the target lane at +91%. Unpicking it found the
thing the A/B could not: `resqlite_query_hash` resets the statement on exit, so
the decode pass that follows opens a *fresh* read transaction. The two passes
were reading two different database states, and the second one was quietly
handing the subscriber a newer snapshot than the digest it stored. Collapsing
them into one pass made hash and rows consistent — the better contract — and
cost 12% more emissions during a write burst, because the stream lost its free
refresh and needed another round to converge.

*Reapplies to any duplicated read on a path where state can change underneath
it: a re-query, a revalidation, a second scan after a first pass. Two passes
over a mutable source are not one pass done twice — they sample at two times,
and the later sample may be load-bearing even when nobody chose it. Before
deduplicating, ask what the second read sees that the first did not, and check
whether anything downstream depends on the difference. A digest-equality test
will not tell you: both arms here produced identical digests for identical
data, and the divergence was in *which* data each arm read.*

### A sentinel you are draining toward must be unreachable by the drain

Exp 283, discovered in review of its own PR after four order-flipped passes had
agreed on the wrong number.

The harness measured how long a fan-out backlog takes to clear by issuing a
write burst, then a sentinel write that must change one specific stream, and
timing until that stream emits — the unchanged majority emits nothing and can
never be waited on directly, so the sentinel stands in for the whole queue. But
the sentinel stream was an ordinary partition the burst also wrote to, and its
completer was armed before the burst started. Each sample therefore ended at
whichever of that stream's reruns fired first: a random prefix of the backlog,
and a prefix whose length depended on how fast each arm finished changed reruns
— exactly the quantity under test. Reserving a partition for the sentinel and
arming the completer after the burst moved the primary lane from −12.5%
(reproduced across an order flip) to −1.7% (drift-suspected), and moved the lane
that actually wins from −5.7% to −11.3%.

*Reapplies to every "wait for a marker to know the queue drained" metric. Two
checks before trusting one: can the workload itself trigger the marker, and is
the marker armed before the workload starts? If either is yes, samples end on a
race, and a race whose timing depends on the change under test will reproduce
across order flips exactly like a real effect. Order-flipping catches drift; it
does not catch a metric that is measuring the wrong interval in both arms.*

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
