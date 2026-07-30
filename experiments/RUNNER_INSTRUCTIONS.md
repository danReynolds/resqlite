# Scheduled Experiment Runner Instructions

Use this file as the copyable instruction block for any scheduled or recurring
Resqlite performance experiment runner.

## Goal

Improve Resqlite performance while preserving the lean public API. The normal
successful outcomes are an accepted optimization or a rejected implementation
experiment with useful evidence. A measurement/profiling improvement is valid
support work only when it unlocks a named future optimization decision or lets
future runners reject a candidate confidently.

### The public API is near-frozen

Resqlite's value is a lean, stable public surface: the symbols exported from
`lib/resqlite.dart` and the signatures of the types they expose. **Growing or
changing that surface is discouraged by default** — a performance experiment
must not add or alter public API as a matter of course.

- **Deliver wins under the existing API.** The strong default is to make the
  current surface faster transparently — a faster `select` / `selectBytes` /
  `execute` path, a better internal representation, a smarter native encoder —
  not to add a new method or type the caller must opt into. A new export is a
  permanent maintenance and compatibility cost that every future release carries;
  a niche or trade-off-shaped win rarely repays it.
- **Only propose a public API change for a massive, broadly-applicable win.**
  "Massive" means a large improvement on a *common* workload that genuinely
  cannot be delivered under the existing surface — not a big multiplier on a
  narrow shape, and not a win paired with a regression the caller has to steer
  around. If the caller has to pick the new API based on the shape of their data,
  it is a trade-off, not a massive win, and the answer is no.
- **This applies to moonshots too.** A frontier experiment may still challenge an
  architectural assumption, but if the only way to express it is new public
  surface, that surface must clear the same bar and be named and justified in the
  PR: the assumption, the size and breadth of the win, and why the existing API
  cannot carry it. Prefer proving the mechanism behind the current API first.

An experiment whose win exists only as new public API, and does not clear this
bar, is rejected on those grounds. Record the surface cost as the reason so
future runners do not re-propose it.

For exploit runs, default toward implementation experiments when a plausible,
bounded change also clears the value and representativeness gate below.
Moonshots follow their separate frontier-evidence rule. Measurement-only runs
are lower-frequency support work: use them when implementation would otherwise
be speculative, not as an equal-priority substitute for changing the hot path.

When extra measurement is needed, prefer adding the few counters, profile lanes,
or focused probes directly inside the performance experiment that will consume
them. Run the candidate while that instrumentation is present, then remove the
temporary measurement scaffolding before merge unless it is broadly reusable
across future experiments.

The program has two lanes:

- **Exploit** — incremental, high-confidence work against known hot paths. This
  is the default for ordinary scheduled runs: focused optimizations, correctness
  guards, measurement that directly unlocks a candidate, and cleanup of stale
  directions.
- **Explore / moonshot** — bolder frontier work that challenges a live
  architectural assumption. A moonshot may prototype a new transport shape,
  result representation, stream-maintenance model, or semantic trade-off that no
  prior experiment proved would work. The bar is not "likely to merge"; the bar
  is "attacks a meaningful ceiling and will leave useful evidence even if it is
  rejected."

Moonshots are still bounded experiments. They must name the assumption being
challenged, the frontier they are trying to move, the risk or complexity they
are allowed to add if they win, and the evidence that would kill the direction.
They can succeed by producing a mergeable win, falsifying a tempting direction,
creating a new benchmark/profile that exposes a hidden floor, or proving that a
supposed architecture limit is not real.

## Preflight

Before choosing an experiment, read:

