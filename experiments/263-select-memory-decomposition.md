# Experiment 263: The 60× memory ratio was mostly floor

**Date:** 2026-08-05
**Status:** Accepted
**Category:** Measurement
**Direction:** `result-transfer-shape`, `measurement-system`
**Benchmark Run:** none — focused memory decomposition, no release run; harness
  [`benchmark/experiments/select_memory_decomposition.dart`](../benchmark/experiments/select_memory_decomposition.dart),
  full tables in
  [`benchmark/results/2026-08-05T15-30-00Z-exp263-select-memory-decomposition.md`](../benchmark/results/2026-08-05T15-30-00Z-exp263-select-memory-decomposition.md)

## Problem

[Exp 261](261-focused-memory-guard.md) measured the repo's canonical 6-column
product row at 10,000 rows peaking at ~95 MB while the table holds roughly
1.5 MB of data, and recorded the ~60× ratio as claim 261.4 — "never decomposed",
with `List<Map<String, Object?>>` overhead named as a partial explanation and
exps 008/032's lazy and facade shapes flagged as having been judged on wall time
rather than on this.

A 60× representation overhead would be a serious finding. It would put the
result shape squarely back on the table despite exps 081, 251 and 258 all having
closed storage rewrites on their own evidence.

It is not one. The ratio was an artifact of what was being divided by what.

## Hypothesis and decision rule

Process RSS cannot resolve heap composition — exp 261 established that, and an
AOT binary has no VM service to ask. But it can separate *fixed* from *marginal*
cost, if the only thing that varies is how much is read. Hold seeding constant at
20,000 rows and vary only the timed statement's `LIMIT`: the slope against row
count is the per-row marginal, the intercept is everything that does not scale.

Declared before measuring:

- If the marginal is near the theoretical minimum for the row shape (~280 B/row:
  four `OneByteString`s, one boxed double, six pointer slots, one `Row` facade),
  the ratio is fixed cost and the premise is refuted — close claim 261.4.
- If the marginal is several times that, there is real per-row waste and it
  becomes an implementation candidate.

## Approach

Three modes over the same rows: `select` (the full Dart object graph, with a
cell read from every row so the lazy `Row` facade actually materializes),
`bytes` (`selectBytes`, serialized in C with no Dart object graph), and `id`
(the INTEGER primary key alone — structure without payload, since Smis live
inline). Plus an `open` lane that opens the database, spawns the pool with one
trivial read, and reads nothing else.

**The measurement configuration turned out to be the first finding.** Run the
way exp 261 ran it — 5 warmup plus 21 timed reads — the 10,000-row lane reports
99 MB. RSS never falls, so 26 reads accumulate up to 26 results' worth of
retained garbage, and the number describes a process doing repeated reads rather
than the cost of a result. Run with one read, held live across the sample, the
same lane reports **36.1 MB**. Both are honest; only the second answers the
question the ratio was posed against.

## Results

Single live result, `maxRss`, one process per lane:

| mode | marginal (1k→10k) | vs payload |
|---|---:|---:|
| `select` | 396 B/row | **2.9×** |
| `bytes` | 676 B/row | 4.9× |
| `id` | 140 B/row | — |

The denominator is 137.8 B/row of cell content — the UTF-8 length of each TEXT
cell plus 8 bytes per numeric. It is exact for this fixture (every generated cell
is ASCII, and the harness asserts it, so code units and UTF-8 bytes coincide),
but it is deliberately *not* SQLite's on-disk record size, which stores integers
as varints and carries a per-row header. It is the bytes of actual content the
row represents, which is the thing a representation overhead should be measured
against.

And the floor, which is where the 60× actually lived:

| stage | maxRss |
|---|---:|
| bare AOT Dart process | 14.0 MB |
| + resqlite open, pool spawned | 20.5 MB |
| + seeding 20,000 rows | 32.8 MB |
| + one live 10,000-row result | 36.1 MB |

**The result is the smallest term.** A 10,000-row `select()` holds ~3.6 MB above
a floor of ~32.8 MB, of which 14 MB is the Dart VM before resqlite exists at all,
6.5 MB is resqlite's open connections and isolate pool, and ~12 MB is retained
seeding. Dividing a peak that is ~90% fixed-and-setup cost by the payload is what
produced 60×.

At 396 B/row against 137.8 B of cell content, `select()` carries a **2.9×**
representation overhead — and against the ~280 B/row theoretical minimum for this
row shape it is within about 1.4×. That gap is page granularity and heap slack,
not a structure worth rewriting.

Two secondary findings worth keeping:

- **`selectBytes` costs more memory per row than `select`, not less** — 676 B/row
  against 396. It avoids Dart *objects*, which is what it has always claimed, but
  JSON re-encodes every column name on every row and quotes and escapes every
  value, so the bytes are larger than the object graph they replace. Anyone
  reaching for `selectBytes` to reduce memory rather than allocation churn is
  reaching for the wrong tool.
- **The sacrifice path shows up as sub-linearity, not as a step.** `select`'s
  marginal drops from 396 B/row (1k→10k) to 337 (1k→20k) because results above
  `sacrificeSlotThreshold` return via `Isolate.exit`, ending the worker and
  returning its heap. A memory comparison that spans that threshold is measuring
  transport as much as representation (the exp 258 trap, in its memory form).

## Outcome

**Accepted as measurement; premise refuted.** Claim 261.4's ~60× is closed: the
marginal cost of a `select()` result is 2.9× its payload, near the floor of what
a `List<Map<String, Object?>>` of Dart strings can achieve, and the ratio it was
derived from was dominated by a fixed floor and by retained garbage from repeated
reads.

Nothing here reopens a result-shape rewrite; it removes the one piece of evidence
that might have. If resqlite's memory footprint is ever a target, the numbers say
where to look, and it is not the row representation: 20.5 MB is resident before a
single row is read, and the isolate pool is most of resqlite's share of it. Exp
105 already established that pool size is throughput-critical, so that is a
trade, not a free win — but it is the term that dominates every small and
medium read.

Would reopen the representation question only for a workload holding many result
sets alive at once, where the marginal rather than the floor dominates — which is
the opposite of the read-and-discard shape everything here measures.

## Test plan

- `dart analyze --fatal-infos` on the harness — clean
- Three runs per key lane, isolated processes: `open` 20.5/20.5/20.5,
  `select-1000` 32.8/32.9/32.8, `select-10000` 36.8/36.4/36.8
- Both measurement configurations run over the full sweep, with the contrast
  between them recorded rather than one silently chosen
