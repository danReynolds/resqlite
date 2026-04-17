---
name: resqlite-experiment
description: Running a performance experiment on the resqlite codebase. Use this skill whenever work involves adding or modifying files under experiments/, adding an entry to experiments/README.md, or making code changes explicitly framed as "experiment NNN" or "trying X as a perf optimization". Also trigger when the user says "run an experiment", "benchmark this change", "add a new experiment", or references an experiment number like "experiment 071". This skill enforces the repo's one-commit-per-experiment-with-benchmark convention that the Update Docs Data pipeline depends on.
---

# resqlite Experiment Protocol

The resqlite experiments system is a first-class feature of the repo: every
performance change is documented as an experiment with a benchmark result file,
and those files feed the live charts on the GitHub Pages site
(`docs/experiments/index.html`). Skipping any piece breaks the chart.

## The contract

**Every experiment commit must include all three of:**

1. **The code change** — `native/`, `lib/`, `hook/`, or `test/` as appropriate
2. **The experiment doc** — `experiments/NNN-short-name.md` with
   `**Date:** YYYY-MM-DD` frontmatter and a row in `experiments/README.md`
   (under Accepted or Rejected)
3. **At least one benchmark result file** — `benchmark/results/<ISO-timestamp>-<label>.md`
   whose **filename timestamp's date** matches the experiment doc's `**Date:**`

If you're unsure whether a commit needs a benchmark result, it's because you
ran `dart run benchmark/run_all.dart <label>` locally to validate. That
produced a file — commit it. If you didn't run a benchmark, you should have
before shipping a "performance experiment."

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
~100 bytes of ref metadata, live forever, and keep the commit reachable:

```
git tag archive/exp-NNN <last-commit-on-branch>
git push origin archive/exp-NNN
git branch -D <experiment-branch>
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
