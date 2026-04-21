# Experiment 088: `SQLITE_ENABLE_SETLK_TIMEOUT` — kernel-blocking WAL waits

**Date:** 2026-04-20
**Status:** Rejected (multi-run confirmation, downgraded from Accepted)
**Archive:** [`archive/exp-088-setlk-timeout`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-088-setlk-timeout)

> Numbering note: originally authored as "exp 084," renumbered to 088
> to avoid collision with the concurrently-developed
> `exp-084-columnar-redux` branch. Numbers 083, 085, 086 are already
> claimed by other in-flight branches; 087 was used by a parallel
> VM-pragma audit. 088 was the next free slot on the remote at the
> time of the rename.

## Problem

Exp 080 (dispatch budget) surfaced a 34 ms single-insert outlier in the
p99/max tail (2000× the 16 μs median). The prime suspect was a passive
WAL checkpoint firing mid-insert and blocking the writer. SQLite's
default handling under lock contention in WAL mode is to call
`sqlite3WalBusy` / the `busy_timeout` retry loop, which spin-retries with
`sqlite3_sleep`-style backoff. That loop keeps the thread runnable, so
the OS scheduler still races it against the checkpointer and produces
large tails when things go wrong.

The research pass `research-2026-04-20-peer-and-platform-survey.md` §T1
flagged `sqlite3_setlk_timeout()` — new in SQLite 3.50.0 — as a
low-touch way to turn that polling retry into a kernel blocking wait on
VFSes that support blocking locks (unix-dotfile on POSIX). The kernel
then wakes the waiter immediately when the checkpointer releases the
lock, instead of waiting for the next poll tick.

We ship SQLite 3.51.3 via `sqlite3mc_amalgamation`, which already
contains the API. The feature is gated behind a compile flag
(`SQLITE_ENABLE_SETLK_TIMEOUT`), and has to be opted into per connection
via a runtime call.

## Hypothesis

Enabling `SQLITE_ENABLE_SETLK_TIMEOUT` and calling
`sqlite3_setlk_timeout(db, 10000, 0)` after every successful
`sqlite3_open_v2` should:

1. leave p50 untouched (no lock contention in the happy path),
2. meaningfully cut p99 and max on write-heavy workloads where the
   checkpointer can collide with an in-flight write, and
3. also improve reader p99 because readers block in the kernel when they
   hit a checkpointer-held lock instead of spinning through
   `busy_timeout`.

We expected the single_insert 34 ms outlier (and similar outliers on
merge_rounds / noop) to collapse toward the p90 band.

## Approach

Three small edits, gated and ordered to preserve the existing
`busy_timeout` as a graceful fallback:

1. **`hook/build.dart`** — added `'SQLITE_ENABLE_SETLK_TIMEOUT': null,`
   to the `defines:` map alongside the other `SQLITE_ENABLE_*` flags.
2. **`native/resqlite.c`** — inside `open_connection`, after
   `PRAGMA busy_timeout = 5000`, added:

   ```c
   #ifdef SQLITE_ENABLE_SETLK_TIMEOUT
       int setlk_rc = sqlite3_setlk_timeout(db, 10000, 0);
       if (setlk_rc != SQLITE_OK) {
           fprintf(stderr, "resqlite: sqlite3_setlk_timeout returned %d (non-fatal)\n", setlk_rc);
       }
   #endif
   ```

   The call applies to both the writer and every reader connection
   because they all flow through `open_connection`. We intentionally do
   not pass `SQLITE_SETLK_BLOCK_ON_CONNECT` — we want eligible lock
   waits to block, not the one-to-zero-connections checkpoint dance.
3. **No FFI binding change** — the call lives entirely in C, so
   `lib/src/native/resqlite_bindings.dart` and the `_exportedSymbols`
   list in `hook/build.dart` stay untouched.

`busy_timeout = 5000` remains in place, so on VFSes that don't support
blocking locks (Windows, non-dotfile Unix) the call is a documented
no-op and behaviour is unchanged.

## Results

### Multi-run confirmation (5 runs per side, medians of percentiles)

The initial single-run numbers (§ "Initial single-run results" below) showed
huge p99/max wins on every write workload. Single-run p99/max is noisy — one
GC pause or scheduler hiccup can swing it by an order of magnitude — so we
reran 5× per variant and take the **median of each percentile across the 5
runs** on each side. This is the methodology referenced in
`benchmark/EXPERIMENTS.md` § "Three things to keep in mind" point 1.

Baseline glob: `benchmark/profile/results/baseline-exp088-run{1..5}.json`
Candidate glob: `benchmark/profile/results/exp-088-run{1..5}.json`
Aggregator: `benchmark/profile/diff_multirun.dart`

