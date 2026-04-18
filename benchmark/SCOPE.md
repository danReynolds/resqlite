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
| **drift** ([pub.dev](https://pub.dev/packages/drift)) | `2.21.0` | Codegen-backed, isolate-backed, reactive. Most-used reactive Dart SQL library. |

Pins live in `pubspec.yaml`. Upgrading a peer is a deliberate PR with
before/after benchmark runs attached — see
[METHODOLOGY.md § Peer versions and upgrade policy](./METHODOLOGY.md#peer-versions-and-upgrade-policy).

### Drift-specific setup

Drift is codegen-backed, but we use it via `customSelect` + `customUpdate`
+ `customInsert` rather than the typed DSL. Both are idiomatic drift
usage, and `customSelect` is typically the fast-path choice for drift
users with perf-sensitive queries. The `@DriftDatabase` schema
definitions still generate code — that's what drift's `StreamQueryStore`
needs for invalidation to work correctly.

- Drift schemas live in `benchmark/drift/<scenario>_db.dart`, one per
  benchmark scenario, mirroring each scenario's SQL DDL 1:1 (tables +
  indexes + constraints).
- Generated `<scenario>_db.g.dart` files are **gitignored** — they
  regenerate deterministically via `dart run build_runner build`.
- `benchmark/run_all.dart` auto-regenerates on stale-ness before the
  suite runs; contributors don't think about it.
- Drift runs in an isolate via `NativeDatabase.createInBackground` —
  same async-isolate model as resqlite. Fair comparison point.
- Stream invalidation for `customSelect` requires explicit `readsFrom`
  sets. The `DriftPeer` adapter auto-extracts modified table names from
  write SQL via regex. A unit test suite (`test/benchmark_drift_peer_test.dart`)
  verifies streams actually emit on INSERT/UPDATE/DELETE/batch/INSERT
  OR REPLACE, so schema/SQL changes that break invalidation surface as
  test failures, not as silently-fast benchmark numbers.

## Peers we do NOT compare against

### sqflite ([pub.dev](https://pub.dev/packages/sqflite))

Excluded until mobile CI lands. The desktop-compatible variant
(`sqflite_common_ffi`) uses sqlite3.dart under the hood and would not
represent actual mobile sqflite performance:

- Platform channel serialization cost is absent under the ffi variant.
- Mobile iOS/Android ship different SQLite versions with different
  default PRAGMAs.
- F2FS (Android) vs APFS (macOS) vs ext4 (Linux) fsync behavior differs
  meaningfully, and the ffi variant reflects the dev-machine filesystem,
  not the device's.

Including `sqflite_common_ffi` with a caveat would be misleading;
excluding and saying why is honest. Will be added when `flutter test
integration_test/` on simulators/emulators is wired into CI.

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

- **No sqflite, libsql_dart** (see "Peers we do NOT compare against" above)
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
