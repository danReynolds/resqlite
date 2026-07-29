# Experiment 258: Columnar typed-array result store

**Date:** 2026-07-29
**Status:** Rejected
**Category:** Moonshot
**Direction:** `result-transfer-shape`
**Benchmark Run:** none — focused
  [`benchmark/experiments/columnar_result_transfer.dart`](../benchmark/experiments/columnar_result_transfer.dart),
  AOT-compiled, two order-flipped passes; receipt in
  [`benchmark/results/2026-07-29T11-23-43Z-exp258-columnar-result-transfer.md`](../benchmark/results/2026-07-29T11-23-43Z-exp258-columnar-result-transfer.md).
  No release-suite lane isolates the container mechanism (build/transfer/access)
  from SQLite stepping, so the focused harness is the durable gate.

## Problem

Every `select()` result is backed by one flat, row-major `List<Object?>`
(`decodeQuery` in `lib/src/query_decoder.dart`, consumed through
`ResultSet`/`Row` in `lib/src/row.dart`). Decoding boxes every numeric cell
into that list; the list then crosses the reader→main isolate boundary, and
`Row['col']` reads the boxed value back out on the main isolate.

[Exp 224](224-numeric-row-batching-moonshot.md) (2026-07-12) closed the *FFI
crossing* axis of the rows path — leaf crossings are already cheap — and in
doing so named the real remaining cost out loud: "Dynamic numeric-run batching
removes crossings but does not remove SQLite stepping or **Dart object
construction**." That is the boxing. [Exp 055](055-columnar-typed-arrays.md)
(2026-04-15) proposed the obvious structural answer — replace the boxed flat
list with **per-column typed arrays** (`Int64List`/`Float64List` for numeric
columns, `List<String>` for text) — but it was *assessed, never implemented*:
it *estimated* "~1.8× faster isolate transfer" and "10–15% faster iteration,"
then rejected on the grounds that the throughput win looked too small versus
the noise floor and that the memory win "would require a different benchmark
methodology (memory profiling, GC pause tracking) to validate." Its own Future
Consideration says columnar "would be the right fix" if memory profiling ever
showed GC pressure. [Exp 081](081-binary-row-result-storage.md) measured a
*row-major binary slab* (a different shape) and rejected it because per-cell
main-isolate access got slower.

Two things changed since 2026-04 that make the columnar typed-array mechanism
worth measuring for the first time:

1. The memory-profiling methodology 055 lacked now exists — `ProcessInfo.currentRss`
   and the RSS diagnostics from [exp 174](174-selectbytes-view-transfer.md)/[exp 183](183-json-buf-retention-audit.md),
   and the process-isolated transfer harnesses from [exp 244](244-pool-burst-eager-respawn.md)/[exp 245](245-prepared-result-handoff.md).
2. Exp 224 gives direct evidence that Dart object construction, not the FFI
   crossing, is the top rows-path cost — the exact cost columnar removes.

## Hypothesis

**Assumption challenged:** the `select()` result backing store must be a boxed,
row-major `List<Object?>`. If numeric columns were stored as typed arrays, the
worker would skip boxing during decode, the container would cross the isolate
boundary as a `memcpy` instead of a boxed structured-clone, and the main isolate
would box lazily only on the cells a caller actually reads.

The columnar container trades between three costs, and no prior experiment
measured all three of the *typed-array* form end-to-end:

- **build** (worker wall, off the main isolate) — flat boxes every cell;
  columnar fills typed arrays with no boxing.
- **hop** (main-observed round trip: build + serialize + structured-clone
  receive) — this is 055's "1.8× faster transfer" claim.
- **consume** (main-isolate wall, reading every cell as `Object?` the way
  `Row['col']` does) — flat reads already-boxed pointers; columnar boxes on
  access. This is exp 081's concern.

Accept a production rewrite only if columnar moves resqlite's *primary* metric —
main-isolate time (`hop + consume`) — on a realistic result shape, with no
memory regression. Reject if the main-isolate win is confined to shapes the
existing transfer machinery already handles, or if memory regresses.

## Approach

The harness (`columnar_result_transfer.dart`) feeds both containers identical
raw numeric source data (a `Float64List`) and measures build / hop / consume
across a real worker→main `SendPort` hop, AOT-compiled, two order-flipped
passes. It deliberately does **not** stand up SQLite: the goal is to isolate the
container mechanism 055 estimated and never ran, not to re-measure the decode
loop exp 224 already covered.

The load-bearing production detail the harness encodes explicitly: the reader
**sacrifices** (hands its heap to main via `Isolate.exit`, zero-copy) once a
result exceeds `sacrificeSlotThreshold = 32 × 1024` structural slots
(`rows × cols`), and the `read_worker.dart` comment (from exp 244/245/246)
records that on the `SendPort` path "string and number leaves are shared;
structure is the only thing send actually copies." So lanes are tagged by which
production path they take: `(send)` lanes stay under the threshold (real
`SendPort` copy); `(exit)` lanes exceed it (production transfers them for free).
A columnar container's `hop` win only *reaches production* on the `(send)`
lanes — the `(exit)` lanes already zero-copy the transfer regardless of shape.

## Results

