---
name: resqlite-experiment
description: Running a performance experiment on the resqlite codebase. Use this skill whenever work involves adding or modifying files under experiments/, adding an entry to experiments/README.md, or making code changes explicitly framed as "experiment NNN" or "trying X as a perf optimization". Also trigger when the user says "run an experiment", "benchmark this change", "add a new experiment", or references an experiment number like "experiment 071". This skill enforces the repo's one-commit-per-experiment-with-benchmark convention that the Update Docs Data pipeline depends on.
---

# resqlite Experiment Protocol

The resqlite experiments system is a first-class feature of the repo: every
performance change is documented as an experiment with a benchmark result file,
and those files feed the live charts on the GitHub Pages site
(`docs/experiments/index.html`). Skipping any piece breaks the chart.

> **First, every run:** do the [Preflight](#preflight-claim-your-slot-before-doing-any-work)
> — sync from `main`, claim your experiment number with an atomic tag push, and
> confirm no open PR/branch is already doing your follow-up. Skipping it is how
> exp 168 and exp 175 ended up claimed by multiple runs at once.

## The contract

**Every experiment commit must include all three of:**

1. **The code change** — `native/`, `lib/`, `hook/`, or `test/` as appropriate
2. **The experiment doc** — `experiments/NNN-short-name.md` with
   `**Date:** YYYY-MM-DD` frontmatter and a row in `experiments/README.md`
   (under Accepted or Rejected)
3. **At least one benchmark result file** — `benchmark/results/<ISO-timestamp>-<label>.md`
   whose **filename timestamp's date** matches the experiment doc's `**Date:**`

If you're unsure whether a commit needs a benchmark result, it's because you
ran `dart run benchmark/run_release.dart <label>` locally to validate. That
produced a file — commit it. If you didn't run a benchmark, you should have
before shipping a "performance experiment."

For A/B comparisons between an experiment branch and baseline (where you
want to see dispatch-vs-work split, p99/max, and cross-isolate timelines),
use profile mode instead:

```bash
dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
  --out=benchmark/profile/results/<baseline-or-exp>.json
```

Both sides of the A/B run under the same `-DRESQLITE_PROFILE=true` flag
so the diagnostic overhead cancels out in the delta. See
[benchmark/EXPERIMENTS.md](../../../benchmark/EXPERIMENTS.md) for the
full workflow.

### What to commit from profile mode (and what not to)

Profile JSONs are **~10–15 MB each** — raw per-sample timing arrays.
They are local scratch, not a committed artifact:

- **Commit:** the aggregate markdown produced by `diff_multirun.dart`,
  e.g. `benchmark/profile/results/<label>-aggregate.md` (~5 KB). That
  file has the medians, CVs, and per-run values the decision actually
  rested on.
- **Do NOT commit:** the raw `*.json` outputs. They are gitignored
  (`benchmark/profile/results/*.json`) and a CI job
  (`guard-raw-profile-json` in `ci.yml`) will fail any PR that adds them.
- **Workflow:**
  ```bash
  # Run N times per side locally (raw JSONs stay untracked)
  for i in 1 2 3 4 5; do
    dart run -DRESQLITE_PROFILE=true benchmark/run_profile.dart \
      --out=benchmark/profile/results/baseline-expNNN-run$i.json
    # ...and candidate side
  done

  # Aggregate once, commit the markdown only
  dart run benchmark/profile/diff_multirun.dart \
    --baseline='benchmark/profile/results/baseline-expNNN-run*.json' \
    --candidate='benchmark/profile/results/exp-NNN-run*.json' \
    > benchmark/profile/results/exp-NNN-aggregate.md
  git add benchmark/profile/results/exp-NNN-aggregate.md
  ```

Raw JSONs are not comparable across time/hardware — a future evaluator
re-runs against their own current baseline anyway. The aggregate
captures the decision-relevant signal; 10 × 15 MB of per-sample arrays
does not.

## Why all three

The Update Docs Data workflow (`.github/workflows/update-experiments.yml`)
runs on push to `main` when `experiments/*.md` or `benchmark/results/*.md`
change. It regenerates `docs/experiments/history.json` by:

1. Parsing every `benchmark/results/*.md` to extract resqlite median timings
2. Parsing `experiments/README.md` rows and individual experiment files to
   build the experiments list with dates + status
3. Mapping experiments to runs **by date** — the filename timestamp's
   YYYY-MM-DD must match the experiment doc's `**Date:** YYYY-MM-DD`

A chart point appears only when an experiment date matches at least one
benchmark run date. Drop the result file and the experiment is invisible
on the chart (though it still shows in the text list).

See `benchmark/generate_history.dart` for the parser logic if you need to
debug a missing mapping.

## Before committing an experiment, check

Run this mental (or literal) checklist:

- [ ] `git status --short benchmark/results/` — is there an untracked result file?
- [ ] Does that file's filename timestamp match `grep "^**Date:**" experiments/NNN-*.md`?
- [ ] Is the experiment listed in `experiments/README.md` (Accepted or Rejected section)?
- [ ] Does the experiment doc have the headings the parser expects?
      (`Problem`, `Hypothesis`, `Approach` or `What We Built`, `Results`,
      `Decision` or `Why Accepted` / `Why Rejected`)

The generator's section extraction tolerates a few heading variants; see
`_extractSection` in `generate_history.dart` for the full list.

## Filename convention

Result files use: `YYYY-MM-DDTHH-MM-SS-<label>.md`

Label patterns that work well with the chart:
- `exp043-swar-escape` — per-experiment runs (the chart uses these for points)
- `baseline-for-expNNN` — the fresh pre-change baseline taken right
  before a candidate run, when doing an A/B that uses
  `--compare-to=...baseline-for-expNNN.md`. The candidate's `expNNN-*`
  prefix is what makes the experiment->chart linker pick the right
  file; if you call your candidate something else (e.g. `bind-rewrite`),
  the chart will not find it. CI will fail the freshness check via
  `_assertAcceptedExperimentsLinkToCandidates` if an accepted
  experiment ends up linked to a baseline-shaped run while a candidate
  is available.
- `round5-baseline` — round-level baselines for diff anchors
- `round5-aggregate` — post-round aggregate result

Avoid committing: intermediate exploration runs (e.g., the 8+ files I
accidentally created while iterating on a single experiment), PGO
training outputs, or aborted pipeline runs. One clean "after experiment"
run per experiment is the right unit.

## Validating locally before pushing

```
dart run benchmark/generate_history.dart
```

Look for:
- `Parsed N benchmark runs from M files` — if N < M, some result files
  didn't parse (missing resqlite metrics section usually)
- `Parsed K experiments` — should equal the table row count in README
- The new experiment should appear in the output's generated JSON

If you edited `generate_history.dart` itself, also test that
`dart run benchmark/generate_blog.dart` still runs clean — it's triggered
by the same workflow.

## Rejected experiments — preserve the implementation

A rejected experiment's writeup lives on; its code usually doesn't. If the
branch is deleted without any other ref pointing at it, git garbage-collects
the commit and the implementation is gone. That's expensive when (a) the
benchmark floor later shifts, (b) the codebase evolves in a way that changes
the calculus, or (c) a seemingly-rejected idea turns out to be the right
starting point for a follow-up.

**Tag rejected experiments before cleaning up the branch.** Tags are
~100 bytes of ref metadata, live forever, and keep the commit reachable.

Point the tag at a **single slim commit off `main`** — not the messy
working-branch HEAD. The slim commit should contain exactly what a
future evaluator needs to cherry-pick the idea onto the current tree:

- Code change (under `native/`, `lib/`, `hook/`)
- `experiments/NNN-*.md` writeup with full reasoning + root cause
- `experiments/README.md` row
- `benchmark/profile/results/<label>-aggregate.md` (the medians, not
  the raw JSONs)
- Any tooling added (e.g. `diff_multirun.dart`)
- `benchmark/results/<timestamp>-<label>.md` (release-mode summary)

```
# Build the slim commit off a fresh branch from main
git checkout -b tmp-archive-slim origin/main
git checkout <code-commit> -- <paths under native/, lib/, hook/>
git checkout <docs-branch> -- experiments/NNN-*.md experiments/README.md \
  benchmark/profile/results/<label>-aggregate.md \
  benchmark/results/<timestamp>-<label>.md
git commit -m "exp NNN: archived — <title> (rejected)"

# Move the tag
git tag -f archive/exp-NNN HEAD
git push -f origin archive/exp-NNN
git checkout main
git branch -D tmp-archive-slim
```

Then add an **Archive** line to the experiment writeup so readers can jump
to the code:

```markdown
**Archive:** [`archive/exp-NNN`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-NNN)
```

The `generate_history.dart` parser reads this field and the experiments
page renders an "Archived code" link. That means future re-evaluations
become trivial: `git cherry-pick archive/exp-NNN` gives you the original
implementation to rebase onto current main.

Skip this only when the rejection reason is "the implementation itself
was broken" (correctness bugs, crashes) — in which case the writeup is the
full artifact and preserving the broken code adds nothing. For any
rejection of the form "measured, below noise floor, not worth the
complexity," tag it.

## Closing out the PR: merge, auto-merge, or hold

Every experiment ends as a PR. Decide what happens to it **by the diff, not
by the verdict word** — a "rejected" that still ships code must not
auto-merge:

```bash
git diff --name-only origin/main...HEAD
```

- **Touches none of `lib/`, `native/`, `hook/`** (only `experiments/`,
  `benchmark/`, `test/`, `docs/`) → no runtime behavior change. This is a
  recorded rejection, a measurement lane, or a tooling/CI guard. **Enable
  auto-merge** so it lands the moment CI is green, before it can stale a
  sibling:
  ```bash
  gh pr merge <N> --squash --auto
  ```
  Exception: if a recorded rejection adds *no reusable signal* — no
  `signals.json` prune, no JOURNAL lesson, a pure duplicate of an existing
  dead end — **close** the PR instead of merging. Don't spend a `main`
  commit on an empty record.
- **Touches `lib/`, `native/`, or `hook/`** → it changes runtime behavior
  (an accepted win, or a rejection that still ships code like a kept
  measurement hook). **Leave it open for human review.** Do not auto-merge
  runtime code, even when CI is green and the verdict is "rejected."

## Preflight: claim your slot before doing any work

Do this **first, every run** — before picking a follow-up, before writing any
code. Start from fresh `origin/main`, but get there **non-destructively**: never
`git reset --hard` / `git checkout -f` your checkout to "catch up" — that
silently discards any uncommitted work, and this skill is followed by humans,
not just the runner. Just fetch, then do the whole experiment in an isolated
worktree off `origin/main` (steps below), leaving the current tree untouched:

```bash
git fetch origin
```

Every experiment PR rewrites the same three shared files —
`experiments/README.md`, `experiments/signals.json`, and the generated
`docs/experiments/history.json` — and CI's `check_generated_data.dart` fails
any PR whose `history.json` predates a merge. So concurrent runs that grab the
same number, or do the same work, collide and stale each other (exp 168 was
claimed by three PRs; exp 175 by two runs shipping the *same* follow-up).

**1. Claim the number atomically.** A plain "check open PRs, then pick the next
free" *races*: two runs check, both see N free, both take N. That is exactly
how 168 and 175 collided. Use a remote tag as the lock — pushing a tag that
already exists is rejected regardless of commit, so the push itself is the
atomic test-and-set:

```bash
# N = 1 + highest experiment number across origin/main, open PRs, and branches
# (read origin/main, not the local tree, so a stale/dirty checkout can't fool you):
#   git ls-tree -r --name-only origin/main -- experiments/ | grep -oE '/[0-9]+'
#   gh pr list --state open ; git branch -r | grep -oE 'exp-[0-9]+'
git tag exp-$N-claim && git push origin exp-$N-claim
#   rejected ("already exists") -> another run claimed $N first; bump $N, retry.
#   success                     -> $N is yours; name your branch exp-$N-<slug>.
```

Then build the experiment in a fresh worktree branched off `origin/main` — never
in your main checkout, so nothing local is ever at risk:

```bash
git worktree add -b exp-$N-<slug> ../resqlite-exp-$N origin/main
cd ../resqlite-exp-$N
```

When it merges or closes, clean up: `git worktree remove ../resqlite-exp-$N`
and `git push origin :exp-$N-claim`.

**2. Don't duplicate the work.** A unique number doesn't help if two runs ship
the same lane (exp 175: both independently picked exp 174's large-`selectBytes`
follow-up). Before implementing anything from a writeup's Future Notes or
`signals.json` `openCandidates`, scan open PRs **and** branches for one already
targeting the same follow-up/direction; if one exists, **stop** — choose
different work or build on it. Re-check right before you open the PR, to catch a
run that started inside your window.

**3. One experiment in flight.** Don't open experiment N+1 while a prior
experiment PR is unmerged, unless that prior is a held-for-review code PR — in
which case expect to regenerate `history.json` on the later one.

> The bulletproof fix lives at the scheduler: run experiments **serially** (one
> at a time) so two never overlap. The claim-tag above is the in-agent backstop
> for when they do.

## Resolving a stale derived-file conflict

If a PR did fall behind `main`, the conflict is mechanical — only
generated/narrative files collide:

```bash
git merge origin/main
dart run benchmark/generate_history.dart      # rebuilds docs/experiments/history.json
dart run benchmark/generate_devices.dart      # rebuilds docs/benchmarks/devices.json
# hand-reconcile experiments/signals.json: keep BOTH sides' entries
dart run benchmark/check_generated_data.dart  # must print "up to date"
dart run benchmark/check_experiment_signals.dart
git add -A && git commit --no-edit
```

`experiments/README.md` usually auto-merges (rows append). `signals.json`
needs care: two experiments editing the same `currentRead` /
`notesForExperimenters` narrative is a real weave, and two experiments
claiming the same `experiments.<N>` key is a number collision — fix the
numbering, never overwrite a prior experiment's entry.

## Post-merge

After the experiment branch merges to main, the Update Docs Data workflow
fires automatically and commits the regenerated `docs/experiments/history.json`
back to main. GitHub Pages rebuilds from that. Within a minute or so the
new chart point is live at `https://danReynolds.github.io/resqlite/experiments/`.

No manual intervention needed — as long as the three pieces above were in
the commit.

## What I missed in experiments 041-070

Every experiment in rounds 1-5 had the code + doc but not the result file.
The result files piled up in `git status` untracked. I eventually backfilled
them in commit `1e80959` — but that cost an extra commit and created the
appearance that the experiments had no benchmark data. Don't repeat this.
The fix: `git add benchmark/results/<your-file>.md` as part of the same
commit that adds `experiments/NNN-*.md`.
