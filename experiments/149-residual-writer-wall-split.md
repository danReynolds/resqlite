# Experiment 149: Residual writer/request wall split

**Date:** 2026-06-09
**Status:** In Review
**Direction:** `stream-rerun-dispatch`, `measurement-system`
**Benchmark Run:** None

## Problem

Experiment 147 split writer-side burst wall on stream-fanout workloads into
SQLite-facing write calls (9–18 %), main-isolate stream invalidation
(15–19 %), and a "writer/request residual" bucket that dominated everything
left (63 % on keyed-PK, 72 % on A11c overlap). Experiment 148 then took the
natural follow-up — collapsing N short-circuited reader-pool replies into one
handler invocation — and rejected it: the profile counter improved, the
Tracelite measured-elapsed primary gates did not.

Experiment 148's decision listed four named sub-buckets of exp 147's residual
as the next plausible implementation targets: dirty-set harvest, writer reply
send, main-isolate request resolution, and drain-time coordination. Without
sizing those buckets, the next implementation pass would either re-attempt
one of them speculatively or default back to a workload-shape change.

The bounded question for this run: *of exp 147's residual writer/request
wall, how much sits in each named sub-bucket, and is any of them individually
large enough to justify an implementation experiment?*

## Hypothesis

If one of exp 148's named sub-buckets is large enough to clear a Tracelite
A/B primary gate, the audit will surface it as a measurable fraction of
writer-burst wall. If they are all individually small, the dominant residual
is something exp 148 did not name — most likely the same exp-136 reader-pool
completion handler chain firing BETWEEN writes during the writer burst, in
which case dispatch-area implementation work needs a different framing than
the four-bucket decomposition.

This measurement is useful in either branch: it either makes the next
dispatch implementation experiment concrete, or it removes the "split exp
147's residual" prompt from `signals.json#stream-rerun-dispatch`.

## Approach

Added five profile counters that subdivide writer-side burst wall to the
last currently-measurable level:

- `writer_handle_us` / `writer_handle_count` — total per-request
  writer-isolate handler wall (SQLite + dirty harvest + writer-internal
  overhead, captured BEFORE the `replyPort.send(...)`).
- `writer_dirty_us` / `writer_dirty_count` — `getDirtyTableDependencies(...)`
  cost on the writer isolate.
- `main_writer_reply_us` / `main_writer_reply_count` — main-isolate
  `Writer._request<T>` reply handler wall: port close, exception unwrap,
  `completer.complete(...)`. The downstream `await` continuation runs in a
  later microtask and is not counted here.

The new fields are carried back through `ExecuteResponse`, `BatchResponse`,
and `QueryResponse` analogous to exp 147's `writerSqliteUs`. Three
`ProfileCounters.recordWriter*` helpers wire them into the main-isolate
counter aggregation at every existing exp 147 site (`Database.execute`,
`Database.executeBatch`, `Database.transaction` commit path, `Transaction`
mirrors). `TraceliteProfile.profileCounters(...)` adds the new IDs so
Tracelite-backed profile runs preserve them.

Then added
[`benchmark/profile/residual_writer_wall_audit.dart`](../benchmark/profile/residual_writer_wall_audit.dart),
which reuses the shared `audit_workloads.dart` A11c (baseline / disjoint /
overlap) and keyed-PK runners introduced in exp 121 / 136 / 147. Wall
convention matches exp 147: subscriptions warm first, counters reset,
stopwatch stops on the last write, drain runs after wall capture. The new
audit also surfaces exp 136's `completion_handler_us` at burst-end so
in-burst reader-pool completion work can be separated from the
event-loop-and-mutex residual.

Derived per workload:

```text
writer_send_us = writer_handle_us - writer_sqlite_us - writer_dirty_us
rest_us        = wall_us - writer_handle_us - invalidate_us - main_writer_reply_us
```

`writer_send_us` approximates exp 148's "writer reply send" bucket (writer
handler overhead beyond SQLite + dirty, excluding the SendPort send itself).
`rest_us` covers main-isolate inter-request scheduling: writer mutex
acquisition, request build/serialize, awaits between writes, in-burst
reader-completion work, and measurement overhead.

The aggregate report is committed at
[`benchmark/profile/results/exp-149-residual-writer-wall-aggregate.md`](../benchmark/profile/results/exp-149-residual-writer-wall-aggregate.md).

## Results

Command:

```text
dart run -DRESQLITE_PROFILE=true \
  benchmark/profile/residual_writer_wall_audit.dart --markdown
```

