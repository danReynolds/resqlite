# Exp 241 — sacrifice re-evaluation (rejected)

Apple M1 Pro / macOS. Sacrifice A/B via `RESQLITE_SACRIFICE_THRESHOLD` compile
define (reverted on the branch; set to 1 TiB to force the send-only lane).

## Transport model — `native_vs_heap_send.dart` (ships, self-contained)

Median round-trip µs; send a heap `Uint8List` vs a native-backed (malloc'd,
asTypedList) view of the same size.

| size | native-view send | heap send | ttd(native, incl fromList) |
|---|---:|---:|---:|
| 142KB | 18.0 | 13.2 | 13.5 |
| 512KB | 22.7 | 203.7 | 20.1 |
| 731KB | 43.7 | 271.5 | 28.5 |

Heap send blows up with size; native-view send stays cheap. Send cost tracks the
mutable/copyable payload, not the byte count of external-backed content.

## Sacrifice crossover — `sacrifice_crossover.dart` (toggle-coupled; recipe below)

Reproduce: default lane = sacrifice (256 KB); send lane =
`dart run -DRESQLITE_SACRIFICE_THRESHOLD=1099511627776 ...`. Requires re-applying
the one-line `sacrificeByteThreshold` -> `int.fromEnvironment` define in
`read_worker.dart`.

Numeric lane (4 cols; structural slots = rows × 4), median µs/select:

| lane | slots=2000 | 8000 | 20000 | 32000 | 48000 |
|---|---:|---:|---:|---:|---:|
| sacrifice | 76.8 | 238.6 | 976.5 | 1194.8 | 1856.3 |
| send | 72.3 | 226.3 | 931.9 | 1233.8 | 1932.6 |

Text lane (200 B strings, 1 col), median µs/select:

| lane | rows=1000 | 3000 | 8000 |
|---|---:|---:|---:|
| sacrifice | 438.3 | 486.9 | 1201.6 |
| send | 149.4 | 405.5 | 1077.0 |

Send wins/levels across the practical numeric range and wins large on text
(shared strings); sacrifice edges ahead only above ~32k numeric slots, by a
noisy ~3–4%. Rejected — see `experiments/241-sacrifice-reeval.md`.
