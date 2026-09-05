# Experiment 282: the missing half of the hop

Collected 2026-09-05 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline tree is `origin/main` at `9e43935`. The candidate replaces every
record on the reader's reply path with a small `final` class; the exact
prototype is preserved at `archive/exp-282` (`760f931`). No runtime code ships
on the publication branch.

Both arms are separate AOT bundles built from separate worktrees with
`dart build cli`, so nothing is toggled in-process (exp 249's in-process toggle
reported a false −27%).

```console
dart build cli --target=bin/exp282_ab.dart --output=<arm>   # in each worktree
<arm>/bundle/bin/exp282_ab --lane=<lane> --samples=41 --warmup=8
```

**Host caveat.** Load average ranged 2.5–4.3 across the session; the host was
not idle. Every A/B figure below is order-flipped per pass and lane-isolated
per process, and the `writes` lane is a zero-ceiling control, so the
collection's own floor is readable off it (±0.4% median, ±2.7% worst pass).
The decomposition parts are single-process ladders with lane rotation per
sample, so drift lands on every lane equally.

Harness sources retained on `main`:
[`read_request_residual.dart`](../experiments/read_request_residual.dart) and
[`reader_reply_envelope_ab.dart`](../experiments/reader_reply_envelope_ab.dart).

## 1. The named per-request items

`read_request_residual.dart --part=items`, AOT, 15 samples × 20,000 iterations,
lane order rotated per sample. These are the seven items claim 279.3 named,
plus `to-resultset` and the envelope handling.

| item | ns per call |
|---|---:|
| `completer` — `_WorkerSlot.request`'s `Completer.sync()` and its resolution | 38.6 |
| `hint-lookup` — `_rowHints[sql]` over a full 128-entry map | 9.6 |
| `setbusy` — the worker's bracket, two leaf FFI calls | 5.9 |
| `record` — `RowSizeMemory.record` on the hit path | 5.2 |
| `materialize` — `blobTransfer.materializeCells`, nothing wrapped | 4.8 |
| `reply-envelope` — building and destructuring `(result, false, null)` | 4.7 |
| `dispatch-scan` — the four-slot scan, first slot free | 4.7 |
| `request-build` — `SelectRequest` plus the two-field hint stamp | 2.6 |
| `to-resultset` — `RawQueryResult.toResultSet` | 2.6 |
| **total** | **78.8** |

## 2. The hop, re-measured

`--part=e2e`, 15 samples × 500 reads per arm, arms alternated per sample. Six
columns, one row, one long-warm statement. The inline arm runs `executeQuery` +
`toResultSet` + `materializeCells` on the calling isolate against a second
handle on the same file.

| lane | µs per read |
|---|---:|
| `pool` | 4.625 |
| `inline` | 1.355 |
| **hop** | **3.270** |

Claim 265.1 records this hop at 6.3 µs. The inline arm here omits the async
prologue and hint bookkeeping exp 265's inline routing kept, so 3.270 is an
upper bound on what the worker path adds.

## 3. The transport ladder

`--part=reply`, one echo isolate, 15 samples × 2,000 round trips, lane order
rotated per sample. No SQLite and no pool in any lane.

| lane | µs per round trip |
|---|---:|
| `reply-echo` — int out, int back | 1.631 |
| `reply-one` — a 1-slot `List` back | 1.953 |
| `reply-list3` — `<Object?>[1, false, null]` back | 1.919 |
| `reply-triple` — `(1, false, null)` back | 3.002 |
| `reply-pair` — `(1, false)` back | 3.004 |
| `reply-nest-list` — a list inside a list | 2.025 |
| `reply-nest-rec` — a record inside a record | 3.025 |
| `reply-bare` — the real `ResultSet`, no envelope | 2.287 |
| `reply-listenv` — the same inside a `List` envelope | 2.328 |
| `reply-nomap` — inside the record, schema carrying no index | 3.001 |
| `reply-real` — inside the record, schema carrying its index | 3.096 |
| `reply-279` — exp 279's `iso-result` payload, verbatim | 3.018 |
| `req-one` — a 1-slot `List` out, int back | 1.968 |
| `req-real` — a real `SelectRequest` out, int back | 2.029 |
| `full-real` — real request out, real reply back | 3.180 |