Three independent single-pass runs on top of `origin/main`. All percentages
are share of writer-burst wall.

### Pass 1

| workload | wall_ms | sqlite | dirty | send | invalidate | main_reply | completion | rest |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 33.31 | 32.40% | 9.73% | 1.33% | 0.00% | 1.76% | 0.00% | 54.78% |
| A11c disjoint | 38.59 | 21.04% | 6.32% | 1.03% | 20.31% | 1.87% | 0.00% | 49.43% |
| A11c overlap | 86.90 | 15.08% | 4.36% | 0.56% | 16.07% | 1.04% | (n/a in pass 1) | 62.89% |
| keyed PK subs | 20.99 | 21.43% | 2.37% | 0.92% | 16.35% | 1.54% | (n/a in pass 1) | 57.38% |

### Pass 2

| workload | wall_ms | sqlite | dirty | send | invalidate | main_reply | completion | rest |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 33.45 | 31.57% | 10.18% | 1.25% | 0.00% | 1.96% | 0.00% | 55.04% |
| A11c disjoint | 38.36 | 21.46% | 7.56% | 0.96% | 18.32% | 1.87% | 0.00% | 49.83% |
| A11c overlap | 98.58 | 12.87% | 4.30% | 0.49% | 14.34% | 1.28% | (n/a in pass 2) | 66.73% |
| keyed PK subs | 21.23 | 22.85% | 2.57% | 0.98% | 15.38% | 1.69% | (n/a in pass 2) | 56.52% |

### Pass 3 (completion column added)

| workload | wall_ms | sqlite | dirty | send | invalidate | main_reply | completion | rest |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 33.44 | 32.31% | 9.84% | 1.36% | 0.00% | 1.65% | 0.00% | 54.83% |
| A11c disjoint | 38.13 | 22.49% | 6.82% | 1.05% | 21.30% | 1.83% | 0.00% | 46.51% |
| A11c overlap | 87.52 | 12.97% | 3.93% | 0.79% | 15.96% | 1.08% | 44.83% | 65.28% |
| keyed PK subs | 21.48 | 22.43% | 2.03% | 0.68% | 16.53% | 2.59% | 35.76% | 55.73% |

Per-write averages (pass 3):

| workload | writer_handle | writer_dirty | main_reply |
|---|---:|---:|---:|
| A11c baseline | 29.10 us/write | 6.58 us/write | 1.11 us/write |
| A11c disjoint | 23.16 us/write | 5.20 us/write | 1.40 us/write |
| A11c overlap | 30.96 us/write | 6.87 us/write | 1.88 us/write |
| keyed PK subs | 27.01 us/write | 2.19 us/write | 2.78 us/write |

Cross-checked the exp 147 audit on the same machine to confirm comparability:

```text
A11c overlap (exp 147 audit on this machine):
  wall_ms=87.22  sqlite=12.70%  invalidate=16.12%  residual=71.18%
A11c overlap (exp 149 pass 1):
  wall_ms=86.90  sqlite=15.08%  invalidate=16.07%
                 dirty=4.36% + send=0.56% + main_reply=1.04% + rest=62.89%
                 sum of exp-149 sub-buckets = 68.85% ≈ exp-147 residual
```

The minor gap (~2 %) is the writer-handler overhead measured in
`writer_handle_us` that includes work outside the original
`writer_sqlite_us`. Exp 147's residual reproduces.

Headline findings:

1. **None of exp 148's named writer-side sub-buckets is individually
   material on the active stream workloads.** Writer dirty-set harvest is
   2–10 % of wall, writer-handler residual ("send") is 0.5–1.4 %,
   main-isolate writer reply resolution is 1–3 %. Each is below the
   per-benchmark decision threshold the Tracelite suite uses to call
   primaries.
2. **The dominant sub-bucket of exp 147's residual is `rest_us` at
   46–67 % of writer-burst wall.** On stream-fanout workloads
   (A11c overlap, keyed-PK) the `completion_us` burst-end value alone
   accounts for **two-thirds of `rest_us`** (A11c overlap pass 3:
   completion 39.24 ms vs. rest 57.14 ms; keyed-PK pass 3: completion
   7.68 ms vs. rest 11.97 ms). On non-streaming and disjoint workloads
   `completion_us = 0` and `rest_us` is still 46–55 %.
