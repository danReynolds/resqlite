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
- [`JOURNAL.md`](JOURNAL.md) — the runner's notebook. Read this carefully:
  it carries the transferable lessons from prior runs, but also surprises,
  hunches, external changes, and "that wasn't what I expected" notes that
  the structured maps don't surface. Skim it for anything relevant to the
  direction you're considering before committing — a previous runner may
  have already flagged the trap you're about to walk into, or pointed at
  the workload that would make your idea worth running.
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
- add to [`JOURNAL.md`](JOURNAL.md). The journal is the runner's notebook —
  most runs should leave at least one entry behind. Things worth jotting:
  surprises during measurement, a finding that didn't fit the experiment
  writeup, an external change worth flagging for future runners, a hunch
  that deserves a future experiment, a small breakthrough about how a
  subsystem actually behaves, a "huh, that wasn't what I expected" moment.
  Free-form is fine — a paragraph, a short list, a single sentence with a
  link. Keep entries short enough that the next reader actually reads them,
  cite the experiment(s) involved, and end transferable lessons with a
  *Reapplies* note. Per-direction state still belongs in `signals.json`,
  not the journal; narrative milestones still belong in `MILESTONES.md`,
  not the journal.
- do not edit [`MILESTONES.md`](MILESTONES.md) as part of an experiment run.
  That file is updated on maintainer request, not per experiment.
- regenerate docs/check generated data as needed
- run focused validation plus the relevant repo checks
- open a PR, watch CI/review, and address actionable feedback

## PR description

The PR body is a *summary of the experiment markdown for someone who
hasn't read it yet*, not a checklist of process metadata. It should be
readable on its own and roughly mirror the structure of the writeup:

- **Hypothesis / question** the experiment was answering, in one or two
  sentences.
- **What was changed** — a brief implementation summary (or, for a
  pre-implementation rejection, a brief audit summary). Link to the
  files / functions touched. Skip if the markdown writeup is short
  enough that the reader will just open it.
- **Notable benchmark deltas** in a markdown table, with the workload,
  baseline, candidate, and delta columns. Call out wins, regressions,
  and any noisy control metrics. For pre-implementation rejections,
  substitute the cost framing or audit table that justified the
  decision.
- **Conclusion** — accepted / rejected / deferred / in-review, plus the
  one-line reason.
- **Takeaways and reopen triggers** — what future runners should learn
  or watch for. This is the same content as the experiment markdown's
  *Future Notes* and the `signals.json` `nextSignals`, restated for the
  reviewer.
- **Test plan** — the validation actually run, plus anything the
  reviewer should sanity-check.

A PR that reads like a stripped-down version of the markdown is
correct. A PR that reads like a list of files touched + a CI status
report is not — the reviewer should not have to open the markdown to
learn what the experiment was about.

The final summary in your run output (separate from the PR body)
should clearly state what was tried, what happened, whether each idea
was accepted/rejected/deferred, and what future experimenters should
learn from the run.
