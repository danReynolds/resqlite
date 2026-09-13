# Experiment 289: Each reader's first post-commit read starts cold

**Date:** 2026-09-11 through 2026-09-13
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`, `sqlite-version-and-build-config`
**Benchmark Run:** [`benchmark/results/2026-09-11T08-27-49-exp289-warm-connection-reruns.md`](../benchmark/results/2026-09-11T08-27-49-exp289-warm-connection-reruns.md)
— five-sample headline sweep of the archived prototype; the later safety guard
rejects that runtime independently
**Archive:** [`archive/exp-289`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-289)

## Problem

A reactive stream is invalidated because a commit preceded it. That is the
engine's premise: a write lands, the reply names dirtied tables, and matching
streams query again. Earlier experiments priced the isolate hop (claim 282.2),
the hash pass (claim 283.2), and rerun messaging (claim 287.1), but timed SQLite
on a connection that had not just watched another connection commit.

In WAL mode that misses a first-use transition. When a connection begins its
first read transaction after the shared wal-index header differs from its
cached header, SQLite calls `pager_reset`: it discards the connection's page
cache and, when `mmap_size` is enabled, unmaps the database file. Later reads
under the same header remain warm; multiple commits before the connection
reads collapse into one reset, and an ordinary read may pay it before a stream
rerun. A one-reader immediate rerun reliably exercises the cold transition.
In fan-out, the tax occurs at most once per participating reader for that WAL
generation, so its incidence depends on commit and reader-dispatch scheduling.
The writer connection stays warm after its own commit because it wrote the
header it compares against.

## Hypothesis

**Assumption challenged:** a rerun is a read, so it belongs on the reader pool.

The prediction was that the post-commit tax on a reader would be a multiple of
a small query's warm cost and that the writer would avoid most of it. Two
candidates followed:

- **A:** disable `mmap` on reader connections if remapping dominates the tax.
- **B:** run one rerun on the writer connection when the writer appears idle,
  using its warm cache.

Candidate B's predeclared kill condition was strict: an emission-latency win
that delays the next write is rejected, not accepted as a trade-off.

## Approach

`benchmark/experiments/rerun_snapshot_tax.dart` opens one native database with
two readers, seeds and checkpoints it, and times the same
`resqlite_query_hash` statement warm, after another connection commits, and on
the writer after its own commit. It also applies `mmap_size = 0` through the
normal connection setup path.

`benchmark/experiments/reader_snapshot_tax_ab.dart` then drives the public API
through stream-shaped point, page, transaction, fan-out, and write-burst lanes.
The archived Candidate B added a writer `RerunRequest`, offered at most one
entry per flush round when the writer queues appeared idle. It admitted a
stream initially by row count and later by its prior measured writer time.

Review found that this policy did not create a reservation. A new write could
arrive after the point-in-time idle check and queue behind the complete
synchronous SQLite statement. The first two reruns were admitted with no
timing evidence, later eligibility used the smaller of two historical samples,
and the stopwatch excluded statement acquisition. None of those signals bound
arbitrary SQL work, consistent with claim 269.2.

`benchmark/experiments/writer_rerun_opaque_guard.dart` makes that gap explicit.
It uses a one-row stream containing `length(randomblob(16 MiB))`, invalidates
it, then enters another write on the next event turn. The row shape passes the
candidate's first-use gate while the built-in function performs tens of
milliseconds of opaque work inside SQLite.

## Results

### 1. The first-use post-commit tax is real

AOT, one hash pass, microseconds (median of 15 samples by 300 iterations):

| Shape | Reader warm | Reader after commit | Writer after own commit |
|---|---:|---:|---:|
| point, 1 row x 3 | 1.34 | 3.53-5.64 | 2.22 |
| partition, 14 rows x 2 | 2.68 | 7.89-8.33 | 3.59 |
| index page, 50 rows x 3 | 9.68 | 30.95-31.59 | 10.75 |
| scan, 1,000 rows x 2 | 38.11 | 45.92-46.48 | 39.26 |
| full scan, 10,000 rows x 4 | 675.9 | 698.8-698.9 | 682.6 |

A 50-row index page costs **3.2 times** its warm price on a reader after a
commit and 1.1 times on the writer. The tax follows pages touched more than
rows returned: it is about 22 us on the scattered index page, about 8 us on a
sequential 1,000-row scan, and disappears inside a 676 us full scan.

### 2. Candidate A: rejected

Turning reader `mmap` off halves the tax on one- and two-page shapes but makes
the fifty-page shape worse because those pages return through `pread` and a
copy instead of faults on an existing mapping.

| Lane | 256 MB mmap | mmap off | Delta |
|---|---:|---:|---:|
| point after write | 13.54 us | 9.88-10.21 us | -26% |
| 50-row page after write | 39.54 us | 51.92-52.33 us | +32% |
| stream latency, 50-row page | 73.00 us | 82.31-85.04 us | +13-17% |

The existing reader mapping stays.

### 3. Candidate B: fast on its target

Four order-flipped AOT passes reproduced the warm-cache mechanism:

| Lane | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| changed 50-row stream, write to emission | 74.1-76.8 us | 51.2-51.7 us | -31% to -33% |
| changed one-row stream | 36.3-38.2 us | 29.7-32.3 us | -11% to -22% |
| three-write transaction to emission | 98.9-114.9 us | 79.6-89.3 us | -19% to -24% |
| 200 awaited writes with one stream | 3.38-3.61 ms | 3.36-3.44 ms | -5% to +1% |
| 50 streams x 200 writes | 7.10-7.29 ms | 6.76-7.48 ms | -7% to +5% |

The focused lanes proved the mechanism: a small changed stream can reach its
subscriber roughly a third sooner on the warm writer. They did not prove the
no-write-delay invariant because their SQL cost was small and predictable.

The archived candidate's five-repeat headline sweep reported 6 wins, 1
regression, and 162 neutral lanes against the exp 266 anchor. The exact
candidate artifact is retained as mechanism and guard evidence; it does not
override the later safety rejection.

### 4. The safety guard rejects Candidate B

The durable receipt is
[`benchmark/results/2026-09-13T10-13-28Z-exp289-writer-rerun-opaque-guard.md`](../benchmark/results/2026-09-13T10-13-28Z-exp289-writer-rerun-opaque-guard.md).

| Runtime | Min | Median | Max |
|---|---:|---:|---:|
| current main `90619dc` | 74 us | 82 us | 26,031 us |
| archived candidate `79c0646` | 51,206 us | 51,958 us | 53,589 us |

All seven candidate samples serialized the opaque rerun ahead of the next
write. The fastest candidate wait was 51.2 ms, more than **800 times** the
declared 64 us ceiling. Current main returned six of seven writes in 74-95 us;
its one 26 ms outlier is scheduling or CPU contention, not a policy that puts
the complete rerun in the writer FIFO.

The query changes on every evaluation, so the candidate runs both the hash
pass and the decode pass before servicing the queued write. A row cap cannot
see that work, a historical minimum cannot bound a future execution, and an
idle check cannot stop a write from arriving after it. Candidate B therefore
fails its own kill condition even though its target latency gains reproduce.

## Decision

**Rejected.** Candidate A loses the representative index-page shape. Candidate
B improves emission latency but cannot guarantee that it leaves writes
undelayed; the adversarial one-row query exceeded its claimed bound by more
than 800 times. The runtime, tests, and architecture text are reverted. The
exact prototype is preserved at `archive/exp-289`; the focused probes, public
A/B harness, opaque-work guard, and research record remain.

The cold-cache discovery survives the rejection: the first read on each
reader whose cached WAL header is stale starts cold, while the writer stays
warm after its own commit. Later reads on that reader under the same header do
not reset again, so fan-out prevalence is a scheduling question this
experiment does not claim to measure. The lifecycle fact is useful for future
designs, but it does not make the writer a safe general-purpose reader.

Reopen writer-side reruns only if a write arriving after dispatch can take
priority through real preemption, cancellation, or yielding inside SQLite, or
if the rerun uses a non-serializing connection or path. A reservation alone
does not help once synchronous rerun work has started. A deliberately
restricted API is a separate design: it must expose an independently bounded
write-delay contract and clear the near-frozen public-API gate. Another row
threshold, historical-time heuristic, opcode counter, queue-depth check, or
larger writer-side budget is closed by this experiment and claim 269.2.

## Future Notes

- Run `rerun_snapshot_tax.dart` before changing reader `mmap_size`, cache size,
  or checkpoint policy; the checkpoint location and remap/page-read trade are
  coupled.
- Keep `writer_rerun_opaque_guard.dart` in every future proposal that lets
  reads or reruns occupy the writer. Small-query burst guards do not cover the
  unpriced first-admission race it exposes. A future history-based proposal
  must also add a slow-after-fast mode; old timings still cannot prove a hard
  bound on later opaque work.
- The first plain `select()` assigned to a reader with a stale WAL header pays
  the same cold-reader tax, but routing it to the writer has the same
  unbounded-work problem and no cached digest to reduce the work.
- Do not take the archived candidate's named larger writer-side rerun budget as
  a follow-up. The issue is not the size of the budget; it is that admission is
  predictive and cannot preempt or yield to a later write.
