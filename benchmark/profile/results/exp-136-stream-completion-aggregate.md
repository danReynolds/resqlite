# Experiment 136 - Stream Completion Wall Audit

Profile-mode harness: `benchmark/profile/stream_completion_audit.dart`

Reader pool size: 4 (`(Platform.numberOfProcessors - 1).clamp(2, 4)`)

Wall-clock convention: `wall_us` is writer-side burst wall - the stopwatch stops on the last write (matches exp 119 / 121 / 135). Main-isolate stream counters are picked up from `ProfileCounters` directly; writer counters from `Database.snapshotWriterProfileCounters`.

Command:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/stream_completion_audit.dart --markdown
```

## Counters

| workload | shape | wall_ms | invalidate_us | complete_us | complete_count | emit_us | emit_count | parked_total | max_parked | emissions |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams x 500 writes | 32.38 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c disjoint | 50 streams x 500 writes | 37.34 | 7878 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| A11c overlap | 50 streams x 500 writes | 91.74 | 13677 | 29122 | 3920 | 187 | 34 | 0 | 0 | 35 |
| keyed PK subscriptions | 50 streams x 200 random writes | 23.70 | 3296 | 4630 | 1126 | 10 | 2 | 0 | 0 | 3 |

## Derived fractions

| workload | invalidate / wall | complete / wall | emit / wall | accounted / wall | emit / complete | us per complete | us per emit |
|---|---:|---:|---:|---:|---:|---:|---:|
| A11c baseline | 0.00% | 0.00% | 0.00% | 0.00% | 0.00% | 0.00 | 0.00 |
| A11c disjoint | 21.10% | 0.00% | 0.00% | 21.10% | 0.00% | 0.00 | 0.00 |
| A11c overlap | 14.91% | 31.74% | 0.20% | 46.65% | 0.64% | 7.43 | 5.50 |
| keyed PK subscriptions | 13.91% | 19.54% | 0.04% | 33.45% | 0.22% | 4.11 | 5.00 |

## Reading the table

- `invalidate_us` is exp 121's existing counter: cumulative wall inside the synchronous body of `StreamEngine.onDependencyChanges` (table index lookup, column intersection probes, dirty/in-flight scheduling, and the `_flushQueue` kickoff).
- `complete_us` is exp 136's new counter: cumulative wall inside the synchronous post-`await` body of `StreamEngine._requery` (bookkeeping, hash-changed shortcut, `entry.emit`, and the trailing `_flushQueue` re-entry). Captures the per-re-query completion cost that runs after the reader pool resolves.
- `emit_us` is a strict subset of `complete_us`: the `for` loop in `StreamEntry.emit` that calls `StreamController.add` on every open subscriber. Captures per-subscriber fan-out, not bookkeeping.
- `accounted / wall` = `(invalidate_us + complete_us) / wall_us` is the share of writer-burst wall that the main-isolate synchronous stream-engine code accounts for. The remainder lives in framework microtask scheduling, subscriber callbacks, reader-pool internals, and any unmeasured async boundary.
- `parked_total` and `max_parked` should both stay at zero post-exp-120 / 122, reproducing earlier acceptance signals as a sanity check on top of the new counters.

## Interpretation

See `experiments/136-stream-completion-counter.md` for the decision and follow-up notes attached to these numbers.
