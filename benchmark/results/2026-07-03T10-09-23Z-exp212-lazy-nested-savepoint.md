# Exp 212: Lazy nested-savepoint materialization moonshot

Date: 2026-07-03T10:09:23Z

Focused harness:

```bash
dart run benchmark/experiments/savepoint_name_compression.dart
```

Prototype archive:

- `archive/exp-212`
- prototype commit: `ce0c13b`

## Pair 1 - baseline first

Baseline (`origin/main` at exp 211):

| Case | Median ms | Min | Max |
|---|---:|---:|---:|
| empty fanout x500 | 4.760 | 3.914 | 10.652 |
| write fanout x100 | 1.603 | 1.392 | 2.147 |
| rollback fanout x100 | 2.383 | 1.893 | 2.911 |
| deep chain 100 x depth=5 | 3.702 | 3.554 | 4.752 |

Candidate (`archive/exp-212` prototype):

| Case | Median ms | Min | Max |
|---|---:|---:|---:|
| empty fanout x500 | 1.052 | 0.635 | 4.549 |
| write fanout x100 | 2.802 | 1.837 | 4.049 |
| rollback fanout x100 | 2.738 | 1.789 | 4.535 |
| deep chain 100 x depth=5 | 3.934 | 3.731 | 4.444 |

## Pair 2 - candidate first

Candidate (`archive/exp-212` prototype):

| Case | Median ms | Min | Max |
|---|---:|---:|---:|
| empty fanout x500 | 1.230 | 0.624 | 4.598 |
| write fanout x100 | 2.174 | 1.544 | 3.149 |
| rollback fanout x100 | 2.462 | 1.795 | 3.113 |
| deep chain 100 x depth=5 | 4.004 | 3.845 | 4.651 |

Baseline (prototype reverted):

| Case | Median ms | Min | Max |
|---|---:|---:|---:|
| empty fanout x500 | 4.823 | 3.943 | 9.830 |
| write fanout x100 | 1.612 | 1.338 | 2.494 |
| rollback fanout x100 | 2.445 | 1.878 | 3.124 |
| deep chain 100 x depth=5 | 3.736 | 3.498 | 4.045 |

## Deltas

Negative means candidate faster.

| Case | Pair 1 | Pair 2 |
|---|---:|---:|
| empty fanout x500 | -77.9% | -74.5% |
| write fanout x100 | +74.8% | +34.9% |
| rollback fanout x100 | +14.9% | +0.7% |
| deep chain 100 x depth=5 | +6.3% | +7.2% |

## Decision

Rejected. Empty nested bodies benefit strongly, but the representative
one-write nested fanout regresses in both pass orderings. Runtime complexity
for lazy savepoint materialization is not justified.

