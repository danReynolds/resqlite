# Cross-Isolate Data Transfer: Memory Model, Mechanisms, and the Two Routing Rules

This document explains how query results and write parameters move between
isolates in resqlite, why moving them is expensive, and the rules that decide
which transfer mechanism to use. It assumes no prior knowledge of Dart's memory
model — the necessary pieces are built up here.

Two rules run **orthogonally**, and keeping them apart is the single most
important thing to take away:

- **the blob-wrap rule (§5)** — decided per byte buffer, in **bytes**, because a
  `Uint8List` really is copied byte-for-byte;
- **the sacrifice rule (§6a)** — decided per result, in **mutable slots**,
  because strings and numbers are *shared* rather than copied, so byte size says
  nothing about what a result costs to send.

They once shared a 256 KB figure, which made them look like one rule. That was a
coincidence, and reading it as coupling is what produced a real routing bug
(§6a).

It is the reference companion to the experiments that established the model:
[exp 234](../../experiments/234-blob-param-transfer.md) (write params),
[exp 236](../../experiments/236-blob-cell-transfer.md) (read blob cells),
exp 238 (validating the blob-wrap rule; writeup not yet published),
[exp 243](../../experiments/243-blob-alias-table-protocol.md) (the write-param
aliasing fix in §5), and the four-experiment **send-vs-sacrifice arc** behind §6a:
[exp 241](../../experiments/241-sacrifice-reeval.md) (why the first A/B was
confounded), [exp 244](../../experiments/244-pool-burst-eager-respawn.md) (pool
replacement capacity), [exp 245](../../experiments/245-prepared-result-handoff.md)
(the intrinsic transfer mechanism), and
[exp 246](../../experiments/246-slot-sacrifice-guard.md) (the slot-count trigger
that §6a's rule now ships). [exp 242](../../experiments/242-selectbytes-ttd.md) is
the selectBytes-TTD rejection.

---

## 1. Why cross-isolate transfer exists at all

resqlite keeps SQLite work off the main (UI) isolate. Reads run on a pool of
worker isolates; writes run on a dedicated writer isolate. That means every
query result has to travel **from a worker isolate to main**, and every write
parameter has to travel **from main to the writer** — across an isolate
boundary.

The boundary is the whole problem, because of one rule of Dart's concurrency
model:

> **Isolates do not share *mutable* Dart objects — semantically.** That's the
> language-level data-race-free guarantee. But resqlite's workers are in one
> *isolate group* on a **common managed heap** (§2a): eligible immutable
> objects can be shared by reference, while mutable graphs must be copied,
> transferred, or bequeathed through a VM-supported mechanism.

So a value cannot simply be "handed over" by reference. To cross the boundary
it must either be **copied** into the receiver, or **moved** by a mechanism the
VM specifically supports. Everything below is about the cost of doing that, and
how to minimize it.

---

## 2. The Dart memory model, in five facts

You need five facts about the Dart VM to understand the rest.

**(a) Isolation is semantic; the heap is shared.** Isolates may not share
*mutable* Dart objects — that's the language guarantee. But since Dart 2.15,
isolates spawned with `Isolate.spawn` live in one **isolate group operating on a
common managed heap**, and collaborate on GC. So "isolated" is a semantic
contract, not separate physical heaps. (resqlite's workers are all same-group.)
Keeping *language-level isolation* and *VM-level heap organization* distinct
avoids a lot of wrong reasoning.

**(b) Same-group `send` SHARES immutable objects and COPIES mutable ones.**
This is the fact most people get wrong, and it drives the whole rows-path
policy. On a `SendPort.send` within a group, the VM's object-graph copy
(`object_graph_copy.cc`, `CanShareObject`) **pointer-aliases** immutable/canonical
objects — **strings and numbers are shared, not byte-copied** — while it
**deep-copies mutable graph nodes** (a growable `List`, a `Uint8List`/TypedData;
`CopyTypedData` does the memmove). Consequences that matter:
- A large `String` result does **not** have its characters copied by `send`.
- Send cost tracks the **mutable structural graph** (the flat values-list slot
  array, the wrapper/schema containers, and any mutable payloads), **not** the
  total decoded byte size.
- A `Uint8List` (BLOB) *is* mutable, so it *is* copied — which is exactly why
  blobs, and only blobs, get the TTD treatment.

**(c) The heap has two generations, and large objects skip the young one.**
New objects go into **new space** (young generation) — small, collected
frequently by a *scavenge*, which is a **copying** collector: it evacuates
(memcpy's) every still-live object out of new space, so a live new-space object
can be copied by the GC repeatedly. **Old space** (tenured) is collected by
mark-sweep, which reclaims in place. (The VM *does* have an incremental
old-space compactor that evacuates regular old-space pages — so "old space
never moves objects" is not a general invariant — but threshold-sized typed
data goes on *dedicated large pages*, separate from the regularly-compacted
pages, so it is not repeatedly moved.) Crucially, the VM's
`kNewAllocatableSize` is **256 KB**: any object larger than that is allocated
**straight into old space**. So a 256 KB+ blob/typed-data is *never* a
young-generation object and is *never* scavenge-evacuated.

**(d) External memory is not traced — but it is accounted for.** `malloc`'d
memory (a TTD's backing buffer) is never traced, evacuated, or marked, and the
collector only reaches it through a small *finalizer handle* that eventually
calls `free`. But it is **not "invisible":** the VM records its size against an
external-memory budget, and external-allocation pressure can itself trigger
collections. So external bytes carry allocation, external-pressure,
finalization, and eventual-free costs — just not *tracing/evacuation* cost.
(This is *why* a high count of medium TTD buffers can lose even at large
aggregate volume.)

**(e) A free transfer is not free residence.** Moving a payload for free
(`Isolate.exit`, TTD ownership move) does not make it free to *keep*. Where it
lands — GC-heap vs external — determines an ongoing cost separate from the
one-time move.

> **Honest note on the GC mechanism.** Earlier drafts explained the 256–512 KB
> blob-wrap win as "repeated young-generation scavenge evacuation." Fact (c)
> shows that's wrong at those sizes — the payload is old-space, never
> scavenge-evacuated. The wins (exp 234) are *real and measured* (fewer, shorter
> GC pauses), but their precise cause is some combination of managed-heap
> allocation pressure, the graph copier's slow-path chunked copy
> (`CopyTypedDataBaseWithSafepointChecks`, 100 KB safepoint-polled chunks),
> old-space/isolate-group GC scheduling, and pauses landing while the writer is
> stepping SQLite — **not** young-gen evacuation. We measured the effect, not
> the exact chain.

---

## 3. The three transfer mechanisms

resqlite has three ways to get a value across an isolate boundary. They are
**complementary tools, not competitors** — each reaches different data and has
a different cost shape.

### 3a. Graph copy — `SendPort.send`

The default. The VM's object-graph copy
(`runtime/vm/object_graph_copy.cc`) walks the message and **copies it into a
fresh *mutable* graph owned by the receiver within the shared managed heap**, in one pass, on the *sending*
isolate's thread. That same traversal **verifies sendability inline** — as it
visits each object it checks the object is legal to send (not a `ReceivePort`,
a native `Pointer`, etc.) via `CanCopyObject`. So there is no separate
"verify it's sendable" pass and no receive-side rebuild: one traversal that
copies *and* validates together, on the sender.

- **Cost:** traversal of the message, plus allocation and copying of its
  **mutable** graph nodes and mutable payloads — the immutable leaves (strings,
  numbers) are *shared*, not copied (§2b). So cost depends on mutable structure,
  pointer slots, mutable typed-data bytes, aliasing, and allocation paths —
  **not** the logical decoded result size. The copied mutable graph is owned by
  the receiver within the shared managed heap.
- **Best for:** small results, where the copy is cheap and there's no reason to
  involve heavier machinery.
- **Reaches:** anything (any sendable object graph — it shares immutable leaves
  and copies mutable structure/payloads).

### 3b. Sacrifice — `Isolate.exit`

For large results, the worker calls `Isolate.exit(port, result)`. This transfers
the payload's **memory** to main **without copying the bytes** — the receiver
adopts it in constant time — then the worker *dies* and the reader pool respawns
a replacement in the background.

**Zero-*copy* is not zero-*cost*.** Before ownership passes, the VM still
**walks the reachable object graph to verify every object is sendable** (the
same `CanShareObject` / `CanCopyObject` check as the copy path in §3a, but
without copying the byte payloads). That validation walk's cost scales with the
**number of reachable objects** — each visited once — and is **independent of
their byte sizes**: a `Uint8List` is a single node whether it holds 1 KB or
1 MB. So sacrifice is *not* a flat, size-independent handoff; it is flat in
*bytes* but linear in *object count*.

- **Cost:** a worker respawn (`Isolate.spawn` + a fresh SQLite connection +
  port setup, ~2-5 ms amortized across the pool) + **cold caches** on the
  replacement (empty statement and schema caches until it re-warms) + the
  **sendability validation walk** above. The respawn and cache costs are
  roughly fixed per result; the **validation scales with object count**. That
  is why sacrifice is cheap for a *blob* result (a handful of large `Uint8List`
  nodes) but expensive for a *row-heavy* one: a 20,000-row map result reaches
  hundreds of thousands of objects, and [exp 008](../../experiments/008-flat-list-lazy-resultset.md)
  measured `Isolate.exit` validation at **~38 % of the whole query**. resqlite's
  flat-list `ResultSet` exists precisely to keep that object count minimal (the
  values list + schema + the value objects, rather than a map per row).
- **Best for:** large **structural** results — many slots (rows × columns).
  It is the only mechanism that moves the *structure* without copying it. Note
  it is **not** uniquely good for strings: `send` already shares string bytes
  rather than copying them (§2b), so a string-heavy result gains nothing from
  sacrificing and merely pays the respawn (§6a).
- **Reaches:** the entire result graph, of any shape.
- **Catch:** the transferred objects are adopted onto **main's GC heap**, so a
  large payload still pays §2c's recurring GC cost on the receiver.

### 3c. Move — `TransferableTypedData` (TTD)

TTD moves a **single contiguous byte buffer** by ownership transfer.
`TransferableTypedData.fromList([bytes])` copies the source **once** into a
`malloc`'d **external** buffer (it does *not* neuter the source); sending it is
a constant-time pointer handoff; and `materialize()` on the receiver wraps that
same external buffer as a `Uint8List` **view** (no copy, ~1 µs regardless of
size).

- **Cost:** the same one copy as the alternatives, **plus a fixed per-buffer
  machinery fee** — one `malloc`, one finalizer handle, one wrapper object, one
  `materialize` on receive. This fee is *per buffer*, independent of the
  buffer's size.
- **Benefit:** the payload lives in **external memory**, so it escapes §2c
  entirely — the GC never evacuates or manages the bytes on either isolate.
- **Reaches:** only typed data. In resqlite that means a **BLOB** value
  (`Uint8List`) on reads, or a `Uint8List` parameter on writes. **It cannot
  move strings, numbers, or the row structure** — those are not byte buffers.

What is a BLOB? It is one of SQLite's five storage classes (`NULL`, `INTEGER`,
`REAL`, `TEXT`, `BLOB`) — raw bytes stored verbatim. It decodes to a Dart
`Uint8List`, which is exactly (and only) what TTD can move. `TEXT` decodes to a
`String` (a heap object, not a byte buffer); numbers decode to boxed
`int`/`double`. That is the whole reason TTD is blob-specific.

---

## 4. The central insight: transfer cost ≠ residence cost

The naive framing is "sacrifice is zero-copy, so it wins." That framing is
incomplete, and untangling it is the key to the whole design.

Consider one large BLOB crossing from a worker to main. **Both** the sacrifice
path and the TTD path:

1. copy the blob's bytes exactly **once** out of SQLite's memory (SQLite reuses
   that memory after the next step, so this copy is mandatory), and
2. transfer it across the isolate boundary **without a second copy**.

So on those two axes they are *identical*. What differs is **where the bytes
land and therefore what happens to them afterward**:

- **Sacrifice (plain heap `Uint8List`):** the blob lands on **main's managed
  GC heap** (old space at these sizes — §2c), where it adds allocation and
  collection-scheduling pressure the collector must service. Under a loop of
  large reads that is a real, recurring GC cost on main (exp 234 measured
  fewer/shorter pauses when it's removed — though the exact chain is not
  pinned; see §2's honest note).
- **TTD (external buffer):** the blob lives in `malloc`'d memory the GC never
  traces. Main holds a small view object with a finalizer; the GC manages the
  *handle*, not the bytes; the bytes are `free`d in one shot when the view dies.

> **A free transfer is not free residence.** Moving the bytes for free does not
> make them free to *keep*. Hosting a large payload on the GC heap carries a
> recurring, size-proportional tax that hosting it in external memory does not.

This is why wrapping a large blob wins **even when the result sacrifices
anyway** (exp 238, "Q1"): the wrapped
blob rides the `Isolate.exit` transfer as an embedded TTD, but because it lives
in external memory it never joins main's GC-managed churn. Measured ~30-55%
faster than the same result with the blob on the heap, on an operation that
sacrifices in both cases. It is the same effect [exp 234](../../experiments/234-blob-param-transfer.md)
proved by direct GC attribution on the write side (29 collections / 8.6 ms of
pause versus 20 / 1.2 ms over 300 large writes).

### What the TTD path costs on receive

TTD does add one thing the heap path lacks: a `materialize()` call per buffer
on main. It is **~0.6-1 µs and flat in payload size** — measured 0.63 µs at
256 KB and 0.97 µs at 16 MB, a 64x size increase for 1.5x the cost, which is
what confirms it wraps rather than copies. After that, *interacting* with the
data is **equal effort** — an external-backed `Uint8List` and a heap-backed one
have identical element-access cost.

Main's total unwrap cost therefore scales with the **number of wrapped cells**,
not their bytes: ~0.5 µs each, so 93 µs for 200 cells. That count is bounded by
the size gate — every wrapped cell is ≥ 256 KB, so 200 of them is already a
50 MB result. Reaching even 1 ms of unwrapping would take ~2,000 cells (~500 MB
in one result), which exhausts memory long before it costs a frame. This is the
*cheap* side of the trade: the heap alternative copies those same bytes onto
main, and that cost **is** size-proportional.

(The receive boundary also has to *find* the wrapped cells. That scan is
O(slots) and unbounded, so it is skipped entirely via a flag the decoder sets —
see `materializeTransferableBlobCells`.)

---

## 5. The decision rule

This is **not** one universal rule — it is **two** rules, because reads and
writes differ in whether object identity matters.

> **Read-cell rule (local).** A freshly decoded BLOB cell ≥
> `blobCellTransferThreshold` (currently 256 KB) is externalized through
> TTD. The decision is local to that cell — every result cell is independently
> materialized, so there is no aliasing to preserve.

> **Write-envelope rule (identity-aware).** Externalization of write parameters
> is decided over the **unique backing stores in the whole message envelope**,
> *not* per parameter occurrence, and aliases are preserved: a buffer referenced
> N times shares **one** wrapper, referenced at all N positions. Implemented by
> the **table protocol** ([exp 243](../../experiments/243-blob-alias-table-protocol.md)).

> **Everything that is not a big byte buffer** keeps its existing transport:
> small results graph-copy; large *structural* results sacrifice (§6a).

**Why writes need the identity-aware rule.** The graph copier preserves object
identity: a buffer referenced N times is copied *once* and aliased N times. The
original `wrapBlobParams` (exp 234) instead called `TransferableTypedData.fromList`
for *each occurrence*, duplicating a shared buffer into N external copies — a
regression even on a **single** request:

```dart
await db.execute('INSERT INTO t(a, b) VALUES (?, ?)', [blob, blob]); // was 2 wraps
```

and the coalescing pump multiplied it across a `MultiExecuteRequest`. Exp 243 fixed
it with the **table protocol**: wrap by identity through a per-envelope
`HashMap(equals: identical)` so each unique buffer gets exactly one
`TransferableTypedData`, referenced at every occurrence; the graph copier then
sends that wrapper once (identity preserved) and the writer materializes it once
(a shared unwrap cache spans the coalesced group's writes, since a second
`materialize()` throws). An isolated transport measurement ranked it strictly best
of three shapes at every reference count — flat and fastest, versus the old
per-occurrence wrapping (linear blow-up, ~27× at N=32) and a "leave aliased on the
graph copy" census (flat but slow, the heap slow-path copy). So the read-cell rule
and the write-envelope rule are now *both* implemented, and the write rule adds
identity-awareness the read path does not need (read cells are distinct objects
with no aliasing to collapse).

This is checked as a single integer comparison **inside the encode/decode loop
that already visits every value** — no additional *sender-side* decision pass.
(The main-isolate *receive* boundary does scan the flat values list to find and
materialize wrapped cells; that's a fixed, cheap post-receipt pass.)

The two thresholds it composes:

- **Type gate — byte buffer only.** TTD can't move strings/numbers/structure,
  so they are never candidates.
- **Size gate — ≥ 256 KB.** Below this, the per-buffer machinery fee (§3c)
  exceeds the GC saving (a small blob barely churns the collector), so wrapping
  *loses*. Measured: wrapping was +23 % *slower* at 64 KB and only turned
  positive at 256 KB. This is a **byte** gate, and correctly so — a `Uint8List`
  really is copied byte-for-byte. It is *independent* of the sacrifice decision,
  which counts slots (§6a); the two used to share a 256 KB figure, but that
  coupling was coincidental and is now gone.

### Why the rule is *local* (and why that's the real justification)

The wrap decision for a given blob depends **only on that blob's size** — not
on the other cells, not on the total result size, and not on whether the result
will sacrifice. Two independence results, both measured in
exp 238:

- **Independent of sacrifice** (Q1): a big blob wins whether or not the result
  sacrifices, because the GC-relief applies either way; sacrifice-avoidance is
  a *bonus* when the result is blob-dominated.
- **Independent of count** (Q2): ten 512 KB blobs still win ~12-40 %, because
  each wrap is an individually-positive, independent decision — N of them is N
  wins.

Because each decoded SQLite BLOB cell is **independently materialized**, its
wrap decision is genuinely local — for *read cells* there is no relevant
context, and every "smarter" variant we tried *lost*:

- **Cumulative / tipping** (wrap sub-threshold blobs when they collectively push
  a result toward sacrifice — a motivation that no longer exists at all, since
  slot routing means blob bytes cannot trigger a sacrifice): made a
  20 × 150 KB gallery result **2× slower**.
  Wrapping 20 medium blobs pays the per-buffer machinery 20 times, which exceeds
  the single sacrifice it was trying to avoid. And computing this decision needs
  the whole-result totals, which are only known *after* decode — by which point
  the native memory is gone and acting on it would force a second copy.
- **Lowering the threshold:** wraps small blobs whose GC saving can't cover the
  machinery — measured slower.

The failure mode in all of them is the same: they add **result-level
coordination** to a decision that is inherently **per-value**, paying scanning
and machinery cost to weigh information that does not change the per-blob
answer. The many-medium case is not a counterexample to "wrap large blobs" — it
is a pile of *sub-threshold* blobs that the size gate correctly declines to
wrap.

---

## 6. Worked cases

| Result shape | What happens | Why |
|---|---|---|
| 1 × 512 KB blob | wrap, no sacrifice | big enough to wrap (allocation domain); 1 slot, so it was never a sacrifice candidate (~5× faster) |
| 10 × 512 KB blobs | wrap all 10, no sacrifice | each blob individually clears the gate; 10 independent wins (~12-40 %) |
| 400 KB text + 512 KB blob | wrap the blob, **no** sacrifice | 2 slots — far under the slot threshold, and the text is *shared* by `send` rather than copied, so nothing forces a sacrifice. The blob is wrapped purely for the allocation domain |
| 20 × 150 KB blobs | **no wrap**, no sacrifice | every cell is sub-threshold, and 20 slots is nowhere near the slot threshold |
| 20k rows × 2 cols, one row holding a 300 KB blob | wrap that cell **and** sacrifice | the two rules are orthogonal: the cell clears the byte gate, while 40k slots independently clears the slot threshold — so a wrapped buffer rides `Isolate.exit` rather than a graph copy (covered by a round-trip test) |
| large **numeric/structural** result (≥ ~32k slots) | **sacrifice** (no wrap) | no byte buffer for TTD; the flat slot array is large enough that `Isolate.exit`'s zero-copy beats `send`'s per-slot copy (§6a) |
| large **string** result (few rows, big `TEXT`) | **send** (no wrap, no sacrifice) | strings are *shared* on send (§2b) — few slots, so `send` copies almost nothing; sacrificing it would respawn a reader for no copy avoided (§6a, exp 246) |
| small result of any shape | graph copy | cheap; no reason to involve heavier machinery |

---

## 6a. When the rows path sends vs sacrifices (exp 241/244/245/246)

The rows path chooses `SendPort.send` (worker lives) vs sacrifice
(`Isolate.exit`, worker dies + respawns). Getting this right took **four**
experiments, because the first attempt (exp 241) was confounded: it alternated
send and sacrifice inside one long-lived pool, but sacrifice is a *state-changing
treatment* (it destroys a worker, respawns, clears caches), so each measurement
altered the next, and the respawn accumulation biased the result. Peer review
identified that send-vs-exit is three **distinct estimands** — intrinsic
transfer, pool replacement capacity, and decode — that no single through-the-pool
harness can isolate. Splitting them settled it.

**Intrinsic transfer (exp 245 — a prepared-result barrier, one fresh process per
observation, construction/spawn/decode all outside the timed interval).** Three
mechanistic facts, each isolated by an empty-envelope control:
- **`Isolate.exit` carries a ~47 µs fixed-overhead premium** over `send` — its
  sendability walk plus isolate teardown. For any small result, `send` wins on
  this alone.
- **`send`'s cost tracks the mutable flat-list slot count, not payload bytes.**
  This is §2b, now measured: a 400 KB *string* adds ~0 µs to `send` (it is shared,
  not copied), while numeric payload cost rises 27 → 163 → 636 µs across
  20k → 48k → 200k slots (the pointer-array copy).
- **`Isolate.exit` is zero-copy, but its verify walk also scales with slots** —
  just *more slowly* than `send`'s copy (exit payload 42 → 244 µs over the same
  20k → 200k). So it is **copy-per-slot vs verify-per-slot**, verify being the
  cheaper per-slot op. Exit overtakes send once that per-slot saving beats its
  fixed premium: the **intrinsic crossover is ~48k slots**, widening to −345 µs at
  200k.

**Pool replacement capacity (exp 244 — an 8-request / 4-worker barrier burst,
pool reset between bursts, measuring decode-free dispatch queue-wait).** At the
production pool size there is **no capacity hole** — if anything sacrifice is
*favorable*: the no-sacrifice lane had the *highest* parked queue-wait (~+19%),
because `send`'s copy runs on the worker before it can take the next request,
blocking the slot longer than `Isolate.exit` plus an overlapped respawn. A
tempting **eager-respawn** fix (start the replacement before completing the
caller — the reply handler does it after a `Completer.sync()` runs the whole
completion chain) was **rejected**: dead-even with current, because at pool-4 the
respawn overlaps other workers' queries and is off the critical path. So
**sacrifice is not retirable** — it is correct for large structural results, and
its respawn cost is amortized by the pool.

**The trigger the rule now ships (exp 246).** The historical trigger sacrificed on
estimated **bytes** (≥ 256 KB). That is the wrong axis: because strings/blobs are
*shared* on `send`, a result large in bytes but small in slots — a few rows with a
big `TEXT`/`BLOB` column — is cheap to send yet was **misrouted into a sacrifice**,
paying a reader respawn on *every such read* for a copy that never happens.
Exp 246 routes on **mutable slot count** (`values.length`) instead. Two calibration
points:
- The threshold is **32 × 1024 slots**, the exact all-integer equivalent of the
  256 KB byte threshold (8 bytes/cell), so **numeric/structural routing is
  byte-for-byte unchanged**.
- It is set *end-to-end below* the ~48k intrinsic crossover on purpose: exp 244
  showed the send copy is on the worker's critical path, so at the real pool
  sacrifice becomes favorable earlier. A first pass at 48k regressed a 40k-slot
  result by +12%; 32k restores parity while keeping the string fix.

Measured: the misroute shape (4 rows × 100 KB string) stopped sacrificing
(1.00 → 0.00 sacrifices per select) and ran **31% faster**, eliminating the reader
churn it previously caused on every call; every numeric/structural shape stayed at
parity. Slot count is also *free* — it is the flat list's length, needing none of
the decoder's per-cell byte accounting. (The byte machinery — the old
byte threshold, `RawQueryResult.estimatedBytes`,
and the decoder's per-cell `byteEstimate` — was **deleted** in the same change:
routing on slot count left it with no readers. Exp 236's `transferableBytes`
subtraction went with it, since blob size can no longer influence the decision.)

**selectBytes is a separate, already-optimal path.** It sends a `Uint8List`
view over the reader's native `json_buf` and **never sacrifices**. The precise
reason a TTD wrap doesn't help (exp 242, neutral-to-slower at every JSON size):
the *baseline is already an external native view*, and when the object-graph
copy encounters external typed data it allocates a **new external buffer**
(`malloc` + `memmove`) and copies into it. So both baseline and TTD candidate
make **one copy** and both end **externally backed** — TTD only adds wrapper +
materialize machinery, while removing no sacrifice and changing no allocation
domain.

This reconciles a subtlety with §4's Q1 result (a heap-backed BLOB cell can win
via TTD *even when the outer result still sacrifices*, by changing the BLOB's
allocation domain). The unified statement: **for heap-backed BLOB cells, TTD
helps by moving the BLOB out of the managed heap; for selectBytes the bytes are
already external, so TTD changes no allocation domain and only adds machinery.**
Under slot routing this is cleaner than it was when first written — TTD never
"avoids a sacrifice" any more, because blob bytes no longer feed that decision.
Its only benefit is the allocation domain, which is exactly why Q1 (a win even
when the result sacrifices anyway) was the right result all along.

---

## 7. Boundaries and honest edges

- **The size threshold is a measured floor on one machine** (Apple M1 Pro /
  macOS). The crossover between machinery fee and GC saving is machine- and
  heap-configuration-dependent; re-measure if shipping broadly.
- **Very large blobs (≥ ~1 MB)** allocate straight into old space, which is not
  scavenge-evacuated, so the GC-relief component shrinks toward neutral. On the
  *read* path the wrap still keeps the payload off main's managed heap for its
  whole life. On the *write* path the end-to-end win washes out to
  neutral at multi-MB (never negative). Hence the threshold is a **floor with no
  upper cutoff**: wrapping an oversized blob is at worst harmless.
- **Extreme counts are reasoned, not measured.** Independence of count is
  verified to ~10 large blobs; hundreds *should* remain positive (independent
  decisions) but haven't been benched.

---

## 8. What TTD deliberately does not solve: the heterogeneous frontier

A large **string/numeric** result (e.g. an analytics table) gets no help from
TTD, because there is no contiguous byte buffer to move — it is a graph of
`String`/`int`/`double` objects. Its transport is decided by the §6a slot-count
rule instead: a large **numeric/structural** result (many slots) **sacrifices**,
which is the correct tool for it; a large **string** result (few slots, big
shared `TEXT`) is **sent**, since `send` copies almost nothing.

There is an existing escape hatch: **`selectBytes()`** encodes the *entire*
result into one JSON byte buffer **in C** and returns a native-backed
`Uint8List` view. Because that is a single byte buffer, it crosses efficiently
with no sacrifice *and* skips building thousands of Dart objects on the worker —
at the cost of returning raw bytes instead of Map-ergonomic `Row`s.

Unifying the two — `select()`'s ergonomics with `selectBytes()`'s transfer
efficiency — is a specialized, workload-specific research direction (not the
obvious generic successor to `select()`; the message-graph benchmark already
found the current ResultSet beats a binary row facade end-to-end once field
access is counted) — "byte-backed
rows"): encode the whole result to one compact binary buffer in C, TTD that
single buffer across (worker lives, no sacrifice), and lazily decode fields on
access. The blocker is the tradeoff it forces — it shifts decode cost from the
worker to the point of access, and the encode must stay in C to win
(a Dart-level codec loses to the VM's native copy; see
[exp 005](../../experiments/005-dart-binary-codec-transferable-typed-data.md)).
A broad language request for shared-memory multithreading
(dart-lang/language #333) is a long-term *watch item* — no milestone or
implementation — that could eventually reduce isolate-hop copying; it is not a
promised architecture. The more directly relevant near-term watch item is the
open request for lightweight typed-data communication between long-lived
isolates.

---

## Related

- [Architecture overview](architecture.md) — the system-level map this doc
  drills into.
- [Understanding Dart Isolate Transfer Costs](../stories/2026-04-06-zero-copy.md)
  — the original narrative on `Isolate.exit` graph-validation cost.
- Experiments: [234](../../experiments/234-blob-param-transfer.md) (write
  params), [236](../../experiments/236-blob-cell-transfer.md) (read blob cells),
  exp 238 (blob-wrap rule validation; writeup not yet published),
  [243](../../experiments/243-blob-alias-table-protocol.md) (write-param aliasing,
  §5); and the send-vs-sacrifice arc behind §6a:
  [241](../../experiments/241-sacrifice-reeval.md) (confound),
  [244](../../experiments/244-pool-burst-eager-respawn.md) (pool capacity),
  [245](../../experiments/245-prepared-result-handoff.md) (intrinsic transfer),
  [246](../../experiments/246-slot-sacrifice-guard.md) (slot-count trigger).
