# Release process

How to ship a new version of `resqlite` to pub.dev and tag it on GitHub.

The flow is: **investigate → benchmark → classify → write → bump → publish →
tag**. Don't skip the investigation or the benchmark — the changelog is the only
thing most users will read, and its headline numbers come from a real
previous-version comparison, not from memory.

`resqlite` ships as a small family of packages. The root package is the one
users depend on; the companion packages (`resqlite_vector`, `resqlite_js`) and
the private workspace package (`resqlite_extension_test`) pin a caret constraint
on it. **A `resqlite` version bump that crosses the caret boundary breaks every
companion until it is re-released** — see [§6](#6-bump-the-companion-packages).
Plan for all of them up front.

## 1. Investigate what's in the release

Pin the previous release commit and walk every commit since.

```bash
PREV=$(git describe --tags --abbrev=0 --match 'v*')   # e.g. v0.5.0
git log "$PREV"..HEAD --oneline
```

For each commit, decide whether it's user-visible. Bucket them:

- **Behavior change** — anything a user upgrading from the previous version
  could be silently bitten by. Default-on pragmas, changed defaults, removed
  warnings, altered exception types, atomicity/ordering changes. These are the
  most important entries and drive the version-bump decision.
- **New public API** — anything new exported from `lib/resqlite.dart`, or a new
  member on an already-exported type (a new `Diagnostics` field counts). Diff
  the export file and the public types against the previous release:
  ```bash
  git diff "$PREV" HEAD -- lib/resqlite.dart
  git diff "$PREV" HEAD -- lib/src/diagnostics.dart   # public types re-exported
  ```
  New public surface is a minor-version signal.
- **Removed or renamed public API** — anything *removed* is a major-version
  signal. Same diff as above.
- **Performance (accepted experiments)** — the headline of most releases. List
  the experiments accepted since the last release that actually shipped runtime
  code, and the experiments rejected in the same window (recorded for
  traceability, far less prominent in the changelog):
  ```bash
  # Runtime files that changed at all since the previous release.
  git diff --stat "$PREV"..HEAD -- lib/ native/ hook/

  # Experiment-bearing commits since the previous release.
  git log "$PREV"..HEAD --oneline | grep -iE 'exp [0-9]+'
  ```
  Cross-check each against `experiments/README.md`'s **Accepted** and
  **Rejected** tables. An accepted experiment is "featured" only if it touched
  `lib/`, `native/`, or `hook/` — a measurement-only or coverage-only accept
  (e.g. a release-lane addition) is not a user-facing win and does not earn a
  changelog bullet. A rejection that left no runtime code is, by definition, not
  in the diff; it belongs only in the lower-priority "also explored" list.
- **Documentation only** — README/doc changes that surface a real limitation or
  new guidance to users. Worth a bullet. Pure typo fixes are not.
- **Internal** — benchmark/runner/CI/`.pubignore`/profile-plumbing changes.
  Skip these unless they materially change the published archive.

If a commit is unclear, read the PR body — `gh pr view <num>` — rather than
guessing from the subject line.

## 2. Run a full perf comparison against the previous version

The changelog's "Wins at a glance" line and every per-experiment number must
come from a real comparison of *this* release against the *previous published
version on the same machine in the same session*. Numbers from different
machines or different days are not comparable (thermal state, background load,
and SDK version all move the floor) — never quote a delta you didn't measure
side-by-side.

Run the previous release in an isolated worktree (so the native build is rebuilt
for that tag, and your release branch is untouched), then run the candidate with
`--compare-to` pointed at the baseline result:

```bash
# Baseline: the previous release tag, in its own worktree.
git worktree add ../resqlite-prev "$PREV"
( cd ../resqlite-prev && dart run benchmark/run_release.dart "prev-${PREV}" --repeat=5 )
cp ../resqlite-prev/benchmark/results/*-prev-${PREV}.md /tmp/baseline-${PREV}.md

# Candidate: this release, compared against the baseline.
dart run benchmark/run_release.dart "<X.Y.Z>" --repeat=5 \
  --compare-to=/tmp/baseline-${PREV}.md

git worktree remove ../resqlite-prev
```

`run_release.dart` defaults to 5 repeats and reports medians plus a CV per
metric; with `--compare-to` it renders a delta table against the baseline. Flags
worth knowing: `--include-slow` (adds the long-running suites — use it for the
release comparison, skip it for quick checks), `--repeat=N`, and
`--no-auto-compare` (suppress the implicit comparison to the newest file already
in `benchmark/results/`). The harness refuses to compare across incompatible
environments and tells you why; that guard is the point.

**Discriminate real deltas from drift before quoting them.** A single
order's deltas can be time-correlated noise, exactly the trap
`benchmark/ab_drift_check.dart` (exp 177) exists to catch. For any metric you
intend to feature — and any *regression* the comparison flags — re-run the pair
in the opposite order (candidate-baseline then baseline-candidate) and confirm
the effect keeps its sign with comparable CVs. A sign flip across the order
swap, or CV asymmetry on the flagged metric, means drift: do not put it in the
changelog. (See the [drift discriminator](../experiments/177-ab-drift-discriminator.md).)

The output of this step is two things: the headline numbers for the changelog,
and confidence that no metric silently regressed. If something regressed for
real, that is a release blocker, not a footnote.

## 3. Classify the version bump (semver)

Apply the rules in order; the first match wins.

| Change | Bump |
|---|---|
| Removed/renamed any public API, or changed the type/signature of an existing one | **Major** (e.g. 0.3.0 → 1.0.0, or 0.3.x → 0.4.0 pre-1.0) |
| Behavior change that user code can observe (default pragmas, exception types, semantics of an existing API) | **Major** if it can break correct user code; **Minor** if it only changes performance or adds enforcement most users want |
| New public API, new exported type, new member on a public type, new parameter with a default | **Minor** |
| Bug fixes, perf wins, doc-only changes | **Patch** |

Pre-1.0 caveat: per the Dart/pub.dev convention, while the package is at
`0.x.y`, breaking changes bump the **minor** (`0.x` → `0.(x+1)`). New API and
backward-compatible features also bump the **minor** in practice for this
package — that is how 0.4.x → 0.5.0 and 0.5.x → 0.6.0 were treated even though
both were non-breaking — while pure bug-fix/perf-only releases bump the
**patch**.

Write down the bump and the one change that drove it. If you can't name the
driver in one sentence, you probably haven't finished the investigation.

## 4. Write the CHANGELOG entry

Edit `CHANGELOG.md` directly; insert the new section above the previous release.
Match the existing voice — the reader is a Dart developer scanning pub.dev's
changelog tab.

Structure (this is the order):

1. **One-line release character + upgrade safety.** e.g. "Performance and
   observability release. No breaking changes … safe to upgrade from 0.5.x."
2. **Wins at a glance.** One bold sentence with the two or three headline
   numbers from [§2](#2-run-a-full-perf-comparison-against-the-previous-version).
3. **Behavior changes**, then **new APIs**, then **performance**, then **docs**.
4. **Performance — feature the accepted experiments.** This package's changelog
   *does* call out the accepted experiments that shipped runtime code, because
   traceability to the experiment + PR is a feature here. Give each featured win
   its own sub-bullet: the user-facing effect, the measured number from the
   side-by-side comparison, and links to both the PR and the experiment writeup:
   ```markdown
   - **Cross-call write batching (group commit)** — standalone `execute()` calls
     that pile up while a write is in flight coalesce into one request; −26% to
     −32% on the concurrent single-insert lane
     ([#184](https://github.com/danReynolds/resqlite/pull/184),
     [exp 180](https://github.com/danReynolds/resqlite/blob/main/experiments/180-group-commit-request-batching.md)).
   ```
   Only experiments that touched `lib/`/`native/`/`hook/` get a bullet.
   Measurement-only and coverage-only accepts do not.
5. **Link PRs and experiments with full URLs**, never bare `#184`.

**Rejected experiments are not in `CHANGELOG.md`.** Users don't act on what
didn't ship. Record them — less prominently — in the release PR description and
the GitHub release notes ([§9](#9-tag-the-release-on-github)) as an "Also
explored (rejected)" list, so the release is self-documenting without cluttering
the pub.dev changelog. Keep the full perf-comparison table in the PR body too.

## 5. Bump the root package version

Edit `pubspec.yaml`:

```yaml
version: X.Y.Z
```

The README's "Getting Started" install snippet pins a `^X.Y.Z` constraint —
update it whenever the bump crosses the caret boundary (pre-1.0, that's any
minor bump like `^0.5.0` → `^0.6.0`). There are usually two occurrences:

```bash
grep -rn "resqlite: \^[0-9]" README.md
```

Then sanity-check nothing else hardcodes the old version:

```bash
grep -rn "0\.[0-9]\+\.[0-9]\+" README.md lib/ doc/ 2>/dev/null | grep -v CHANGELOG
```

## 6. Bump the companion packages

This is the step the rest of the ecosystem depends on and the one easiest to
forget. The companions pin `resqlite` with a caret. For a `0.x` dependency,
`^0.5.0` resolves to `>=0.5.0 <0.6.0` — so the moment `resqlite` becomes
`0.6.0`, **every package still pinning `^0.5.0` fails to resolve against the new
release.** A `resqlite` minor bump therefore requires a coordinated release of
each companion.

For each published companion (`packages/resqlite_vector`,
`packages/resqlite_js`):

- Bump its dependency constraint to the new `resqlite` minor, e.g.
  `resqlite: ^0.6.0`.
- Bump its own version by a **patch** (`0.1.1` → `0.1.2`) — it's a
  compatibility release with no functional change of its own.
- Add a CHANGELOG entry in its own `packages/<name>/CHANGELOG.md`:
  ```markdown
  ## 0.1.2

  - Require `resqlite: ^0.6.0`. Compatibility release for the resqlite 0.6.0
    bump; no functional changes.
  ```

For the private workspace package `packages/resqlite_extension_test`
(`publish_to: none`): bump only its `resqlite:` constraint to `^X.Y.Z`. It is
never published, has no version field, and needs no CHANGELOG — but if you skip
it, `dart pub publish --dry-run` for the root package fails version resolution
inside the workspace.

Confirm nothing still pins the old constraint:

```bash
grep -rn "resqlite: \^" --include=pubspec.yaml . | grep -v '\.dart_tool'
```

## 7. Verify every package is publishable

Run pub's dry-run from each published package's directory. It validates
`pubspec.yaml`, runs the analyzer, and reports the archive contents.

```bash
dart pub publish --dry-run                                   # root resqlite
( cd packages/resqlite_vector && dart pub publish --dry-run )
( cd packages/resqlite_js     && dart pub publish --dry-run )
```

Expect zero warnings except the benign "N checked-in files are modified in git"
notice, which clears once the release commit lands. Common real warnings to fix
first:

- Files unintentionally included → add to `.pubignore`.
- Only `build.dart`/`link.dart` are allowed under `hook/` — pub.dev rejects any
  other file there server-side, and the dry-run does **not** catch it. Keep
  build helpers in `lib/` and import them via a `package:` URI.
- Missing `repository`/`description`, or analyzer issues → fix and re-run.

Also confirm the suite is green:

```bash
dart analyze lib/
dart test
```

## 8. Commit, then publish

Commit the changelog, root version bump, README, and all companion changes
together:

```bash
git add CHANGELOG.md pubspec.yaml README.md packages/
git commit -m "Release X.Y.Z"
```

Open a PR, wait for **CI green on `main` after merge**, then publish — pub.dev
publishes are permanent (7-day retraction only, and only if nothing depends on
the version yet).

If a push to `main` is rejected because the remote is ahead, the auto-doc-update
bot (`Auto-update docs (experiments + devices + blog)`) likely landed a
`docs/`-only commit. It only ever touches `docs/` (the GitHub Pages site, the
plural directory), never `doc/`, `lib/`, or `native/`, so a rebase is
conflict-free: `git pull --rebase origin main && git push`.

**Publish in dependency order.** The root package must exist on pub.dev at the
new version before the companions can resolve their `^X.Y.Z` constraint against
it. **Ask the user before each `dart pub publish` — it's irreversible.**

```bash
dart pub publish                                   # 1. resqlite (must go first)
( cd packages/resqlite_vector && dart pub publish ) # 2. then companions
( cd packages/resqlite_js     && dart pub publish )
```

Pub prints a confirmation prompt with the file list and total size for each; the
user reviews and types `y`. `resqlite_extension_test` is never published
(`publish_to: none`).

## 9. Tag the release on GitHub

One git tag covers the whole release (the companions are versioned in their own
pubspecs/changelogs but share the repo tag). After the publishes succeed:

```bash
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z
```

Create the GitHub release with the changelog body plus the richer
release-notes material from the PR (the full perf-comparison table and the
"Also explored (rejected)" list):

```bash
gh release create vX.Y.Z --title "vX.Y.Z" \
  --notes "$(awk '/^## X.Y.Z$/,/^## /' CHANGELOG.md | sed '$d')"
```

(The `awk … sed` pulls the section between `## X.Y.Z` and the next `## ` heading,
dropping the trailing heading line. Append the rejected-experiments list and perf
table by editing the release, or pass a fuller `--notes` string.)

## Checklist

- [ ] `git log $PREV..HEAD` walked, commits bucketed
- [ ] Accepted (runtime-bearing) experiments listed; rejected experiments noted
- [ ] Public-API diff against previous release reviewed
- [ ] Side-by-side perf comparison run on one machine; deltas drift-checked
- [ ] No metric silently regressed (a real regression blocks the release)
- [ ] Bump classified (major / minor / patch) with a one-sentence driver
- [ ] `CHANGELOG.md` entry written — featured accepted experiments with numbers + links
- [ ] Root `pubspec.yaml` bumped; README `^` pin updated
- [ ] Companion packages bumped (constraint + version + CHANGELOG) and `resqlite_extension_test` constraint bumped
- [ ] `dart pub publish --dry-run` clean for root + both companions
- [ ] `dart test` green
- [ ] Release commit merged, CI green on `main`
- [ ] User confirmed before each `dart pub publish`
- [ ] Published in dependency order: resqlite, then companions
- [ ] `vX.Y.Z` tag pushed
- [ ] GitHub release created (changelog + perf table + rejected list)