Median-across-runs, baseline vs candidate:

| workload · op               | metric | baseline median | candidate median | Δ        | Δ%      | baseline CV |
|-----------------------------|--------|----------------:|-----------------:|---------:|--------:|------------:|
| single_insert · execute     | p50    | 17 μs           | 18 μs            | +1 μs    | +5.9%   | 2.4%        |
| single_insert · execute     | p90    | 23 μs           | 31 μs            | +8 μs    | +34.8%  | 7.0%        |
| single_insert · execute     | p99    | 67 μs           | 182 μs           | +115 μs  | +171.6% | 22.2%       |
| single_insert · execute     | max    | 1246 μs         | 3918 μs          | +2672 μs | +214.4% | 22.8%       |
| single_insert · execute     | work   | 6 μs            | 6 μs             | +0 μs    | +0.0%   | 14.9%       |
| merge_rounds · executeBatch | p50    | 105 μs          | 109 μs           | +4 μs    | +3.8%   | 0.9%        |
| merge_rounds · executeBatch | p90    | 121 μs          | 141 μs           | +20 μs   | +16.5%  | 5.5%        |
| merge_rounds · executeBatch | p99    | 294 μs          | 381 μs           | +87 μs   | +29.6%  | 17.4%       |
| merge_rounds · executeBatch | max    | 759 μs          | 980 μs           | +221 μs  | +29.1%  | 18.8%       |
| merge_rounds · executeBatch | work   | 95 μs           | 97 μs            | +2 μs    | +2.1%   | 1.2%        |
| noop · execute              | p50    | 11 μs           | 12 μs            | +1 μs    | +9.1%   | 6.9%        |
| noop · execute              | p90    | 20 μs           | 22 μs            | +2 μs    | +10.0%  | 6.6%        |
| noop · execute              | p99    | 65 μs           | 128 μs           | +63 μs   | +96.9%  | 16.8%       |
| noop · execute              | max    | 605 μs          | 3807 μs          | +3202 μs | +529.3% | 84.0%       |
| noop · select               | p50    | 7 μs            | 7 μs             | +0 μs    | +0.0%   | 7.4%        |
| noop · select               | p90    | 15 μs           | 16 μs            | +1 μs    | +6.7%   | 9.7%        |
| noop · select               | p99    | 48 μs           | 98 μs            | +50 μs   | +104.2% | 13.8%       |
| noop · select               | max    | 970 μs          | 5757 μs          | +4787 μs | +493.5% | 143.7%      |
| point_query · select        | p50    | 7 μs            | 7 μs             | +0 μs    | +0.0%   | 5.6%        |
| point_query · select        | p90    | 11 μs           | 12 μs            | +1 μs    | +9.1%   | 5.7%        |
| point_query · select        | p99    | 27 μs           | 47 μs            | +20 μs   | +74.1%  | 20.6%       |
| point_query · select        | max    | 565 μs          | 1944 μs          | +1379 μs | +244.1% | 117.6%      |

`CV` = coefficient of variation of the baseline's 5 per-run values for that
metric. Lower CV means the metric is stable run-to-run; higher CV means a
single-run number on that metric is largely noise. The `max` CVs on the
baseline range from 22.8 % (single_insert) to 143.7 % (noop select), which
tells you single-run `max` is effectively unusable as a signal on this bench
— one bad run dominates everything. p99 is less volatile but still noisy
(13–23 % on writes, up to 20 % on point_query).

**Findings — the single-run wins do not replicate:**

- **p50 is unchanged to very slightly worse** on every workload (+0 to
  +1 μs, within one-tick noise of the dispatch floor). Consistent with the
  hypothesis that p50 is not lock-bound — also consistent with p50 being
  the one metric where setlk_timeout *shouldn't* matter.
- **p90 ranges from flat to ~+35 % worse** on write workloads. The
  single-run numbers claimed p90 wins of -24 % to -64 %; neither
  direction's magnitude is defensible at the multi-run median.
- **p99 is 74 – 172 % WORSE at the median**, the opposite of the
  single-run claim. Candidate p99 on single_insert is 182 μs vs baseline
  67 μs. The original baseline's 678 μs p99 and 116 409 μs max never
  reappear in any of the 5 re-runs (baseline max range: 1104–1985 μs) —
  that 116 ms baseline outlier was a single bad measurement, not a
  property of the code under test.
- **max is 29 – 529 % WORSE at the median**, though max CV is so high
  (up to 144 %) that the median isn't meaningful — we mostly learn that
  the candidate does *not* reliably suppress tail spikes.
