# Experiment 257: Native independent-autocommit envelope

**Date:** 2026-07-29T06:29:09-04:00
**Status:** Rejected
**Category:** Moonshot
**Direction:** `stream-rerun-dispatch`
**Benchmark Run:** none (focused order-flipped cross-worktree gate; exact
  prototype and harness archived together)
**Archive:** [`archive/exp-257`](https://github.com/danReynolds/resqlite/tree/archive/exp-257)

## Problem

Exp 180 already coalesces concurrently issued standalone writes into one
`MultiExecuteRequest`. The worker still loops over the members in Dart,
allocating and freeing one native parameter arena, calling `resqlite_execute`,
reading one native result, and harvesting dirty dependencies for every
statement. Each member deliberately remains an independent SQLite autocommit.

That left a tempting distinction after exp 197: true group commit is fast but
changes visibility, durability, and failure semantics; perhaps the runtime
could keep those semantics and remove only the repeated Dart/native
orchestration.

### Preflight selection

Wednesday is moonshot-default cadence. Four live candidates were ranked before
the claim:

| Candidate | Incidence | Potential value | Complexity | Disposition |
|---|---:|---:|---:|---|
| Native independent-autocommit envelope | 3 | 3 | 2 | selected bounded moonshot |
| Alias-aware `BatchRequest` BLOB retest | 1 | 2 | 2 | no fresh production incidence; adjacent BLOB work already active |
| sqlite3mc 2.4.0 audit | 2 | 1 | 1 | current signal waits for a relevant 3.54.x point release or hot-path changelog |
| Stream lineage / rerun scheduling | 3 | 3 | 3 | collided with open stream work in PRs #274 and #155 |

The selected candidate had a public workload already in the repository, no
public API growth, and an immediate kill gate.

## Hypothesis

**Assumption challenged:** preserving independent autocommit outcomes requires
one Dart-to-C execution orchestration per coalesced member.

For a homogeneous, parameterized `MultiExecuteRequest`, pack all parameter sets
once and call one private native loop. The loop reuses the cached statement and
writer mutex, but fully steps and resets each set outside an explicit
transaction so every success remains its own autocommit. It stops at the first
error; Dart snapshots that error, then resumes later members through the scalar
path to retain per-caller failure isolation.

Acceptance required the public homogeneous insert burst to improve at least
10% in both process orders. Sequential and mixed-SQL routes had to stay neutral.
The candidate also had to preserve per-member results, later writes after an
error, trigger/FK side effects, and final stream state. Failure to reproduce
the 10% insert win was the predeclared kill condition.

## Approach

The exact prototype is commit `d502717` at `archive/exp-257`:

1. add a private `resqlite_run_independent_autocommits` C entry point;
2. admit only groups with two or more writes sharing SQL text and positive
   parameter arity;
3. flatten the whole parameter matrix with `allocateBatchParams`;
4. collect the successful `WriteResult` prefix and first error in one call;
5. resume the remaining suffix through `executeWrite`; and
6. harvest one dirty-dependency union for the native prefix.

The prototype changed no public API. Its expanded coalescing suite covered
monotonic insert IDs, interleaved errors with later commits, triggers, FK
cascades, exact error snapshots, mixed-SQL fallback, and final stream state.

The decision harness in the archive runs 3 warmups plus 11 samples per lane.
Each burst contains 256 concurrent calls; a measured round contains 20 bursts
(5,120 independent autocommits). The insert lane uses the public
`Future.wait([db.execute(...)])` shape. An integer-only no-op `UPDATE` lane
removes WAL payload and isolates fixed envelope machinery. Mixed SQL and
sequential writes are inert controls.

## Results

Separate baseline and candidate worktrees ran in both orders. Lower is better;
delta is candidate relative to baseline.

| Order | Lane | Baseline p50 | Candidate p50 | Delta |
|---|---|---:|---:|---:|
| candidate → baseline | **homogeneous insert** | 75.502 ms | 62.132 ms | **−17.7%** |
| baseline → candidate | **homogeneous insert** | 57.564 ms | 55.503 ms | **−3.6%** |
| candidate → baseline | integer-only no-op | 15.286 ms | 17.994 ms | **+17.7%** |
| baseline → candidate | integer-only no-op | 15.091 ms | 17.186 ms | **+13.9%** |
| candidate → baseline | mixed-SQL fallback | 59.385 ms | 61.827 ms | +4.1% |
| candidate → baseline | sequential control | 61.125 ms | 60.112 ms | −1.7% |

The primary lane does not reproduce the required 10% win: it improves 17.7%
in one order but only 3.6% in the reverse order. More importantly, the
integer-only no-op lane is slower in both orderings. Removing repeated FFI
calls did not remove the dominant independent autocommit work, while the
whole-group parameter/result allocation added enough fixed cost to regress a
lane with almost no SQLite payload.

An initial run of the older `writer_pipelining.dart` harness changed sign
(+16.1% slower, then −18.8% faster), which is why the larger warmed gate above
was used for the decision rather than treating a noisy smoke result as a win.
The mixed and sequential controls remain within the same small host-noise band;
they do not rescue the failed homogeneous lanes.

## Safety review

The archived implementation passed its focused tests, but review found
additional blockers that would have required redesign even if performance had
cleared the gate:

- `sqlite3_reset()` can surface a deferred commit failure after
  `sqlite3_step()` returns `SQLITE_ROW`; the loop ignored reset's result and
  could report an uncommitted member as successful.
- Dirty dependencies were drained even when the native prefix had no success
  to carry them, and a union attached to the last success could schedule
  invalidation after earlier member futures resolved. `OR FAIL` and
  conditional-trigger side effects make that observable.
- The packed matrix keeps every variable-width payload live at once. A
  homogeneous burst of large BLOBs can add tens of MiB beyond the scalar
  path's one-row arena, so any retry needs an admission cap and peak-RSS gate.
- The C ABI relied on implicit result-struct padding, and cached statements
  retained `SQLITE_STATIC` bindings after Dart freed the packed arena. A kept
  design needs explicit layout assertions and `sqlite3_clear_bindings()`.
- Holding the writer mutex for the full envelope makes main-isolate diagnostic
  calls wait inside leaf FFI for the whole burst rather than between members.

These are documented reopen requirements, not patched in the rejected
prototype.

## Outcome

**Rejected.** One native call is not a useful substitute for one native call
per member while the expensive semantic boundary — N independent SQLite
autocommits — remains. The product-shaped insert win missed the bar in the
reverse order, and the int-only diagnostic regressed consistently. The runtime
prototype was archived and then reverted.

Keep exp 180's scalar member loop. Reopen this shape only if a design avoids
whole-group repacking (for example, transport already delivers a bounded
native-ready arena), clears 10% on public 100/200-member insert bursts in both
orders, holds 2/8/32-member bursts neutral, and includes BLOB peak-RSS plus
diagnostic-latency guards. It must also honor reset-time commit errors and
apply dependency changes before resolving any affected member.

True commit merging remains a separate semantic/API question. This experiment
does not weaken exp 197's measured ceiling; it shows that retaining every
autocommit while only collapsing the FFI loop is too small and too costly.

## Transferable lesson

Collapsing N calls into one native envelope is not automatically amortization.
If the envelope first materializes all N inputs and results, it can replace an
optimized scalar encoder and bounded one-row lifetime with a larger allocation
whose cost exceeds the removed call boundaries. Benchmark the aggregate
materialization path, not only the native loop.

## Test plan

Archived prototype:

- focused analysis of the two changed Dart library files — no issues
- `dart test test/write_coalescing_test.dart` — 6/6 passed
- two order-flipped insert and no-op comparisons from separate worktrees
- exact prototype and harness pushed to `archive/exp-257`

Final publication branch:

- runtime files restored to `origin/main`
- retained coalescing regression covers constraint error snapshots, later
  autocommits, trigger/FK effects, and awaited final stream state
- retained focused suite — 4/4 passed
- generated-code build completed
- `dart analyze --fatal-infos` — no issues
- `dart test -j 1` — 355/355 passed
- experiment finalizer and terminal-disposition check passed
