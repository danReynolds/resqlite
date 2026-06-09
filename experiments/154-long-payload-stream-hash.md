# Experiment 154: Long-Payload Stream Hash Workload

**Date:** 2026-06-09
**Status:** Rejected
**Direction:** `long-text-stream-hashing`, `measurement-system`
**Benchmark Run:** streaming release-suite probe plus focused Tracelite guardrail
**Archive:** Not created; the rejected native candidate was a small
`fnv_combine_bytes` loop-unroll variant, and the snippet below is enough to
recreate it if a future compiler or workload changes the trade-off.

## Problem

Experiment 110 made long TEXT stream hashing visible with an 8-stream, 256-row,
4KB TEXT unchanged-fanout benchmark and accepted the current 8-byte FNV byte
fold. The signal map still had one open measurement blocker: no workload
covered larger payloads or mixed TEXT/BLOB cells.

The bounded question for this run was not "add another benchmark" by itself.
The experiment needed to use that larger workload to evaluate a concrete,
low-risk hash-loop implementation and decide whether the implementation should
land.

## Hypothesis

For large TEXT/BLOB cells, loop overhead in `fnv_combine_bytes` may still be
visible after exp 110's 8-byte folding. Unrolling the large-buffer path four
8-byte words at a time should reduce loop-control overhead while preserving the
same hash operation order. Cells shorter than 64 bytes would stay on the
existing loop so short stream rows remain unaffected.

Reject if the new large-payload workload does not move materially or if the
normal short-cell / 4KB stream guardrails trend worse.

## Approach

Added a release streaming workload:

- 4 unchanged streams.
- 64 unchanged rows per stream.
- Each row carries one 32KB TEXT cell and one 32KB BLOB cell.
- A tiny `COUNT(*)` barrier stream is registered after the unchanged streams so
  timed iterations wait for the fanout wave without decoding a changed
  multi-megabyte result.

The attempted native candidate was:

```c
if (len >= 64) {
    for (; i + 32 <= len; i += 32) {
        uint64_t word0;
        uint64_t word1;
        uint64_t word2;
        uint64_t word3;
        memcpy(&word0, b + i, 8);
        h ^= word0;
        h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
        memcpy(&word1, b + i + 8, 8);
        h ^= word1;
        h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
        memcpy(&word2, b + i + 16, 8);
        h ^= word2;
        h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
        memcpy(&word3, b + i + 24, 8);
        h ^= word3;
        h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
    }
}
```

The final branch removes this native change. It keeps the workload and a long
BLOB hash correctness test because the workload resolves the measurement
blocker and the implementation result is a useful rejection.

## Results

Target streaming probe:

- Baseline root: `/Users/dan/.codex/worktrees/resqlite-exp154-baseline-20260609-122314`
  at `origin/main` (`c14bbbd`) with only the new benchmark harness applied
  locally.
- Candidate root: `/Users/dan/.codex/worktrees/resqlite-exp154-long-payload-stream-hash-20260609-122314`
  with the temporary native unroll candidate.

| workload | baseline | unrolled candidate | change |
|---|---:|---:|---:|
| Short unchanged fanout | 0.515 ms | 0.582 ms | +13.0% |
| Long-text unchanged fanout (4KB TEXT) | 4.002 ms | 5.234 ms | +30.8% |
| Large-payload unchanged fanout (32KB TEXT + 32KB BLOB) | 6.014 ms | 5.866 ms | -2.5% |

The target large-payload row moved only -2.5%, which is not meaningful in this
suite. The short-cell and 4KB guardrails moved the wrong way in the same pass.

Tracelite short-cell guardrail:

```text
dart run benchmark/run_tracelite_experiment.dart \
  --tracelite-root=/Users/dan/.codex/worktrees/tracelite-pinned-a2bf364 \
  --baseline-root=/Users/dan/.codex/worktrees/resqlite-exp154-baseline-20260609-122314 \
  --candidate-root=/Users/dan/.codex/worktrees/resqlite-exp154-long-payload-stream-hash-20260609-122314 \
  --label=exp-154-long-payload-stream-hash \
  --direction=stream-rerun-dispatch \
  --runs=1 \
  --min-repetitions=3 \
  --max-repetitions=6 \
  --suite-scenarios=keyed-pk-subscriptions \
  --policy-scenarios=keyed-pk-subscriptions \
  --out-dir=build/tracelite-experiments/exp-154-long-payload-stream-hash-guardrail
```

The wrapper collected baseline and candidate histories, but the single-run
baseline policy was `not_ready`, so the formal wrapper decision exited 65. The
underlying exploratory decision with `--allow-unready-policy=true` was:

| scenario | peer | metric | baseline | candidate | change | max CV | p | verdict | effect |
|---|---|---|---:|---:|---:|---:|---:|---|---|
| `keyed-pk-subscriptions` | `resqlite` | `measured_elapsed_ns` | 413 ms | 342 ms | -17.3% | 40.9% | 0.75 | neutral | inconclusive |

Guardrails passed, but this is not production-ready evidence because the
baseline policy was not ready and the lane was noisy/harness dominated.

Artifacts:

- `/tmp/resqlite-exp154-baseline-streaming.md`
- `/tmp/resqlite-exp154-candidate-streaming-rerun.md`
- `build/tracelite-experiments/exp-154-long-payload-stream-hash-guardrail/baseline/history.json`
- `build/tracelite-experiments/exp-154-long-payload-stream-hash-guardrail/candidate/history.json`
- `build/tracelite-experiments/exp-154-long-payload-stream-hash-guardrail/decision/decision-allow-unready.json`

## Decision

Reject the unrolled native hash loop.

The larger mixed TEXT/BLOB workload does exercise the intended path, but the
semantics-preserving loop-unroll variant did not produce a meaningful target
win and made existing stream hash guardrails look worse. No runtime code is
kept.

This is not a standalone measurement PR: the branch added the missing workload
to evaluate a concrete hash-loop candidate, used that workload to reject the
candidate, and keeps the workload so future hash variants can be tested
without repeating the measurement gap.

## Future Notes

- Do not retry simple loop unrolling inside `fnv_combine_bytes` unless a new C
  compiler/runtime changes the codegen materially.
- Future long-payload hashing work needs a stronger implementation candidate
  than loop-control reduction, such as a deliberately different large-payload
  hash strategy with an explicit collision-quality argument.
- Compare future hash-loop variants against both `Large-Payload Unchanged
  Fanout` and the existing short / 4KB stream rows before keeping runtime code.

## Validation

- `dart pub get` in candidate and baseline worktrees.
- `dart test test/query_decoder_test.dart test/stream_test.dart --timeout 60s`
- `dart test test/query_decoder_test.dart --timeout 60s` in the baseline
  worktree to build native assets for the benchmark-only probe.
- `dart run build_runner build --delete-conflicting-outputs` (the flag is
  ignored by the installed build_runner, but Drift outputs were generated).
- `dart analyze --fatal-infos`
- `dart run benchmark/finalize_experiment.dart --experiment=experiments/154-long-payload-stream-hash.md`
- `dart run benchmark/check_generated_data.dart && dart run benchmark/check_experiment_signals.dart`
- Streaming probe via temporary runner with `.dart_tool/package_config.json`
  against baseline and candidate.
- Tracelite guardrail command above; histories collected, wrapper decision
  failed on unready single-run policy, exploratory CLI decision produced an
  inconclusive neutral result with passing guardrails.
