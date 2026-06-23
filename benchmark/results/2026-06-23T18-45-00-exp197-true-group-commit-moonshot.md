# Exp 197 - True group commit moonshot

Focused harness: `dart run benchmark/experiments/writer_pipelining.dart`

Baseline: `origin/main` at `0f17307`.
Candidate: prototype commit `9e502e5`, archived as `archive/exp-197`.

## Pass 1 - candidate first

| Lane | Baseline median | Candidate median | Delta |
|---|---:|---:|---:|
| sequential-awaited (2000 writes) | 61.577 ms | 63.715 ms | +3.5% |
| concurrent-burst (10 x 200 writes) | 49.999 ms | 5.931 ms | -88.1% |
| transaction-guardrail (50 tx x 10) | 8.545 ms | 7.475 ms | -12.5% |

## Pass 2 - baseline first

| Lane | Baseline median | Candidate median | Delta |
|---|---:|---:|---:|
| sequential-awaited (2000 writes) | 66.486 ms | 65.836 ms | -1.0% |
| concurrent-burst (10 x 200 writes) | 44.919 ms | 5.717 ms | -87.3% |
| transaction-guardrail (50 tx x 10) | 7.678 ms | 7.686 ms | +0.1% |

## Reading

The concurrent-burst win reproduces across the order flip at roughly 8x faster.
Sequential writes and explicit transaction guardrails are effectively neutral.

This is not a mergeable hidden default: the candidate changes coalesced
standalone writes from independent autocommits into one shared SQLite
transaction. Caller-facing per-statement errors still passed the existing exp
180 tests, but concurrent read visibility, crash-window durability, and
atomicity semantics are no longer the same contract. The useful result is the
ceiling: true commit merging is a large frontier, but it needs an explicit API
or opt-in semantics rather than hidden transport behavior.
