# Experiment 285: what a parked worker costs, and what waking it costs

Collected 2026-09-08 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Tree is `origin/main` at `5e62b6e` plus the harness; the writer-isolate
prototype and the `e2e` lane that drove it are preserved at `archive/exp-285`
(`0724113`). No runtime code ships on the publication branch.

Every lane is AOT (`dart build cli`), lanes alternate inside one process, and
each figure is a median across samples and then across passes.

```console
cp benchmark/experiments/worker_keep_warm.dart bin/exp285_probe.dart
dart build cli --target=bin/exp285_probe.dart --output=<dir>
<dir>/bundle/bin/exp285_probe --part=all --samples=15 --writes=400 --warm-us=40
```

**Host caveat.** Load average sat at 3.8–4.3 for the whole session (a Flutter
tool daemon, an analysis server and a DevTools instance); the host was not
idle. Every comparison below is between lanes that alternate inside one
process on one build, so drift lands on both sides. The `e2e` lane in §4 is
also single-process and single-build — the two `Database` handles differ only
in the window handed to their writer isolate at spawn.

Workload throughout: `INSERT INTO t(name, value) VALUES (?, ?)` against
`t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, value REAL NOT NULL)`, WAL,
`synchronous = NORMAL` — the schema and statement the release suite's
`Single Inserts (100 sequential)` row uses, and the one exp 284 decomposed.

## 1. The four lanes

All against exp 284's hand-rolled floor writer, so the numbers are the isolate
architecture on its own rather than resqlite's. `cold` is that worker as exp
284 left it. `timer` and `self` add a keep-warm loop on the worker built from
a zero-duration `Timer` and from a token the isolate sends to its own port
respectively. `both` is `self` plus the same token loop on the calling
isolate, which parks awaiting the reply exactly as the worker parks awaiting
the request.

Three passes of fifteen samples of four hundred sequential writes, `--warm-us=40`:

| lane | pass 1 | pass 2 | pass 3 | median | Δ vs `cold` | CPU µs/write | Δ CPU |
|---|---:|---:|---:|---:|---:|---:|---:|
| `cold` | 13.155 | 12.960 | 12.970 | **12.970** | — | 14.76 | — |
| `timer` | 16.200 | 16.218 | 16.233 | **16.218** | **+25.0%** | 23.35 | +58% |
| `self` | 13.920 | 13.710 | 13.498 | **13.710** | **+5.7%** | 16.69 | +13% |
| `both` | 12.393 | 12.078 | 11.315 | **12.078** | **−6.9%** | 21.80 | +48% |
| `inline` | 7.963 | 7.853 | 7.817 | **7.853** | — | — | — |

A fourth pass captured after the runtime revert, on the retained harness,
reproduces the pattern: `cold` 12.678, `timer` 16.032 (+26.5%), `self` 13.338
(+5.2%), `both` 11.160 (−12.0%), `inline` 7.692.

Boundary (`lane − inline`), which is what claim 284.1 prices at 5.303 µs:

| lane | boundary µs | Δ |
|---|---:|---:|
| `cold` | 5.117 | — |
| `self` | 5.857 | +14.5% |
| `both` | **4.225** | **−17.4%** |

## 2. The cold tax, measured where it lands

Each worker times its own `executeWrite` calls, so the tax is read inside the
C call rather than inferred from the round trip. Medians of the same three
passes, 6,400 writes per worker per pass:

| worker | pass 1 | pass 2 | pass 3 | median | Δ vs `cold` |
|---|---:|---:|---:|---:|---:|
| `cold` | 9.606 | 9.511 | 10.046 | **9.606** | — |
| `timer` | 9.826 | 9.476 | 9.112 | **9.476** | −1.4% |
| `self` | 9.358 | 8.974 | 8.829 | **8.974** | **−6.6%** |
| `self` (inside `both`) | 9.113 | 8.724 | 8.460 | **8.724** | **−9.2%** |

The identical C call, same statement, same parameters, same handle, runs
0.63–0.88 µs faster on a worker that never stopped being runnable.

## 3. Why `timer` loses and `self` only nearly wins

Cost of one keep-warm turn, from each loop's own spin accounting
(`spun_us / spins`), pass 1:

| loop | spins | spun µs | µs per turn |
|---|---:|---:|---:|
| `timer` (worker) | 18,542 | 120,598 | **6.50** |
| `self` (worker) | 52,820 | 97,961 | **1.85** |
| `self` (calling isolate) | 140,581 | 91,698 | **0.65** |

A zero-duration `Timer` turn costs about ten times a self-sent port message,
and a request that arrives mid-spin waits behind one turn.

## 4. The shipping path

The same token loop inside resqlite's real writer isolate, `await
db.execute(...)` against a writer that parks. Two `Database` handles in one
process, blocks alternating, three passes of fifteen samples of four hundred
writes each. (The writer isolate spawns on a database's first write, not in
`Database.open`, so each handle is driven through one write while its intended
window is still set — reading that the other way round inverted this lane's
first result.)

`--warm-us=15`:

| lane | pass 1 | pass 2 | pass 3 | median | CPU µs/write |
|---|---:|---:|---:|---:|---:|
| parked writer | 14.162 | 14.245 | 14.010 | **14.162** | 16.60 |
| keep-warm writer | 15.515 | 15.803 | 15.012 | **15.515** | 19.30 |
| | | | | **+9.6%** | **+16.3%** |

`--warm-us=40`:

| lane | pass 1 | pass 2 | pass 3 | median | CPU µs/write |
|---|---:|---:|---:|---:|---:|
| parked writer | 14.110 | 14.410 | 14.203 | **14.203** | 16.47 |
| keep-warm writer | 16.047 | 14.925 | 15.477 | **15.477** | 19.26 |
| | | | | **+9.0%** | **+17.0%** |

Three further passes captured alongside the floor lanes at `--warm-us=40`
agree: 14.348 / 14.297 / 14.340 parked against 15.235 / 15.425 / 15.123
keep-warm, **+6.2%**.

At `--warm-us=5` the loop never engages — the round trip is longer than the
window, so the token finds the deadline already past and the loop exits on its
first turn (`spins=0`). That lane reads 14.567 against 14.523, i.e. baseline,
which is the control confirming the tax and the cost both come from the loop
actually running.

## 5. Window sweep

Eleven samples of three hundred writes, one pass per window, floor lanes:

| window | `cold` | `timer` | `self` | `both` | `inline` |
|---|---:|---:|---:|---:|---:|
| 5 µs | 13.100 | 16.560 | 14.040 | 13.440 | 8.210 |
| 15 µs | 13.197 | 16.653 | 13.937 | 12.400 | 8.120 |
| 40 µs | 13.510 | 16.733 | 14.133 | 11.953 | 8.390 |
| 200 µs | 13.810 | 17.087 | 14.540 | 13.123 | 8.490 |

`self` is above `cold` at every window. `both` is below it at every window and
best in the middle, where the loop bridges the gap to the next request without
running long past it.