- **point_query regressions in the single run were noise**: single-run
  showed +25 % p50 / +12 % max (interpreted as "within noise"); multi-run
  shows +0 % p50 but persistent +74 % p99 / +244 % max. The p50 part
  *was* noise; the p99/max part was actually directionally correct but
  is now also the wrong sign from what we'd expected.
- **noop · execute max** went from baseline 605 μs median to candidate
  3807 μs median — a catastrophic regression on the no-op path, where
  setlk_timeout *should* be a pure no-op. This suggests the call is
  actually doing something and it's not good.

Per-run p99 variability (coefficient of variation across the 5 baseline
runs) is 13.8 – 22.2 % on the write workloads. That alone means a one-run
p99 delta smaller than ~25 % is indistinguishable from noise — and the
single-run deltas we originally reported (−21 % to −81 % on p99) sit
well inside that noise envelope on the candidate side too.

### Initial single-run results (kept for historical reference)

Original single-run numbers from
`benchmark/profile/results/baseline-exp088.json` vs `exp-088.json`:

```
## merge_rounds
  TIME executeBatch:
    p50      125μs →    119μs      -6μs  (-4.8%)
    p90      663μs →    501μs    -162μs  (-24.4%)
    p99     3366μs →   2661μs    -705μs  (-20.9%)
    max    44588μs →   9761μs  -34827μs  (-78.1%)

## noop
  TIME execute:
    p50       13μs →     11μs      -2μs  (-15.4%)
    p99     1619μs →    418μs   -1201μs  (-74.2%)
    max   319996μs →  12888μs  -307108μs  (-96.0%)
  TIME select:
    p50        8μs →      6μs      -2μs  (-25.0%)
    p99     1021μs →    230μs    -791μs  (-77.5%)
    max   203748μs →  29901μs  -173847μs  (-85.3%)

## point_query
  TIME select:
    p50        8μs →     10μs      +2μs  (+25.0%)
    p99      157μs →    130μs     -27μs  (-17.2%)
    max     4664μs →   5258μs    +594μs  (+12.7%)

## single_insert
  TIME execute:
    p50       17μs →     18μs      +1μs  (+5.9%)
    p99      678μs →    131μs    -547μs  (-80.7%)
    max   116409μs →   3322μs  -113087μs  (-97.1%)
```

These numbers look excellent in isolation but do not survive 5× re-runs.
The baseline outliers (678 μs p99 / 116 ms max on single_insert; 320 ms
max on noop execute; 204 ms max on noop select) do not appear in any of
the 5 baseline re-runs, meaning the original single-run baseline captured
a transient bad state (cold cache, first-run JIT, unrelated macOS
scheduling) that we mistook for a property of main. The candidate p99/max
on the 5 re-runs land *worse* than the baseline p99/max, which is the
opposite of what the single run suggested.

## Decision

**Rejected.** Downgraded from "Accepted" after multi-run confirmation.

The large single-run p99/max wins were noise — the original baseline
captured a transient outlier that never reproduced in 5 re-runs. At the
median-of-5-runs level, the candidate is measurably *worse* than baseline
on every tail metric on every workload: p99 +74 % to +172 % worse on
writes, max +29 % to +529 % worse, and noop regresses even though it has
no WAL lock contention to resolve.

The fact that noop · execute and noop · select regress at p99/max is
the strongest evidence this is not a neutral change. These workloads
have no concurrent writer-plus-checkpointer contention for setlk_timeout
to suppress, so the flag should be an observationally-invisible no-op.
It isn't.

## Root cause (verified in SQLite source)

Enabling `SQLITE_ENABLE_SETLK_TIMEOUT` is **not** just "add a timeout
option to an otherwise-unchanged lock path." It changes the SHM
locking architecture itself. From the amalgamation source in
`third_party/sqlite3mc/sqlite3mc_amalgamation.c` around line 43893:

> Normally, when `SQLITE_ENABLE_SETLK_TIMEOUT` is not defined, mutex
> `pShmMutex` is used to protect the `aLock[]` array and the right to
> call `fcntl()` on `unixShmNode.hShm` to obtain or release locks.
>
> If `SQLITE_ENABLE_SETLK_TIMEOUT` is defined though, we use an array
> of mutexes — one for each locking slot. To read or write locking
> slot `aLock[iSlot]`, the caller must hold the corresponding mutex
> `aMutex[iSlot]`. Similarly, to call `fcntl()` to obtain or release
> a lock corresponding to slot `iSlot`, mutex `aMutex[iSlot]` must be
> held.

