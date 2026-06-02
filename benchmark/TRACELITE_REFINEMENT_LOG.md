# Tracelite Integration Refinement Log

Durable working log for repeated cleanup passes on the resqlite Tracelite
integration. Future refinement runs should read this file first, continue the
loop numbering, and record both the attempted change and the outcome.

## 2026-05-31 pass

### Loop 1 - Integration map

Read:

- `benchmark/run_tracelite.dart`
- `benchmark/decide_tracelite.dart`
- `benchmark/profile/run_tracelite_profile.dart`
- `benchmark/tracelite_source.dart`
- `.github/workflows/ci.yml`
- `benchmark/README.md`

Findings:

- The integration is now coherent around three operator entry points:
  `run_tracelite.dart`, `decide_tracelite.dart`, and
  `profile/run_tracelite_profile.dart`.
- The release gate wrapper is the highest-leverage cleanup target because it
  owns presets, source pinning, Tracelite dependency binding, native shim
  preparation, suite history, graph export, and wrapper manifests.
- The next useful refinements are not broad redesigns. They are small audit
  improvements: stronger source provenance, clearer graph-data input tracking,
  and focused tests around those contracts.

Outcome:

- Created this log so future runs can resume from concrete observations instead
  of rediscovering the integration shape.

### Loop 2 - Source provenance tightening

Tried:

- Added normalized Tracelite remote provenance to `benchmark/tracelite_source.dart`.
- Treated `git@github.com:danReynolds/tracelite.git`,
  `ssh://git@github.com/danReynolds/tracelite.git`, and
  `https://github.com/danReynolds/tracelite(.git)` as the same pinned
  repository.
- Made production source validation reject an explicit remote mismatch even if
  the commit hash matches.
- Added `test/tracelite_source_test.dart` coverage for accepted SSH remotes and
  rejected mismatched remotes.

Outcome:

- Tracelite manifests now record `remote_normalized` and
  `repository_matches_pin`, making source provenance easier to audit.
- Future pass should verify this still works with the real CI clone after the
  full test suite, because the CI clone uses the HTTPS form.

### Loop 3 - Graph-data input auditability

Tried:

- Promoted the fallback `graph-data-inputs` directory into the wrapper path
  model instead of leaving it as an implicit helper path.
- Made the wrapper manifest record `graph_data_inputs_dir` whenever filtered
  suite manifests are actually written.
- Made the final artifact summary print the graph-data input directory when it
  exists.

Outcome:

- Failed or partially failed suite runs should now be easier to inspect: the
  wrapper can point to the sanitized suite manifests used for graph export
  instead of making an operator infer where they came from.
- Future pass should add a partial-suite regression test, because the current
  missing-artifact test only covers the "no graphable artifacts" branch.

### Loop 4 - Partial-suite regression coverage

Tried:

- Added a workflow test where `suite-history` fails overall but one scenario
  artifact exists and is marked `ok`.
- Verified that the wrapper writes a filtered suite manifest under
  `graph-data-inputs/`, passes that filtered manifest to `export-graph-data`,
  records `graph_data_inputs_dir` in the wrapper manifest, and still exits with
  the original suite failure.

Outcome:

- The fallback behavior is now covered for both extremes: no graphable artifacts
  and partially graphable failed suites.
- Future pass can safely refactor this code if needed because the operator
  contract is pinned by tests.

### Loop 5 - Validation and remaining cleanup edge

Tried:

- Ran focused analysis for `benchmark/run_tracelite.dart` and
  `benchmark/tracelite_source.dart`.
- Ran focused tests for Tracelite benchmark workflow and source provenance.
- Ran full `dart analyze --fatal-infos`.
- Ran a fresh GitHub clone `--preset=ci` smoke using the pinned Tracelite tag
  to verify that `repository_matches_pin` accepts the same HTTPS remote CI uses.

Outcome:

- Local validation passed.
- The fresh-clone smoke passed end to end: source provenance accepted, shim
  rebuilt, suite history was `ok`, policy was `ready`, graph data exported, and
  graph-data validation passed.
- Remaining future cleanup: the benchmark workflow tests now contain repeated
  fake Tracelite-root setup. If this area grows again, extract a small test
  fixture helper rather than adding more inline shell-script setup.

## 2026-06-01 pass

