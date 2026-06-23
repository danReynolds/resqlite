# resqlite Experiments

Each file documents a performance experiment: what we tried, what we measured, and whether it worked. These serve as institutional memory — before trying a new optimization, check here to see if we've already explored it.

## Accepted

Experiments that proved their value and were merged into the codebase.

| # | Experiment | Impact | Commit |
|---|---|---|---|
{{ROWS:accepted}}

## In Review

Recent or pending-acceptance experiments. An entry sits here either
because the PR is still open, or because the experiment has merged but
is in its post-merge soak window — typically two weeks, longer if a
release-cycle metric has not run yet. Soak is for catching regressions
that only surface under realistic workloads or downstream rebases (see
the journal entry on exp 114 for the canonical example). Promote rows
to **Accepted** once the soak window closes and no new evidence has
moved them.

| # | Experiment | Impact | PR |
|---|---|---|---|
{{ROWS:in_review}}

## Rejected

Experiments that didn't work out. Each has valuable context on *why* — check before revisiting similar ideas.

| # | Experiment | Why Rejected |
|---|---|---|
{{ROWS:rejected}}

## Conventions

- **Experiment number:** Monotonically increasing, never reused
- **Date:** When the experiment was run (full timestamp preferred: `2026-04-14T12:30:00`)
- **Status:** `Accepted` (merged + soak window closed), `In Review` (PR open or in post-merge soak window — typically two weeks), or `Rejected` (abandoned, with explanation). New experiments start at `In Review` and graduate after the soak.
- **Commit:** Git hash of the implementing commit (added to header of each accepted experiment)

### Research Map

Scheduled experimenters should use
[`RUNNER_INSTRUCTIONS.md`](RUNNER_INSTRUCTIONS.md) as the copyable instruction
block for recurring experiment systems. Those instructions point runners at
this README, [`signals.json`](signals.json), [`JOURNAL.md`](JOURNAL.md), and
the project [`stories`](../doc/stories/) before choosing work.

`signals.json` is the canonical research map. These files are steering context,
not an allowed list. They should make prior work easy to understand without
preventing creative experiments outside the current map. A strong new
experiment can follow an active direction, revisit an area that recently looked
weak, or open a new direction entirely. The important thing is to explain why
the attempt is worth a bounded pass in light of prior work.

When an experiment changes what future work should try, de-emphasize, measure,
or watch:

- update the experiment writeup with the record of what happened
- update `signals.json` with machine-readable direction context
- add to `JOURNAL.md` only when the run surfaced a transferable lesson a
  future runner could reapply elsewhere
- leave `../doc/stories/` alone — story posts are updated on maintainer
  request, not per experiment

`signals.json` per-direction fields (see the inline `schemaNotes` block at
the top of the file for the canonical descriptions):

- `keyPriors` (required, max 6) — experiments a future runner must read.
- `archive` (optional) — older or superseded evidence; not required reading.
  Curate from `keyPriors` when a new accepted experiment supersedes an
  older one.
- `openCandidates` (optional) — dated candidate ideas waiting for the
  right workload, signal, or runner. Each item is `{idea, addedDate,
  addedAfter?, blockedOn?}`. Prune entries older than ~3 months that
  nobody picked up.
- `blockedOnMeasurement` (optional) — measurements that must land before
  the next implementation experiment in this direction is worth
  attempting. Empty if no measurement is gating new work.

### Standard Template

Use these exact headings so the experiments page can extract content automatically:

```markdown
# Experiment NNN: Title

**Date:** 2026-04-14
**Status:** Accepted / Rejected
**Direction:** `direction-id`
**Commit:** [`abc1234`](https://github.com/danReynolds/resqlite/commit/abc1234)
**Archive:** [`archive/exp-NNN`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-NNN)

## Problem

What performance issue or opportunity was identified.

## Hypothesis

The proposed optimization and why it should work.

## Approach

What was built or changed. Implementation details.

## Results

Benchmark measurements. Use markdown tables for comparisons.

## Decision

Why accepted or rejected. Trade-offs considered.

## Future Notes

Optional. Short notes for future experimenters: adjacent prior work, what would
make the area interesting again, or what to measure before revisiting.
```

Header fields:

- **Commit** — required for Accepted experiments; points at the merged
  implementation commit on main.
- **Archive** — added for Rejected experiments *whose implementation is
  worth preserving for future re-evaluation* (the common case when the
  rejection reason is "below noise floor, not worth the complexity").
  Points at a git tag (`archive/exp-NNN`) that pins the last commit of
  the experiment branch before it was deleted. See the
  `resqlite-experiment` skill for the tagging workflow. Skip this field
  for rejections of the form "implementation was broken" — there's
  nothing worth preserving.

Older experiments use varied headings (`What We Built`, `Changes`, `Benchmark`, `Why Accepted`, etc.) — those still work, but new experiments should follow this template.
