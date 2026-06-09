# Scheduled Experiment Runner Instructions

Use this file as the copyable instruction block for any scheduled or recurring
Resqlite performance experiment runner.

## Goal

Improve Resqlite performance while preserving the lean public API. The normal
successful outcomes are an accepted optimization or a rejected implementation
experiment with useful evidence. A measurement/profiling improvement is valid
support work only when it unlocks a named future optimization decision or lets
future runners reject a candidate confidently.

Default toward implementation experiments when there is a plausible, bounded
performance change to try. Measurement-only runs are lower-frequency support
work: use them when implementation would otherwise be speculative, not as an
equal-priority substitute for changing the hot path.

When extra measurement is needed, prefer adding the few counters, profile lanes,
or focused probes directly inside the performance experiment that will consume
them. Run the candidate while that instrumentation is present, then remove the
temporary measurement scaffolding before merge unless it is broadly reusable
across future experiments.

## Preflight

Before choosing an experiment, read:

- [`README.md`](README.md) — the experiment table and templates
- [`signals.json`](signals.json) — the canonical per-direction research map
- [`JOURNAL.md`](JOURNAL.md) — transferable lessons from prior experiments
- [`../doc/stories/`](../doc/stories/) — the curated narrative arc, for context
  on how the current state was reached
- recent individual experiment writeups relevant to the area you are considering

`signals.json` is the canonical research map. Treat it as context, not an
allowed list. You may pursue active directions, revisit areas that recently
looked weak, or open a new speculative direction. The important thing is to
explain why the attempt is worth a bounded pass in light of prior work.

Inside each direction, the fields you should actually read first:

- `keyPriors` — the experiments you must understand to evaluate work in
  this direction. Read all of them.
- `blockedOnMeasurement` — if non-empty, the next implementation
  experiment in this direction is gated. Prefer a measurement run only when
  it unblocks a named implementation path or can rule out a direction that
  would otherwise waste an implementation pass. If the measurement is not
  needed for that kind of decision, pick a different direction.
- `openCandidates` — dated candidate ideas. Prefer entries with a recent
  `addedDate` and a clear `blockedOn` you can resolve.

Prefer high-signal implementation work. If the missing piece is measurement,
profiling, or a benchmark, improve that first only when you can name the
optimization it enables or the candidate it will let future runners reject
confidently.

Before splitting out a measurement-only PR, ask whether the same branch can add
the small amount of instrumentation needed, run the implementation candidate,
and then remove or narrow the instrumentation after the decision is made. A
separate measurement run is the exception, not the default.

For branch-vs-baseline implementation experiments, prefer the integrated
Tracelite A/B wrapper in `benchmark/run_tracelite_experiment.dart`; it keeps
baseline history, candidate history, decision JSON, insights, graph data, and
the draft writeup together. Use focused profile or audit harnesses instead when
the signal map names a measurement blocker and the experiment's deliverable is
the new counter or aggregate evidence, not a production code-path change.

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
- what implementation candidate you are trying; if the run is measurement-only,
  why that candidate cannot be attempted in the same pass
- what new evidence, benchmark, workload, implementation shape, or external
  change makes it worth trying now
- what result would make you accept, reject, or defer the idea
- for measurement-only runs, the specific follow-up optimization, rejection, or
  de-prioritization decision the measurement is expected to unlock
- for temporary instrumentation, what will be removed before merge and what
  would justify keeping any counter, benchmark, or profile lane permanently

This note does not need to be committed directly, but the final experiment
writeup should make the reasoning clear.

## Measurement

Measurement is in service of performance work. Use it to choose, constrain, or
reject implementation ideas; do not stack diagnostic runs just because another
counter would be interesting.

Prefer "instrument and implement" over "instrument now, optimize later": add
only the measurements needed to make the current candidate legible, run the
candidate, and then delete temporary counters or harness branches unless the
result proves they should become shared infrastructure.

Before selecting a measurement-only run, make sure at least one of these is
true:

- `signals.json` marks the chosen direction as blocked on a missing measurement.
- A concrete implementation candidate exists, but the current suite cannot tell
  whether its target cost is material.
- A recent accepted or in-review experiment changed the hot path enough that an
  older candidate may now be obsolete.
- The measurement will let future runners remove or de-prioritize a candidate
  from `signals.json`.

Avoid back-to-back measurement-only runs unless the current signal map makes an
implementation pass genuinely speculative or a maintainer explicitly asks for
the diagnostic pass. After a measurement experiment lands, the next runner
should usually consume that signal with an implementation, rejection, or
direction cleanup rather than adding another diagnostic layer.

Permanent profiling code has a high bar. Keep a counter, benchmark, or Tracelite
profile lane only when it will be reused by multiple future experiments, guards
a release-facing regression risk, or replaces a weaker legacy measurement path.
Otherwise, preserve the insight in the experiment writeup and `signals.json`,
then remove the local scaffolding before opening the PR.

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
- do not edit [`../doc/stories/`](../doc/stories/) as part of an experiment
  run. Story posts are updated on maintainer request, not per experiment.
