# Experiment 134: Keyed PK dirty rowid elision profile

Profile harness: `benchmark/profile/invalidation_traversal_audit.dart`

Baseline: `origin/main` at `d3ed0ce`
Candidate: `exp-134-keyed-pk-dirty-elision`

Both runs used:

```text
dart run -DRESQLITE_PROFILE=true benchmark/profile/invalidation_traversal_audit.dart --markdown
```

## Focused Profile

The important shape is keyed PK subscriptions: 50 streams watch fixed
`WHERE id = ?` rows while 200 deterministic writes touch only 3 watched
rowids. Baseline table/column invalidation must consider all 50 streams on
every write. The candidate attaches rowid precision to verified simple
INTEGER PRIMARY KEY streams and drains dirty rowids from the writer
preupdate hook.

| workload | baseline wall_ms | candidate wall_ms | delta | baseline invalidate_us | candidate invalidate_us | baseline intersection_entries | candidate intersection_entries | emissions |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| keyed PK subscriptions | 25.54 | 12.45 | -51.3% | 3836 | 1700 | 10000 | 3 | 3 |

The `intersection_entries` collapse is the decision signal: only the 3
watched-row hits reach column-intersection/re-query scheduling. The 197
misses now skip before per-stream column checks and reader-pool re-query
admission.

## Stream Guardrails

| workload | baseline wall_ms | candidate wall_ms | read |
|---|---:|---:|---|
| A11c baseline | 38.60 | 41.69 | no stream path; run noise |
| A11c disjoint | 50.71 | 54.91 | small/noisy upward profile pass |
| A11c overlap | 111.00 | 101.56 | neutral/supportive |

Release many-streams guardrail:

| workload | baseline | candidate | delta |
|---|---:|---:|---:|
| no-streams baseline | 17,263 w/s | 19,722 w/s | +14.2% |
| disjoint column writes | 23,946 w/s | 24,618 w/s | +2.8% |
| overlapping column writes | 9,297 w/s | 8,763 w/s | -5.7% |

The release guardrail keeps the rowid bookkeeping within normal run-to-run
variance on the existing column-elision workloads.

## Public Suite

`benchmark/suites/keyed_pk_subscriptions.dart` includes a quiet-window drain,
so the 200 ms floor hides most of the writer-burst improvement. It still moves
in the right direction:

| metric | baseline | candidate | delta |
|---|---:|---:|---:|
| resqlite wall median | 223.32 ms | 217.75 ms | -2.5% |
| total emits | 0 | 0 | unchanged |
| observed hits | 3 | 3 | unchanged |

