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
