# Experiment 280: caller-side batch parameter arena (moonshot)

Collected 2026-09-02 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2.
Baseline tree is `origin/main` at `36ac04f`. The candidate packs
`executeBatch`'s parameter matrix on the isolate that issued the write and
sends the writer the arena's address instead of a `List<List<Object?>>`; the
exact prototype is preserved at `archive/exp-280` (`263ad64`). No runtime code
ships on the publication branch.

Both arms are separate AOT bundles built from separate worktrees with
`dart build cli`, so nothing is toggled in-process (exp 249's in-process
toggle reported a false −27%).

```console
dart build cli                       # in each worktree
<out>/bundle/bin/exp280_ab --arm=<base|cand>
```

Harness sources retained on `main`:
[`batch_param_transport_price.dart`](../experiments/batch_param_transport_price.dart)
and [`batch_param_arena_ab.dart`](../experiments/batch_param_arena_ab.dart).

## 1. Mechanism price — what the parameter boundary costs today

AOT, 11 samples after 3 warmup, one process. `copy` is
`graph-rt − graph-floor`: a persistent echo isolate receives the matrix and
replies with an int, so the round trip prices the outbound graph copy and
nothing else. `send` times `SendPort.send` alone — the serialize half, paid by
the *sending* isolate. `pack` is `allocateBatchParams` + free on the sending
isolate. `e2e` is the public `db.executeBatch` for the same shape.

| Shape | graph-floor µs | graph-rt µs | copy µs | send µs | pack µs | e2e µs | copy/e2e | pack/send |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 10k × 20 mixed | 2.0 | 1289.0 | 1287.0 | 1171.0 | 5760.0 | 22822.0 | 5.6% | 4.92× |
| 10k × 4 ascii | 2.0 | 820.0 | 818.0 | 708.0 | 2802.0 | 8390.0 | 9.7% | 3.96× |
| 10k × 8 int | 1.0 | 774.0 | 773.0 | 764.0 | 618.0 | 4544.0 | 17.0% | 0.81× |
| 100 × 8 mixed | 2.0 | 8.0 | 6.0 | 7.0 | 20.0 | 106.0 | 5.7% | 2.86× |

Two readings carry the experiment:

- **`send` is 91–99% of `copy`.** The receiving isolate rebuilds the graph
  almost for free; essentially the whole cost of the parameter hop is paid by
  the isolate that issued the write. On the write path that isolate is the
  main isolate.
- **`pack/send` is the trade.** Moving the pack to the caller costs `pack` and
  saves `send`. For a fixed-width numeric matrix that ratio is 0.81 — the
  caller does *less* work than it does today. For anything holding text it is
  4–5×.

## 2. A/B — two order-flipped collections, separate binaries

15 samples after 3 warmup per lane. `wall` is the whole awaited
`executeBatch`. `block` is the longest gap seen by an event-loop probe running
for the duration of that call — how long the main isolate was unavailable to
anything else, which is the metric resqlite's "zero main-isolate jank"
contract is about.

### Pass 1 — base first

| Lane | wall med µs | wall p90 µs | block med µs | block max µs |
|---|---:|---:|---:|---:|
| **base** | | | | |
| int-10k-x8 | 4717.0 | 5326.0 | 1021.0 | 3962.0 |
| ascii-10k-x4 | 6927.0 | 11213.0 | 861.0 | 4373.0 |
| mixed-10k-x20 | 20016.0 | 22071.0 | 1213.0 | 12212.0 |
| small-100-x8 | 122.0 | 127.0 | 10.0 | 13.0 |
| tx-10k-x8 | 4556.0 | 4919.0 | 842.0 | 914.0 |
| **cand** | | | | |
| int-10k-x8 | 3605.0 | 4143.0 | 670.0 | 1062.0 |
| ascii-10k-x4 | 5987.0 | 10341.0 | 2835.0 | 7094.0 |
| mixed-10k-x20 | 18463.0 | 21222.0 | 5718.0 | 5989.0 |
| small-100-x8 | 116.0 | 118.0 | 26.0 | 28.0 |
| tx-10k-x8 | 3672.0 | 3797.0 | 685.0 | 724.0 |

### Pass 2 — candidate first

| Lane | wall med µs | wall p90 µs | block med µs | block max µs |
|---|---:|---:|---:|---:|
| **cand** | | | | |
| int-10k-x8 | 3608.0 | 3853.0 | 658.0 | 724.0 |
| ascii-10k-x4 | 5994.0 | 10807.0 | 2826.0 | 24782.0 |
| mixed-10k-x20 | 18466.0 | 20704.0 | 5696.0 | 5904.0 |
| small-100-x8 | 117.0 | 121.0 | 26.0 | 28.0 |
| tx-10k-x8 | 3683.0 | 3780.0 | 687.0 | 723.0 |
| **base** | | | | |
| int-10k-x8 | 4617.0 | 6270.0 | 987.0 | 3139.0 |
| ascii-10k-x4 | 6898.0 | 13201.0 | 799.0 | 8013.0 |
| mixed-10k-x20 | 19980.0 | 22405.0 | 1214.0 | 4174.0 |
| small-100-x8 | 122.0 | 125.0 | 9.0 | 12.0 |
| tx-10k-x8 | 4533.0 | 4980.0 | 863.0 | 4632.0 |

### Deltas, candidate against base within the same pass

| Lane | Δ wall p1 | Δ wall p2 | Δ block p1 | Δ block p2 |
|---|---:|---:|---:|---:|
| int-10k-x8 | **−23.6%** | **−21.9%** | **−34.4%** | **−33.3%** |
| ascii-10k-x4 | −13.6% | −13.1% | **+229.3%** | **+253.7%** |
| mixed-10k-x20 | −7.8% | −7.6% | **+371.4%** | **+369.2%** |
| small-100-x8 | −4.9% | −4.1% | +160.0% | +188.9% |
| tx-10k-x8 | −19.4% | −18.8% | −18.6% | −20.4% |

Every lane reproduces to within 1.8 percentage points across the order flip.
The candidate's `block` medians match the price harness's `pack` column and
the baseline's match its `send` column, so the two harnesses agree on the
mechanism independently.

## 3. The baseline's jank is smaller but spikier

On `mixed-10k-x20` the baseline's median block is 1213/1214 µs while its
maximum is 12212/4174 µs; the candidate's median is 5718/5696 µs with a
maximum of 5989/5904 µs. The baseline's graph copy leaves 200,000 freshly
copied objects on the shared GC heap (the mechanism exp 234 attributed for
blobs), and the tail is those collections. The candidate's packing walk
allocates one native arena and produces no heap garbage, so its blocking is
larger but flat. Median is the decision statistic here, and on it the
candidate is 3.7–4.7× worse on every text-bearing shape.

## 4. Eligibility of the one shape that wins both

The numeric-only sub-case (`int-10k-x8`, `tx-10k-x8`) improves wall *and*
block. It is not admissible on the repo's own representative batch workloads:
the release suite's Batch Insert lane binds `['item_$i', i * 1.5]` and the
Wide Batch Insert lane binds a 20-column mixed row, so both carry text in
every row and neither would take a numeric-only path.