Record lanes cluster at 3.00–3.10 and non-record lanes at 1.92–2.33, with no
dependence on field count and none on how many records the message holds.

### 3a. Hardening the record effect

Each row is the same message with a record envelope and with a class envelope,
varying what else about the payload is realistic.

| payload | record µs | class µs | Δ µs |
|---|---:|---:|---:|
| `fresh-rec` / `fresh-class` — built per message | 3.632 | 2.042 | +1.59 |
| `fresh-rec-str` / `fresh-class-str` — + non-canonical TEXT cells | 3.872 | 3.015 | +0.86 |
| `real-rec` / `real-class` — + a run-time-built schema | 3.916 | 3.062 | +0.85 |
| `busy-rec` / `busy-class` — + worker busy ~2.3 µs first | 5.957 | 4.704 | +1.25 |

`real-rec` at 3.916 µs is a **one-way** reply lane measuring more than the
entire 3.270 µs round-trip hop of §2. That is the first sign the ladder
overstates.

### 3b. Parking the caller costs nothing

The worker burns a calibrated interval before replying. `spin-1u` measures
564.3 ns and `spin-4u` 2253.3 ns on the same host, so the spin column is
`units/4 × 2253.3`.

| lane | round trip µs | spin µs | overhead µs |
|---|---:|---:|---:|
| `busy-0u` | 3.165 | 0.00 | 3.17 |
| `busy-4u` | 4.896 | 2.25 | 2.64 |
| `busy-8u` | 7.217 | 4.51 | 2.71 |
| `busy-20u` | 14.358 | 11.27 | 3.09 |

## 4. End-to-end A/B

`reader_reply_envelope_ab.dart`, four order-flipped passes, 41 samples after 8
warmup, one lane per process, both arms AOT from separate worktrees. Δ is
candidate against base within each pass.

| lane | four passes (Δ%) | median |
|---|---|---:|
| `point1` | +0.3 −1.2 −0.7 −1.0 | −0.84% |
| `point1-wide20` | +0.8 −2.3 −0.7 −0.9 | −0.76% |
| `bytes1` | +1.2 +2.3 +0.0 +1.3 | +1.24% |
| `bytes1k` | −0.3 −0.4 +2.9 −2.7 | −0.36% |
| `rows20` | +12.1 +0.0 −0.7 +3.0 | +1.49% |
| `rows1k` | −0.8 −0.2 +3.9 −2.9 | −0.51% |
| `stream-rerun` | +1.3 +2.2 −7.2 +3.5 | +1.75% |
| `rows10k` (guard, `Isolate.exit`) | −10.6 −3.5 +1.6 −0.9 | −2.18% |
| `writes` (control, zero ceiling) | −2.7 −0.1 −0.4 −0.4 | −0.42% |

An earlier six-pass collection of `point1` alone, 61 samples per process:

| lane | six passes (Δ%) | median |
|---|---|---:|
| `point1` | −0.1 −0.1 −1.1 −3.6 +0.3 −3.1 | −0.58% |
| `writes` (control) | +0.8 +0.1 +6.0 −1.1 −0.7 +1.6 | +0.49% |

The ladder predicts −17% to −27% on `point1` and more on `bytes1`, which loses
two records rather than one. `bytes1` is the only primary lane that came out
positive.

## 5. The in-situ reading that settles it

A temporary `Stopwatch` around the real reader worker's own `eventPort.send`,
added to both worktrees, printed when the worker shuts down. JIT, one process
per arm, `--lane=point1 --samples=21`, 5,800 sends each. The instrumentation
was reverted immediately after; it exists only in this receipt and the writeup.

| arm | what it sends | ns per `send` | sends |
|---|---|---:|---:|
| base | `(result, false, null)` — a record | 1416.8 | 5,800 |
| candidate | `ReadReply(result)` — a class | 1457.3 | 5,800 |

The operation §3a prices at 0.85–1.59 µs apart measures identical in the
shipping path, 3% in the wrong direction. This is the evidence the rejection
rests on, together with §4.