3. **On A11c overlap, `completion_us` (44.83 % of wall) is the same
   exp-136 reader-pool reply handler chain exp 148 already targeted and
   rejected.** It fires inside the same main-isolate event-loop turns the
   harness `await Future<void>.delayed(Duration.zero)` pairs release
   between writes — so it lands inside writer-burst wall even though it
   is reader-side work.
4. **The truly unaccounted residual after subtracting `completion_us` is
   ~20 % of wall on overlap and ~20 % on keyed-PK** — about 36 us/write
   of writer mutex acquisition + request build + microtask scheduling +
   harness-yield overhead. No single line in that chain is individually
   visible at the current measurement floor.

## Decision

**Accept for review – measurement.** The result reframes the
`stream-rerun-dispatch` direction in two ways:

1. Exp 148's four-bucket decomposition was the right frame but the wrong
   answer: dirty harvest, writer reply send, and main-isolate request
   resolution are each individually too small to clear a Tracelite primary
   gate. Future dispatch experiments should NOT add or revisit a candidate
   that only targets one of those buckets.
2. The dominant overlap-and-keyed-PK residual is the same exp-136 reader
   completion chain exp 148 batched and the suite rejected — it surfaces as
   `completion_us` inside `rest_us` because writer-burst wall includes the
   `await Future.zero` event-loop turns that let reader replies fire between
   writes. There is no new large writer-side bucket waiting to be split.

The implementation candidate that survives this measurement is workload-
shape rather than writer-side: any change that reduces the number of
distinct `db.execute(...)` round-trips during a stream-fanout burst would
collapse both `rest_us` and `completion_us` proportionally. That is exactly
what `executeBatch` already provides for homogeneous writes; what is missing
is a heterogeneous-batch API, and that is a public-API change outside the
lean-API goal.

The two narrow implementation candidates left in scope are:

- a writer-side `_request<T>` micro-optimization that removes the per-call
  `RawReceivePort` + `Completer` allocations (target: ~1–2 us/write of the
  ~36 us/write generic residual, well below the Tracelite primary gate);
- a stream-engine reschedule that moves reader-pool reply work OUT of the
  writer-burst event-loop turns by changing dispatch admission timing
  (target: the `completion_us` share of `rest_us`, but exp 148 already
  showed that reducing the per-callback count without changing measured
  elapsed is not enough).

Neither is currently bounded enough for a single-pass A/B without a stronger
hypothesis. Recording them in `signals.json` rather than starting a Tracelite
A/B this run.

## Future Notes

- `writer_handle_us` is captured BEFORE `replyPort.send(...)`; the send
  itself is excluded. Same-isolate-group sends are sub-microsecond and the
  receiver pays the deep-copy cost, so this approximation under-counts by
  much less than the per-write decision threshold. A future experiment that
  needs end-to-end writer-side wall (including send) could move the
  capture point AFTER send by restructuring the handlers to return
  responses instead of calling `replyPort.send` themselves.
- The harness `await Future<void>.delayed(Duration.zero)` pairs are
  load-bearing: removing them would skew A11c overlap wall by removing the
  realistic between-write reader-pool concurrency. They also conflate
  reader-completion work into "writer-burst wall" — a future audit that
  wants a clean writer-only wall could snapshot counters before each
  `db.execute(...)` and accumulate.
- `getDirtyTableDependencies(...)` cost is ~2–7 us/write outside
  transactions and zero inside. A future writer-side optimization that
  removes a per-write FFI call would have to target this counter directly;
  do not retry blanket "writer reply send" or "main-isolate request
  resolution" ideas without an allocation profile that shows them as
  material at the per-write scale.

## Validation

- `dart pub get`
- `dart format lib/src/profile_counters.dart lib/src/tracelite_profile.dart lib/src/writer/write_worker.dart lib/src/writer/writer.dart lib/src/database.dart lib/src/transaction.dart benchmark/profile/residual_writer_wall_audit.dart`
- `dart analyze lib/src/profile_counters.dart lib/src/tracelite_profile.dart lib/src/writer/write_worker.dart lib/src/writer/writer.dart lib/src/database.dart lib/src/transaction.dart benchmark/profile/residual_writer_wall_audit.dart benchmark/profile/audit_workloads.dart`
- `dart test test/database_test.dart test/transaction_test.dart test/stream_test.dart`
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/writer_sqlite_wall_audit.dart` (cross-check against exp 147 on the same machine)
- `dart run -DRESQLITE_PROFILE=true benchmark/profile/residual_writer_wall_audit.dart --markdown` (×3 passes)
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/149-residual-writer-wall-split.md`