Medians in ms, columnar-vs-flat Δ (negative = columnar faster), both order
passes. `NET = hop + cons` is the main-isolate-charged decision figure.

| Lane | build Δ | hop Δ | cons Δ | NET Δ |
|---|---:|---:|---:|---:|
| 1k × 8 INTEGER **(send)** | −22/−26% | −17/−25% | −48/−49% | −37/−41% |
| 1k × 8 REAL **(send)** | −61/−56% | −55/−37% | −13/−11% | −30/−21% |
| 1.5k × 20 REAL **(send)** | −58/−60% | −82/−46% | −12/−6% | −56/−21% |
| 10k × 8 INTEGER (exit) | −67/−66% | −73/−73% | −52/−48% | −64/−61% |
| 10k × 20 INTEGER (exit) | −62/−63% | −74/−74% | −51/−49% | −63/−62% |
| 10k × 8 REAL (exit) | −88/−90% | −86/−88% | −6/−5% | −58/−63% |
| 10k × 20 REAL (exit) | −90/−91% | −91/−85% | −5/−8% | −67/−56% |
| 10k × (16 REAL + 4 TEXT) (exit) | −85/−86% | −83/−82% | −17/−17% | −56/−57% |

The signs are stable across the order flip, so these are real effects, not
drift. But the mechanism splits into three findings that point in different
directions once mapped back to what production actually does:

**1. The worker-side build win is large and real — but off the main isolate.**
Skipping boxing makes columnar build 60–90% faster, biggest on `REAL` columns
(doubles always box in Dart; a 10k × 20 REAL container builds ~10× faster).
This is genuine, and it survives the sacrifice path (build happens before any
transfer decision). But it is *worker* wall — it shortens the reader round trip
and end-to-end `select()` latency, a secondary metric, not the main-isolate
time resqlite's contract keys on.

**2. The headline transfer win does not reach production where it is largest.**
The `(exit)` lanes show hop improving 73–91% — but those results *sacrifice* in
production, so their transfer is already a zero-copy `Isolate.exit` pointer
handoff, and columnar's `memcpy` competes with free. Where columnar's transfer
win *does* apply — the `(send)` lanes under 32 K slots — the absolute saving is
tens of microseconds (1k × 8 REAL: 31 µs → 14 µs), well below the sub-millisecond
`select()` round-trip floor that [exp 105](105-reader-pool-sizing.md) showed
dominates small reads. This is exactly the "throughput win too small" that
055 *estimated*; the harness now shows *why* — the sacrifice path already
solved the large-transfer case.

**3. One surprise: integer consume is ~2× faster on the main isolate.** `Int64List`
sequential access with no covariant-load barrier beats pointer-chasing a
`List<Object?>` of `Smi`s by ~50% on every integer lane, in both orders. `REAL`
consume, by contrast, is only neutral (−5 to −13%) — columnar must box each
double on access, which nearly cancels the locality gain — but it never
*regresses*, which refutes exp 081's box-on-access fear for the columnar
(as opposed to binary-slab) shape.

**4. Memory is a wash-to-regression, not the clean win 055 hoped for.** RSS
holding 40 live result sets moves inconsistently: −30% on 10k × 20 INTEGER but
+20–25% on 10k × 8 REAL and the mixed lane, +10–14% on the small-int lanes.
`Smi` integers live inline in a `List<Object?>` (tagged pointers, no heap box),
so an `Int64List` column actually costs *more* per cell than the flat list it
replaces; only boxed-double columns save box headers. There is no reliable
memory argument for the rewrite.

## Decision

**Rejected** — do not rewrite the `ResultSet` backing store to columnar typed
arrays.

The one axis that would justify touching resqlite's hottest, most-tested path —
main-isolate time on a realistic result — is not moved by columnar in the
general case. The transfer win it was built on is neutralized by the existing
`Isolate.exit` sacrifice path for large results and sits below the round-trip
floor for small ones; `REAL` consume is neutral; and memory does not improve.
The large build win is real but lands off the main isolate, and a full columnar
`ResultSet` is a multi-layer change (all six `Row`/`ResultSet` access sites, the
stream initial-decode/hash path, the sacrifice slot-count heuristic, and
`RowSchema`) — far more surface than a secondary-metric win warrants. This
completes 055's open assessment with the first real measurement of the typed-array
mechanism, and confirms 081's main-isolate-access caution generalizes: the boxed
flat list is the right default under the current transfer machinery.

**Reopen only if** a workload profile shows **integer-heavy, main-isolate-bound
reads** dominating — the one place columnar showed a real primary-metric signal
(the ~2× `Int64List` consume). That is a *narrow* columnar path (numeric columns
only, and only worthwhile when the consumer scans many integer cells on the main
isolate), not the whole-store rewrite 055 imagined. It is out of budget for this
run — it needs its own design pass for how `Row` dispatches columnar-vs-flat per
column without slowing the text path — and it is recorded as a scoped candidate
in the signal map, backed by this measurement. Do not reopen the broad columnar
rewrite on the transfer or memory arguments; this run closes both.

## Validation

- `dart analyze --fatal-infos benchmark/experiments/columnar_result_transfer.dart`
- AOT-compiled focused A/B, two order-flipped passes (signs stable across the flip)
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/258-columnar-result-store.md`
