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
- why this is not just a duplicate attempt — neither of a prior *rejected*
  experiment nor of any open PR or branch **in flight right now** (two runs
  shipping the same follow-up is how exp 175 collided)
- what implementation candidate you are trying; if the run is measurement-only,
  why that candidate cannot be attempted in the same pass
- what new evidence, benchmark, workload, implementation shape, or external
  change makes it worth trying now
- what result would make you accept, reject, or defer the idea
- for runs that add measurement, the specific implementation experiment the
  measurement unlocks — which this same run must then execute and report
  (see "A measurement run carries the experiment it unlocks" below), or
  the explicit escape hatch that applies
- for temporary instrumentation, what will be removed before merge and what
  would justify keeping any counter, benchmark, or profile lane permanently

This note does not need to be committed directly, but the final experiment
writeup should make the reasoning clear.

### Claim your slot before any work

Once you've chosen the experiment — before writing code — claim it atomically so
a concurrent run can't take the same number or ship the same follow-up. (Full
rationale: the resqlite-experiment skill's "Preflight" section.)

- **Number.** `N` = 1 + the highest experiment number across `origin/main`, open
  PRs, and remote branches — read `origin/main`, not the local tree:
  `git ls-tree -r --name-only origin/main -- experiments/`; `gh pr list
  --state open`; `git branch -r | grep -oE 'exp-[0-9]+'`. Then claim it with a
  tag push, which is rejected if the tag already exists, so the push itself is
  the atomic test-and-set:

  ```bash
  git tag exp-$N-claim && git push origin exp-$N-claim   # rejected -> bump $N, retry
  ```

  "Pick highest + 1" alone *races* — both runs pick the same `N`; the claim is
  what makes it safe (exp 168/175). Delete the tag on merge/close:
  `git push origin :exp-$N-claim`.
- **No duplicate work.** Now, and again right before opening the PR, confirm no
  in-flight work is already doing your follow-up — **use `gh pr list --state
  open`**, not a raw branch-by-file diff: stale/merged branches all "touch" any
  recently-edited file (e.g. ~55 branches show as touching `row.dart` because
  exp 158 last edited it), so that heuristic is fog. A branch that matters backs
  an open PR. If your follow-up is already in flight, stop — pick different work
  or build on it. A unique number doesn't help if two runs ship the same lane.

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

### A measurement run carries the experiment it unlocks

A measurement justified by "it unblocks implementation X" must, **in the
same run**, actually run X against the new signal and report both
results in one writeup and one PR:

1. Build the counter / benchmark / harness and capture the baseline
   signal.
2. Run the implementation candidate the measurement was justified by —
   a fresh bounded change, or an archived one (`archive/exp-NNN`)
   re-tested under the new workload. This is the
   [exp 111](111-nested-tx-benchmark-savepoint-cache.md) pattern: the
   measurement is the lasting contribution either way, and a rejection
   against a real signal is a stronger result than an unconsumed
   measurement (see the matching `JOURNAL.md` lesson).
3. The PR's **Results** section includes the implementation outcome —
   accepted, or rejected with the measured evidence — alongside the new
   signal. A PR whose Results contain only a counter reading is
   incomplete under this rule.

Two escape hatches, each of which must be stated explicitly in the PR
body:

- **Out of budget**: the unlocked implementation is genuinely beyond a
  bounded run (multi-layer change, needs a design pass). Say so, and add
  a scoped `openCandidates` entry naming the measurement that now backs
  it — that candidate becomes the default pick for the next run in the
  direction.
- **Premise refuted**: the measurement shows no headroom. Record the
  numbers that close the candidate and prune it from the signal map —
  that is a complete, valuable outcome.

