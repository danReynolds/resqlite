# Experiment 289: every rerun starts cold

**Date:** 2026-09-11
**Status:** Accepted
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`, `sqlite-version-and-build-config`
**Benchmark Run:** [`benchmark/results/2026-09-11T08-27-49-exp289-warm-connection-reruns.md`](../benchmark/results/2026-09-11T08-27-49-exp289-warm-connection-reruns.md) — the headline release sweep from the committed tree with the regression and memory gates on; the fourth of four sweeps, the first three of which are dispositioned in Results §5

## Problem

A reactive stream is re-run because a commit preceded it. That is the whole
premise of the engine: a write lands, the writer's reply names the dirtied
tables, the stream engine re-queries the streams that depend on them. Two
hundred and eighty-eight experiments have priced what happens *around* that
rerun — the isolate hop (claim 282.2, 3.27 µs), the hash pass (claim 283.2,
4.54 µs for 100 rows × 2 columns), the messaging (claim 287.1, not the
constraint) — and every one of them measured the rerun's SQLite work on a
connection that had not just watched another connection commit.

In WAL mode that is not the connection a rerun ever runs on. SQLite's
`pagerBeginReadTransaction` compares the wal-index header a connection last
read against the current one, and when they differ it calls `pager_reset`: the
connection's entire page cache is discarded, and if `mmap_size` is set the
database file is unmapped as well (`sqlite3OsUnfetch(fd, 0, 0)`, which is
`unixUnmapfile`). resqlite's reader pool is four such connections, and by
construction every stream rerun is the first statement one of them runs after a
commit on the writer. So every rerun begins by re-reading every page it
touches, and — with the 256 MB `mmap_size` that has been in `open_connection`
since 0.1.0 — by remapping the file first. The writer connection is the one
exception: it wrote the header itself, so its cache survives its own commits.

Nothing in the repo had measured this. [Exp 026](026-db-status-probe.md) read
page-cache hit rates of 99.9–100% and closed the page-cache direction, but its
four workloads were reads with no interleaved commits, which is the one shape
in which the reset never fires.

## Hypothesis

**Assumption challenged: that a stream rerun is a read, so it belongs on the
reader pool, and that a reader connection's configuration makes it a warm,
read-optimised engine whose cost for a rerun is the query.** Neither half holds
after a commit. The rerun's SQLite cost is the query *plus* a cache reset and a
page-by-page re-read, and the only connection in the process that skips both is
the writer's.

The prediction, made before the probe ran: on stream-shaped queries the
post-commit tax on a reader is a multiple of the query's own cost, the same
query on the writer connection after its own commit costs about what a warm
run costs, and the tax has an `mmap` term (a `munmap`/`mmap` pair per rerun)
that a reader could avoid by not mapping the file.

Two candidates follow from that, cheapest first:

- **A — `PRAGMA mmap_size = 0` on reader connections.** One line in
  `open_connection`, if the `mmap` term dominates the tax.
- **B — run the rerun on the writer connection when the writer is idle.** A
  new writer request that hashes and conditionally decodes on the writer's
  warm cache. The risk it carries is serialisation: a rerun on the writer runs
  ahead of the next write, so a write that arrives during it waits.

Predeclared: the target lanes are write-to-emission latency on stream-shaped
queries; the guards are sequential and concurrent write bursts with streams
open, which must stay inside the collection's noise, and `write-only`. A
candidate that improves latency by delaying the next write is rejected, not
traded.

## Approach

### The probe

[`benchmark/experiments/rerun_snapshot_tax.dart`](../benchmark/experiments/rerun_snapshot_tax.dart)
opens one `resqlite_db` with two readers, seeds a table, checkpoints so the
base pages live in the main file (the shape an application reads: a
checkpointed base plus the few WAL frames each write adds), acquires the same
statement on reader 0 and on the writer, and times one hash pass
(`resqlite_query_hash`, the unchanged-rerun cost) with no isolates and no
messages. The write that precedes it in the `after-*` lanes runs outside the
stopwatch. `--reader-mmap=0` applies the PRAGMA through the same connection
setup path extensions use.

### Candidate B

`RerunRequest` in `write_worker.dart` runs exactly the reader pool's
`SelectIfChangedRequest` on the writer connection: `resqlite_query_hash`, and
`decodeQuery` only when the hash or row count moved, with the stream's own last
row count as the decode hint. It is declined (and the engine falls back to the
pool) if the writer is inside a transaction, so a rerun can never read
uncommitted rows; that branch is defensive, because the main isolate never
sends one while a transaction holds the writer lock, and a transaction opened
afterwards is queued behind the rerun on the writer's FIFO port.

`StreamEngine._flushQueue` offers one eligible entry to the writer per round
and dispatches the rest to the pool as before. Eligible means a last result of
≤ 256 rows *and* a measured writer-side time of ≤ 64 µs for the entry's own
previous warm reruns — the writer reports the wall of every rerun it runs, and
the entry keeps the smaller of its last two, ignoring the first, which
prepares the statement on the writer connection and costs several times the
steady state. A rerun on the writer runs ahead of the next write, so the time
it holds the writer is what that write may wait; rows bound the first offer
and the entry's own measurement bounds every later one, because rows say
nothing about bytes (§5 is the lane that showed this). *When* the engine asks
is the other load-bearing part. Writer replies resolve `sync` completers, so a caller
awaiting `db.execute()` runs its continuation inside the reply chain, before
the stream engine's flush returns to the event loop; but `Database.execute`
re-enters the writer only after one `await _runtime` hop, so a write the
caller issues next is not yet visible in the writer's queues when the flush
runs. Two things close that:

- `Database` counts writes from their public entry, before the first `await`,
  and the writer is offered nothing while the count is non-zero.
- A flush that comes from a write's reply chain holds its candidate entry and
  decides in a microtask, after the caller's continuation has run. A flush that
  comes from a rerun completion has no such caller and dispatches at once.

Three designs were tried first and are reported below because each measures a
hazard the shipped one avoids: a `Timer.run` deferral (correct ordering, 2.5 µs
per timer), a microtask deferral without the caller-side count (idle misread
on every sequential write), and a rows-only eligibility cap (a 256-row × 4 KB
stream holding the writer for hundreds of microseconds ahead of the next
write, caught by the headline release run's regression gate).

No public API change: `WarmRerunner` and `attachWarmRerunner` live in
`stream_engine.dart` but `lib/resqlite.dart` exports `StreamEngine` alone.

### The gate

[`benchmark/experiments/reader_snapshot_tax_ab.dart`](../benchmark/experiments/reader_snapshot_tax_ab.dart)
drives the public API: 10,000 rows in 200 owners of 50, an index on `owner_id`,
checkpointed after seeding. Latency lanes time one write to the emission it
causes; burst lanes time 200 awaited writes with one or fifty streams open;
`*-after-write` lanes time a plain `select()` after an unrelated commit. One
AOT bundle per arm (`dart build cli`, the candidate gated behind a const that
was removed before merge), one process per arm per pass, arm order flipped
between passes, 400 iterations per latency lane.

## Results

### 1. The tax is real and it is most of a small rerun

AOT, one hash pass, microseconds (median of 15 samples × 300 iterations).
`after-noise` commits to a different table between passes; `after-items` to
the queried one. The shipped `mmap_size` (256 MB) on the left, `--reader-mmap=0`
on the right.

| shape | reader warm | reader after commit | writer after own commit | reader after commit, mmap off |
|---|---:|---:|---:|---:|
| point, 1 row × 3 (100-row table) | 1.34 | 5.64 / 3.53 | 2.22 | 3.28 / 3.31 |
| partition, 14 × 2 by index (100 rows) | 2.68 | 7.89 / 8.33 | 3.59 | 5.15 / 5.21 |
| page, 50 × 3 by index (10,000 rows) | 9.68 | 30.95 / 31.59 | 10.75 | 42.66 / 42.84 |
| scan, 1,000 × 2 (10,000 rows) | 38.11 | 45.92 / 46.48 | 39.26 | 46.21 / 46.29 |
| full, 10,000 × 4 | 675.9 | 698.8 / 698.9 | 682.6 | 726.5 / 725.3 |

A 50-row index page — the shape of a feed, a conversation, a filtered list —
costs **3.2× on a reader after a commit** what it costs warm, and the same
statement on the writer after its own commit costs 1.1×. A point read is 2.6–4.2×.
The tax is per page touched, not per row: it is ~22 µs on the 50-row page whose
rows sit 200 apart (about fifty leaf pages) and ~8 µs on the 1,000-row
sequential scan (about seventeen), and it disappears into the noise of a
675 µs full scan. The writer pays about 1 µs for the same transition, which is
the read-mark update every first reader after a commit makes and not a cache
cost.

The `mmap` term is there, and it is not the story. Turning it off halves the
tax on the one- and two-page shapes (a `munmap`/`mmap` pair is ~2–3 µs) and
**raises it by a third on the fifty-page shape**, because every page then comes
back through `pread` and a copy instead of a fault on an existing mapping.

### 2. Candidate A: rejected in one pass

The same trade end to end, on the baseline bundle with `--mmap=readers`:

| lane | 256 MB | mmap off | Δ |
|---|---:|---:|---:|
| point-after-write | 13.54 | 10.21 / 9.88 | **−26%** |
| page-after-write | 39.54 | 52.33 / 51.92 | **+32%** |
| stream-latency (50-row page) | 73.00 | 82.31 / 85.04 | +13–17% |
| scan-after-write | 72.46 | 73.60 / 72.04 | 0 |
| large-after-write | 1244 | 1290 / 1279 | +3% |

Point reads win a quarter and every index-driven page loses a third. The
mapping stays. Exps 016 and 021 chose these pragmas on read-only lanes; this is
the first measurement of them under interleaved commits, and the choice holds.

### 3. Candidate B: the latency lanes move by the tax, the guards do not

Shipped build, four passes, two in each arm order (candidate first in p19–p20,
baseline first in p21–p22); the burst guards were then repeated four more
times at 40 samples each. Microseconds unless marked.

| lane | base | candidate | Δ per pass |
|---|---:|---:|---|
| **stream-latency** (50-row page, write → emit) | 74.1 / 75.3 / 74.9 / 76.8 | 51.3 / 51.4 / 51.7 / 51.2 | **−31 / −32 / −31 / −33%** |
| **stream-latency-1row** | 37.9 / 38.2 / 36.3 / 36.3 | 29.8 / 29.7 / 30.3 / 32.3 | **−21 / −22 / −16 / −11%** |
| **tx-latency** (BEGIN, 3 writes, COMMIT → emit) | 112.1 / 114.9 / 98.9 / 100.6 | 89.3 / 87.4 / 79.6 / 80.3 | **−20 / −24 / −19 / −20%** |
| unchanged-fanout (1 canary + 10 unchanged) | 226 / 207 | 201 / 195 | −11 / −6% |
| burst-seq-stream, ms (200 awaited writes, 1 stream; 40 samples) | 3.42 / 3.61 / 3.39 / 3.38 | 3.44 / 3.42 / 3.36 / 3.41 | +1 / −5 / −1 / +1% |
| many-streams-burst, ms (50 streams, 200 writes; 40 samples) | 7.10 / 7.10 / 7.29 / 7.14 | 6.83 / 6.86 / 6.76 / 7.48 | −4 / −3 / −7 / +5% |
| burst-concurrent, ms (100 concurrent writes) | 0.86 / 0.88 | 0.88 / 0.88 | +2 / 0% |
| write-only | 17.2 / 17.1 | 18.0 / 17.5 | +5 / +2% |
| point-after-write (plain `select`, control) | 13.7 / 13.8 | 14.0 / 13.5 | +2 / −2% |
| page-after-write (control) | 42.0 / 41.0 | 40.8 / 39.5 | −3 / −4% |

A write that changes a 50-row list reaches the subscriber **a third sooner**,
and the saving is the tax from §1: 75 → 51 µs is 24 µs, against 31.6 − 10.8 =
20.8 µs of cache reset plus the difference between a hop to a parked reader and
a reply from the writer that is already awake. The one-row stream saves 6–8 µs
of its 37, and a three-statement transaction saves ~20 µs of its ~100. The
eleven-stream fan-out moves by one warm rerun's worth, which is what the design
gives it: the writer takes one member per round and the pool the rest.

The guards are flat. The sequential burst — 200 awaited writes each changing an
open stream, the shape in which a rerun on the writer would sit ahead of the
next write — reads within ±5% in all four 40-sample passes; a first 20-sample
pass had read +21% on one sample-starved median and is why the guard was
repeated. `write-only` and the plain `select()` controls do not move.
`point-warm`, whose code is byte-identical in both arms, read +0.3–0.4 µs on
every candidate binary in the earlier collections, the per-binary layout
offset claim 259.4 describes.

The same table was collected on the rows-only-cap build before the release
gate fired on it (§4), four passes: −34 / −34 / −33 / −32% on stream-latency,
−20% on the one-row stream, −24 to −28% on the transaction, and every guard
flat — the time cap changes which entries the writer takes, not what it does
for the ones it takes.

### 4. What the earlier designs cost, and why the shipped one is shaped as it is

All were run on the same harness; the first three before the caller-side count
existed, the fourth before the writer-side time cap.

| design | stream-latency | burst-seq-stream | many-streams-burst | release gate |
|---|---:|---:|---:|---|
| `Timer.run` deferral, every flush | −30% | 0% | **+7 / +14%** | — |
| `Timer.run` deferral, reply flushes only; immediate on completion | −25% | +2% | **+8 / +24%** | — |
| microtask deferral, no caller-side count | −32% | **+160 / +161%** | **+95 / +91%** | — |
| microtask + caller-side count, rows-only cap | −33% | 0% | 0% | **fired**: Long-Text Unchanged Fanout (256 × 4 KB) +11.6% |
| microtask + count, writer-side cap, first sample taken at face value | −0% (page retired by its own first run) | — | — | — |
| shipped: writer-side cap after acquire, retire on two over-cap samples | −31 to −33% | flat | flat | see §5 |

The first two rows are the price of a zero-duration timer on the main isolate:
2.5 µs per `Timer.run` against 0.008 µs per `scheduleMicrotask`, measured in a
20,000-hop AOT chain, and a fan-out burst schedules hundreds of them. The third
row is the serialisation hazard measured directly: with the writer misread as
idle between one awaited write and the next, a ~10 µs warm rerun lands ahead of
every write and a 3.3 ms burst becomes 8.7 ms. The idle signal has to come from
the caller's side of `await _runtime`, which is what `Database._writesEntered`
is.

The fourth and fifth rows are the same hazard in bytes, and what it takes to
bound it without losing the target. The release suite's Long-Text
Unchanged Fanout lane holds eight unchanged 256-row × 4 KB streams and times a
write to the emission of a ninth; the caller awaits that emission, not a
write, so the writer is idle by every signal the engine has, takes a 256-row
stream, and hashes a megabyte of TEXT while the *next* iteration's write
queues behind it. The rows-only cap admitted it; +0.18 ms on a 1.55 ms lane is
about one such hash pass. The writer-side measurement retires it after two
over-cap samples. Three shapes of that measurement were tried and rejected on
this harness before the shipped one: a main-isolate stopwatch around the
request, which includes the hop and the wake and put the 50-row page (43 µs of
writer time, the target shape) over a 32 µs line; a writer-side stopwatch that
included statement acquisition, whose first sample is the prepare (715 µs in
JIT, ~140 µs in AOT) and retired every stream after one run; and a stopwatch
started after acquisition but with the first sample taken at face value, which
still retired the changed 50-row page, because a statement's first run on a
connection fills the decoder's schema cache and sizes its result buffer and
reads well above the 43 µs steady state even with the prepare excluded. The
shipped rule needs two consecutive samples over 64 µs, which is also what
keeps one slow sample from retiring a small stream for good; a
megabyte-hashing stream is offered the writer twice in its life.

### 5. Headline release run

`run_release.dart exp289-warm-connection-reruns --repeat=5 --fail-on-regression
--fail-on-memory-regression --compare-to` the exp 266 anchor, from the
committed tree. The committed artifact is the fourth sweep; the first three
are the regression net doing its job and are reported here because the code
changed in response to two of them.

| sweep | build | verdict | flagged lanes | disposition |
|---|---|---|---|---|
| 1 | rows-only cap | 8 wins / 2 regressions / 159 neutral | Long-Text Unchanged Fanout (256 × 4 KB) +11.6% | **mine**: a megabyte hash pass on the writer ahead of the next write; fixed by the time cap (§4) |
| 2 | time cap incl. acquire, first sample skipped | 6 / 3 / 160 | Long-Text +17.0%; selectBytes large payload +17.5% | Long-Text: the skip let each big stream run warm twice; tightened (§4). selectBytes: see sweep 4 |
| 3 | time cap after acquire, first sample counted | 8 / 2 / 159 | High-Cardinality Fan-out +83%; selectBytes large payload +15.8% | Fan-out: the lane's known one-vs-two 200 ms settle-window bimodality ([#318](https://github.com/danReynolds/resqlite/issues/318)); it read 234.8 and 233.3 ms in sweeps 1–2 and 237 in sweep 4. Build retired the target page (§4) |
| **4** | **shipped** | **6 wins / 1 regression / 162 neutral** | Concurrent Reads 8× +18.0% | **not plausibly mine**: a read-only lane with no writes and no streams; read 0.72 / 0.62 / 0.58 / 0.72 across the four sweeps against the anchor's 0.61, and standalone alternation reads main 0.81 / 0.81 / 0.79 against the candidate's 0.68 / 0.64 / 0.69 ([#324](https://github.com/danReynolds/resqlite/issues/324)) |

Every sweep ran on a host with `mediaanalysisd` at ~160% CPU and an unrelated
process at 100%, both for the preceding day and a half, load average 4–5.5;
`check_peer_drift.dart --since=2026-08-09` reads −2.7% median / 72% agreement,
so the apparatus as a whole held. The selectBytes large-payload lane, which
the diff cannot reach, is bimodal at 0.24 / 0.28 ms in both arms over fifteen
standalone invocations on this host; the anchor's 0.24 is one mode, and the
lane's threshold sits between the modes ([#324](https://github.com/danReynolds/resqlite/issues/324)).
Long-Text Unchanged Fanout, the lane sweep 1 was right to fire on, reads
neutral in sweeps 3 and 4 and neutral across three AOT and three JIT
alternations of the shipped build (§4).

Committed artifact, the wins:

| lane | anchor | exp 289 | Δ |
|---|---:|---:|---:|
| Streaming / Unchanged Fanout Throughput (1 canary + 10 unchanged) | 0.19 ms | 0.10 ms | **−46%** |
| Streaming / Long-Payload Unchanged Fanout (8 streams, 64 × 32 KB TEXT + BLOB) | 2.65 ms | 0.31 ms | **−88%** |
| Streaming / Long-Text 32KB Unchanged Fanout (8 unchanged, 64 × 32 KB) | 2.76 ms | 2.44 ms | −11% |
| Streaming (Column Granularity) / Disjoint column writes, re-emits | 4193 | 4021 | peer row (`sqlite_async`) |

The two large ones need reading correctly, because they are real and they are
not what the lanes were built to measure. Both time a write to the emission of
a small *canary* or *barrier* stream registered after a wave of large unchanged
streams, on the assumption that the canary's rerun queues behind the wave and
so its emission marks the wave's drain. With the writer taking one small
eligible entry per round, the canary is exactly the entry it takes — the big
streams retire themselves from the writer after two samples — and its
emission no longer waits behind eight megabyte hash passes on the pool. A
subscriber to a small stream sees its change 0.1 ms after the write instead of
0.19, or 0.3 ms instead of 2.65, which is the behaviour a user wants and the
inverse of the head-of-line hazard exps 239 and 249 were rejected for. What
the lanes no longer report is the unchanged wave's drain time, which is
unchanged: it still runs on the pool, cold, and is simply not on the canary's
path any more. The memory gate had no anchor section to compare against and
records this run's values for the next one.

## Decision

**Accepted.** Candidate B ships; candidate A is rejected by §2 and the pragma
is unchanged.

The moonshot's finding is §1, and it stands whatever happens to the code: a
reader connection in this architecture is cold for every stream rerun, because
the rerun exists only because a commit preceded it, and the cost of that is a
multiple of the query on every stream-shaped read. The only warm connection in
the process is the writer's. Running the rerun there when the writer is idle
collects that difference on write-to-emission latency — a third on a list, a
fifth on a row, a quarter on a transaction — with the write path unchanged,
because the writer is offered a rerun only when the count of writes in progress
from the caller's side is zero and its own queues are empty, and it is offered
one at a time.

The persistent complexity is one writer request type, one interface and one
attach function inside `stream_engine.dart`, a held-entry slot and a
`deferWarm` flag on the flush, two ints on `StreamEntry`, and a counter on
`Database`. The eligibility rule is a row cap for the first offer and the
entry's own measured writer-side time after that, so the most a write can
wait behind a warm rerun is 64 µs plus the hop, and a stream that costs more
than that on the writer is offered it at most twice in its life. The one
policy number in the design is that 64 µs; a changed 50-row page is 43 µs of
writer time and an unchanged one 12 µs, so the cap sits above the target shape
and below anything that hashes a megabyte.

## Future Notes

- The remaining tax on a *pool* rerun is untouched by this run and is the
  larger number: on the fifty-page shape a reader still pays ~21 µs after every
  commit, and only one member of a dirtied set gets the writer per round.
  Nothing in resqlite can keep a reader's cache across a commit — that is
  SQLite's `pager_reset` — so the lever is which connection runs the rerun,
  not how the reader is configured.
- The fan-out drain lanes did not move, and exp 287 already showed messaging
  is not what they are made of. What they are made of is now more specific:
  four cold readers re-reading the same partitions after every write. A
  writer-side rerun budget larger than one member per round is the obvious
  follow-up, and it needs the sequential-burst guard from this harness, which
  is what caught the serialisation hazard in §4.
- `rerun_snapshot_tax.dart` should be run before any change to reader
  connection pragmas, `cache_size`, or the checkpoint policy: a checkpoint
  moves pages from the WAL (`pread` on a reader) into the mapping (a fault), so
  checkpoint frequency and the `mmap` term in §1 are coupled.
- Plain `select()` after a write pays the same tax and this run does not
  collect it: a `select()` has no last hash and no reason to prefer one
  connection over another. The point-after-write control shows the size of it
  (13.7 µs against 6.2 µs warm).