- [`README.md`](README.md) — the experiment tables and templates (generated
  from `experiments/index/NNN.json` fragments; read it, don't hand-edit it)
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

- `beliefs` — the generated current belief set: what this direction currently
  holds true (`live`), each claim with its source experiment and measurement
  conditions, plus what has been revised (`superseded` / `refuted`). Read this
  *before* the prose: it is the fastest correct answer to "what do we know,
  and on what evidence." Check `coverage` — where `entriesWithClaims` is well
  below `entriesInDirection`, `currentRead` still holds beliefs that were
  never distilled into claims, so read it too. **Never cite a superseded or
  refuted claim's number as current**; cite what superseded it.
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

### Value before mechanism

A focused all-hit benchmark can prove that a mechanism works; it cannot prove
that the mechanism matters to real users. Before claiming an **exploit** slot,
briefly rank at least three plausible candidates from different live directions
when available. Do not choose the easiest candidate to isolate merely because
it can produce a large synthetic percentage.

For each shortlisted exploit candidate, record:

- **Representative incidence.** Name the evidence that the affected operation
  and eligible data shape occur often enough to matter: a production/downstream
  trace, an AOT trace from a representative application, a release workload, a
  representative schema, or an existing measured distribution. An assertion
  that a value or shape is "common" is not evidence.
- **Expected aggregate value.** Estimate `operation frequency × eligible share
  × per-hit saving`, then subtract any miss-path tax. The estimate may be rough,
  but it must distinguish a broad win from a large multiplier on a tiny slice.
- **Persistent complexity budget.** List the branches, helpers, platform paths,
  exported test hooks, state, or semantic boundaries that would remain on main.
  Narrower eligibility requires stronger incidence evidence as this maintenance
  surface grows.

For a distribution-dependent narrow specialization — such as a value lattice,
rare query shape, or caller pattern — shipping requires a representative mixture
backed by the incidence evidence above. A 100%-eligible target is a
mechanism/ceiling lane, not a product-value adoption gate.

For a size, width, or count threshold, keep two distinct gates. The first
admitted threshold workload remains the load-bearing **path-level** adoption
lane: it must clear the declared performance bar, and a far-end win cannot
rescue it. Separately, representative incidence and aggregate value must show
that the operation and admitted payload distribution matter enough to repay the
complexity. Neither gate substitutes for the other.

Moonshots may be claimed without representative incidence when they attack a
meaningful architectural ceiling and the bounded prototype will leave useful
falsification or feasibility evidence. They must still state their complexity
risk. A narrow runtime win from that prototype may not ship until it clears the
representative-incidence and aggregate-value gate; otherwise reject/archive the
runtime while preserving the frontier evidence.

If prevalence is unknown for an exploit, measure it in the same run. If the
signal supports the candidate, execute it; if it refutes the premise, close the
candidate under the existing **premise refuted** escape; if implementation is
genuinely beyond the run, use the existing **out of budget** escape. This does
not create a separate incidence-only exception to the measurement rule below.

Apply a local-search brake as well: after two consecutive experiments in the
same subsystem or mechanism family, another exploit there needs fresh
production/release evidence, a relevant external runtime change, or a newly
resolved measurement blocker. A prior experiment merely naming the next nearby
micro-optimization is not enough.

A direction marked `watch` with no unblocked candidate needs the same fresh
trigger; adjacency to its last experiment is not enough. If no exploit clears
this gate, do not manufacture one: choose a qualifying moonshot when cadence
allows, or refresh/prune the signal map without claiming an experiment number.
Any measurement-only claim still follows "A measurement run carries the
experiment it unlocks" and its two named escape hatches.

Before coding, write a short working note for yourself:

- whether this run is **exploit** or **moonshot**, and why the current cadence
  requires or allows that lane
- for a moonshot: the architecture assumption being challenged, the frontier it
  attacks, and the risk budget you are intentionally allowing for the prototype
- what prior experiments are adjacent — search the belief sets (or
  `docs/experiments/knowledge-graph.json`) for claims about the mechanism you
  are targeting before trusting a README-table skim
- why this is not just a duplicate attempt — neither of a prior *rejected*
  experiment nor of any open PR or branch **in flight right now** (two runs
  shipping the same follow-up is how exp 175 collided)
- what implementation candidate you are trying; if the run is measurement-only,
  why that candidate cannot be attempted in the same pass
- what new evidence, benchmark, workload, implementation shape, or external
  change makes it worth trying now
- for an exploit: the candidate shortlist, incidence evidence, expected
  aggregate value, and persistent complexity budget from the gate above; for a
  moonshot: the meaningful ceiling evidence and what product-value evidence
  would still be required before shipping a narrow runtime result
- what result would make you accept, reject, or defer the idea
- for runs that add measurement, the specific implementation experiment the
  measurement unlocks — which this same run must then execute and report
  (see "A measurement run carries the experiment it unlocks" below), or
  the explicit escape hatch that applies
- for temporary instrumentation, what will be removed before merge and what
  would justify keeping any counter, benchmark, or profile lane permanently

This note does not need to be committed directly, but the final experiment
writeup should make the reasoning clear.

### Moonshot cadence

Do not let the runner always take the safest local optimization.

- **Wednesday and Friday scheduled runs are moonshot-default.** On those days,
  choose a moonshot unless a maintainer has named an active release,
  correctness, or CI blocker that must be handled first, or unless another
  moonshot PR is already open and needs completion before starting a new one.
- If the runner is not scheduled on weekdays, enforce the same mix by experiment
  number: after three consecutive non-moonshot experiment claims, the next
  scheduled experiment must be a moonshot.
- A non-moonshot day may still pick a moonshot when `signals.json`, a production
  profile, or a recent rejection points at a real architectural ceiling.
- Do not satisfy the moonshot requirement with a larger version of the same
  micro-optimization. The attempt must challenge a broader assumption, such as
  one request per isolate round trip, Dart-object-first result transfer,
  all-or-nothing stream invalidation, or hidden-vs-explicit batching semantics.

If you skip a moonshot on a moonshot-default day, say why in the PR body or
handoff. The reason should be concrete, not "no good ideas found"; in that case,
spend the run drafting and testing a frontier candidate instead of taking the
easy path.

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

### Keep the dashboard charts moving: clean headline runs

The experiments dashboard ([`../docs/experiments/index.html`](../docs/experiments/index.html))
plots one point per experiment that has a mapped **headline release run** —
`benchmark/run_release.dart` output, the pristine peer-comparison suite that
feeds `history.json`. Focused microbenchmarks under `benchmark/experiments/`
never feed the charts; an experiment gets a chart point only when a release
run is captured and linked. To contribute one:

1. Run the headline suite **from a clean, committed tree**:

   ```bash
   dart run benchmark/run_release.dart expNNN-short-slug --repeat=5 --no-auto-compare
   ```

   Label it `expNNN-...` so `generate_history.dart` maps it to the experiment
   by exact prefix. Commit the resulting `.md` + `.json` under
   `benchmark/results/` as sources (the bot regenerates `history.json`).

2. **The tree must be clean and multi-sample.** `run_release.dart` records
   `git status` at run start; the chart intentionally hides any run flagged
   `gitDirty` — or single-sample (`--repeat=1`) — as a **gap**, so the trend
   line isn't pulled through uncommitted or statistically-thin numbers. A run
   captured with your fix still unstaged is silently dropped. Commit first,
   then benchmark, and confirm `"gitDirty": false` in the run's `.json` before
   relying on it. (`.g.dart` / `.dart_tool` are gitignored and don't count as
   dirty.)

3. Don't point an accepted experiment at a run whose label contains
   `baseline` / `pre` — that trips the linker's baseline guard. Name the
   candidate run plainly (`expNNN-<slug>`).

Declaring `**Benchmark Run:** none (…)` stays a valid opt-out for a
focused-only change, but it means **no chart point** — and a run of
focused-only accepted work stalls the headline timeline. When a stretch has
gone focused-only, capture one clean headline run at HEAD and map it to the
newest accepted milestone to refresh the timeline; that experiment's
`**Benchmark Run:**` header then cites the run instead of opting out (see
exp 229).

## Postflight

When finished:

- write or update the experiment record. Keep markdown human-readable;
  when a *load-bearing number* from a prior experiment appears in your
  reasoning, cite its claim id (e.g. "claim 245.2") rather than restating the
  figure bare — the CI linter warns on citations of claims that later become
  superseded, which is how stale numbers get caught instead of quoted forever;
  machine-oriented direction metadata belongs in `signals.json`. For rejected
  experiments, the writeup should explain why the direction looked plausible,
  what was measured, and what would make the area interesting again — a
  "rejected, no signal" record is worth less than a "rejected because X, would
  reopen if Y" record. For moonshots, add `**Category:** Moonshot` in the
  writeup header and include a short "Assumption challenged" sentence in the
  **Hypothesis** or **Approach** section.
- record the run's signal in its own file,
  `experiments/signals/entries/NNN.json` (directions, outcomeClass,
  changedBeliefs, nextSignals) — never the generated `signals.json`, and never
  a shared file, so two concurrent runs can't collide on it. Record each
  *durable, citable* result as a typed claim too: `claims: [{id: "NNN.x",
  text, conditions, edges}]`. When your result revises an earlier claim, say
  so with an edge (`supersedes` / `refutes` / `refines` / `validates` →
  `"MMM.y"`) instead of prose — claim state is derived from edges, and the
  generated per-direction belief set (plus
  `docs/experiments/knowledge-graph.json`) is built from them. If you
  supersede another *experiment's* headline wholesale, also add
  `supersededBy` / `amendedBy` to that experiment's `index/NNN.json` row so
  the README shows the lineage. When the result you are revising predates
  claims, **mint the old claim on demand**: add it to *that experiment's*
  entry file, worded from its own `changedBeliefs`, in the same run — then
  edge to it. Claims are adopted incrementally; the generated belief sets
  carry a `coverage` count so nobody mistakes a partially-migrated direction
  for a complete one. When the run
  changes how future agents should read a whole *direction*, also update that
  direction's synthesis in [`signals/base.json`](signals/base.json). For
  moonshots, record the class in the signal source too:
  `experimentClass: "moonshot"`.
- when a claim's rationale *rests on* an earlier finding — the earlier result is
  the reason this one holds, not merely a related one — record that with a
  `dependsOn` edge. It is the only edge that points at a foundation rather than
  at something replaced, and it is what makes a belief visibly lose its
  justification when the finding under it is later refuted. Without it, a design
  decision keeps reporting `live` after its evidence is gone.
- **write `changedBeliefs` against the computed impact, not from memory.** Run:

  ```sh
  dart run tool/knowledge/impact.dart origin/main
  ```

  It lists what the run learned, what it retired, which claims lost their
  justification transitively, and every documented passage now standing on
  something that moved. Read the affected passages, then write
  `changedBeliefs` as prose a person can follow: what we believed, what we
  believe now, and what a reader of those passages should do about it. Name any
  claim you knocked over and any chapter that needs a rewrite. The tool reports
  *what* moved; `changedBeliefs` is the only place that says what it *means*,
  and it is what gets posted on the PR beside the affected set.
- add to [`JOURNAL.md`](JOURNAL.md) only when the run surfaced a *transferable*
  lesson — something a future runner could reapply to a different direction or
  could waste time relearning. Per-direction state goes in `signals.json`, not
  the journal.
- do not edit [`../doc/stories/`](../doc/stories/) as part of an experiment
  run. Story posts are updated on maintainer request, not per experiment.
- register the experiment by adding its **README row fragment**,
  `experiments/index/NNN.json` — `{file, title, impact, status, link}` (status
  is `accepted` / `in_review` / `rejected`). `experiments/README.md` is
  *generated* from these fragments; do not edit the README table by hand. A
  split experiment that has both an accepted and a rejected finding (like 014)
  stores a JSON array of rows. For moonshots, start the `impact` text with
  `Moonshot:` so the generated README/category surfaces make the class visible.
- run the experiment finalizer after the writeup, the `index/NNN.json` row
  fragment, and `experiments/signals/entries/NNN.json` are in place:

  ```bash
  dart run benchmark/finalize_experiment.dart \
    --experiment=experiments/NNN-short-slug.md
  ```

  This verifies the generated-docs **sources** build cleanly and the signal map
  is valid. It does **not** write `docs/experiments/history.json`,
  `docs/benchmarks/devices.json`, `experiments/signals.json`, or
  `experiments/README.md` — those are generated aggregates owned by the
  post-merge Update-Docs bot. **Never commit them on your branch** (CI's
  `guard-generated-docs` job blocks the JSON aggregates). You commit only
  sources: the writeup, your `index/NNN.json` row fragment, your signal
  fragment, benchmark result files, and any code; the bot regenerates the
  aggregates on `main` after merge. This is what keeps a stale branch from
  re-conflicting on generated files the way the old "regenerate + commit
  `history.json` on every branch" rule did.
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
  is triageable at a glance. GitHub calls these PR "labels", not tags.
  Moonshot PRs use `type: moonshot`.
- **Distinguish local completion from merge readiness.** A local experiment is
  complete when the branch has coherent code/docs/artifacts, focused validation
  has passed, and the finalizer is green. A PR is not ready to merge until CI
  and review feedback have also been checked.
- **Wait for CI on the PR and address actionable failures** before declaring a
  PR ready to merge. A red PR is not merge-ready.
- **Classify the PR before merge.** Only final PRs that keep source
  implementation changes are held for human review before merge. "Source
  implementation" means runtime or public behavior changes in `lib/`, `native/`,
  package sources, generated source, or public API surfaces. These PRs may be
  accepted optimizations, correctness changes, or a rejected experiment that
  still intentionally keeps implementation code. They block on merge until CI is
  green and review feedback has been checked.
- **Auto-merge publication-only experiments.** Failed/rejected experiments whose
  final branch reverts the runtime prototype and keeps only the experiment
  writeup, index/signal fragments, benchmark result files, focused harnesses,
  tests, or other documentation/tooling artifacts are the auto-merge class.
  Once CI is green and there are no unresolved actionable review threads, put
  them on auto-merge or merge them yourself; do not stop at "ready for review"
  unless a reviewer or maintainer explicitly asks for a hold.
- **Wait for automated review, not just CI, before merge readiness** — for PRs
  *held for human review* by the classification above. A publication-only PR you
  put on auto-merge may land before any review arrives; that race is benign, so
  don't block on the poll for it. For held PRs, after opening the PR, poll
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
  - `type: moonshot` — a frontier experiment that intentionally challenges a
    broader architecture assumption. Use this even when the branch mostly
    produces a prototype, archive tag, benchmark, or rejection evidence.
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
    the candidate was abandoned. Rejected moonshots are still valuable when the
    writeup makes the falsified assumption clear.
  A still-undecided or deferred experiment carries no outcome label until its
  verdict lands.

```bash
gh pr edit <N> --add-label "type: performance" --add-label "approved"
```

For a moonshot:

```bash
gh pr edit <N> --add-label "type: moonshot" --add-label "rejected"
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
