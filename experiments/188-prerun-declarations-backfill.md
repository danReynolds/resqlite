# Experiment 188: Pre-178 benchmark-run declarations backfill

**Date:** 2026-06-19
**Status:** Accepted
**Direction:** `measurement-system`
**Benchmark Run:** none (CI guardrail / methodology tooling extension; no runtime code, structural counter evidence below)

## Problem

[Exp 178](178-missing-run-declaration-guard.md) added
`_assertNewExperimentsLinkOrDeclareRun` over a pure
`findUndeclaredMissingRunExperiments` detector that fails the build when a
chartable (accepted / in-review) experiment numbered `>= 178` has no linked
release run AND no `**Benchmark Run:**` opt-out declaration. The cutoff was a
pragmatic pilot — it bought the guard for new work without forcing a backfill
in the same PR. The structural tally exp 178 ran at the time:

| Status     | null-run count | declare `**Benchmark Run:**`? |
|------------|---------------:|-------------------------------|
| accepted   | 7              | 0 of 7                        |
| in_review  | 16             | 5 of 16                       |

So `~17` pre-178 chartable experiments were sitting outside the guard's scope,
still indistinguishable from forgotten result artifacts. Exp 178's
`nextSignals` named the follow-up directly:

> to pull the ~17 pre-178 silently-unmapped chartable experiments under the
> guard, backfill their `**Benchmark Run:**` headers (or commit their missing
> result files) and lower `_benchmarkRunDeclarationCutoff` in the same change

This experiment is that pass.

### Structural evidence at the start of this run

Mirroring exp 178's pure detector against `docs/experiments/history.json` on
the current `main`:

| # | status | title | header at start of run |
|---|---|---|---|
| 003 | accepted | C-level connection + statement cache | (absent) |
| 004 | accepted | NOMUTEX with per-query locking | (absent) |
| 007 | accepted | C-level connection pool | (absent) |
| 008 | accepted | Flat value list + lazy ResultSet | (absent) |
| 009 | accepted | Batch FFI (resqlite_step_row) | (absent) |
| 037 | accepted | Persistent JSON buffer per reader | (absent) |
| 038 | accepted | Stack allocation for column name arrays | (absent) |
| 083 | in_review | Stream rerun pre-dispatch queue | (absent) |
| 116 | in_review | Wide batch insert release coverage | (absent) |
| 118 | in_review | FIFO dispatch waiters with counter gate | (absent) |
| 119 | in_review | Post-FIFO dispatch pressure audit | (absent) |
| 125 | in_review | Wide ASCII batch parameter encoding | (absent) |
| 126 | in_review | Wide UTF-8 batch parameter packing | (absent) |
| 136 | in_review | Completion-side reader-handler counter | (absent) |
| 161 | in_review | Concurrent standalone writes release coverage | (absent) |
| 172 | in_review | Long-payload stream hash coverage | (absent) |

Plus one experiment that **did** carry a `**Benchmark Run:**` header but whose
content did not start with one of the opt-out keywords
(`none`/`n/a`/`tracelite`):

| # | status | title | header at start of run |
|---|---|---|---|
| 174 | in_review | selectBytes native-view transfer | `Focused A/B (large_bytes_transfer.dart), ...` |

The probe that produced these rows is a thin transcription of
`findUndeclaredMissingRunExperiments` for sanity checking; it is intentionally
not committed (the live test
`the live experiment set passes the guard at the shipped cutoff` is the
durable equivalent).

## Hypothesis

Walking the cutoff back from `178` to `1` would catch every chartable id under
the same `find/assert` chain exp 178 shipped — provided each of the 16
silently-unmapped experiments above plus exp 174 gains a declared
`**Benchmark Run:**` header that starts with an opt-out keyword. After the
backfill:

1. `docs/experiments/history.json` should be **byte-for-byte unchanged for
   every pre-existing experiment row** (only the new exp 188 row is added),
   because none of the backfilled experiments were linked to a release run
   anyway — the linker recorded `benchmarkRun: null` — and the
   `_skipBenchmarkRunMapping` flag is consumed inside
   `_attachBenchmarkRunMappings` before serialization.
2. The pure detector at `cutoff: 1` should return zero issues on the live
   experiment set — codified as a regression test.

## Approach

Per-experiment dispositions (no result files exist for any of these dates and
ids — `expNNN-*` prefix matching produces no candidates, and same-day baselines
are general baselines, not exp-NNN-specific):

- **003, 004, 007, 008, 009, 037, 038, 083** — Pre-convention. The
  `**Benchmark Run:**` line records that and points at the same-day general
  baselines.
- **116, 161** — Release-suite *coverage* rows. The wins they enable land in
  downstream experiments (125/126 for 116; the writer-scheduling cluster for
  161). The coverage row itself ships no benchmark delta.
