---
component: boundary
title: Cross-isolate transfer
kicker: isolate boundary
zone: boundary
order: 1
directions: [result-transfer-shape]
diagram: boundary
---

Dart isolates share no mutable state, so the boundary between the main isolate and the workers is where resqlite’s performance is won or lost: every query result must travel worker→main, and every write parameter main→writer. Nothing crosses for free — but not everything crosses at the same price, and the entire design rests on knowing which is which.

## Four ways across

Strings and numbers are immutable, and the VM shares them across the hop by reference — a 400 KB string adds roughly nothing to a send [[245.1]]. What send() actually copies is structure: the flat values array underneath a result, paid per slot. A Uint8List is the odd one out — mutable, so copied byte-for-byte — which is why blobs get special treatment. And for results whose structure is itself enormous, the worker can hand its entire heap over with Isolate.exit and die: zero copy, a ~47 µs validation premium, and a background respawn [[245.2]].

## The two rules

Everything above collapses into one governing distinction: bytes for mutable payloads, slots for structure. Blobs of 256 KB or more are wrapped into TransferableTypedData in both directions — the same single copy they would have paid anyway, but landing in external memory the GC never traces, then crossing as an ownership move [[234.1]] [[236.1]]. Wrapping is identity-keyed, so a caller passing the same buffer to five positions still ships one buffer, not five [[243.1]].

Large results sacrifice the worker when their slot count crosses 32k — slot count, not bytes, because bytes lie. The original byte-based trigger misread every big-TEXT result as expensive and killed a reader on every such read, paying a respawn to avoid a copy that sharing had already made free. Re-routing the trigger on slot count fixed the misroute and deleted the byte accounting entirely [[246.1]] [[236.2]]. The pool absorbs the respawns comfortably: measured at production pool size, the no-sacrifice lane actually queued longest, because a send’s copy blocks a worker longer than an exit plus an overlapped respawn [[244.1]].

## What we tried and rejected

The boundary’s rules are narrow on purpose, and the rejections prove the edges. Wrapping batch blobs regressed — the win only exists across many independent round-trips parking fresh allocations on the heap, which one batch round-trip never does [[237.1]]. Wrapping selectBytes’ native view bought nothing — there is no GC-heap destination to escape [[242.1]]. And the question that settled all of this — is sacrifice worth keeping at all? — could not be answered by A/B-ing a live pool, because sacrifice mutates the pool it runs in; it took splitting the question into isolated estimands to close it [[241.1]].
