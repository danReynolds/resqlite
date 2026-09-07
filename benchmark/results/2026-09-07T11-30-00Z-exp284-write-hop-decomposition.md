# Experiment 284: where a standalone write's time goes

Collected 2026-09-07 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Tree is `origin/main` at `2f6a236` plus the harness; the in-situ probes and the
reply-port candidate that produced §3 and §4 are preserved at
`archive/exp-284` (`e31d41c`). No runtime code ships on the publication branch.

Every lane is AOT (`dart build cli`), lanes alternate inside one process, and
each figure is the median of five passes of fifteen samples of four hundred
sequential awaited writes.

```console
cp benchmark/experiments/write_hop_decomposition.dart bin/exp284_probe.dart
dart build cli --target=bin/exp284_probe.dart --output=<dir>
<dir>/bundle/bin/exp284_probe --part=all --samples=15 --writes=400
```

**Host caveat.** `mediaanalysisd` held roughly one core for the whole session
and load average sat at 5.6–6.4; the host was not idle. Nothing here is a
wall-time A/B between two trees, though — every comparison is between lanes
that alternate inside one process on one build, so drift lands on both sides.
The one figure that is a two-build comparison (§4) is reported as a mechanism
slice rather than as an end-to-end delta, for exactly that reason.

Workload throughout: `INSERT INTO t(name, value) VALUES (?, ?)` against
`t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)`, WAL,
`synchronous = NORMAL` — the schema and statement the release suite's
`Single Inserts (100 sequential)` row uses.

## 1. The hop, and the floor under it

| lane | µs per write |
|---|---:|
| `writer` — `await db.execute(...)` | 13.895 |
| `floor-hop` — hand-rolled isolate writer, no resqlite machinery | 12.915 |
| `inline` — the identical `executeWrite` on the calling isolate | 7.612 |
| **hop** (`writer − inline`) | **6.283** |
| **boundary** (`floor − inline`) | **5.303** |
| **resqlite's own** (`writer − floor`) | **0.980** |

Per-pass, so the spread is visible:

| pass | writer | floor-hop | inline |
|---|---:|---:|---:|
| 1 | 14.082 | 14.518 | 7.645 |
| 2 | 13.895 | 12.863 | 7.593 |
| 3 | 13.893 | 12.505 | 7.612 |
| 4 | 14.037 | 13.078 | 7.600 |
| 5 | 13.863 | 12.915 | 7.755 |

Pass 1's `floor-hop` is the first lane the process runs and carries its own
warm-up; the other four agree inside 0.6 µs.

The `floor` lane sends a two-slot parameter list to an isolate that calls the
same `executeWrite` and sends an `int` back. It has no coalescing pump, no
writer mutex, no blob wrapping, no dirty-dependency harvest, no response
object and no completer queue. It does not even carry the SQL on the wire.
It is deliberately the cheapest isolate-backed write this codebase can express.

## 2. What the woken side pays

The floor worker times its own `executeWrite` call:

| where the identical call runs | µs |
|---|---:|
| inline, on an isolate that is already running | 7.612 |
| on a worker isolate that was parked until the message arrived | 9.380 |

The same C entry point, the same statement, the same parameters: **+1.77 µs**
because the thread running it was asleep a microsecond earlier.

`--part=wake` isolates the other half — the synchronous cost of the `send`
call itself, for a message shaped like a write request:

| target | µs per `send` |
|---|---:|
| a port in the sending isolate (graph copy only) | 0.272 |
| another isolate, already draining a backlog | 0.445 |
| another isolate, parked waiting | 0.737 |

So of the 5.30 µs boundary: ~0.27 µs is the object-graph copy, ~0.47 µs is
waking the writer, ~1.77 µs is the writer running cold once woken, and the
remainder is the symmetric cost on the reply.

## 3. The in-situ decomposition

Stopwatch marks in the shipping path on both sides of the boundary
(`archive/exp-284`), median of three passes, 5,200 writes on the main side and
11,200 on the writer side. One `Stopwatch.elapsedTicks` read costs 18.2 ns on
this host, so the eleven marks tax a write by ~0.2 µs — visible as the probed
build's 14.2 µs against the clean build's 13.9 µs.

| slice | side | µs per write |
|---|---|---:|
| `executeWrite` (SQLite, param arena, result buffer) | writer | 8.455 |
| `ExecuteResponse` build + `replyPort.send` | writer | 1.640 |
| `SendPort.send` of the `ExecuteRequest` | main | 1.481 |
| transport + scheduling residual | — | 0.945 |
| `_onReply` → `Database.execute` returns | main | 0.348 |
| `Writer.execute` entry → writer mutex held | main | 0.307 |
| `getDirtyTableDependencies` | writer | 0.288 |
| `blobTransfer.unwrapParams` | writer | 0.192 |
| `ExecuteRequest` build (incl. `wrapParams`) | main | 0.074 |

Everything resqlite owns — the last five rows — sums to **1.209 µs**, against
the 0.980 µs the floor lane attributes to it independently. No single item is
larger than 0.35 µs, or 2.5% of a write.

## 4. The candidate the decomposition named

Every writer request has carried `SendPort replyPort` since before exp 159 gave
the writer a single persistent reply port, so each message was asking the VM to
carry a port handle the worker could have kept. The prototype removes the field
from all eight request types and hands the port over once, in the spawn
arguments.

| build | in-situ `send` slice, µs |
|---|---:|
| baseline (port on every request) | 1.469 / 1.485 / 1.521 |
| candidate (port handed over once) | 1.471 / 1.483 / 1.484 |

The slice the change targets does not move. End-to-end wall (14.15 µs baseline
against 14.19 µs candidate across the same probed builds) is inside the pass
spread and is not offered as evidence either way — §2 already says why the
mechanism cannot pay: `send`'s cost is the wake, and a port field is not
measurable beside it.

## 5. Against the release suite

The public row this run set out to explain, from
`2026-08-09T20-36-47-exp266-headline-refresh.md`:

| lane | resqlite | sqlite3 | drift | sqlite_async |
|---|---:|---:|---:|---:|
| Single Inserts (100 sequential), ms | 1.577 | 0.934 | 2.648 | 2.703 |
| Concurrent Single Inserts (100), ms | 0.819 | 0.858 | 1.623 | 2.517 |

15.77 µs against 9.34 µs per sequential write. This harness reproduces both
ends in one process (13.90 against 7.61) and attributes the difference: 5.3 µs
of it is the isolate boundary and 1.0 µs is resqlite. The row directly beneath
is the same workload issued concurrently, where the coalescing pump amortises
the boundary across the group and resqlite is already faster than the
synchronous peer.
