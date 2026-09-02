# Experiment 280: who should pack the parameters

**Date:** 2026-09-02
**Status:** Rejected
**Category:** Moonshot
**Direction:** `parameter-encoding-and-binding`
**Archive:** [`archive/exp-280`](https://github.com/danReynolds/resqlite/tree/archive/exp-280)
**Benchmark Run:** none — the runtime prototype is reverted and no code ships
  in `lib/`, `native/` or `hook/`. The decision evidence is the mechanism price
  plus two order-flipped, separate-binary A/B collections in
  [`benchmark/results/2026-09-02T11-20-00Z-exp280-caller-side-param-arena.md`](../benchmark/results/2026-09-02T11-20-00Z-exp280-caller-side-param-arena.md).

## Problem

`db.executeBatch(sql, paramSets)` hands the writer isolate a
`List<List<Object?>>`. For the release suite's Wide Batch Insert shape that is
10,000 inner lists holding 200,000 slots, and the VM copies that whole object
graph across the `SendPort` before the writer has done anything at all. The
writer then walks the rebuilt graph a second time, in `allocateBatchParams`, to
produce the flat native arena SQLite actually binds from.

[Exp 234](234-blob-param-transfer.md) named that main→writer hop "copy (1)" and
removed it for a single large blob (claim 234.1). Nothing has ever measured
what it costs for a whole parameter *matrix*, and the obvious way to remove it
is not a smaller copy but no copy: pack the arena on the isolate that issued
the write and send the writer an address.

**Assumption challenged.** Parameters must cross the writer boundary as a Dart
object graph, and packing them is the writer's job because the writer is where
the native handle lives. Neither half is load-bearing — a `calloc`'d arena is
process memory, and any isolate can fill it.

## Hypothesis

If the issuing isolate packs the matrix and sends `paramsAddress`, then the
graph copy disappears from the write entirely: the caller pays a packing walk
instead of a serialize walk, and the writer pays nothing before it binds. The
work is conserved, one full pass over the parameter data is not.

The bet has a stated risk. The walk the candidate moves lands on the isolate
that called `executeBatch`, which in a Flutter application is the UI isolate,
and resqlite's stated contract is that its work runs "with zero main-isolate
jank". So a wall-time win is necessary and not sufficient: the candidate had to
be judged on main-isolate blocking as well, and a wall win bought with a large
jank regression is a rejection, not a trade to be argued about later.

Predeclared:

- accept only if wall improves on representative batch shapes in both orders
  **and** main-isolate blocking does not get worse on them;
- reject if the wall win exists only by moving blocking onto the caller;
- if some narrow shape wins both, it still has to clear representative
  incidence before it can ship.

## Approach

Two harnesses, both retained.

[`batch_param_transport_price.dart`](../benchmark/experiments/batch_param_transport_price.dart)
prices the boundary before anything is built, in the shape of exp 278's lesson.
A persistent echo isolate receives the matrix and replies with an int, so
`graph-rt − graph-floor` is the graph copy and nothing else; a second lane
times `SendPort.send` alone, which is the serialize half and the half the
sender pays; a third times `allocateBatchParams` on the sending isolate; a
fourth is the public `executeBatch` denominator.

The prototype (`archive/exp-280`, `263ad64`) changes four files. `BatchRequest`
carries `(sql, paramsAddress, paramCount, rowCount)` instead of `paramSets`;
`Writer.executeBatchLocked` calls `allocateBatchParams(paramSets, owned: true)`
before sending; `_handleBatch` reconstructs the pointer and calls new
`executeBatchWriteFromArena` / `executeNestedBatchWriteFromArena` bindings that
free the arena on every path out.

One correctness detail is load-bearing and worth recording even though the
prototype is reverted. `allocateReusableParamStructBuf` hands packs of ≤64 KB
an **isolate-local** scratch buffer, and `freeReusableParamStructBuf` decides
whether to free by comparing against that isolate's own scratch pointer. A
buffer packed on one isolate and freed on another therefore must be owned
memory, or the freeing isolate misses the comparison and frees a buffer the
packing isolate still holds. Hence the `owned: true` flag — and hence the
`small-100-x8` lane, which prices what small batches lose by giving up the
scratch buffer.

[`batch_param_arena_ab.dart`](../benchmark/experiments/batch_param_arena_ab.dart)
is the gate. Each lane reports the awaited `executeBatch` wall and, for the
same call, the longest gap seen by an event-loop probe that reschedules itself
on the event queue — how long the main isolate was unavailable to anything
else. Both arms are separate AOT bundles from separate worktrees, because
exp 249's in-process toggle reported a false −27%.

## Results

Full tables in the
[receipt](../benchmark/results/2026-09-02T11-20-00Z-exp280-caller-side-param-arena.md).

### The boundary is real, and the sender pays for all of it

| Shape | copy µs | send µs | pack µs | e2e µs | copy/e2e | pack/send |
|---|---:|---:|---:|---:|---:|---:|
| 10k × 20 mixed | 1287.0 | 1171.0 | 5760.0 | 22822.0 | 5.6% | 4.92× |
| 10k × 4 ascii | 818.0 | 708.0 | 2802.0 | 8390.0 | 9.7% | 3.96× |
| 10k × 8 int | 773.0 | 764.0 | 618.0 | 4544.0 | 17.0% | 0.81× |
| 100 × 8 mixed | 6.0 | 7.0 | 20.0 | 106.0 | 5.7% | 2.86× |

The parameter graph copy is 5.6–17.0% of a batch write, so it is worth
attacking. But `send` is 91–99% of `copy`: the receiving isolate rebuilds the
graph almost for free, and essentially the entire hop is already paid by the
isolate that issued the write. That single number decides the experiment before
the A/B runs, because it means the candidate is not removing a cost from the
main isolate — it is *replacing* main-isolate serialize work with main-isolate
packing work, and `pack/send` is the exchange rate. For a fixed-width numeric
matrix it is 0.81, for anything holding text it is 4–5×.

### The A/B agrees, in both orders

Candidate against base within the same pass; negative is faster / less blocked.

| Lane | Δ wall p1 | Δ wall p2 | Δ block p1 | Δ block p2 |
|---|---:|---:|---:|---:|
| int-10k-x8 | **−23.6%** | **−21.9%** | **−34.4%** | **−33.3%** |
| ascii-10k-x4 | −13.6% | −13.1% | **+229.3%** | **+253.7%** |
| mixed-10k-x20 | −7.8% | −7.6% | **+371.4%** | **+369.2%** |
| small-100-x8 | −4.9% | −4.1% | +160.0% | +188.9% |
| tx-10k-x8 | −19.4% | −18.8% | −18.6% | −20.4% |

Every lane reproduces to within 1.8 percentage points across the order flip,
and the candidate's blocking medians land on the price harness's `pack` column
while the baseline's land on its `send` column — two independent harnesses
agreeing on the same mechanism.

So the mechanism works exactly as hypothesized. **Wall time improves on every
batch shape measured**, by 4–24%, and the win is largest where the packing is
cheapest. It is also not a transport curiosity: the `tx-10k-x8` lane shows the
nested-batch path inside `db.transaction` behaves the same way.

And on every text-bearing shape the main isolate is blocked 2.3–4.7× longer for
it. A 10k × 20 batch takes the UI isolate from 1.2 ms to 5.7 ms of continuous
unavailability — at 60 fps, from most of a frame to most of three.

### The baseline's jank is smaller but spikier

On `mixed-10k-x20` the baseline's median block is 1213/1214 µs against a
maximum of 12212/4174 µs, while the candidate's median is 5718/5696 µs against
a maximum of 5989/5904 µs. The baseline's graph copy leaves 200,000 freshly
copied objects on the shared GC heap — the mechanism claim 234.1 attributes for
blobs — and its tail is those collections; the candidate allocates one native
arena and produces no heap garbage, so its blocking is larger but flat. This is
a genuine point in the candidate's favour and it does not rescue it: the
median, which is what a UI isolate experiences on the ordinary batch, is
several times worse.

### The one shape that wins both has no incidence

`int-10k-x8` and `tx-10k-x8` — fixed-width numeric matrices — improve wall
*and* blocking, because packing an unboxed integer is cheaper than serializing
the list slot that holds it. That is a real result and it cannot ship. The
repo's own representative batch workloads are the release suite's Batch Insert
lane, which binds `['item_$i', i * 1.5]`, and its Wide Batch Insert lane, which
binds a 20-column mixed row. Both carry text in every row; neither is eligible.
A numeric-only admission would also have to *prove* the matrix is numeric, and
the only sound proof is a full scan — while a row-0 speculation is exactly the
shape [exp 226](226-one-pass-numeric-batch.md) measured regressing a
final-row TEXT fallback.

## Decision

**Rejected.** The assumption is false — parameters do not have to cross as a
Dart object graph, and not crossing as one is 4–24% faster end to end, in both
orders, on every batch shape measured. The direction is closed anyway, because
of *where* the saving comes from. The parameter hop is already paid almost
entirely by the sending isolate, so relocating the packing walk does not remove
main-isolate work; it exchanges serialize for pack at 4–5× on any matrix
holding text. resqlite exists to keep that isolate free, and buying 8% of batch
wall with 3.7× the UI-isolate blocking is the wrong side of its own trade.

This is not a "below the noise floor" rejection, so the prototype is worth
keeping: `archive/exp-280` holds a working implementation, including the
cross-isolate ownership fix that any future version needs.

### Reopen conditions

- A representative workload — a downstream AOT trace, not an assertion — where
  all-numeric `executeBatch` matrices are a material share of batch writes.
  The numeric case wins both metrics today; only its eligibility is missing.
- A packer that runs off both the writer and the caller. If the arena could be
  filled by a third isolate, or incrementally by the writer as rows arrive, the
  wall win survives without the jank; nothing in the current design needs the
  packing and the binding to happen on the same isolate.
- A Dart transfer primitive that moves a `List<List<Object?>>` by ownership
  rather than by copy. That removes `send` without adding `pack`, which is the
  only version of this idea that is free.

Do **not** reopen it as a shape-keyed default. The eligibility test is a scan,
the misprediction lands on the UI isolate, and the cost of being wrong is
measured above.

## Future Notes

- The price harness generalizes past this candidate: `send ≈ copy` means *any*
  proposal that changes what crosses the writer boundary is trading
  main-isolate time, and can be costed in ten minutes before it is built.
- `block` — an event-loop probe's largest gap across an awaited call — is the
  metric this library's contract is actually about, and no release-suite lane
  reports it. Any future candidate that moves work between isolates should be
  judged on it, not on wall time alone.

## Test plan

- [x] `dart analyze --fatal-infos` on the prototype and both harnesses
- [x] `dart test -j 1` on the prototype tree — 503/503 passed, covering batch
      writes, nested/transaction batches, and batch error paths
- [x] AOT price harness, 11 samples after 3 warmup, one process
- [x] two order-flipped A/B collections from separate worktrees and separate
      AOT bundles, 15 samples after 3 warmup per lane
- [x] prototype archived at `archive/exp-280`; publication branch restores
      `lib/` to `origin/main`
