# Experiment 184 — Writer residual re-split (post-159/180)

Profile-mode harness: `benchmark/profile/writer_sqlite_wall_audit.dart` (exp 147's),
re-run on `main` after exp 159 (writer pipelining) + exp 180 (group commit) to
check how the writer-burst breakdown shifted.

`residual_us = wall_us − writer_sqlite_us − invalidate_us`. The audit issues
writes **sequentially** (`audit_workloads.dart:167` — `await db.execute` per
write), so exp 180's concurrent-burst coalescing does not apply here; this maps
the **sequential** writer path.

## Counters

| workload | shape | wall_ms | writer_sqlite_us | invalidate_us | residual_us | emissions |
|---|---|---:|---:|---:|---:|---:|
| A11c baseline | 0 streams × 500 writes | 35.63 | 13536 | 0 | 22091 | 0 |
| A11c disjoint | 50 streams × 500 writes | 45.39 | 10776 | 9782 | 24829 | 0 |
| A11c overlap | 50 streams × 500 writes | 97.34 | 13281 | 15616 | 68441 | 33 |
| keyed PK | 50 streams × 200 random writes | 21.96 | 5195 | 3167 | 13603 | 3 |

## Derived fractions (vs exp 147 original)

| workload | SQLite/wall | invalidation/wall | residual/wall | exp147 residual |
|---|---:|---:|---:|---:|
| A11c baseline | 38.0% | 0.0% | 62.0% | — |
| A11c disjoint | 23.7% | 21.6% | 54.7% | ~54.7% |
| A11c overlap | 13.6% | 16.0% | **70.3%** | 71.8% |
| keyed PK | 23.7% | 14.4% | 61.9% | 63.3% |

## Reading

The breakdown is essentially unchanged from exp 147 — expected, because exp 180
targeted *concurrent* writes and this audit is sequential, where the residual is
the per-write isolate round-trip (the SDK-gated floor; the remaining lever is a
shared-memory transport). The cleanly-attackable buckets are smaller and either
spoken for or hard:

- **Invalidation / re-query precision (14–22%):** the real lever (exp 134 halved
  keyed-PK wall) but the *traversal* is at its floor (exp 121); the
  *re-query-count* reduction is what the in-flight **exp 160** (incremental view
  maintenance, PR #155) implements.
- **Dirty-table harvest (~4–6%, exp 182):** small; gating it hurt the
  with-streams path.
- **SQLite (14–38%):** sqlite3mc-config territory (exp 016/044/144), mined.

Directive: retire writer-residual micro-opts from the active candidate list. The
next reactive-engine win is exp 160; further sequential-write reduction needs the
shared-memory transport.