Avoid back-to-back measurement-only runs unless the current signal map makes an
implementation pass genuinely speculative or a maintainer explicitly asks for
the diagnostic pass. Under the paired-run rule above, a measurement-only
run should exist only via the escape hatches. After one lands, the next
runner in the direction defaults to consuming its signal with an
implementation, rejection, or direction cleanup rather than adding
another diagnostic layer.

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
  **Run it as the very LAST step.** If you edit *any* tracked file afterward —
  the writeup, README, `signals.json`, a result artifact, a relocated fixture —
  re-run it, or you commit a stale `history.json`. The freshness check then
  fails *post-merge* (it can slip through if the PR auto-merges before CI
  re-runs), and only the Update-Docs bot saves you — a runner without that bot
  ships a red `main`. This is exactly how exp 177 briefly reddened the main tip.
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
  directly. Create the worktree off current `origin/main` **only after the
  atomic claim above**, with branch `exp-NNN-short-slug` (e.g.
  `exp-115-dispatcher-park-counters`) where `NNN` is the *claimed* number,
  not a bare highest-row + 1. If the runner already starts you
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
- **Label the PR when you open it.** Apply one `type:` label and the outcome
  label `approved`/`rejected` (see [PR labels](#pr-labels) below) so the PR list
  is triageable at a glance.
- **Distinguish local completion from merge readiness.** A local experiment is
  complete when the branch has coherent code/docs/artifacts, focused validation
  has passed, and the finalizer is green. A PR is not ready to merge until CI
  and review feedback have also been checked.
- **Wait for CI on the PR and address actionable failures** before declaring a
  PR ready to merge. A red PR is not merge-ready.
- **Wait for automated review, not just CI, before merge readiness** — for PRs
  *held for human review* (runtime-code changes). A docs-only/tooling PR you put
  on auto-merge may land before any review arrives; that race is benign — those
  are the auto-merge class anyway — so don't block on the poll for them. For held
  PRs, after opening the PR, poll
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

### PR labels

Every experiment PR carries one `type:` label and one outcome label. The labels
already exist in the repo with fixed colors — apply them by name with `gh pr
edit`, never recreate them.

- **`type:`** — the kind of run (independent of whether it ships runtime code):
  - `type: performance` — an implementation experiment changing a runtime hot
    path.
  - `type: measurement` — counters, profiling, benchmarks, or focused probes. A
    measurement hook that is kept still counts as `type: measurement` even
    though it ships `lib/`/`native/`.
  - `type: correctness` — a public-API guard or audit with no performance claim.
- **outcome** — whether the experiment *succeeded or failed*. This is the
  experiment verdict, not the PR or `README.md` status:
  - `approved` — the experiment succeeded: a kept win, or a passing correctness
    guard. An accepted win is `approved` as soon as its result is known, even
    while its README row still reads "In Review" during the soak.
  - `rejected` — the experiment failed: measured below the bar, regressed, or
    the candidate was abandoned.
  A still-undecided or deferred experiment carries no outcome label until its
  verdict lands.

```bash
gh pr edit <N> --add-label "type: performance" --add-label "approved"
```

If `gh pr edit` errors with a Projects-classic `projectCards` GraphQL message
(this repo trips it), add the labels via the REST endpoint, which skips the
projects lookup:

```bash
gh api --method POST repos/danReynolds/resqlite/issues/<N>/labels \
  -f "labels[]=type: performance" -f "labels[]=approved"
```

If the verdict flips during review, swap the outcome label with
`--remove-label`/`--add-label` rather than leaving both attached.

### What the PR description must contain

The PR body is the human-readable handoff — most reviewers read it and
nothing else. Write it the way you would **explain the experiment to a
colleague who hasn't seen the code**: full sentences, plain language, and
enough *why* that they understand the decision without opening the diff or
the writeup. The experiment doc (`experiments/NNN-*.md`) already tells this
story — its Problem / Hypothesis / Approach / Results sections are usually
well-written prose. **Lift that narrative into the PR body; do not compress it
back into keyword fragments.** A reader who finishes the body should be able to
say, in their own words, what you tried, why, what happened, and what it means.

Required sections, in this order:

1. **Hypothesis** — open with the *motivation*: what you noticed in the code or
   a prior experiment that made this worth trying (this is the writeup's
   "Problem"), in plain terms. Then state the change you expected to help and
   why. The reader should understand the bet before any symbol or function name
   appears.
2. **Approach** — what you actually changed, in words, not just a list of
   identifiers. Say what stays on the old path and why the change is safe — the
   conservative boundaries matter to a reviewer as much as the fast path. Link
   the writeup for full detail.
3. **Results** — the numbers *and what they mean*. Put the decision-relevant
   figures inline as a small table, then **interpret them in 1–3 sentences**:
   the magnitude in intuitive terms ("~5× faster", not only "−79%"), what the
   control / guard lanes confirm (e.g. "fractional values stay flat, exactly as
   intended"), and when the result actually matters in real usage. Never make
   the reviewer derive the takeaway from a delta column on their own.
4. **Outcome** — plain Accepted / Rejected / Deferred, and what it means going
   forward. For a win: roughly how big and where it applies. For a rejection:
   "rejected because X, would reopen if Y" — specific enough that a future
   runner can tell whether their new evidence changes the calculus.
5. **Test plan** — the validation that actually ran (focused tests,
   `dart analyze`, generated-data checks, any profile/release benchmark passes).

The PR is not finished if a section is missing, if **Results is a bare table
with no interpretation**, or if **Hypothesis leads with the mechanism instead
of the motivation**. Don't rely on the linked writeup to carry the headline —
reviewers triage from the body first.

#### Worked example

Too terse — mechanism only, numbers without meaning (what *not* to ship):

```markdown
## Summary
- add a conservative SQLITE_FLOAT helper routing exact integral REALs through fast_i64_to_str
## Results
- 10k x 8 integral REAL: -79.2% / -79.0%
- 10k x 20 fractional REAL guard: +0.5% / +0.5%
```

Better — motivation, plain approach, interpreted results:

```markdown
## Hypothesis
`selectBytes()` formats every REAL cell with `snprintf("%.17g")`. But REAL
columns often hold whole numbers — scores, timestamps, metrics kept under REAL
affinity — and for those the JSON output is identical to what our fast integer
encoder already produces. So: detect exactly-integral REAL values and route
them through `fast_i64_to_str`, expecting a large win on integer-heavy REAL
rowsets and no change for genuine fractionals.

## Approach
Added `fast_double_to_json_num`: finite values in the exact integer range
(`|v| <= 2^53`) cast to `long long` and reuse the integer path; everything
risky — fractionals, huge magnitudes, NaN/Inf, negative zero — stays on
`snprintf`. Deliberately narrow: not a general float-formatting rewrite (see
exp 041). Full detail in experiments/194-real-integer-fastpath.md.

## Results
| Lane | Δ (order-flipped pair) |
|---|---|
| 10k × 20 integral REAL | −81.5% / −81.4% |
| 10k × 20 fractional REAL (guard) | +0.5% / +0.5% |
| 10k × 8 mixed | −38.7% / −34.7% |

Integer-heavy REAL encoding is **~5× faster**; genuine fractionals are
untouched (the guard confirms they stay on the safe path), and mixed rowsets
improve in proportion to how many integral-REAL cells they carry. This only
moves wall time on workloads that read many whole-number REAL cells — a
per-cell encoder win, invisible to the release suite, so the focused harness is
the durable gate.

## Outcome
Accepted (in review): a contained, conservative ~5× win on integral-REAL
selectBytes, with the fractional path provably unchanged.

## Test plan
- [x] `dart analyze --fatal-infos` on the harness + tests
- [x] `dart test test/database_test.dart -n selectBytes` (integral, fractional, huge fallback)
- [x] focused A/B both orders; `finalize_experiment.dart` green
```