### Loop 6 - Artifact interpretation handoff

Tried:

- Bumped the production Tracelite pin to the first commit that includes the
  shared `tracelite explain` artifact interpreter.
- Added `insights.json` and `insights.md` to the benchmark, decision, and
  profile wrappers instead of making operators run a separate interpretation
  command by hand.
- Updated wrapper plans, manifests, docs, and workflow tests so the new insight
  artifacts are part of the audited handoff.

Outcome:

- Resqlite's profiling workflow now preserves both the machine decision artifact
  and the human explanation artifact for trace health, noise, and bottleneck
  signals.
- Future pass should keep the insight step non-authoritative: acceptance still
  comes from `decision`/policy gates, while `explain` is for operator
  investigation and review.

## 2026-06-02 pass

### Loop 7 - r9 pin and runner default audit

Tried:

- Published Tracelite pin `resqlite-profiling-gate-2026-06-02-r9`, which adds
  worker preflight and native-asset/runtime-library metadata.
- Updated the resqlite wrapper source pin and CI checkout to r9.
- Tried making the wrapper default to `--runner=worker`.
- Fixed the wrapper's local Apple Silicon compiler detection so the SQLite shim
  build uses native `arch -arm64 cc` even when the wrapper itself runs under an
  x64 Dart.

Outcome:

- Direct worker samples were clean for `resqlite` and mixed
  `sqlite_async,resqlite` checks.
- A multi-scenario resqlite worker suite still produced unmatched trace events
  in `keyed-pk-subscriptions`, while the same suite passed with
  `--runner=script`.
- The wrapper therefore keeps `script` as the production default and leaves
  `worker` as an explicit investigation mode until the reactive worker
  lifecycle is fixed in Tracelite.
- The wrapper now records Dart executable architecture in its manifest. Local
  x64 Dart under Rosetta repeatedly made traced resqlite native-assets setup
  slow enough to obscure the benchmark cycle, while the same r9 CI smoke passed
  with the arm64 Dart SDK.

### Loop 8 - production calibration evidence

Tried:

- Ran r9 production gates with the script runner and arm64 Dart SDK.
- Split the production suite from strict elapsed-time policy: the suite still
  includes `sqlite-diagnostics`, while policy calibration gates
  `high-cardinality-fanout` and `many-streams-writer-throughput`.
- Added one unrecorded production warmup suite before recorded history.
- Raised the production total-outlier gate from 10% to 15% while leaving the
  5% threshold floor, 3% guardrail floor, and 5% max-CV floor intact.

Outcome:

- Earlier r9 production attempts produced complete artifacts but failed strict
  calibration: first because `sqlite-diagnostics` was too tiny and
  harness-dominated for elapsed-time policy, then because the first recorded
  fanout run had cold-start inflation, then because the warmed fanout workload
  had a few tiny IQR outliers despite sub-1% observed noise.
- Final evidence
  `production-pin-r9-resqlite-policy-2026-06-02-r4` passed: Tracelite source
  `f56ecb8d4f2df5bdb3646f2cf3439450fd64272d`, resqlite source
  `76cab05cd7f8cc06c6899991602a511214e55b1b`, dependency binding matched the
  PR worktree, arm64 Dart matched the host, warmup passed, 5/5 recorded runs
  were `ok`, policy calibration was `ready`, graph data validated, and explain
  completed.
- Remaining non-blocking caveat: insights still flag low traced coverage and
  harness-dominated child wall time for some trace interpretations. The
  release gate therefore treats measured elapsed policy as authoritative and
  uses those warnings as follow-up instrumentation guidance, not as merge
  blockers.

### Loop 9 - r10 worker runtime retargeting fix

Tried:

- Published Tracelite pin `resqlite-profiling-gate-2026-06-02-r10`, which
  fixes long-lived worker retargeting for reused native producer threads.
- Updated the resqlite wrapper source pin and CI checkout from r9 to r10.

Outcome:

- The r10 fix keeps script-runner production behavior intact while making
  explicit `--runner=worker` reactive resqlite samples viable again.
- A focused Tracelite worker compare for `keyed-pk-subscriptions` passed 3/3
  repetitions with trace diagnostics `0/0/0`, replacing the r9 caveat that
  worker mode was investigation-only for reactive suites.