Concretely, per WAL lock operation:

|                            | Flag off (baseline)                    | Flag on (candidate)                               |
|----------------------------|----------------------------------------|---------------------------------------------------|
| SHM mutex structure        | 1 shared `pShmMutex`                   | `SQLITE_SHM_NLOCK` (= 8) per-slot mutexes         |
| `fcntl` syscall            | `F_SETLK` (non-blocking) + busy-retry  | `F_SETLKW` (blocking with timeout bookkeeping)    |
| Per-lock state             | none                                   | `iBusyTimeout` read/saved/restored per op         |
| `unixShmNode` struct size  | smaller                                | `SQLITE_SHM_NLOCK` extra mutex pointers           |

This fully explains the noop regression. An `UPDATE ... WHERE 1 = 0`
still runs a WAL commit, which acquires the WAL-index SHM write lock
even with zero frames to append. In the baseline, that is one
`pShmMutex` lock + one non-blocking `F_SETLK` + release — two
lightweight ops. In the candidate, the same commit goes through the
per-slot mutex array and issues `F_SETLKW`, which is a heavier syscall
path even when the lock is immediately grantable, plus the
`iBusyTimeout` save/restore dance around it. The cost is paid on
every write, contended or not. The regression shape (tens of μs added
to p99 of every write workload, matching noop) matches this
prediction exactly.

Readers pay the same kind of cost on their WAL read-lock slot
registration, which is why `noop · select` also regressed.

## Platform note

The feature was designed primarily for Linux with `F_OFD_SETLKW` (OFD
locks + itimer-backed timeout), where the blocking path is native and
cheap. macOS does not support `F_OFD_*` locks — it falls back to
POSIX `F_SETLKW`, which is heavier. So the same experiment on
Android/Linux with heavy concurrent readers plus active checkpointing
*could* still be a win — but on macOS with a single-writer
bench, the per-op cost dominates any tail benefit.

## Before revisiting

Prerequisites for a re-attempt:

- A proper concurrent-reader + writer + checkpointer workload. The
  profile harness is effectively single-isolate-at-a-time today, so
  the scenario the flag targets is never exercised.
- A runtime VFS probe (`sqlite3_vfs_find` + capability check) so we
  can gate the call on platforms where blocking locks are native.
- A much shorter timeout (e.g. 50–100 ms) so that if anything *does*
  block, the worst case is bounded below `busy_timeout` (5 s) rather
  than well above it.

Source edits are kept in the branch but not merged. The +1 μs p50
cost would be tolerable on its own, but the tail regressions — plus
the mechanism above that reproduces on non-contended workloads —
make this a clear reject at the multi-run median.

## Protocol lessons

Two items worth carrying forward to future experiments:

1. **A compile flag that appears to "enable an optional runtime call"
   may restructure internal data structures.** Always read the
   implementation to see what the flag actually changes inside the
   library, not just what the advertised feature does. One
   `#ifdef` block can swap a global mutex for an N-mutex array.
2. **Noop regressions are the cleanest tell.** When a candidate
   regresses on a workload that has no mechanism to benefit from it,
   the per-op cost is real and any apparent "win" elsewhere is
   likely either noise or a coincident second-order effect. If noop
   regresses, reject or investigate before trusting any gains.

## Reproducing

Single-run comparison (fast, but do not trust the p99/max numbers — see
the confirmation section above for why):

```bash
git checkout exp-088-setlk-timeout
dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
  --out=benchmark/profile/results/exp-088.json
dart run benchmark/profile/diff.dart \
  benchmark/profile/results/baseline-exp088.json \
  benchmark/profile/results/exp-088.json
```

Multi-run confirmation (what the "Rejected" decision is based on) — run
the candidate branch for the 5 candidate JSONs, then check out the
parent and re-run for the 5 baseline JSONs (or revert
`hook/build.dart` + `native/resqlite.c` for the baseline runs without
changing branches):

```bash
# Candidate (branch HEAD)
for i in 1 2 3 4 5; do
  dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
    --out=benchmark/profile/results/exp-088-run${i}.json
done

# Baseline (checkout or revert source files)
git checkout HEAD~1 -- hook/build.dart native/resqlite.c
for i in 1 2 3 4 5; do
  dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
    --out=benchmark/profile/results/baseline-exp088-run${i}.json
done
git checkout HEAD -- hook/build.dart native/resqlite.c

# Aggregate medians across runs
dart run benchmark/profile/diff_multirun.dart \
  --baseline='benchmark/profile/results/baseline-exp088-run*.json' \
  --candidate='benchmark/profile/results/exp-088-run*.json'
```
