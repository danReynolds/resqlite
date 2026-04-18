# Benchmark Scope

This document states **exactly** what the resqlite benchmark suite
tests and, just as importantly, what it does not. Read this before
interpreting any number on the public dashboard.

The statistical and measurement rules that govern every test are in
[`METHODOLOGY.md`](./METHODOLOGY.md).

## Peers we compare against

| Peer | Version | Role in comparison |
|---|---|---|
| **resqlite** | this repo (current commit) | Subject of benchmarks |
| **sqlite3.dart** ([pub.dev](https://pub.dev/packages/sqlite3)) | `3.3.0` | Synchronous FFI baseline — the "raw sqlite" reference |
| **sqlite_async** ([pub.dev](https://pub.dev/packages/sqlite_async)) | `0.14.0-wip.0` | Async, isolate-pool-backed, reactive peer |

Pins live in `pubspec.yaml`. Upgrading a peer is a deliberate PR with
before/after benchmark runs attached — see
[METHODOLOGY.md § Peer versions and upgrade policy](./METHODOLOGY.md#peer-versions-and-upgrade-policy).

## Peers we do NOT compare against

### drift ([pub.dev](https://pub.dev/packages/drift))

The most-used reactive Dart SQL library. Not included because:
- Drift is codegen-backed; integrating it into our benchmark
  harness requires a build step per workload, which conflicts with the
  "simple dart run" ergonomic the existing suite has.
- Drift's reactive stream heuristic is table-set based and covered
  equivalently by `sqlite_async`'s `watch()` for our current comparison
  purposes.
- Adding drift would materially increase the surface area of the
  benchmark package — we'd need to track drift's codegen output in source
  control or generate it on each run.

This is a real gap. When drift ships a measurable architectural change
(e.g., column-level invalidation, IVM-style maintenance) and resqlite
wants to claim a specific win against it, drift gets added.

### sqflite ([pub.dev](https://pub.dev/packages/sqflite))

The Flutter-default SQLite library. Not included because:
- sqflite is Flutter-only (uses platform channels). Our benchmarks run
  under `dart` not `flutter`; adding sqflite would force a
  `flutter test`-based harness for its portion, splitting the runner.
- sqflite's synchronous-over-platform-channel model is fundamentally
  slower than any in-process peer; including it wouldn't change our
  narrative, only add noise.

When mobile CI lands (not currently scoped), sqflite becomes comparable
alongside the mobile-oriented workloads.

### libsql_dart (Turso)

Promising but still maturing. Not a stable release in pub.dev as of this
writing. Revisit when published and shipping local reactive queries.

### Others

`prisma-dart`, `supabase-dart`, anything that wraps a network
database — out of scope. We benchmark in-process SQLite only.

## Hardware we test on

Primary reference:

| Field | Value |
|---|---|
| Machine | MacBook Pro 14" |
| CPU | Apple M1 Pro (10 core) |
| Memory | Unified LPDDR5 |
| OS | macOS 26.2 |
| Dart | 3.11 |

Additional devices can be added via `benchmark/HARDWARE_RESULTS.md`;
the dashboard's device selector handles multiple rows natively. There
is **no CI device matrix** — all published numbers are from hand-run
sessions on dated machines.

## Hardware we do NOT test on

- Android devices (Pixel 6a/7a, Samsung A-series, any mid-range phone)
- iOS devices (iPhone SE, any iPhone)
- Windows desktops (any)
- Linux servers (any)
- Intel Macs

If you deploy resqlite on any of these, **our published numbers do not
describe your environment**. Performance on mobile in particular is
known to be meaningfully different — LPDDR4 vs LPDDR5, thermal
throttling behavior, F2FS vs APFS `fsync` semantics, and Dart FFI
first-call latency on iOS are all different from our M1 Pro reference.

Mobile coverage is a named Known Gap (see below). If you run resqlite
benchmarks on a mobile device, PRs adding the result to
`HARDWARE_RESULTS.md` are welcome.

## Workload categories

Each category appears on the dashboard as its own section. Full details
per workload live in the workload's source comments and in
`METHODOLOGY.md § Interpreting results`.

### Operation-level microbenchmarks (existing)

| Category | What it isolates |
|---|---|
| Scaling (select → maps) | Pure read throughput across row counts |
| Scaling (select → JSON bytes) | C-native JSON serializer throughput |
| Schema shapes | Cost of narrow/wide/text/numeric/nullable schemas |
| Writes (single inserts) | Per-insert latency including commit |
| Writes (batch inserts) | Prepared-statement + single-transaction throughput |
| Transactions | Nested savepoint + commit/rollback cost |
| Concurrent reads | Reader pool throughput at 1/2/4/8 parallel callers |
| Parameterized queries | Prepared-statement cache hit rate |
| Streaming | Initial emission latency, invalidation latency, fan-out, churn |
| Point query | Per-call dispatch overhead (hot loop) |
| Memory (RSS) | Process-level allocation delta around per-op workloads |
| Streaming (column granularity) | Disjoint vs overlapping column writes; ratio metric exposes per-column suppression precision |

### Scenario-level benchmarks (Phase 1+ of Track A)

| # | Workload | Status | Story |
|---|---|---|---|
| A11 | Keyed PK subscriptions | **Shipped** (Phase 1) | Many watchers each on a single PK; baseline for `watchRow()` API |
| A5 | Chat sim | Planned (Phase 2) | Mixed R/W with joins and Zipfian distribution |
| A6 | Feed paging | Planned (Phase 2) | Keyset pagination + reactive stream under concurrent writes |
| A11b | High-cardinality fan-out | Planned (Phase 2) | 500 streams on a 10K-row table |
| A7 | Sync burst | Planned (Phase 3, `--include-slow`) | 50K-row bulk insert with active stream |
| A9 | 1 GB working set | Planned (Phase 3, `--include-slow`) | mmap behavior and cache locality |

Column-disjoint streaming, originally planned as A10, is superseded by
the more comprehensive `Streaming (Column Granularity)` microbenchmark
already in the suite — it measures disjoint vs overlapping writes and
reports the ratio, which is a cleaner precision metric than a single
disjoint-only count.

## Known gaps

These are real gaps that should be explicit rather than hidden:

### Performance coverage

- **No mobile-device results** (see hardware section above)
- **No sustained write-heavy workload** — our write benchmarks are
  either single-inserts or one burst. Real apps doing logging or chat
  produce steady writes over minutes. A11b partially covers the read
  side; writes remain uncovered.
- **No transaction-contention workload** — we test single-writer
  transactions. Nothing exercises many concurrent callers contending
  for the writer isolate.
- **No cold-start benchmark** — how long from `Database.open()` to first
  query? We don't measure it. (The original Track A plan included one as
  "A8" but deferred it due to harness-kill fragility.)
- **No encryption-path coverage** — we ship AES-256 support via
  SQLite3 Multiple Ciphers. It is not in any benchmark.
- **No degenerate-query workload** — everything we benchmark hits
  indexes. A full-table scan on a large table tells us how resqlite
  degrades; we don't test it.
- **No connection-lifecycle benchmark** — open/close cycles matter for
  CLI tools and short-lived scripts. Not tested.

### Methodological gaps

- **No machine-variance characterization** — we do not have data on
  how much our own M1 Pro numbers drift day to day on an unchanged
  codebase. Single-run comparisons within a session are trustworthy;
  cross-session comparisons are taken on faith.
- **No thermal-state instrumentation** — long suites on M1 Pro can
  throttle after ~5 minutes of sustained load. We do not detect or
  report this.
- **No chaos/fault injection** — workloads run in benign conditions.
  What happens when a reader worker crashes mid-stream? Not tested.
- **No framework self-regression testing** — we do not have tests that
  verify the benchmark framework itself measures what it claims. A
  buggy workload that does no real work would show as fast.

### Compared-to gaps

- **No drift, sqflite, libsql_dart** (see "Peers we do NOT compare against" above)
- **No version-drift testing** on peers — we pin versions deliberately,
  but don't test resqlite against the latest nightly of each peer.

These gaps are acknowledged and publicly displayed. The benchmark page
on GitHub Pages will surface an abridged version of this "Known gaps"
section so readers are not misled by the headline numbers.

## Publishing policy

- Every committed change to `benchmark/results/*.md` must also update
  `docs/experiments/history.json` (via `generate_history.dart`) in the
  same commit. This is enforced by the
  [`resqlite-experiment`](.claude/skills/resqlite-experiment/SKILL.md)
  skill convention.
- `HARDWARE_RESULTS.md` is the source of truth for which result files
  are "canonical" for each device and therefore rendered on the public
  benchmarks page.
- When workloads are added or changed, this `SCOPE.md` must be updated
  in the same PR. "What we test" cannot silently drift.

## Changelog

- **2026-04-16**: Initial draft as part of Track A Phase 0.4.
