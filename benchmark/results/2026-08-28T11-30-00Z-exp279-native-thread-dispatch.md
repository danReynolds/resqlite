# Experiment 279: native-thread dispatch (moonshot)

Collected 2026-08-28 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline tree is `origin/main` at `1b4bb32`. The prototype adds
`native/resqlite_nport.c` (a POSIX worker-thread pool plus `Dart_PostCObject_DL`
completions) and the `hook/build.dart` wiring that compiles it against the Dart
SDK's `include/dart_api_dl.c`; nothing in `lib/` links against it, so both arms
of every lane run the same shipped code. The exact prototype is preserved at
`archive/exp-279`.

All figures are microseconds per awaited round trip, median of 11 samples of
2,000 round trips (60–2,000 for the end-to-end lanes). Every lane runs in its
own process, and passes alternate collection order.

```console
dart build cli --target=bin/native_port_dispatch.dart --output=<out>
<out>/bundle/bin/native_port_dispatch --samples=11 --threads=1 --lanes=<lane>
```

`bin/` is only where `dart build cli` requires the entry point to live; the
harness source is `benchmark/experiments/native_port_dispatch.dart` on
`archive/exp-279`, of which the isolate-only lanes are retained on `main` as
[`isolate_transport_price.dart`](../experiments/isolate_transport_price.dart).

## Mechanism price — six order-flipped lane-isolated passes

| lane | p1 | p2 | p3 | p4 | p5 | p6 | median |
|---|---|---|---|---|---|---|---|
| `iso-echo` | 2.982 | 1.417 | 1.655 | 1.467 | 1.462 | 1.377 | **1.46** |
| `iso-request` | 1.957 | 1.960 | 1.940 | 1.971 | 2.025 | 1.958 | **1.96** |
| `iso-result` | 3.217 | 3.182 | 3.237 | 3.196 | 3.196 | 3.180 | **3.20** |
| `iso-full` | 3.203 | 3.237 | 3.256 | 3.224 | 3.191 | 3.235 | **3.22** |
| `nport-here` | 0.682 | 0.661 | 0.671 | 0.659 | 0.666 | 0.665 | **0.67** |
| `nport-spin` | 3.202 | 3.031 | 3.201 | 3.224 | 3.152 | 3.139 | **3.18** |
| `nport-thread` | 4.292 | 4.309 | 4.293 | 4.275 | 4.244 | 4.282 | **4.28** |
| `iso-bytes` | 8.979 | 9.021 | 9.042 | 9.002 | 9.013 | 9.011 | **9.01** |
| `nport-bytes` | 11.889 | 11.866 | 11.938 | 11.908 | 11.965 | 11.839 | **11.91** |
| `nport-bytes-nocopy` | 5.619 | 5.620 | 5.604 | 5.653 | 5.635 | 5.640 | **5.63** |

`iso-echo`'s pass-1 reading is the first process of the collection and reads
high in every collection taken; the other five agree to within 0.28 µs.

`iso-*` lanes cross a persistent worker isolate and back. `nport-thread` hands
the job to a POSIX worker parked on a condvar; `nport-spin` is the same worker
spinning on the queue (a burned core, not a shippable design, included so the
result cannot be blamed on the primitive); `nport-here` posts from the calling
thread itself, so the main isolate never sleeps. Bytes lanes carry 256 KB.

## Payload backing — four order-flipped passes

Identical 256 KB in both lanes; only the backing differs.

| lane | p1 | p2 | p3 | p4 | median |
|---|---|---|---|---|---|
| `iso-bytes` (view over malloc'd memory) | 9.053 | 8.995 | 8.979 | 9.009 | **9.01** |
| `iso-bytes-heap` (heap `Uint8List`) | 43.263 | 43.033 | 42.712 | 43.237 | **43.06** |

Re-measured on the retained isolate-only harness over six order-flipped passes:
`iso-bytes` 8.96 µs, `iso-bytes-heap` 41.06 µs.

## End to end — four order-flipped passes

`iso-query` is `db.selectBytes('SELECT * FROM items')` as shipped. `nport-query`
runs the same SQL through `resqlite_query_bytes` on a native worker thread and
posts the serialized bytes back as external typed data, with no Dart isolate
between the caller and SQLite. The lanes are sequential, so the native thread
borrows reader slot 0 while no reader worker is using it.

| rows | arm | p1 | p2 | p3 | p4 | median | Δ |
|---|---|---|---|---|---|---|---|
| 1 | `iso-query` | 5.518 | 6.287 | 5.357 | 5.441 | **5.48** | |
| 1 | `nport-query` | 6.386 | 6.425 | 6.457 | 6.426 | **6.43** | **+17.3%** |
| 1,000 | `iso-query` | 246.490 | 246.585 | 246.190 | 246.700 | **246.5** | |
| 1,000 | `nport-query` | 249.135 | 248.925 | 249.505 | 249.950 | **249.3** | **+1.1%** |
| 5,000 | `iso-query` | 1240.717 | 1244.617 | 1237.900 | 1233.833 | **1239** | |
| 5,000 | `nport-query` | 1236.133 | 1229.183 | 1230.050 | 1236.583 | **1233** | −0.5% |

Native dispatch is slower on the small read, slower at a thousand rows, and
inside the noise floor at five thousand. It is never faster.
