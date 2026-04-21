# Daily Research — 2026-04-21

Scheduled-task research pass scouting for viable performance experiments.
Covers: SQLite upstream (through 3.53), Dart SDK (through 3.10-ish), peer
libraries (better-sqlite3, bun:sqlite, node:sqlite, libSQL/Turso, rusqlite,
GRDB, drizzle, Drift).

Current state of this repo: 81 experiments, ~34 accepted, ~47 rejected /
deferred. Recent accepted: 075 (native-buffered hash), 077 (cheap-check
sweep). Recent rejected/deferred: 081 (binary row storage), 082
(message-graph handoff), 088 (`sqlite3_setlk_timeout`).

---

## Investigation outcomes (appended 2026-04-21, after deep-dive)

All three ranked candidates below were investigated in follow-up worktrees.
**All three were retired.** Summary:

| Candidate | Verdict | Report |
|---|---|---|
| A. Deeply-immutable `ResultSet` | **Blocked upstream** — `List<Object?>` isn't DI-eligible; `Uint8List` (BLOB cells) requires [SDK #50068](https://github.com/dart-lang/sdk/issues/50068), open since 2022 | [2026-04-21-deeply-immutable-probe.md](2026-04-21-deeply-immutable-probe.md) |
| B. Bump sqlite3mc to 3.51+ | **Already shipping** — `third_party/sqlite3mc` is already 3.51.3 as of 2026-03-13 | [2026-04-21-sqlite-bump-investigation.md](2026-04-21-sqlite-bump-investigation.md) |
| C. `wal_checkpoint=NOOP` refinement | **Skip** — premise was wrong; exp-029 is a commit-hook, not a periodic timer, and already gates on `pages_in_wal`. No empty-tick cost for NOOP to eliminate | [2026-04-21-checkpoint-noop-design.md](2026-04-21-checkpoint-noop-design.md) |

Two of three retired by facts the research pass got wrong: it didn't check
`third_party/sqlite3mc/VENDORING.md` for current version (B), and it
mischaracterised exp-029's implementation shape (C). Future daily-research
passes should verify candidate premises against the codebase before
escalating them. The ranked-candidate section below is preserved for
historical reading; treat as stale.

---

## Candidates, ranked

### A. Deeply-immutable `ResultSet` for zero-copy isolate transfer — **highest potential**

