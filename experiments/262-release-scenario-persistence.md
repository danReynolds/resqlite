# Experiment 262: Persist the release suite per scenario, and let memory fail a run

**Date:** 2026-08-05
**Status:** Accepted
**Category:** Measurement
**Direction:** `measurement-system`
**Benchmark Run:** none — this changes the harness, not the runtime. The
  evidence is a deliberately killed run, described under Results; committing its
  partial artifact would put a scratch label on the trend charts.

## Problem

Two things were wrong with the release suite, and they turn out to be the same
problem seen from different ends: **a memory regression could not stop anything,
and neither could a crash stop costing everything.**

**A crash still destroyed the run.** #282 diagnosed this and fixed it one level
too coarsely. It made the suite persist after each completed *repeat*, so a run
that got through four of five repeats keeps four. But the peer segfault it was
written against — `pkg_sqlite3_connection_pool_notify_updates`, in sqlite_async's
native code — fires at the `Memory` scenario, which is the fifteenth of sixteen
*inside repeat 1*. No repeat ever completes, so nothing is ever written. Exps
260 and 261 both attempted a release run and both produced no artifact at all,
after running fourteen scenarios successfully each time. That is the concrete
reason the trend charts are sparse, and #282's own commit message ("a partial run
self-excludes from trends rather than polluting them") already had the right
idea — it just needed to apply below the repeat.

**A memory regression was reported and then ignored.** `generateMemoryComparison`
has always produced a table with per-benchmark thresholds (bootstrap MDE, 0.5 MB
floor) and a `🔴 Regression` marker. Nothing ever consumed it. `signals.json` has
carried a candidate for "per-benchmark RSS acceptance criteria" since 2026-05-02;
the criteria existed, the *acceptance* did not.

[Exp 261](261-focused-memory-guard.md) closed the equivalent hole for focused
harnesses and established that peak read-path memory has been flat for three
months. That makes this the right moment to gate: there is no backlog of
regressions for a new gate to trip over.

## Approach

**Per-scenario persistence.** `_runSuiteOnce` now takes an `onScenario` callback
and invokes it after each scenario with the markdown accumulated so far. The
runner persists the artifact on every callback, so the file on disk is never more
than one scenario behind the process.

Two details keep a partial run from lying:

- `repeatCount` counts only repeats that *finished*. A run killed inside repeat 1
  reports `repeatCount: 0`, so nothing reading it for sample depth can be fooled
  by a repeat that was still in flight.
- The artifact gains `scenariosCompleted`, `scenarioTotal`, and `partial: true`
  when the two differ — self-exclusion in the same shape as `gitDirty` and
  `--repeat=1`, both of which already drop a run from the trend charts.

Rewriting the scenario list through a `step()` helper also fixed a live
inconsistency: the standard suite counted `[1/15]` through `[14/15]` and then
`[15/16]`, `[16/16]`. `scenarioTotal()` is now the single source for both the
progress labels and the persisted total, so they cannot drift again.

**Memory acceptance criteria.** `compareMemory` returns a `MemoryComparison` —
the same table as before, plus `wins`/`regressions`/`neutral` and the names of
the benchmarks that regressed. `generateMemoryComparison` stays as a render-only
wrapper so existing callers are untouched. The runner prints a regression banner
naming each benchmark, and `--fail-on-memory-regression` makes it exit non-zero.

The flag is opt-in rather than default deliberately. A local run should still
report a regression without failing; CI is where a gate belongs, and turning it
on there is a maintainer's call, not this experiment's.

## Results

**The persistence fix, tested by killing a run.** `SIGKILL` during scenario 10 of
16, `--repeat=1`:

| | before | after |
|---|---|---|
| artifact written | none | `2026-08-05T09-12-35-exp262-probe.json` |
| scenarios preserved | 0 | 9 of 16 |
| resqlite metrics preserved | 0 | 153 |
| `repeatCount` | — | 0 (correct: no repeat finished) |
| `partial` | — | `true` |

Nine scenarios and 153 metrics survive a kill that previously produced nothing.
Against the crash that actually happens — the peer dying at scenario 15 — this
preserves fourteen scenarios including every read, write and streaming lane;
the Memory scenario itself is the one lost, which is unavoidable while the peer
crashes inside it.

**The gate**, covered by `test/release_partial_run_test.dart`: a rise beyond the
per-benchmark threshold sets `hasRegression` and names the benchmark with its
delta; a fall is a win and never trips it; a move inside the threshold is
neutral; and neither a missing `## Memory` section nor a missing baseline can
fail a run, since a gate that fires on absent data is a gate people disable.

The gate shipped to review **unable to fail anything.** It set the global
`exitCode` and the runner then called `exit(0)`, which discards it. The unit
tests could not have caught that: they exercised `compareMemory` thoroughly and
never asked what the caller did with the verdict, so a comparison that correctly
reported a regression sat behind an exit path that always reported success. The
fix passes the status explicitly (`exit(memoryGateFailed ? 1 : 0)`), and the
decision is now a named `shouldFailOnMemory` with its own tests — which covers
the predicate, though it is worth being clear that what actually caught this was
review, not a test, and that an integration test asserting the process exit
status is the only thing that would have.

## Outcome

**Accepted.** A crash now costs the scenario in flight rather than everything
before it, and a memory regression is something a caller can act on.

What this does not fix: the peer crash itself, which is a sqlite_async
regression (#282 established that exp 229's own sha crashes today at the same
stage, so only the peers changed). It also leaks its temp databases — the
segfault skips the `finally` that removes them, and ten of them, ~1.2 GB, had
accumulated on this machine from the crashed runs of the last two days. Worth a
follow-up that seeds into a directory the runner cleans on startup rather than
relying on unwind.

Would revisit the opt-in default if a memory regression ever reaches `main`
unnoticed; at that point `--fail-on-memory-regression` belongs in CI's release
job rather than in a maintainer's hands.

## Test plan

- `dart analyze --fatal-infos` on `benchmark/` and the new test — clean
- `test/release_partial_run_test.dart` — 10 tests: partial-run marking,
  `repeatCount` not inflating mid-repeat, backward compatibility when the new
  fields are absent, and the six gate behaviours above
- End-to-end kill test described in Results, artifact inspected and then removed
- `dart test` — full suite
