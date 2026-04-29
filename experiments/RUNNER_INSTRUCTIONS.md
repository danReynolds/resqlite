# Scheduled Experiment Runner Instructions

Use this file as the copyable instruction block for any scheduled or recurring
Resqlite performance experiment runner.

## Goal

Improve Resqlite performance while preserving the lean public API. It is valid
for a run to produce an accepted optimization, a rejected experiment with useful
evidence, or a measurement/profiling improvement that makes future experiments
better.

## Preflight

Before choosing an experiment, read:

- [`README.md`](README.md) — the experiment table and templates
- [`signals.json`](signals.json) — the canonical per-direction research map
- [`JOURNAL.md`](JOURNAL.md) — transferable lessons from prior experiments
- [`MILESTONES.md`](MILESTONES.md) — the curated narrative arc, for context on
  how the current state was reached
- recent individual experiment writeups relevant to the area you are considering

`signals.json` is the canonical research map. Treat it as context, not an
allowed list. You may pursue active directions, revisit areas that recently
looked weak, or open a new speculative direction. The important thing is to
explain why the attempt is worth a bounded pass in light of prior work.

Prefer high-signal work. If the missing piece is measurement, profiling, or a
benchmark, improve that first instead of forcing an implementation experiment.

## Research

- Check recent Dart, SQLite, sqlite3mc, compiler, OS, and peer-library changes
  when they could affect the chosen direction.
- Prefer official/primary sources for language, runtime, SQLite, and tooling
  claims.
- Connect external findings back to Resqlite's actual hot paths and API goals.

## Experiment Selection

Before coding, write a short working note for yourself:

- what prior experiments are adjacent
- why this is not just a duplicate attempt
- what new evidence, benchmark, workload, implementation shape, or external
  change makes it worth trying now
- what result would make you accept, reject, or defer the idea

This note does not need to be committed directly, but the final experiment
writeup should make the reasoning clear.

## Measurement

- Use focused benchmarks when they better isolate the target path.
- Use multi-run comparisons when measuring small effects.
- Treat noisy control metrics as evidence about the run, not just the
  implementation.
- Keep raw per-run profile JSONs local; commit aggregate markdown when useful.
- If an idea targets memory or allocation, prefer profiler/RSS evidence over
  wall-time-only claims.

## Postflight

When finished:

- write or update the experiment record. Keep markdown human-readable;
  machine-oriented direction metadata belongs in `signals.json`. For rejected
  experiments, the writeup should explain why the direction looked plausible,
  what was measured, and what would make the area interesting again — a
  "rejected, no signal" record is worth less than a "rejected because X, would
  reopen if Y" record.
- update [`signals.json`](signals.json) if the run changes how future agents
  should interpret an area.
- add to [`JOURNAL.md`](JOURNAL.md) only when the run surfaced a *transferable*
  lesson — something a future runner could reapply to a different direction or
  could waste time relearning. Per-direction state goes in `signals.json`, not
  the journal.
- do not edit [`MILESTONES.md`](MILESTONES.md) as part of an experiment run.
  That file is updated on maintainer request, not per experiment.
- regenerate docs/check generated data as needed
- run focused validation plus the relevant repo checks
- open a PR, watch CI/review, and address actionable feedback

The final summary should clearly state what was tried, what happened, whether
each idea was accepted/rejected/deferred, and what future experimenters should
learn from the run.
