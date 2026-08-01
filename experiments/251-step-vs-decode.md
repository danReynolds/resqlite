# Experiment 251: SQLite step vs Dart decode (measurement)

**Date:** 2026-08-01
**Status:** Accepted (measurement; premise refuted)
**Direction:** `result-transfer-shape`, `measurement-system`
**Benchmark Run:** none — focused AOT decomposition harness
  [`benchmark/experiments/step_vs_decode.dart`](../benchmark/experiments/step_vs_decode.dart),
  five fresh processes; raw tables and build receipt in
  [`benchmark/results/2026-08-01T10-26-15Z-exp251-step-vs-decode.md`](../benchmark/results/2026-08-01T10-26-15Z-exp251-step-vs-decode.md).

## Problem

[Exp 245](245-prepared-result-handoff.md) and
[exp 246](246-slot-sacrifice-guard.md) settled result handoff: intrinsic transfer of
a 200k-slot result costs about 391 us through `Isolate.exit`, against roughly
6.1 ms for a large public `select()`. Transport is therefore only 6-12% of
the read. The remaining bucket was still labelled "SQLite stepping plus
building the Dart object graph" without measuring the split.

That undivided ~90% bucket had begun to act like a candidate: if Dart value
materialization dominated it, a different row store or decode representation
could attack most of large-read wall. But [exp 258](258-columnar-result-store.md)
complicated the premise. Its synthetic container harness found a 60-90%
worker-side build win from avoiding boxing, yet the broad columnar result store
still failed the real transfer/consume and memory gates. Before another storage
rewrite, the production read loop needed a direct decomposition.

This experiment resumes the already-claimed exp-251 measurement rather than
opening a new slot. It changes no runtime or public API.

## Hypothesis and decision rule

Measure `SQLite step/native cell fill` separately from `Dart value
materialization` on representative integer, mixed, and text results.

- If stepping is more than 60% of worker wall across the representative large
  shapes, close Dart row-storage work as the general bottleneck.
- If Dart materialization is more than 60% across the representative large
  shapes, reopen a narrowly scoped storage or decode candidate against the
  public end-to-end denominator.
- If the split changes materially by shape or neither side dominates, reject
  the premise that the residual names one general optimization target.

## Approach

The focused harness uses the same direct native handle and cached SQL for three
interleaved lanes:

1. `step`: acquire and run `resqliteStepRow` over every row, counting rows but
   materializing no Dart cell values and doing no synthetic per-cell Dart work.
   This includes SQLite execution, native cell-buffer fill, and the minimal
   Dart stepping loop.
2. `full`: production `executeQuery`, which performs the same stepping and
   decodes every cell into the flat `ResultSet.values` list.
3. `bytes`: production `executeQueryBytes`, an independent reference that
   performs the stepping plus native JSON encoding without building the Dart
   row object graph.

`full - step` estimates the residual attributable to Dart decode and result
construction. It is a directional decomposition, not a sampled CPU profile.
The `bytes` lane uses a distinct native query/JSON path, so it is treated only
as a whole-path, different-representation reference. Each process rotates which
lane runs first on every round. A final phase runs the same four shapes through
real `Database.select()` to supply a main-observed public reader-pool
denominator. The harness was compiled with `dart build cli` so the package
native asset was present, and run in five fresh processes.

## Results

Across-process medians, microseconds. Component values are independent medians
of the five per-process medians; percentages are medians of the five paired
per-process ratios, so the displayed marginal medians need not add exactly.

| shape | step | full | decode/result build | public select | step/full | build/full | build/select |
|---|---:|---:|---:|---:|---:|---:|---:|
| 10k x 20 INTEGER (200k slots) | 2600.2 | 5123.8 | 2524.5 | 5610.7 | 50.7% | 49.3% | 45.0% |
| 10k x 4 INTEGER + 4 TEXT (80k slots) | 1331.2 | 3587.3 | 2259.8 | 3889.6 | 37.0% | 63.0% | 57.9% |
| 5k x 4 INTEGER (20k slots) | 320.0 | 533.3 | 212.5 | 632.9 | 60.2% | 39.8% | 33.5% |
| 5k x 1 TEXT (~190 B) | 222.8 | 458.8 | 233.2 | 483.7 | 48.8% | 51.2% | 48.2% |

The direct worker-path implementation (`full`) is material — typically 84-94%
of separately measured main-observed `select()` latency — but its internals do
not expose one dominant target. The widest mixed row is result-construction-
heavy (63%), the small integer row is step-heavy (60%), and the other two are
roughly even. All five fresh-process repeats preserve that classification; the
separately measured end-to-end denominator shows ordinary pool variance.

The `bytes` reference is 10-40% faster than `full` on the same SQL shapes, but
it returns a different representation with different semantics. It supports
`selectBytes()`/native-representation consumers; it does not license replacing
`ResultSet` or attributing the delta to main-isolate CPU work.

## Interpretation

The measurement accepts the decomposition and refutes its motivating premise:
the unnamed post-transfer bucket is not a single "Dart decode" bottleneck.
One mixed shape does cross the predeclared construction-heavy gate, while one
integer shape crosses the step-heavy gate and the other shapes split roughly
evenly. A general row-storage rewrite therefore cannot claim most of large-read
wall from these numbers; even completely eliminating the estimated construction
residual would bound the observed opportunity at 34-58% before paying for a
replacement representation, transfer, and consumer access.

This sharpens rather than contradicts exp 258. Exp 258's 60-90% improvement was
for a synthetic container-build phase that removed boxing. Exp 251 places that
mechanism inside real statement stepping and object construction, where the
eligible slice is shape-dependent and smaller. Exp 258's broad columnar
rejection therefore stands. Its one narrow positive signal — faster
main-isolate sequential integer consumption from `Int64List` locality — also
stands, but exp 251 supplies no incidence evidence that applications are
integer-heavy and main-isolate-consumer-bound. That candidate remains blocked
on a downstream workload profile.

## Outcome

**Accepted as a measurement; the general implementation premise is refuted.**
Keep the focused harness as the gate for future claims about read-path decode
cost. Ship no runtime or API change, open no general row-store follow-up, and do
not spend more on transport without naming a workload-specific cost that clears
the public `select()` denominator.

Reopen a decode/storage candidate only when a representative downstream profile
identifies a specific eligible shape — for example mixed TEXT materialization
or exp 258's integer-heavy main-isolate consumer — and the proposal attacks
that exact phase without moving cost to transfer or access.

## Validation

- Five fresh AOT CLI processes on arm64 macOS; per-process lane rotation
- `dart analyze --fatal-infos benchmark/experiments/step_vs_decode.dart`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/251-step-vs-decode.md`
- Full repository analysis and serial test suite