- run the experiment finalizer after the writeup, README row, and
  `signals.json` entry are in place:

  ```bash
  dart run benchmark/finalize_experiment.dart \
    --experiment=experiments/NNN-short-slug.md
  ```

  This regenerates `docs/experiments/history.json`, verifies generated docs,
  and checks that the experiment is indexed in both the README and signal map.
- run focused validation plus the relevant repo checks
- open a PR when the local experiment package is coherent enough for review

The final summary should clearly state what was tried, what happened, whether
each idea was accepted/rejected/deferred, and what future experimenters should
learn from the run. For measurement-only runs, also state the implementation
candidate or direction decision that should come next. If the run stops at local
completion, say that explicitly and list the local validation that passed. If it
claims PR or merge readiness, also watch CI/review and address actionable
failures before declaring the run finished.

### Post-merge soak and promotion

A merged experiment lands in **In Review** for a soak window — typically two
weeks, longer if a release-cycle benchmark hasn't run yet. The window catches
regressions that only surface under realistic workloads or downstream rebases
(see exp 114 in `JOURNAL.md` for the canonical "in-flight workload elided by
a freshly-merged accepted experiment" case).

A separate promotion pass moves merged-and-soaked experiments from **In
Review** to **Accepted** in `experiments/README.md`. This is not the
implementing runner's job — it's a periodic curation pass, suitable for a
scheduled maintenance task. The promoter's checklist:

- merge date > 2 weeks ago,
- no release-suite regression has shown up since merge,
- no rebase or follow-up experiment has changed the conclusion.

If any check fails, leave the row in In Review and add a short note in
`signals.json` explaining what's blocking acceptance.

## Branching, worktrees, and PRs

Every scheduled experiment run must:

- **Work on a dedicated git worktree**, never on a checkout of `main`
  directly. Create the worktree off current `origin/main` and use a
  branch name of the form `exp-NNN-short-slug` (e.g.
  `exp-115-dispatcher-park-counters`). If the runner already starts you
  in a worktree on a stale or unrelated branch, create a fresh branch
  from `origin/main` before committing — do not pile a new experiment
  on top of an unrelated in-flight branch.
- **Resolve dependencies in every fresh worktree before local validation.**
  Run `dart pub get` in the experiment worktree before `dart analyze`,
  focused tests, or any direct benchmark script. For Tracelite A/B runs,
  also make sure both baseline and candidate worktrees have dependencies
  resolved before interpreting setup failures as code failures.
- **Push the branch to `origin` and open a real (non-draft) PR.** Do
  not leave the work unpublished, and do not open the PR as a draft.
  Draft PRs are not ready to merge and are easier for reviewers to
  defer or ignore; a runner that finishes cleanly should produce a PR
  that is immediately reviewable.
- **Distinguish local completion from merge readiness.** A local experiment is
  complete when the branch has coherent code/docs/artifacts, focused validation
  has passed, and the finalizer is green. A PR is not ready to merge until CI
  and review feedback have also been checked.
- **Wait for CI on the PR and address actionable failures** before declaring a
  PR ready to merge. A red PR is not merge-ready.
- **Wait for automated review, not just CI, before merge readiness.** After
  opening the PR, poll
  for review submissions for a few minutes, then read inline review
  threads with thread-aware review data. `gh pr view --json` does not
  expose `reviewThreads`; use the GraphQL API directly:

  ```bash
  gh api graphql -f query='query { repository(owner: "<owner>", name: "<repo>") { pullRequest(number: <N>) { reviewThreads(first: 50) { nodes { id isResolved isOutdated comments(first: 5) { nodes { body author { login } path line } } } } reviews(first: 20) { nodes { author { login } state body submittedAt } } } } }'
  ```

  The top-level `gh pr view` overview misses inline comments that only
  live in review threads — and Copilot in particular leaves most of
  its actionable feedback there.
- **Address unresolved, non-outdated actionable review threads** before
  declaring the run finished. After pushing the fix commit, mark each
  addressed thread resolved via:

  ```bash
  gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<thread-id>"}) { thread { id isResolved } } }'
  ```

  If no automated review arrives in the short wait window, say that
  explicitly in the handoff and create a follow-up/heartbeat when the
  environment supports it. After every feedback-response push, watch
  CI again and re-check review threads.

### What the PR description must contain

The PR is the human-readable handoff. Even when the full experiment doc
lives at `experiments/NNN-*.md`, the PR body must stand on its own and
clearly state, in this order:

1. **Hypothesis** — the proposed change and why it should work.
2. **Approach** — what was built or instrumented (one paragraph or a
   short bullet list; link to the experiment doc for full detail).
3. **Results** — the measured outcome. Include the decision-relevant
   numbers (medians, deltas, counter values, ratios) inline as a small
   table; do not force the reviewer to open the aggregate file to see
   the headline number.
4. **Outcome** — Accepted / Rejected / Deferred, with the one-sentence
   reason. For rejections, the reason must be specific enough that a
   future runner can tell whether their new evidence changes the
   calculus ("rejected because X, would reopen if Y" — same shape as
   the experiment doc).
5. **Test plan** — checkboxes for the validation that was actually run
   (focused tests, `dart analyze`, generated-data checks, any
   profile/release benchmark passes).

If any of those sections are missing, the PR is not finished. Do not
rely on the linked experiment doc to carry the headline; reviewers
triage from the PR body first.
