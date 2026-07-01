# Exp 209: Heterogeneous Read Batch

Focused benchmark:

```bash
dart run benchmark/experiments/heterogeneous_read_batch.dart --order=parallel-first
dart run benchmark/experiments/heterogeneous_read_batch.dart --order=batch-first
```

Each round runs three lanes on the same seeded database (10 000 rows in
one table, indexed by category), on both sides:

- **point**: 20 single-row PK lookups (`SELECT ... WHERE id = ?`). Per-query
  SQLite work is well below the reader-pool round trip — the amortization
  lane.
- **medium**: 20 short-list SELECTs (`WHERE category = ? LIMIT 10`, ~10 rows
  each).
- **large** [guard]: 4 full-table 10 000-row SELECTs. Big payload per call —
  the lane where reader-pool fan-out parallelism should still win.

The baseline lane fires each request through `Future.wait([db.select(...)])`.
The candidate lane wraps the same statements in
`db.selectAll([...ReadStatement...])` — one reader-worker round trip.

## Parallel-first

```text
=== Heterogeneous read batch experiment (exp 209) ===
order: _Order.parallelFirst
rounds: 9

point / 20 single-row PK lookups (parallel): median 0.366ms  rounds [0.703, 0.331, 0.409, 0.387, 0.326, 0.510, 0.366, 0.328, 0.361]ms
point / 20 single-row PK lookups (batch): median 0.099ms  rounds [0.105, 0.105, 0.099, 0.093, 0.090, 0.138, 0.082, 0.093, 0.100]ms
medium / 20 ~10-row list SELECTs (parallel): median 0.281ms  rounds [0.281, 0.337, 0.294, 0.278, 0.241, 0.293, 0.219, 0.246, 0.299]ms
medium / 20 ~10-row list SELECTs (batch): median 0.151ms  rounds [0.181, 0.224, 0.163, 0.151, 0.138, 0.751, 0.129, 0.139, 0.135]ms
large / 4 10k-row SELECTs (parallel) [guard]: median 1.567ms  rounds [1.424, 1.567, 1.666, 1.426, 1.857, 1.743, 1.393, 1.695, 1.396]ms
large / 4 10k-row SELECTs (batch) [guard]: median 6.397ms  rounds [4.500, 4.954, 7.348, 4.559, 8.136, 6.397, 6.716, 7.430, 4.806]ms
```

Median deltas:

- point: **−72.9%** (batch ≈ 3.7× faster)
- medium: **−46.3%** (batch ≈ 1.86× faster)
- large [guard]: **+308%** (batch ≈ 4.1× slower — expected)

## Batch-first

```text
=== Heterogeneous read batch experiment (exp 209) ===
order: _Order.batchFirst
rounds: 9

point / 20 single-row PK lookups (parallel): median 0.259ms  rounds [0.347, 0.259, 0.246, 0.188, 0.257, 0.419, 0.307, 0.214, 0.260]ms
point / 20 single-row PK lookups (batch): median 0.103ms  rounds [0.286, 0.097, 0.103, 0.155, 0.089, 0.120, 0.099, 0.101, 0.116]ms
medium / 20 ~10-row list SELECTs (parallel): median 0.259ms  rounds [0.299, 0.227, 0.295, 0.306, 0.220, 0.229, 0.234, 0.292, 0.259]ms
medium / 20 ~10-row list SELECTs (batch): median 0.149ms  rounds [0.210, 0.169, 0.177, 0.141, 0.149, 0.129, 0.156, 0.147, 0.126]ms
large / 4 10k-row SELECTs (parallel) [guard]: median 1.640ms  rounds [1.581, 1.702, 3.442, 1.616, 4.944, 1.505, 1.640, 3.201, 1.601]ms
large / 4 10k-row SELECTs (batch) [guard]: median 4.506ms  rounds [4.506, 4.664, 5.005, 4.499, 6.461, 4.496, 4.492, 4.684, 4.447]ms
```

Median deltas:

- point: **−60.2%** (batch ≈ 2.5× faster)
- medium: **−42.5%** (batch ≈ 1.74× faster)
- large [guard]: **+175%** (batch ≈ 2.75× slower — expected)

## Interpretation

The batch win reproduces same-direction on both order flips for the two
small-read lanes. The magnitude drops slightly in the batch-first pass
because Dart AOT tail effects favor whichever side runs later, but the
sign and the ordering are stable:

- batch wins **most** on the shape where per-query SQLite work is
  smallest relative to the reader-pool round-trip cost;
- batch wins **less** as per-query work grows;
- batch **loses** on the large-payload guard, where parallel fan-out
  across 4 reader workers dominates a single-worker serial loop.

The guard confirms the shape of the trade — `selectAll` is not a free
replacement for `select` fan-out; it is an explicit knob for a specific
workload (many small heterogeneous reads issued together) that the
current parallel-fan-out path cannot serve efficiently.
