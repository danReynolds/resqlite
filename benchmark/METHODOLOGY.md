# Benchmark Methodology

This document governs how resqlite's benchmark suite is run, measured,
compared, and interpreted. Its companion [`SCOPE.md`](./SCOPE.md) states
what we test against and what we don't.

## Goals

1. **Thorough** — workload diversity characterizes real-app behavior, not
   just isolated operations.
2. **Respectable** — fair peer comparison, documented methodology, honest
   scope.
3. **Empowering** — each benchmark tells a clear story; experiment
   comparisons surface the right signal.
4. **Automatic** — new workloads propagate to the public dashboard without
   per-workload manual work.
5. **Respects competitors** — same schema, same operations, idiomatic
   peer APIs, honest gap disclosure.

These are not absolute adjectives. The suite is "thorough within scope",
"respectable within scope", etc. Scope is disclosed in `SCOPE.md`.

## Measurement

### Timing

All timing uses Dart's `Stopwatch` with microsecond resolution (`elapsedMicroseconds / 1000.0` for ms).
Two numbers per operation:

- **Wall time**: total elapsed time from the caller's perspective, including
  any isolate round-trip overhead.
- **Main-isolate time**: CPU time spent on the main (calling) isolate. For
  synchronous libraries (`sqlite3.dart`) this equals wall time. For async
  libraries with worker isolates (resqlite, `sqlite_async`) this is
  typically much lower than wall time and is the critical UI-thread
  constraint in Flutter.

For any synchronous peer, main-isolate time is reported equal to wall time
(not marked N/A) because sync == main. The distinction matters only when
isolate offloading is in play.

### Statistical approach

- **Default repeats**: `--repeat=5`, though quick iteration may use `--repeat=3`.
  Published results use 5.
- **Percentiles reported**: median (p50) and p90. p99 is captured internally
  for scenarios but not surfaced in the default markdown table (future
  enhancement).
- **Noise-aware comparison**: `run_all.dart --compare-to=<baseline>` uses
  threshold `max(10%, 3 × current MAD%)` with a `±0.02 ms` absolute floor.
  - Stable benchmarks: MAD < 5% → 10% threshold
  - Moderate: 5% ≤ MAD < 15% → 3×MAD threshold
  - Noisy: MAD ≥ 15% → marked noisy; deltas treated conservatively
- **"Ultra-fast" floor**: benchmarks under 0.1 ms wall have their change
  threshold absolute-floored at 0.02 ms to prevent noise-induced false
  positives.

A summary line accompanies every comparison: `N wins, M regressions,
K neutral`. An experiment is "real" when its expected workload shows a win
beyond the noise threshold.

### What we do NOT measure (yet)

- **Memory over time** — only point-in-time RSS and SQLite internal counters
  (exposed by `db.diagnostics()` starting in Phase 1.1).
- **Battery impact** — requires device-level instrumentation; out of scope.
- **Thermal throttling effects** — out of scope; users should be aware that
  long-running suites on M1 Pro can throttle after ~5 minutes under load.
- **Variance across OS updates / machine reboots** — we do not baseline
  hardware drift over calendar time. Results are always tagged with date
  and device; interpreting drift is the reader's job.

## Fair comparison protocol

### Same inputs

Every workload must provide all applicable peers with:
- The same schema (DDL)
- The same seed data (rows, distributions)
- The same parameter values (for parameterized queries)

Peer-specific adapters in `benchmark/shared/peer.dart` (Phase 0.2) wrap
setup differences but never alter the logical inputs.

### Equivalent operations

Every peer in a workload must execute the same number of logical
operations. If peer A runs 1000 SELECTs and peer B runs 1000 SELECTs + 1000
type conversions to match some library-specific shape, that's unfair.
Workloads declare expected op counts; the harness verifies post-hoc.

### Idiomatic APIs

Each peer uses the API real users would use. No crippled versions, no
cherry-picked fast paths not exposed in the library's documented surface.

| Library | Idiomatic API |
|---|---|
| resqlite | `db.select()`, `db.execute()`, `db.executeBatch()`, `db.stream()` |
| sqlite3.dart | `db.select()`, `db.execute()`, prepared `Statement.execute()` for bulk |
| sqlite_async | `db.getAll()`, `db.execute()`, `db.executeBatch()`, `db.watch()` |

### Reactive workload specifics

- **sqlite_async throttling disabled**: `db.watch(sql, throttle: Duration.zero)`.
  Otherwise we measure its 30 ms default throttle, not its invalidation
  engine. `streaming.dart` already follows this.
- **Emission counting**: reactive workloads assert expected stream emissions
  alongside timing. A workload that re-fires streams unexpectedly is
  "wrong" even if it's fast.

### Asymmetric capabilities

When a peer doesn't support a workload feature (e.g., `sqlite3.dart` has no
reactive streams), its row in that workload's output is omitted — not
filled with zeros. The omission is noted in the workload's methodology
footnote.

## Peer versions and upgrade policy

Pinned versions live in `pubspec.yaml` (and are reproduced in `SCOPE.md`):

| Peer | Pinned version | Pin type |
|---|---|---|
| `sqlite3` | `3.3.0` | Exact (dev dependency) |
| `sqlite_async` | `0.14.0-wip.0` | Exact (dev dependency) |

**Upgrade cadence:** peer upgrades are deliberate PRs, not side-effects of
`dart pub upgrade`. When upgrading:

