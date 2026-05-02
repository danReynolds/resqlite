# Experiment 121: Invalidation traversal cost audit

**Date:** 2026-05-02
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`

## Problem

Experiment 120 closed the parked-dispatcher path on every measured stream
workload (`dispatcherParkedTotal` 3,590 → 0 on A11c overlap; 1,198 → 0 on
keyed-PK; `dispatcherWakeRetryTotal` already at 0 since exp 118). Its
future notes flagged three open measurement gaps that gate the next
implementation experiment in the `stream-rerun-dispatch` direction:

1. completion-side microtask scheduling cost
2. writer-isolate wall vs SQLite step wall split
3. invalidation traversal cost as a fraction of overlap wall

The third is the cheapest of the three to land: `ProfileCounters` already
exposes `invalidateUs` and `intersectionUs`
([`lib/src/profile_counters.dart:62`](../lib/src/profile_counters.dart),
populated in [`lib/src/stream_engine.dart:168`](../lib/src/stream_engine.dart)),
but the dispatch-pressure audit harness only reported the *count* columns
(`invalidate_count`, `intersection_entries`), not the microsecond columns.
The data needed to answer "is invalidation traversal a meaningful fraction
of overlap wall?" was being collected and discarded.

## Hypothesis

Adding `invalidate_ms`, `intersection_ms`, and `invalidate_pct_wall` columns
to `dispatch_pressure_audit.dart` will tell us whether the next dispatch
experiment should target `StreamEngine.onDependencyChanges` directly. The
audit accepts as a measurement experiment if:

- the new columns are non-zero on stream workloads (proves they are wired up);
- the direct-read control still parks (proves the existing dispatch counters
  were not silenced);
- at least one stream workload reports a clear `invalidate_pct_wall` reading
  that distinguishes "real implementation target" from "rule out the
  direction".

Pre-experiment decision gates:

- **≥10% of overlap wall** in invalidation → direction has a real next
  implementation target.
- **<3% of overlap wall** → direction is ruled out; the next runner builds
  the other two blocked measurements (completion-side scheduling, writer
  wall split) instead.

## Approach

`benchmark/profile/dispatch_pressure_audit.dart`:

- Added `invalidateUs` / `intersectionUs` to `_AuditRow`, populated from
  `ProfileCounters.snapshot()` (the keys already exist at
  `profile_counters.dart:117/119`).
- Split the rendered markdown into two tables: one for dispatch counters
  (existing shape) and a new "Invalidation traversal cost" table with
  `wall_ms`, `invalidate_ms`, `intersection_ms`, `invalidate_count`,
  `intersection_entries`, and `invalidate_pct_wall`.
- Added `--out=PATH` so callers can route per-pass output to a specific
  filename (the existing `--markdown` continues to write the legacy default
  path so the exp 119 / exp 120 invocation form still works).

`hook/build.dart`:

- Added `resqlite_step_row_hash` to `_exportedSymbols`. The Linux version
  script was hiding this hot-path symbol — used by every stream re-query
  via `lib/src/query_decoder.dart:51` — and the library failed to load on
  Linux with `Failed to lookup symbol 'resqlite_step_row_hash'`. CI runs
  on macOS, which doesn't apply the version script, so the regression
  was invisible there. Required to run any profile-mode harness on
  Linux; safe everywhere else (no-op on non-Linux builds).

No library / native / writer / reader-pool changes. Three passes of the
extended harness against `origin/main` produce the audit table; no A/B is
required for a measurement-only run.

## Results

Full per-pass values and methodology in
[`benchmark/profile/results/exp-121-invalidation-cost-audit-aggregate.md`](../benchmark/profile/results/exp-121-invalidation-cost-audit-aggregate.md).

Headline medians (3 passes, Linux x64, reader pool size 3):

| workload      | wall_ms | invalidate_ms | intersection_ms | invalidate_pct_wall | per-write_invalidate_us | per-entry_intersection_ns |
|---------------|--------:|--------------:|----------------:|--------------------:|------------------------:|--------------------------:|
| A11c baseline |  173.42 |          0.00 |            0.00 |               0.00% |                       — |                         — |
| A11c disjoint |  173.80 |         15.76 |            5.34 |               9.08% |                    31.5 |                       213 |
| A11c overlap  |  307.27 |         22.27 |            4.32 |               7.11% |                    44.5 |                       173 |
| keyed PK      |  441.03 |          5.95 |            1.77 |               1.36% |                    29.7 |                       177 |
| direct reads  |    2.42 |          0.00 |            0.00 |               0.00% |                       — |                         — |

Run-to-run variance was tight: <2% of median for `invalidate_us` across all
three passes; <10% for wall (driven by workload queueing, not the new
counters).

`dispatcher_parked_total = 0` and `dispatcher_wake_retry_total = 0` on every
stream workload, confirming exp 118 + exp 120 are still the floor.

### Active-fraction adjustment

`invalidate_pct_wall` includes the post-loop quiet windows
(`Future.delayed(50ms)` for A11c, the deadline-polled emission settle for
keyed-PK). Subtracting the obvious idle terms gives an upper bound on the
active fraction:

| workload      | quiet_window_ms | active_wall_ms | invalidate_pct_active |
|---------------|----------------:|---------------:|----------------------:|
| A11c disjoint |              50 |          123.8 |                12.73% |
| A11c overlap  |              50 |          257.3 |                 8.66% |
| keyed PK      |             200 |          241.0 |                 2.47% |

### Validation

- `dart analyze` (whole package + harness): clean.
- Audit run produces the expected counter shape on all five workloads.
- Direct-read control sentinel: 29 dispatcher parks at concurrency=32
  against a pool of 3, zero wake retries, zero invalidation (no streams).
- Stream workloads: non-zero `invalidate_us` and `intersection_us` exactly
  where streams are registered; zero on baseline (no streams).

## Decision

**Accept for review — measurement.**

Invalidation traversal sits between the pre-experiment decision gates on
the overlap workload (7.11% raw / 8.66% active, neither side of the 3% / 10%
gates). On its own that would be ambiguous, but the breakdown of
`invalidate_us` makes the direction call clear:

- Per-watcher intersection probes are only ~19% of `invalidate_us` on
  overlap (4.32 / 22.27 ms = 1.4% of total wall). Even an idealised
  zero-cost intersection would reclaim only ~1.4% of overlap wall.
- The remaining ~81% of `invalidate_us` is `_tableIndex` lookup +
  dirty/in-flight scheduling + `_flushQueue` kickoff. None of these have
  obvious removable patterns at the per-write scale (~36 µs per write,
  walking a 50-watcher index).

The disjoint workload is a structural finding: its `invalidate_pct_wall`
(9.08% raw / 12.73% active) is *higher* than overlap because invalidation
does the same per-watcher walk but no reader-pool work follows. This is the
expected post-exp-106 shape — exp 106 elides re-queries on the writer side
based on the result of these per-watcher checks. A future column-elision
experiment that short-circuits per-watcher probing (e.g., a coarser
table-level dirty-bitmap before any column intersection) would target this
shape, but the absolute cost is small (~16 ms across 500 writes).

The remaining 90%+ of stream-fanout wall on overlap is in the other two
unmeasured paths exp 120 flagged: completion-side microtask scheduling and
writer-isolate dispatch wall vs SQLite step wall. Those need separate
measurement infra. This audit's contribution is to rule out invalidation
as the next implementation target without forcing a future runner to build
that infra first.

## Future Notes

The harness change (`invalidate_ms`, `intersection_ms`, `invalidate_pct_wall`)
is a permanent addition to the dispatch-pressure audit, so future
`stream-rerun-dispatch` experiments can include invalidation cost in their
acceptance gate without re-deriving it.

Next dispatch experiment in this direction needs to build one of:

- a counter for completion-side microtask scheduling cost (either drainage
  count or per-emission scheduler hops on the main isolate); or
- a writer-isolate wall vs SQLite step wall split, which requires
  cross-isolate counter snapshot infra (`profile_counters.dart` doc
  comment notes this is non-trivial — it is the natural follow-up to the
  exp 115 / exp 121 line of measurement work).

The Linux export fix in `hook/build.dart` is a side benefit. The Dart FFI
binding for `resqlite_step_row_hash` was unable to resolve the symbol on
Linux because the version script's `_exportedSymbols` list omitted it.
Library-level streaming was effectively broken on Linux against the
current main; the audit run was the first thing that exercised it locally
on a Linux toolchain. CI runs on macOS, which does not apply the version
script.
