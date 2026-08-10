---
component: boundary
title: Cross-isolate transfer
kicker: isolate boundary
zone: boundary
diagram: boundary
directions: [result-transfer-shape]
feeds: [readers, writer]
section: architecture
---

Dart isolates share no mutable state. That is the language's data-race-free guarantee, and it is also resqlite's central design constraint: every query result must travel from a worker isolate to main, and every write parameter from main to the writer. Nothing crosses for free — but the costs differ by orders of magnitude depending on *what* is crossing, and the entire read and write path is shaped around knowing which is which.

The rule that governs everything below: **bytes for mutable payloads, slots for structure.**

## What actually costs what

Since Dart 2.15, isolates spawned together live in one isolate group sharing a managed heap. A `SendPort.send` inside that group is not a serialize-and-rebuild round trip; it is a single object-graph traversal on the sending isolate that copies some things and shares others.

Immutable values — strings, numbers, canonical objects — are shared by pointer. They are never copied, at any size. A 400 KB string adds roughly nothing to a send [[245.1]]. Mutable objects are deep-copied: the flat values array underneath a result is copied slot by slot, and a `Uint8List` is copied byte for byte.

So a result's transfer cost tracks the size of its *mutable structure*, not the size of its data. Two results of identical byte weight can differ tenfold in transfer cost depending on whether those bytes live in shared strings or in copied slots. This is the single most counterintuitive fact about the boundary, and getting it wrong produced a real routing bug that shipped for months.

## Four routes across

**Share.** Strings and numbers ride along free in either direction. Nothing to decide.

**Copy the structure.** The default. `send()` walks the result graph, copies the mutable flat values list and its wrapper, and shares every immutable leaf inside it. Cost scales with slot count — rows times columns.

**Move the bytes.** A `Uint8List` of 256 KB or more is wrapped in a `TransferableTypedData` before it crosses. This does not remove the one mandatory copy — the bytes have to leave SQLite's memory regardless — it changes *where that copy lands*: into malloc'd external memory the garbage collector never traces, rather than onto the shared heap. The send then becomes a constant-time ownership move and the receiver materializes a zero-copy view [[234.1]] [[236.1]]. Wrapping is identity-keyed, so a caller passing the same buffer into five parameter positions ships one buffer, not five [[243.1]].

**Hand over the heap.** For results whose *structure* is enormous, the worker calls `Isolate.exit` and dies: the entire result graph transfers without a copy, and the pool respawns a replacement in the background. This is not free either — the VM still walks the graph to validate sendability, which costs a fixed ~47 µs premium plus a per-slot walk. But that walk is cheaper per slot than a copy, so past roughly 48k slots the exit wins on intrinsic transfer alone [[245.2]].

## Why the trigger counts slots, not bytes

For most of resqlite's life the sacrifice decision keyed on estimated bytes: results over 256 KB handed off the heap, discounting any cells already wrapped for transfer [[was:236.2]]. For all-integer results that heuristic is accurate — eight bytes per cell means bytes and slots are proportional — and it went unchallenged because the common case looked right.

It was wrong for exactly the case where it mattered most. A result of four rows holding a 100 KB text column is 400 KB by weight and four slots by structure. Those strings were going to be *shared* on send, costing nothing. The byte trigger read the result as expensive, killed the reader isolate, and paid a respawn to avoid a copy that was never going to happen — on every such read.

Re-routing the trigger onto mutable slot count fixed the misroute and deleted the byte accounting entirely: that shape stopped sacrificing and got 31% faster, while every numeric and structural shape kept byte-for-byte identical routing [[246.1]]. The threshold sits at 32k slots ([[code:sacrificeSlotThreshold=32768]]) — deliberately below the ~48k intrinsic crossover [[245.2]], because at the real pool the send's copy also blocks the worker from accepting its next request, which pulls the practical crossover earlier [[244.1]].

## Why sacrifice survives at all

Killing a worker to return a result looks profligate, and it was repeatedly suspected of starving the pool. Measured at production pool size with a barrier burst, the opposite holds: the lane with sacrifice *disabled* queued longest, because a send's per-slot copy occupies a worker longer than an exit plus an overlapped respawn does [[244.1]]. Starting the replacement earlier changes nothing measurable — the respawn is not on the parked caller's critical path.

## What we tried and rejected

The boundary's rules are narrow on purpose, and the rejections define their edges as sharply as the wins do.

Wrapping blobs in the *batch* path regressed. The wrap's benefit comes from many independent round-trips each parking a fresh allocation on the heap while the writer is mid-step; one batch round-trip has no such pattern to relieve [[237.1]].

Wrapping `selectBytes`' result bought nothing ([[bench:Select → JSON Bytes / Large payload (~650KB) / resqlite selectBytes() ~ 0.24 +-20%]]). Its bytes are already a view over a native buffer — there is no GC-heap destination to escape, so the wrap relocated one copy and added machinery [[242.1]].

And the question underneath all of these — is sacrifice worth keeping? — resisted answering for a long time because the obvious experiment is invalid. Alternating send and sacrifice inside one live pool measures a treatment that mutates the pool it runs in: each sacrifice clears caches and respawns workers, changing the conditions for the next sample. The answer only came from splitting the question into independent estimands and measuring each in isolation [[241.1]]. That methodological lesson generalized well beyond this subsystem.
