# Release process

How to ship a new version of `resqlite` to pub.dev and tag it on GitHub.

The flow is: **investigate → classify → write → bump → publish → tag**. Don't
skip the investigation — the changelog is the only thing most users will read,
and the version bump depends on what's actually in the diff.

## 1. Investigate what's in the release

Pin the previous release commit and walk every commit since.

```bash
PREV=$(git log --diff-filter=M --follow --format=%H -- CHANGELOG.md | head -1)
git log "$PREV"..HEAD --oneline
```

For each commit, decide whether it's user-visible. Bucket them:

- **Behavior change** — anything a user upgrading from the previous version
  could be silently bitten by. Default-on pragmas, changed defaults, removed
  warnings, altered exception types. These are the most important entries and
  drive the version-bump decision.
- **New public API** — anything new exported from `lib/resqlite.dart`. Diff
  the file against the previous release:
  ```bash
  git diff "$PREV" HEAD -- lib/resqlite.dart
  ```
  New exports are a minor-version signal.
- **Removed or renamed public API** — anything *removed* from
  `lib/resqlite.dart` is a major-version signal. Same diff as above.
- **Performance** — accepted experiments since the last release. Cross-check
  against `experiments/README.md`'s "Accepted" table; commits matching
  `exp NNN` or `Exp NNN` that touched `lib/` or `native/` are the candidates.
  Group these into one bullet rather than enumerating every experiment.
- **Documentation only** — README/doc changes that surface a real limitation
  or new guidance to users (e.g. "virtual tables don't get reactive
  invalidation"). Worth a bullet. Pure typo fixes are not.
- **Internal** — benchmark/runner/CI/`.pubignore` changes. Skip these unless
  they materially change the published archive (e.g. a `.pubignore` that drops
  multiple MB).

Useful filters while bucketing:

```bash
# Commits that touched the public surface (lib/ or native/).
git log "$PREV"..HEAD --oneline -- lib/ native/

# Files newly added under lib/ — usually new public types.
git log "$PREV"..HEAD --diff-filter=A --name-only --pretty=format: -- lib/ \
  | sort -u
```

If a commit is unclear, read the PR body — `gh pr view <num>` — rather than
guessing from the subject line.

## 2. Classify the version bump (semver)

Apply the rules in order; the first match wins.

| Change | Bump |
|---|---|
| Removed/renamed any public API, or changed the type/signature of an existing one | **Major** (e.g. 0.3.0 → 1.0.0, or 0.3.x → 0.4.0 pre-1.0) |
| Behavior change that user code can observe (default pragmas, exception types, semantics of an existing API) | **Major** if it can break correct user code; **Minor** if it only changes performance or adds enforcement most users want |
| New public API, new exported type, new parameter with a default | **Minor** |
| Bug fixes, perf wins, doc-only changes | **Patch** |

Pre-1.0 caveat: per the Dart/pub.dev convention, while the package is at
`0.x.y`, breaking changes bump the **minor** (`0.x` → `0.(x+1)`) and
non-breaking changes bump the **patch** (`0.x.y` → `0.x.(y+1)`). We follow
that convention — see how 0.2.0 → 0.3.0 was treated even though it included
a default-on pragma.

Write down the bump and the one change that drove it. If you can't name the
driver in one sentence, you probably haven't finished the investigation.

## 3. Write the CHANGELOG entry

Match the existing voice in `CHANGELOG.md`:

- Top-level heading is `## X.Y.Z` (no date, no link).
- Bullets, terse. The reader is a Dart developer scanning pub.dev's changelog
  tab, not a contributor.
- Lead with behavior changes, then new APIs, then perf, then docs.
- Bundle the perf bucket into a single bullet that points at the
  [benchmark dashboard](https://danreynolds.github.io/resqlite/benchmarks/)
  rather than enumerating experiments. Experiment numbers belong in
  `experiments/README.md`, not the user-facing changelog.
- Link PRs with the full URL (`[#77](https://github.com/danReynolds/resqlite/pull/77)`),
  not bare `#77`.

Edit `CHANGELOG.md` directly; insert the new section above the previous
release.

## 4. Bump the package version

Edit `pubspec.yaml`:

```yaml
version: X.Y.Z
```

Sanity-check nothing else needs to move:

```bash
grep -rn "0\.[0-9]\+\.[0-9]\+" README.md lib/ doc/ 2>/dev/null \
  | grep -v CHANGELOG
```

The README's "Getting Started" install snippet pins a `^X.Y.Z` constraint —
update it if you crossed a major version (in the pre-1.0 sense, that's a
minor bump like `^0.2.0` → `^0.3.0`).

## 5. Verify the package is publishable

Run pub's dry-run from the repo root. It validates `pubspec.yaml`, runs
analyzer, and reports what will be in the archive.

```bash
dart pub publish --dry-run
```

Expect zero warnings. Common ones to fix before proceeding:

- Files unintentionally included → add to `.pubignore`.
- Missing `repository`/`description` → fix `pubspec.yaml`.
- Analyzer issues → fix the code.

Also confirm the example still runs (`example/`) and the test suite is green:

```bash
dart test
```

## 6. Commit, then publish

Commit the changelog + version bump together with a clear message:

```bash
git add CHANGELOG.md pubspec.yaml README.md
git commit -m "Release X.Y.Z"
git push origin main
```

If the push is rejected because the remote is ahead, the auto-doc-update bot
(`Auto-update docs (experiments + devices + blog)`) has likely landed a
`docs/`-only commit while you were preparing the release. It only ever
touches `docs/` (the GitHub Pages site, plural), never `doc/`, `lib/`, or
`native/`, so a rebase is conflict-free:

```bash
git pull --rebase origin main
git push origin main
```

Wait for CI to go green on `main` before publishing — pub.dev publishes are
permanent (you can only retract within 7 days, and only if no one has
depended on the version yet).

Publish to pub.dev. **Ask the user before running this** — it's irreversible:

```bash
dart pub publish
```

Pub will print a confirmation prompt with the file list and total size; the
user reviews it and types `y`.

## 7. Tag the release on GitHub

After `dart pub publish` succeeds, tag the release commit and push the tag:

```bash
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z
```

Then create a GitHub release using the same changelog body:

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z" \
  --notes-from-tag
```

Or, to use the CHANGELOG section verbatim, pass it via `--notes`:

```bash
gh release create vX.Y.Z --title "vX.Y.Z" --notes "$(awk '/^## X.Y.Z$/,/^## /' CHANGELOG.md | sed '$d')"
```

(The `awk … sed` pulls the section between `## X.Y.Z` and the next `## `
heading, dropping the trailing heading line.)

## Checklist

- [ ] `git log $PREV..HEAD` walked, commits bucketed
- [ ] Public-API diff against previous release reviewed
- [ ] Bump classified (major / minor / patch) with a one-sentence driver
- [ ] `CHANGELOG.md` entry written in the existing voice
- [ ] `pubspec.yaml` version bumped
- [ ] README install pin updated if crossing a (pre-1.0) major
- [ ] `dart pub publish --dry-run` clean
- [ ] `dart test` green
- [ ] Release commit pushed, CI green on `main`
- [ ] User confirmed before `dart pub publish`
- [ ] `vX.Y.Z` tag pushed
- [ ] GitHub release created
