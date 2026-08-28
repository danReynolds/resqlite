# Experiment 279: does the reader have to be a Dart isolate?

**Date:** 2026-08-28
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`, `stream-rerun-dispatch`
**Benchmark Run:** none — the runtime prototype is reverted and no code ships in
  `lib/`, `native/` or `hook/`. The decision evidence is the mechanism price and
  the end-to-end pair in
  [`benchmark/results/2026-08-28T11-30-00Z-exp279-native-thread-dispatch.md`](../benchmark/results/2026-08-28T11-30-00Z-exp279-native-thread-dispatch.md).

## Problem

A `select()` does not run where it is called. It is packed into a request
object, sent to a reader isolate over a `SendPort`, executed there, and sent
back. [Exp 265](265-inline-main-isolate-select.md) priced that round trip by
removing it — running the same query on the calling isolate — and found 6.3 µs
of an 8.4 µs canonical point read inside it (claim 265.1). Four experiments have
since tried to collect that 6.3 µs and none succeeded. Exp 265 itself was
rejected because row count cannot bound caller-isolate work (claim 265.6);
[exp 269](269-enforced-inline-reads.md) replaced prediction with enforcement and
was rejected because one SQLite operation can consume arbitrary time before any
cap is checked (claim 269.2); [exp 270](270-read-result-cache.md) removed the
query instead of the hop and was rejected on foreign-writer staleness;
[exp 275](275-cost-aware-read-admission.md) reordered who gets the worker first
and was rejected on incidence (claim 275.1).

Every one of those asked the same question — how do we avoid the worker? — and
answered it by moving work onto the calling isolate, where it cannot be bounded.
None asked the prior question: **does the worker have to be a Dart isolate at
all?**

The hop exists to keep SQLite off the caller's event loop. A POSIX thread does
that just as completely, and unlike a Dart isolate it can be woken by a condvar
rather than a message. Its completion can reach the main isolate through
`Dart_PostCObject_DL` on a native port, and — the part that looked like the real
prize — it can hand a payload over as `kExternalTypedData`, which the receiving
isolate does not copy. If native dispatch were cheaper than the isolate round
trip, the whole direction reopens with the safety intact: no SQLite on the
caller, no freshness contract, no starvation.

## Hypothesis and decision rule

**Assumption challenged:** that keeping SQLite off the calling isolate requires
a Dart isolate round trip, and that the 6.3 µs of claim 265.1 is therefore the
price of safety rather than the price of one particular vehicle.

The prototype adds `native/resqlite_nport.c`: a POSIX worker-thread pool, and
completions posted to a Dart native port via `Dart_PostCObject_DL`, compiled
against the Dart SDK's own `include/dart_api_dl.c`. Nothing in `lib/` links
against it — the comparison is made in a harness, so both arms of every lane run
the shipped code.

The measurement was designed to fail fast. Before building anything on top of a
native thread, the round trip had to be split, because it is two message
deliveries and only one of them is avoidable: the request out (which a native
thread replaces with an FFI call and a condvar signal) and the reply back (which
native dispatch still pays, because the result still has to arrive as a message
on the main isolate). The `nport-here` lane — a native post issued from the
*calling* thread, so nothing sleeps — prices main-isolate delivery alone.

Declared before measuring:

- **Accept the direction** if native dispatch is materially cheaper than the
  isolate round trip at the same payload, *and* an end-to-end `selectBytes`
  through a native worker reproduces the gap.
- **Reject** if the isolate round trip is cheaper — in which case the direction
  is closed for good, not merely unproven, because no arrangement of a slower
  transport beats a faster one.
- The spinning-worker lane exists so a rejection cannot be blamed on a badly
  chosen wake primitive: it burns a core to keep the thread hot and is therefore
  a floor, not a design.

## Results

Full tables in the
[receipt](../benchmark/results/2026-08-28T11-30-00Z-exp279-native-thread-dispatch.md).
Microseconds per awaited round trip; medians of six order-flipped
lane-isolated AOT passes (four for the end-to-end pair).

### The isolate round trip is the faster vehicle

| lane | µs | what it is |
|---|---|---|
| `nport-here` | 0.67 | native post, calling thread — delivery with nothing asleep |
| `iso-echo` | 1.46 | Dart isolate round trip, int each way |
| `nport-spin` | 3.18 | native worker thread, spinning (a burned core) |
| `nport-thread` | 4.28 | native worker thread, parked on a condvar |

A Dart isolate round trip costs **1.46 µs**; handing the same work to a POSIX
thread and getting an answer back costs **4.28 µs**, and **3.18 µs** even with
the worker spinning on the queue so the OS never has to wake it. Native dispatch
is 2.2–2.9× *more* expensive than the thing it was meant to replace.

`nport-here` says where that goes. Posting to the main isolate and having it
pick the message up costs 0.67 µs when nothing has to be woken; everything above
that in the native lanes is the OS scheduling round trip. The Dart VM does the
equivalent handoff *in both directions* for 1.46 µs. Whatever the same-isolate-
group message path does, it is faster than a condvar and a foreign-thread post.

End to end, on a real database, the mechanism price is exactly what shows up:

| rows | `db.selectBytes()` | native worker thread | Δ |
|---|---|---|---|
| 1 | 5.48 | 6.43 | **+17.3%** |
| 1,000 | 246.5 | 249.3 | **+1.1%** |
| 5,000 | 1239 | 1233 | −0.5% |

A one-row `selectBytes` is 17% slower through the native thread — the fixed
dispatch penalty divided by the smallest read there is. By a thousand rows the
query dominates and the penalty is 1%; by five thousand it is inside the noise.
The candidate is never faster at any size, which is the cleanest form the
rejection could take.

### What the 6.3 µs is actually made of

The transport lanes answer a question exp 265 could not, because 6.3 µs is a
*difference* between two arms and everything the worker path does that the
inline path does not is inside it:

| lane | µs | |
|---|---|---|
| `iso-echo` | 1.46 | round trip floor |
| `iso-request` | 1.96 | + a `SelectRequest`-shaped object outbound |
| `iso-result` | 3.20 | + a point read's reply inbound |
| `iso-full` | 3.22 | both, in one trip |

The adders are not additive: 1.46 + 0.50 + 1.74 is 3.70 µs, and carrying both
in one trip measures 3.22. Part of what each shape costs is per-trip rather than
per-payload, so measuring the combination rather than summing the parts is what
the `iso-full` lane is for.

**A point read's entire transport is 3.22 µs — roughly half of the 6.3 µs hop.**
The other ~3.1 µs is resqlite's own per-request work on the two sides of it:
pool bookkeeping and the row-size memory lookup, request construction, the
worker's `setBusy` bracket and request dispatch, the completion handler chain,
the blob materialization pass. A *perfect* transport — zero-cost messages —
would still leave more than three microseconds of the hop standing. That
reframes the target for anything that follows: the messages are not where the
remaining headroom is.

### The VM charges for a payload's backing, not its size

The two bytes lanes carry byte-for-byte identical 256 KB and differ only in how
it is backed:

| lane | µs |
|---|---|
| `iso-bytes` — view over malloc'd memory | 9.01 |
| `iso-bytes-heap` — ordinary heap `Uint8List` | 43.06 |

**4.8× for the same bytes.** This is the number behind
[exp 174](174-selectbytes-view-transfer.md)'s decision to send a `Uint8List`
view over the reader's persistent `json_buf` rather than materialize the result
first (claim 174.1); it was reasoned about there and is measured here. It also
stands as a constraint on anything future: a path that assembles bytes on the
Dart heap before sending them pays roughly five times the transfer, and no
amount of tuning around the send recovers it.

### The one place native dispatch is ahead, and why it stays there

Posting the payload as external typed data lets the *receiving* isolate skip its
copy. Two variants:

| lane | µs (256 KB) |
|---|---|
| `iso-bytes` — shipped path | 9.01 |
| `nport-bytes` — post a fresh malloc'd copy | 11.91 |
| `nport-bytes-nocopy` — post the buffer itself, no copy | 5.63 |

The realistic variant is *slower*, and the subtraction says why it is not the
copy's fault. `nport-bytes` − `nport-bytes-nocopy` puts a malloc plus a 256 KB
`memcpy` at 6.28 µs; `iso-bytes` − `iso-echo` puts the VM's copy of the same
view at 7.55 µs. The two are close, so copying is a wash between the mechanisms
and the entire 2.90 µs by which `nport-bytes` loses is the dispatch penalty
already measured above. Exp 174 reached the compatible conclusion from the other
side when it measured a `NativeFinalizer` zero-copy transfer 14–24% slower at
every size and named buffer reuse, not the copy, as the decisive term.

That leaves the zero-copy variant, which is genuinely 3.38 µs faster than the
shipped path. It is not a design — it posts a buffer it does not own. Making it
real means handing `json_buf` itself to the main isolate and giving the
connection a fresh one, which forfeits exactly the reuse exp 174 found decisive
and the shrink-and-reclaim policy [exp 183](183-json-buf-retention-audit.md)
built on top of it. And the prize is 3.38 µs per 256 KB: 1.4% of the 1,000-row
read measured here, against a fixed dispatch tax on every small read.

## Decision

**Rejected.** Native-thread dispatch is not a cheaper vehicle than a Dart
isolate on this runtime — it is 2.2–2.9× more expensive per round trip and 17%
slower end to end on the read shape it was aimed at. The prototype is reverted;
the exact tree is preserved at `archive/exp-279`.

This closes the vehicle question rather than leaving it open. Exps 265, 269 and
270 were each rejected for a *consequence* of removing the worker — unbounded
caller work, unbounded opaque SQLite work, foreign-writer staleness — which left
the impression that the hop's cost was collectable if only the safety problem
could be solved. It is not: the hop is already the cheapest available way to get
work off the calling isolate and an answer back.

**Would reopen if** the Dart VM's cross-isolate message path regresses, or
`Dart_PostCObject` gains a fast path for a foreign thread posting to a sleeping
isolate — `nport-here`'s 0.67 µs shows the delivery itself is cheap, so the whole
2–3 µs gap is the wake. A future runner should re-run
`benchmark/experiments/isolate_transport_price.dart` against the archived
prototype before assuming this still holds.

What survives for the next candidate in this direction is the decomposition, not
the rejection: a point read's transport is 3.22 µs of claim 265.1's 6.3 µs, so
the remaining half lives in resqlite's per-request work rather than in the
messages, and that is where a candidate should now be aimed.

## What is kept

The isolate-only lanes of the harness, as
[`benchmark/experiments/isolate_transport_price.dart`](../benchmark/experiments/isolate_transport_price.dart).
They need no native code and no database, and they are the ruler this direction
has been missing: any future proposal to change what crosses the isolate
boundary can be priced against them before it is built. The native prototype,
the build-hook wiring that compiles `dart_api_dl.c`, and the three `nport-*`
lanes are reverted and live only at `archive/exp-279`.
