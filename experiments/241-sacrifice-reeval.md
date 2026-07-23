# Experiment 241: Re-evaluating Isolate.exit "sacrifice" for the flat ResultSet (rejected)

**Date:** 2026-07-22
**Status:** Rejected
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused. Self-contained transport check
  [`benchmark/experiments/native_vs_heap_send.dart`](../benchmark/experiments/native_vs_heap_send.dart)
  (ships); sacrifice A/B via a reverted `RESQLITE_SACRIFICE_THRESHOLD` compile
  define. Raw tables in
  [`benchmark/results/2026-07-22-exp241-sacrifice-reeval.md`](../benchmark/results/2026-07-22-exp241-sacrifice-reeval.md).

## Problem

For a large read result (`>= 256 KB` estimated), the reader pool uses
`Isolate.exit` **sacrifice**: a zero-copy transfer of the whole result heap to
the main isolate that *kills the worker*, trading a reader respawn for avoiding
the `SendPort.send` graph copy. The policy predates the current architecture,
and its founding measurement ([exp 082](082-message-graph-handoff.md):
`SendPort.send` 1.048 ms vs `Isolate.exit` 2.580 ms on a 10k mixed result) was
taken before two things that undercut the premise:

1. Since Dart 2.15 isolate groups, `SendPort.send` **shares** immutable leaves
   (strings, ints, canonical objects) across the hop and only *copies* the
   mutable structural graph — so send's cost tracks the structural slot count,
   not the total bytes, and text-heavy results barely copy at all.
2. The flat-list `ResultSet` (exp 008) is a shallow structural graph.

So two questions: **(a)** is sacrifice now retirable (send-always)? **(b)** if
not, should its trigger be **structural slot count** (rows × columns), which is
what send actually costs, rather than estimated bytes?

## Hypothesis

Send may now dominate across the practical range because it shares immutable
leaves, leaving sacrifice's respawn cost unjustified for the flat ResultSet. If
a crossover survives at all, it should live at a high *structural* slot count,
not a byte threshold.

## Approach

- **Transport model check** (`native_vs_heap_send.dart`, self-contained): send a
  heap `Uint8List` vs a native-backed view of the same size, to confirm the send
  cost model that the sacrifice decision rests on.
- **Sacrifice A/B** (`sacrifice_crossover.dart`, behind a
  `RESQLITE_SACRIFICE_THRESHOLD` compile define — **reverted**, one process per
  lane): sacrifice (default 256 KB) vs send-only (threshold set to 1 TiB) across
  structural slot counts, on a **numeric** lane (structure only, no shared-text
  confound) and a **text** lane (shared strings).
- A planned retire-A/B (`sacrifice_reeval_ab.dart`) is not shipped: its
  reader-spawn counter (`debugReaderSpawnCount`) was removed by exp 236's cleanup
  pass, stranding it. The crossover harness carries the signal instead.

The `RESQLITE_SACRIFICE_THRESHOLD` define is reverted; the policy is unchanged.

## Results

**Transport model** — median round-trip µs (`native_vs_heap_send.dart`):

| size | native-view send | heap send | ttd(native) |
|---:|---:|---:|---:|
| 142 KB | 18.0 | 13.2 | 13.5 |
| 512 KB | 22.7 | 203.7 | 20.1 |
| 731 KB | 43.7 | 271.5 | 28.5 |

Send cost tracks the **mutable** payload: a heap `Uint8List` copies in full and
blows up with size (203–272 µs), while a native/external-backed view sends
cheaply (23–44 µs). This is the model the sacrifice decision rests on — send is
only expensive to the extent the result graph is mutable, copyable structure.

**Sacrifice crossover** — median µs/select, numeric lane (4 cols; slots = rows×4):

| slots | sacrifice | send |
|---:|---:|---:|
| 2000  | 76.8 | 72.3 |
| 8000  | 238.6 | 226.3 |
| 20000 | 976.5 | 931.9 |
| 32000 | 1194.8 | 1233.8 |
| 48000 | 1856.3 | 1932.6 |

Text lane (200 B strings, 1 col):

| rows | sacrifice | send |
|---:|---:|---:|
| 1000 | 438.3 | 149.4 |
| 3000 | 486.9 | 405.5 |
| 8000 | 1201.6 | 1077.0 |

Send is faster or level across the entire practical numeric range and **wins
everywhere on text** — large, at 1000 rows (149 vs 438 µs), exactly because
strings are shared on send while sacrifice pays a respawn for a copy it never
needed to make. Sacrifice only edges ahead on the numeric lane above **~32k
structural slots**, and by a noisy ~3–4%.

## Outcome

**Rejected — keep the current 256 KB estimated-byte sacrifice policy unchanged.**
Two candidate changes, both declined:

- **Retire sacrifice (send-always):** rejected. Send wins across most of the
  range, but sacrifice retains a real (if small) edge on the high-structural-count
  tail (>= ~32k slots); a blanket send-always would regress the very large
  structural results the mechanism exists for.
- **Re-trigger on structural slot count instead of estimated bytes:** rejected.
  The crossover is real but sits at a high slot count with a ~3–4% noisy margin,
  and estimated bytes already correlates with slot count for structural results.
  A slot-count threshold adds accounting complexity the measured edge doesn't pay
  for.

The run is also honest about a **measurement confound**: within one process the
repeated sacrifice respawns accumulate and interfere, so this A/B cannot cleanly
isolate a single sacrifice-vs-send at a fixed size — it biases the sacrifice lane
by the respawn history. Would reopen if a clean **single-shot per-process**
sacrifice-vs-send harness removed that confound and still showed send winning at
the high-structural tail, or if a production profile showed results clustering in
the send-favored range where sacrifice fires unnecessarily. Until then the
existing threshold stands.