- **118, 136** — Profile-mode counters gated by `kProfileMode`. The counter
  numbers are the deliverable; no release-suite movement is expected.
- **119** — Post-FIFO profile audit; profile-mode only.
- **125, 126** — Wide-batch parameter encoder rewrites. Both have focused
  `batch_param_flatten.dart` evidence and release Wide Batch Insert A/Bs in
  their Results sections, but no exp-125 / exp-126 release artifact was ever
  committed to `benchmark/results/`. The opt-out header names the focused
  workload directly.
- **172** — Streaming-suite coverage row + focused `streaming.dart` addition.
  No exp-172 release artifact.
- **174** — Existing header was descriptive but did not start with an opt-out
  keyword, so it failed the lowered guard. Rewritten to lead with
  `none — focused A/B ...` while preserving the existing detail and adding the
  cross-link to exp 175's `selectBytes() large bytes` release lane (the actual
  public regression guard for this path).

Plus the one-line constant change:

```dart
-const int _benchmarkRunDeclarationCutoff = 178;
+const int _benchmarkRunDeclarationCutoff = 1;
```

The unit test fixture `100-test.md` (in `benchmark_pipeline_test.dart`'s
`generate_devices parses in-review experiments and Approach sections`) carried
a chartable in-review experiment without a declaration — that fixture predated
the guard at cutoff 178 too, and is updated to declare the opt-out so the test
exercises a representative valid post-cutoff state.

A new test (`exp 188 walked the cutoff to 1 — every chartable id is in scope`)
asserts that the pure detector at `cutoff: 1` flags chartable ids `003` and
`083` when no opt-out is declared, so the cutoff change itself has a regression
anchor in the same place exp 178's tests live.

## Results

After the backfill, running the full generator on the live experiments tree:

```
$ dart run benchmark/generate_history.dart
...
Parsed 130 benchmark runs from 131 files.
Parsed 147 experiments.
docs/experiments/history.json is current (24 tracked metrics).
```

| Check | Before exp 188 | After exp 188 |
|---|---|---|
| `_benchmarkRunDeclarationCutoff` | `178` | `1` |
| Chartable ids in guard scope | `>= 178` (~14 experiments) | every chartable id (148 experiments) |
| Silently-unmapped chartable experiments per pure detector | 17 (probe at cutoff 1 against `main`) | 0 |
| `docs/experiments/history.json` diff after backfill (before adding the exp 188 row) | n/a | empty |
| `docs/experiments/history.json` diff after the experiment doc lands | n/a | only the new exp 188 row |
| `dart test test/benchmark_pipeline_test.dart` | 14 tests pass | 15 tests pass (one new regression anchor) |
| `dart analyze` on touched files | no issues | no issues |

The history.json byte-for-byte equality is the load-bearing claim — it confirms
the chart's data did not move, only the guard's reach.

## Decision

**Accepted.** This is a tooling extension: it strengthens the existing exp 178
guard from a partial cutoff to full coverage. Trades made:

- Pre-convention writeups (003 / 004 / 007 / 008 / 009 / 037 / 038 / 083) now
  carry one extra header line each. The cost is a few hundred bytes of doc
  churn; the value is that *any* future edit to those writeups (e.g. status
  change, title fix) is now under the same guard as new work, so a regression
  where someone accidentally deletes a result file mapping on an old
  experiment fails CI instead of silently dropping a chart point.
- Recent in-review experiments (116 / 118 / 119 / 125 / 126 / 136 / 161 / 172)
  gain explicit declarations of *why* they have no release artifact, which is
  exactly the signal exp 178's lesson named:

  > A guard against the wrong value often leaves the missing value silent.
  > Reapplies whenever a guardrail validates that a present value is correct.
  > Ask the symmetric question: what happens when the value is absent
  > entirely?
  > — [`JOURNAL.md`](JOURNAL.md), seeded by exp 178.

- The single regression candidate the lowered cutoff exposed (exp 174) is now
  also declared, which means future selectBytes-transfer experiments inherit
  the same forced-declaration discipline as 178+ work.

The change touches no runtime code and `history.json` is byte-for-byte
unchanged, so there is no soak risk from this experiment on its own — the
guard's stricter contract is the only behavior change.

## Future Notes

- If the chart ever starts plotting rejected experiments (it currently doesn't,
  per exp 178), the guard's status filter (`accepted` / `in_review`) needs to
  widen too — but no cutoff bump is required after this run.
- If a new pre-cutoff experiment somehow appears (e.g. a renumbering pass), the
  declaration discipline is already enforced by the same constant; no further
  tooling change.
- For any future pre-178 experiment that gains a real release artifact (e.g.
  someone re-runs exp 125 against a current main to capture a fresh
  `2026-MM-DDTHH-MM-SS-exp125-*.md` row), the opt-out header should be
  *removed* in the same change so the linker maps the experiment correctly.