**Source:** Dart language proposal
[333 — shared memory multithreading](https://github.com/dart-lang/language/blob/main/working/333%20-%20shared%20memory%20multithreading/proposal.md)
and tracking issue
[dart-lang/sdk#56841](https://github.com/dart-lang/sdk/issues/56841).
[Deeply-immutable docs](https://github.com/dart-lang/sdk/blob/main/runtime/docs/deeply_immutable.md).

**What changed:** Deeply-immutable instances can be shared across isolates
in the same isolate group (our reader pool *is* one group, spawned from
`Database`). `SendPort.send` of a deeply-immutable object becomes a pointer
handoff, not a copy.

**Why it matters for us:** Today we pay a `SendPort` copy for every result
below the byte-size sacrifice threshold (exp 039). Above the threshold we
pay an `Isolate.exit` + fresh-isolate spawn cost. If `Row` / `ResultSet` /
the backing flat `List` of cells can be marked deeply immutable, every
read — tiny or large — becomes a zero-copy pointer send, potentially
retiring the entire sacrifice-threshold machinery.

**Open question:** which parts of this proposal are actually shipped in
stable Dart today, not just in flight. Needs a direct read of recent
`CHANGELOG.md` entries for 3.7 through whatever 3.10+ has stabilized —
specifically whether `@pragma('vm:deeply-immutable')` is usable outside
`dart:internal`, and whether Flutter's Dart version ships it.

**Experiment shape:** Start with a probe — can we even annotate one of
our result classes with the deeply-immutable pragma on the current SDK
and survive compile? If yes, measure `SendPort.send` on a 1k-row
`ResultSet` before/after. If no, document blockage and re-check next
quarter.

**Priority:** high if the language feature is shipped; blocked otherwise.
This is the only ideat in the pipeline that could *structurally* reset
read-path perf rather than trim another percent.

---

### B. Bump sqlite3mc to pick up SQLite 3.51+ — **cheapest real win**

**Source:**
[SQLite 3.51.0 release notes](https://sqlite.org/releaselog/3_51_0.html)
(2025-11-04). Latest trunk is
[3.53.0](https://sqlite.org/changes.html) (2026-04-09).

**What changed (perf-relevant, automatic):**

- 3.51.0: *"Use fewer CPU cycles to commit a read transaction."* Every
  read goes through commit — this is a per-query free win.
- 3.51.0: early zero-row-join detection, scalar subquery avoidance,
  window-function `BETWEEN :x FOLLOWING AND :y FOLLOWING` speedup.
- 3.47.0: Bloom filters on `IN (subquery)`, `order-by-subquery` and
  `indexed-subtype-expr` optimizations.
- 3.45.0: `SQLITE_DIRECT_OVERFLOW_READ` became default (already helping).

**Also new, for us to consider (not automatic):**

- `PRAGMA wal_checkpoint=NOOP` (3.51) + `SQLITE_CHECKPOINT_NOOP` for
  `sqlite3_wal_checkpoint_v2` — probes checkpoint state without doing
  work. Could refine exp 029's periodic-passive-checkpointing: query
  NOOP first, skip the PASSIVE call when frame count is trivial.
- `sqlite3_db_status64()` (3.51) — 64-bit `db_status` results. Only
  matters if we surface profile telemetry that overflows 32-bit.
- `SQLITE_DBSTATUS_TEMPBUF_SPILL` (3.51) — new counter. Useful for
  diagnostic builds (exp 026 rejected general db-status probes, but
  spill-specific may be worth sampling in profile mode).
- `SQLITE_PREPARE_DONT_LOG` (3.48) — silences error log on speculative
  prepares. Only relevant if we add a speculative-prepare optimization.

**Experiment shape:** single PR — bump sqlite3mc, run the full benchmark
suite, compare. Zero implementation risk; the question is magnitude.
Expect the read-commit change to show up in point-query and small-read
wall time specifically.

**Priority:** high. Do this first — it's a dependency bump plus
benchmark run.

---

### C. Revisit PGO (exp 054) with modern native-assets toolchain

**Source:** Dart 3.8 added
[`--target-os`/`--target-arch` AOT cross-compilation](https://medium.com/dartlang/announcing-dart-3-8-724eaaec9f47).
Dart 3.10 stabilized
[build/code assets](https://dart.dev/resources/whats-new)
for library authors. Turso's Rust rewrite cites PGO wins as part of
their perf story.

**Why revisit:** Exp 054 was rejected because macOS dylib profraw flush
didn't fire from the Dart VM host process — a tooling/plumbing issue,
not a "PGO doesn't help" conclusion. We now have:

1. A richer overnight-benchmark harness (`peer_comparison.dart`,
   `quick_bench.dart`, `sendport_vs_spawn_breakdown.dart`) that can
   drive representative workloads.
2. Native-assets maturity that makes running a separate C-only profile
   binary (outside the Dart VM) more ergonomic.
3. LTO was rejected (exp 042) because of icache pressure across the
   250k-line amalgamation. PGO is different — it only inlines *hot*
   code across units, which should avoid the icache blow-up that killed
   LTO. Worth testing that hypothesis.

**Experiment shape:** two-phase. Phase 1: wire a standalone C profile
binary that executes representative SQL workloads, verify `.profraw` is
generated on both macOS and Linux. Phase 2: rebuild sqlite3mc+resqlite
with `-fprofile-use`, benchmark. Also probe LLVM BOLT as an orthogonal
post-link optimizer (icache-aware layout) since LTO failed on icache
specifically.

**Priority:** medium. High effort (build-system work), but if it lands
it's across-the-board. Tagged for "next quiet weekend."

---

### D. Zero-copy column-value API (rusqlite `ValueRef` pattern)

**Source:** `rusqlite::Row::get_ref` exposes borrowed `&[u8]` / `&str`
views into SQLite's column buffer; valid until the next `step`/`reset`.
No peer SQLite wrapper I surveyed does this for streaming consumers on
top of a C/C++ SQLite.

**What this gives us:** a streaming callback API — one callback per row,
hands a `Uint8List` view backed by `sqlite3_column_text`'s internal
pointer (no copy), valid until the next step. Aimed at byte-fanout
consumers: HTTP bodies that want to stream rows out to sockets without
materializing the full JSON buffer, or ND-JSON exports.

**Tension with lean API:** this would be a *new* method. The scheduled
task brief explicitly says "no new read/write APIs." So — unless we can
retrofit it under `selectBytes` as a streaming variant — this probably
isn't a fit. Document as "if we ever add streaming output, this is how."

**Priority:** low (out of scope for lean-API policy), but noted.

---

### E. Micro: identity-keyed stmt-cache lookup (inspired by node:sqlite SQLTagStore)

**Source:** node:sqlite's `SQLTagStore` (v24.9.0) keys its LRU on tagged
template identity instead of SQL text. O(1) resolution with no hash.

**Adaptation to Dart:** Dart canonicalizes `const` string literals —
`identical(a, b)` is true for two string literals with the same content.
Our statement cache (exp 003, exp 071-deferred) looks up by string. An
`identityHashCode` fast-path *before* the string hash would collapse the
common app-code case (SQL strings that are literal constants passed
repeatedly) to a pointer compare.

**Expected size:** per exp 076 analysis, bind is ~0.3% of re-query wall
time — and hash lookup is probably smaller. This is deep in the noise
floor. Mentioning for completeness; I'd predict it gets rejected on
"unmeasurable" like exp 073 and 076.

**Priority:** low. Only worth it if another experiment opens up a harness
that can measure sub-100ns differences reliably.

---

### F. Expose `sqlite3_serialize` / `sqlite3_deserialize`

**Source:** bun:sqlite ships `.serialize()` / `.deserialize()`; used for
fork-style test isolation and in-memory snapshots.

**Why it's appealing:** Lean-API-compatible (it's one pair of methods on
`Database`), useful for tests and the read-only-open TODO item. Not a
hot-path perf win per se, but could enable lighter-weight read replicas:
serialize writer's in-memory `:memory:` DB once, deserialize into N
reader isolates that never touch disk.

**Priority:** low for perf, moderate for API completeness — probably
belongs in TODO.md, not the experiment log.

---

## What I ruled out

- **Turso / libSQL WALv2, `BEGIN CONCURRENT`, MVCC writes.** Only in
  their fork (C libSQL) or the Rust rewrite; neither is upstream-
  compatible with our sqlite3mc link. Exp 088 already tried
  `sqlite3_setlk_timeout` and got rejected. No path here without a
  fork decision.
- **JSONB (3.45+) for row transport.** It's a column *storage* encoding,
  not a wire format. Would not help our `selectBytes` path.
- **SIMD JSON (simdjson / sonic)** for result serialization. Exp 043
  already does SWAR; full SIMD would add a large dependency for a win
  that's almost certainly in the noise (our benchmarks already show
  string escape is a small fraction of JSON encode time).
- **io_uring for writer.** Linux-only; requires VFS work; exp 044
  already gets us most of the write-I/O reduction on F2FS via batch
  atomic write. Very high effort for limited platform reach.
- **`sqlite3_stmt_scanstatus_v2` + `SQLITE_SCANSTAT_COMPLEX` profiling.**
  Diagnostic, not perf. Useful for an internal profile-mode build, not
  a user-facing win.
- **Audit: column-name map cached per prepare, not per row** (drizzle
  pattern). Checked [resqlite.c:1319-1333](../native/resqlite.c) — we
  already cache `col_names` once per query before the step loop. Not a
  fresh win.

---

## Suggested order of work

1. **Bump sqlite3mc → SQLite 3.51+** (candidate B). One PR, runs the
   benchmark harness. Free win, validates the upstream pipeline is
   current.
2. **Probe deeply-immutable ResultSet feasibility** (candidate A).
   Investigation ticket first, not an implementation: does the pragma
   work on today's stable SDK, at all, outside `dart:internal`? If yes,
   full experiment; if no, park with a "re-check on next Dart stable"
   note.
3. **`PRAGMA wal_checkpoint=NOOP` probe** in the periodic checkpointer
   (refinement of exp 029). Small, contained, low risk. Only do after
   #1 since it requires 3.51+.
4. **PGO revisit** (candidate C), once #1–3 are in. Longer effort,
   higher variance outcome.

---

## Sources

- [SQLite changelog](https://sqlite.org/changes.html)
- [SQLite 3.51.0 release notes](https://sqlite.org/releaselog/3_51_0.html)
- [SQLite 3.47.0 release notes](https://www.sqlite.org/releaselog/3_47_0.html)
- [Dart language proposal 333 — shared memory multithreading](https://github.com/dart-lang/language/blob/main/working/333%20-%20shared%20memory%20multithreading/proposal.md)
- [dart-lang/sdk#56841 — implement shared native memory multithreading](https://github.com/dart-lang/sdk/issues/56841)
- [Dart deeply-immutable design doc](https://github.com/dart-lang/sdk/blob/main/runtime/docs/deeply_immutable.md)
- [Announcing Dart 3.8](https://medium.com/dartlang/announcing-dart-3-8-724eaaec9f47)
- [bun:sqlite docs](https://bun.com/docs/runtime/sqlite)
- [Node.js node:sqlite API](https://nodejs.org/api/sqlite.html)
- [better-sqlite3 API docs](https://github.com/WiseLibs/better-sqlite3/blob/master/docs/api.md)
- [Turso / libSQL direction](https://betterstack.com/community/guides/databases/turso-explained/)
- [Drift changelog](https://pub.dev/packages/drift/changelog)
