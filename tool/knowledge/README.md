# Knowledge pins

Documentation goes stale silently. Prose asserts something true, the code or the
measurement moves underneath it, and nothing says so — the reader just gets
confidently wrong information. This directory makes that failure loud.

The rule: **a documented assertion should name the thing that makes it true, and
that binding should be machine-checkable.**

```markdown
Large results sacrifice the worker when their slot count crosses 32k
([[code:sacrificeSlotThreshold=32768]]) — slot count, not bytes, because bytes
lie [[246.1]], retiring the byte rule that preceded it [[was:236.2]].

A stream always resolves to a value or an error, never silence
([[test:test/stream_test.dart#always emits its initial result]]).
```

Every one of those is verified on each CI run.

## The five namespaces

| pin | source of truth | proves | on failure |
|---|---|---|---|
| `[[test:file#name]]` | the test passed in CI | the statement is **true right now** | error |
| `[[bench:Metric ~ 0.32 +-15%]]` | latest clean benchmark run | the number is **current** | error |
| `[[code:name=value]]` | source declaration | the mechanism is **unchanged** | error |
| `[[code:file#symbol@hash]]` | normalized symbol body | the implementation is **unchanged** | error |
| `[[claim:246.1]]` or `[[246.1]]` | the experiment graph | the belief **is not superseded** | error |
| `[[was:236.2]]` | the experiment graph | the belief **has** been superseded | error |

`was:` exists because narrating history is good writing. *"The original trigger
routed on bytes"* is worth saying, and citing the retired belief makes it
checkable rather than folklore — the linter errors if that claim is still live,
which would mean the prose calls something former that never stopped being true.

The ordering is an epistemic hierarchy, not a preference. A green test *proves*
a statement; an unchanged code hash only proves nobody edited it, and unchanged
code can still be wrong. Prefer the strongest pin a statement admits.

## Usage

```bash
dart run tool/knowledge/verify.dart            # check
dart run tool/knowledge/verify.dart --report   # + groundedness per chapter
dart run tool/knowledge/verify.dart --strict   # unknown counts as failure (CI)
dart run tool/knowledge/verify.dart --fix      # re-pin drifted expectations
```

`--strict` is the difference between a checker and the appearance of one. Without
it `unknown` warns, which is right locally — `test:` pins read a results file
that only CI produces. In CI every dataset is present by construction, so a pin
that cannot be checked means the pipeline that feeds it broke, and the build must
fail rather than report coverage it no longer has.

Three layers defend that, because the failure is silent by nature:

1. `record_passing_tests.dart` exits non-zero when it records zero tests.
2. CI runs the test pipeline under `set -o pipefail`, so a failed `dart test`
   fails the step instead of being masked by the recorder's exit code.
3. `--strict` turns any remaining `unknown` into an error.

`test/knowledge_pins_test.dart` covers all of it, including the case where a
dataset is absent — that test asserts `unknown`, never `current`.

`--fix` is what keeps this maintainable. When a constant or metric legitimately
moves, it rewrites the expectations and leaves a diff to review — *"this number
moved 15%, does the sentence still hold?"* — instead of asking anyone to
hand-edit hashes. It never touches `broken` pins, because those mean the prose
describes something that no longer exists, which is a writing problem rather
than a bookkeeping one.

## What not to pin

Pin what the *argument* rests on. Prose that explains **why** should stay
unpinned — over-citing turns documentation into a bibliography, and the
groundedness report measures load-bearing coverage, not pin density. A chapter
with four well-chosen pins is in better shape than one with forty.

Two kinds of number deserve different treatment:

- **Live** metrics (in the tracked benchmark suite) are re-measured on a
  schedule, so `bench:` pins on them detect real drift.
- **Historical** one-off measurements are recorded once and never re-run. They
  cannot drift, only age — so quote them with their date and don't pretend a
  pin is watching them.

## Porting to another codebase

`pin.dart` and `verify.dart` are project-agnostic: the syntax, the resolver
contract, the reporting, and `--fix`. Everything project-specific lives in
`resolvers.dart` (what counts as ground truth) and the path constants at the top
of `verify.dart`.

To adopt this elsewhere:

1. Copy `pin.dart`, `verify.dart`, and `record_passing_tests.dart`.
2. Write resolvers for that project's sources of truth. A `PinResolver` needs a
   namespace, a one-line description of what it proves, a strength for the
   groundedness report, and a `resolve` returning `current` / `drifted` /
   `broken` / `unknown`.
3. Point the path constants at that project's docs and datasets.
4. Add `verify.dart` to CI.

The distinction worth preserving is `unknown`: when a checker cannot run — no
benchmark history, tests not executed — it must report `unknown` rather than
passing. A checker that silently succeeds when it cannot check is worse than no
checker, because it reads as coverage.