1. Run the full benchmark suite on the old version. Save as
   `benchmark/results/<date>-peer-upgrade-<peer>-baseline.md`.
2. Upgrade the dependency in `pubspec.yaml`.
3. Run the full suite on the new version. Save as
   `<date>-peer-upgrade-<peer>-new.md`.
4. Compare. Any significant change (>10%) must be documented in the PR —
   it means the peer's behavior shifted, and published resqlite numbers
   need to be re-contextualized.
5. Update `SCOPE.md` with the new version.

If a peer upgrade breaks a workload (API change), fix the
`BenchmarkPeer` adapter, not the workload. If the adapter can't absorb the
change, the workload may need to declare a capability gap.

## Adding a workload — Definition of Done

A new workload only lands when **all** of these hold:

- [ ] Markdown result file under `benchmark/results/` parses cleanly via
      `generate_history.dart` (no warnings)
- [ ] `history.json` gains the expected metric entries
- [ ] `docs/benchmarks/index.html` renders the workload under the correct
      section (add a chart builder if needed; see [AUDIT.md](./AUDIT.md))
- [ ] `--compare-to` diff output includes the workload
- [ ] Workload source uses the `BenchmarkPeer` interface (not hand-rolled
      peer setup)
- [ ] Workload declares `ExpectedOpCounts` and harness enforces equality
      across applicable peers
- [ ] Workload has an entry in `SCOPE.md` explaining what it measures and
      any methodology caveats
- [ ] Workload source includes a brief comment explaining:
  - What real-app pattern it models
  - Expected narrative (what story the numbers tell)
  - Known peer-capability gaps (who participates, who's omitted, why)

## Workload versioning

Metric names include a workload version suffix:
```
chat_sim_v1 / Read last-20 messages / resqlite select()
```

When a workload's op mix, schema, or seed changes materially, bump the
version. The old version's history is preserved in `history.json` (with
its `v1` suffix); trajectories on the dashboard reset at the bump.

"Materially" means any of: schema change, seed-row count change >2×,
op-mix ratio change >10%, distribution change (e.g., uniform → Zipfian),
or any new operation type added to the rotation.

Cosmetic changes (comments, formatting, test-only refactors) do not bump.

## Interpreting results

### Reading a single run

- First glance: wall-time and main-isolate time ratios between resqlite
  and each peer.
- Second glance: `Repeat Stability` section at the bottom — which
  benchmarks are flagged `noisy` in this run? Their deltas vs previous
  runs deserve skepticism.
- Third glance: emission counts on reactive workloads. A win on wall time
  that comes from over-firing streams is not a real win.

### Reading a comparison (`--compare-to=...`)

- `🟢 Win (X%)` — beats noise threshold, in the right direction
- `🔴 Regression (+X%)` — beats noise threshold, wrong direction
- `⚪ Within noise` — everything else
- The summary line `N wins, M regressions, K neutral` aggregates these.

### When to trust a 10% win

Only when the comparison is:
- Against a baseline on the same machine, same branch, same Dart version,
  same day (timing drift across days is real but unmeasured).
- Stable: both current and baseline rows flagged `stable`, not `noisy`.
- Beyond the noise threshold.
- Reproducible across at least two independent repeats (run baseline
  twice, run change twice, confirm each replicates).

Any one of those missing, the "win" gets scare quotes.

### When a win doesn't matter

A win in a microbenchmark that doesn't tie to a scenario is not
automatically a product win. When experiment-decision time comes, ask:
*does this improvement show up in A5 (chat), A6 (feed), or A10/A11
(reactive)?* If yes, it's a real product improvement. If only a
microbenchmark moves, the win is theoretical until a scenario confirms.

## Handling flaky benchmarks

A benchmark is "flaky" when its MAD > 30% and the condition persists
across repeat runs on an unchanged codebase. Flaky benchmarks:

1. Are not removed. Their entries stay in the suite for continuity.
2. Are flagged `noisy` in the output; their deltas are treated
   conservatively (3×MAD threshold).
3. Are investigated before being used as decision support. A flaky
   benchmark cannot win or lose an experiment.

If a benchmark becomes flaky only after a specific code change, that's a
regression signal, not a measurement issue.

## Machine policy

All published numbers in `benchmark/HARDWARE_RESULTS.md` are recorded on
a specific machine, with full hardware + OS + Dart version. A second
device can be added to the registry at any time; the dashboard already
supports a device selector. Running on multiple devices is manual — we
do not have CI device matrix.

When running benchmarks, quiet the system: close browsers, stop Spotlight
indexing when possible, plug the laptop in (don't run on battery).
Backgrounded app activity is the single largest source of variance. Repeat
runs until stability is within expected MAD.

## What "hardened" would require (and doesn't)

We are not claiming "hardened" in a production-grade sense. That would
require:
- Machine-variance baselining across calendar time
- Thermal-state instrumentation
- Background-noise isolation
- Adversarial workloads (pathological inputs, fault injection)
- Framework self-regression tests

These are not in scope. `SCOPE.md` names them as Known Gaps.

## Related documents

- [`SCOPE.md`](./SCOPE.md) — what we test, what we don't, peer versions
- [`AUDIT.md`](./AUDIT.md) — pipeline from workload → dashboard
- [`README.md`](./README.md) — running the suite locally
- [`HARDWARE_RESULTS.md`](./HARDWARE_RESULTS.md) — device registry and
  canonical result files
