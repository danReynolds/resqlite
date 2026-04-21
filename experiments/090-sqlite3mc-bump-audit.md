# Experiment 090: sqlite3mc bump audit — already current

**Date:** 2026-04-21
**Status:** Rejected (no bump needed — already on newest stable sqlite3mc)

## Problem

SQLite 3.51.0 (2025-11-04) advertised "use fewer CPU cycles to commit a
read transaction." The daily-research note flagged a bump as a
candidate: if our vendored sqlite3mc is behind, we get across-the-board
read-path wins for free.

## Hypothesis

Vendored copy lags upstream ⇒ a dependency bump pays for itself.

## Investigation

### Current vs. target

| Axis | Current (worktree) | Target candidate | Notes |
|---|---|---|---|
| sqlite3mc release | **2.3.2** (2026-03-19) | 2.3.3 (2026-04-10) | Only delta in 2.3.3 is SQLite uplift + fix for cipher-free nullify (issue #230) |
| Embedded SQLite | **3.51.3** (2026-03-13) | 3.53.0 (2026-04-09) | 3.52.0 was **withdrawn** upstream (index-on-expression / virtual-computed-column bug) |
| Source of truth | `third_party/sqlite3mc/VENDORING.md` | https://github.com/utelle/SQLite3MultipleCiphers/releases/tag/v2.3.3 | |

Our vendored copy is **37 days old**. The premise of the task brief — "If our vendored copy is older, bumping should produce free, across-the-board read-path wins" — does not hold. We already pulled the "fewer CPU cycles to commit a read transaction" work. That change shipped in 3.51.0 and we are on 3.51.3.

### What SQLite 3.53.0 would buy us

Based on the official 3.53.0 release log:

| Category | Change | Relevance to resqlite |
|---|---|---|
| Planner | Improved sort-and-merge for EXCEPT / INTERSECT / UNION | Low — not in hot path |
| Planner | Enhanced multi-way join optimization | Possibly relevant to fanout queries |
| Planner | Better EXISTS-to-JOIN transformation | Low |
| Correctness | WAL-reset corruption bug fix | **Already in 3.51.3** — not a 3.53.0 delta for us |
| Floating point | Default rounding: 15 → 17 significant digits | **Behavior change.** Could affect test snapshots / any caller parsing REAL as string |
| SQL | ALTER TABLE can add/remove NOT NULL / CHECK; REINDEX EXPRESSIONS; TEMP triggers on main schema | Not used by resqlite |
| C API | `sqlite3_str_truncate`, `sqlite3_str_free`, `sqlite3_carray_bind_v2`, `SQLITE_PREPARE_FROM_DDL`, `SQLITE_UTF8_ZT`, `SQLITE_LIMIT_PARSER_DEPTH`, `SQLITE_DBCONFIG_FP_DIGITS` | Additive only. No API we bind via FFI changes signature |
| CLI / QRF | Query Result Formatter, Unicode box-drawing | Not used — we don't ship the CLI |
| Platform | Windows RT removed | Not a platform we target |
| Parser | Bare semicolons after dot-commands silently ignored | CLI only — no impact on embedded |

**Net verdict:** no meaningful read-path or write-path perf win we can reliably bank. The FP default change is a *minor correctness hazard* (snapshot diffs) and adds risk we'd normally want a point release to shake out.

### Compile-flag drift audit

Diffed our `hook/build.dart:84-137` defines against SQLite 3.53.0's documented compile options. No drift:

| Our flag | Still valid in 3.53.0? | Notes |
|---|---|---|
| `SQLITE_DQS=0` | Yes | Unchanged |
| `SQLITE_DEFAULT_LOOKASIDE=1200,128` | Yes | Unchanged |
| `SQLITE_DEFAULT_PCACHE_INITSZ=128` | Yes | Unchanged |
| `SQLITE_ENABLE_BATCH_ATOMIC_WRITE` | Yes | Unchanged |
| `SQLITE_THREADSAFE=2` | Yes | Unchanged |
| `SQLITE_OMIT_UTF16` | Yes | Unchanged |
| `SQLITE_ENABLE_STAT4`, `SQLITE_ENABLE_FTS5`, `SQLITE_ENABLE_MATH_FUNCTIONS`, `SQLITE_ENABLE_PREUPDATE_HOOK` | Yes | Unchanged |
| `SQLITE_OMIT_*` block | Yes | Unchanged |

No removed or renamed flags affect us. No new *required* flags for 3.53.0. One new *optional* flag worth noting for a future bump: `SQLITE_DBCONFIG_FP_DIGITS` runtime option if we ever want to keep 3.52 / pre-3.53 FP rounding on a 3.53 binary.

### Risk table

| Risk | Severity | Mitigation if we bumped |
|---|---|---|
| 3.53.0 is a .0 release, 12 days old | **High** — violates the known-regressions policy | Wait for 3.53.2 |
| FP default rounding 15 → 17 digits | Medium — may break snapshot-based tests and any caller comparing REAL strings | Set `SQLITE_DBCONFIG_FP_DIGITS=15` at `sqlite3_open_v2` time |
| 3.52.0 → 3.53.0 planner delta lumps two releases' worth of changes into one (3.52 was withdrawn, all its features rolled forward) | Medium | None — inherent to skipping 3.52 |
| sqlite3mc 2.3.3 encryption API surface | Low — only delta is issue #230 fix | We don't use the encryption init path in a way affected by the fix |
| `SQLITE_ENABLE_STAT4` interaction with new multi-way join planner | Low–Medium — historically planner reworks + STAT4 have had cost-estimate regressions (e.g. 3.46.x) | Monitor benchmark deltas post-bump |

### Benchmarks

**Not run.** The investigation stopped at target-version feasibility
because 3.53.0 fails our pre-existing .0-release policy. Running a
bench wouldn't change the recommendation: even if 3.53.0 won by 5% on
some workload, we wouldn't land it at .0. The cautionary exp-088
guidance about "don't hand-wave single runs" applies equally to "don't
hand-wave a bake-time policy."

## Decision

**Rejected — hold at sqlite3mc 2.3.2 / SQLite 3.51.3.** Reasons:

1. We are already on the newest stable sqlite3mc tracking a stable SQLite release. The bump thesis ("our vendored copy is old") is false — it is 37 days old.
2. The only newer target (3.53.0) is a .0 release 12 days old, explicitly excluded by the policy in the task brief.
3. No compile-flag drift; no signal of a significant perf win specific to our hot paths in the 3.53.0 changelog.
4. 3.53.0 ships a default FP rounding behavior change that is a small but real snapshot / test hazard.

### Revisit trigger

Re-run this investigation when **any** of these is true:

- SQLite 3.53.2 (or later .2+) ships upstream, and sqlite3mc cuts a release tracking it.
- A specific workload regression surfaces that has a known fix in >3.51.3.
- We decide to adopt a 3.53.0 API (none planned — `sqlite3_carray_bind_v2` is the only mildly interesting one and we have no current consumer).

### If a future bump is approved

Step-by-step plan (for the record, not for this PR):

1. Download `sqlite3mc-<version>-amalgamation.zip` from the GitHub release.
2. Overwrite `third_party/sqlite3mc/{sqlite3.h,sqlite3ext.h,sqlite3mc_amalgamation.c,sqlite3mc_amalgamation.h}`.
3. Update `third_party/sqlite3mc/VENDORING.md` with new version + SHA-256s + source id.
4. If bumping into 3.53.x: add `sqlite3_db_config(db, SQLITE_DBCONFIG_FP_DIGITS, 15)` in `native/resqlite.c::resqlite_open` to pin pre-3.53 FP rounding, **or** explicitly decide to accept the new default and update any test snapshots.
5. `dart pub get && dart test` — zero expected failures.
6. `dart run benchmark/run_profile.dart` on baseline branch and bump branch with `--repeat=5`, then `benchmark/profile/diff.dart`. Commit only `<label>-aggregate.md` per `feedback_profile_json_aggregate_only.md`.
7. Commit order: (a) vendored sources + VENDORING.md, (b) any FP-digits shim in resqlite.c, (c) benchmark aggregate, (d) CHANGELOG entry noting SQLite version.

## Appendix: sqlite3mc release map

| sqlite3mc tag | Date | SQLite | Our status |
|---|---|---|---|
| v2.3.0 | 2026-03-08 | 3.52.0 (withdrawn) | Skipped — upstream withdrew |
| v2.3.1 | 2026-03-13 | 3.51.3 | |
| **v2.3.2** | **2026-03-19** | **3.51.3** | **Current** |
| v2.3.3 | 2026-04-10 | 3.53.0 | Candidate, rejected (too new) |
