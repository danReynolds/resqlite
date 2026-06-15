# Experiment 164: EQP Rowid Dirty Elision

**Date:** 2026-06-14
**Status:** Rejected
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Archive:** [`archive/exp-164`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-164)

## Problem

Exp 134 showed that row-level dirty precision can collapse keyed-PK miss-path
work: only writes touching watched rowids need to re-query a stream shaped like
`WHERE id = ?`. That implementation was rejected because it relied on a custom
SQL recognizer.

The remaining question was whether SQLite could provide enough evidence to keep
the same optimization private without growing a resqlite SQL grammar.

## Hypothesis

Use SQLite's planner instead of parsing SQL text. If `EXPLAIN QUERY PLAN`
reports an INTEGER PRIMARY KEY rowid lookup for a one-parameter, one-table
stream query, then `StreamEngine` can attach a private rowid dependency and the
native writer can publish dirty rowids captured by the preupdate hook.

The change would be worth keeping if rowid stream setup or keyed-PK dispatch
improved while unrelated stream registration and stream dispatch guardrails
stayed neutral.

## Approach

The archived candidate added:

- native dirty `(table, rowid)` harvesting behind the existing preupdate hook;
- a Dart `TableRowDependency` layer that falls back to table/column invalidation
  whenever row precision is absent or unreliable;
- a `StreamEngine` classifier that runs `EXPLAIN QUERY PLAN <query>` for
  one-int-parameter, one-table streams and looks for SQLite's rowid lookup
  detail;
- a small private plan cache keyed by exact SQL and table so repeated stream
  registrations share the planner inspection;
- Tracelite wrapper support for `--direction=stream-initial-drain`, with rowid
  setup as the primary lane and text/indexed-int stream setup as guardrails;
- `warmup_elapsed_ns` guardrails on broader stream-dispatch experiments, so
  invalidation wins cannot hide slower initial stream registration.

The production runtime candidate was removed after measurement. The Tracelite
guardrail additions remain because they make future setup-heavy stream changes
easier to evaluate.

## Results

Focused initial-drain Tracelite A/B:

```bash
dart run benchmark/run_tracelite_experiment.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp163-baseline \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp164-eqp-rowid-elision \
  --label=exp-164-rowid-plan-cache \
  --direction=stream-initial-drain \
  --runs=2 --min-repetitions=5 --max-repetitions=12 \
  --out-dir=build/tracelite-experiments/exp-164-rowid-plan-cache
```

| Scenario | Delta | Verdict | Max CV | p |
|---|---:|---|---:|---:|
| stream-initial-drain-rowid | -2.33% | neutral | 10.97% | 0.945 |
| stream-initial-drain-indexed-int | +1.49% | neutral/pass | 7.38% | 0.323 |
| stream-initial-drain-text | +5.69% | too_noisy | 33.10% | 0.370 |

Decision: `inconclusive`. Trace health passed, but the primary rowid setup lane
did not show a stable win.

Broader stream-dispatch guard run:

```bash
dart run benchmark/run_tracelite_experiment.dart \
  --tracelite-root=/Users/dan/Coding/tracelite \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp163-baseline \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp164-eqp-rowid-elision \
  --label=exp-164-rowid-plan-cache-stream-guard \
  --direction=stream-rerun-dispatch \
  --runs=2 --min-repetitions=5 --max-repetitions=12 \
  --out-dir=build/tracelite-experiments/exp-164-rowid-plan-cache-stream-guard
```

| Scenario | Delta | Verdict | Max CV | p |
|---|---:|---|---:|---:|
| high-cardinality-fanout | +0.70% | neutral | 1.02% | 0.123 |
| keyed-pk-subscriptions | -10.65% | too_noisy | 13.73% | 1.44e-8 |
| many-streams-writer-throughput | -0.08% | neutral | 1.11% | 0.684 |

Decision: `inconclusive`. The clean guardrails stayed mostly neutral, but the
targeted keyed-PK evidence was too noisy and the initial-drain run did not show
the setup win needed to justify the extra layer.

## Decision

**Rejected.** SQLite EQP is a better exploratory tool than a custom SQL parser,
but this candidate still required a bespoke native rowid set, a new dependency
type, plan inspection during stream registration, cache invalidation policy, and
planner-detail coupling. The Tracelite evidence did not show enough rowid setup
or end-to-end dispatch improvement to carry that production complexity.

No runtime code was kept. The implementation is preserved at `archive/exp-164`
because it is a useful reference if a future real workload changes the
cost/benefit case.

## Future Notes

- Keep row-level invalidation on hold unless a real workload or stronger
  dependency model changes the value side of the equation.
- Do not revive this by broadening resqlite's own SQL recognizer. EQP can be a
  bounded probe, but the production design still needs a clearer win than this.
- Keep using Tracelite `stream-initial-drain` and `warmup_elapsed_ns` guardrails
  for stream changes that move setup cost.
