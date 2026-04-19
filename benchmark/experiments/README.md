# resqlite Benchmark Experiments

These scripts are for exploratory benchmarking and architecture tuning.

They are intentionally separate from the main release suite in
[benchmark/run_release.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/run_release.dart)
because they are narrower, more hypothesis-driven, or less apples-to-apples.

For A/B comparisons across an experiment branch vs baseline, see
[benchmark/run_profile.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/run_profile.dart)
and [benchmark/EXPERIMENTS.md](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/EXPERIMENTS.md)
— that's the profile-mode harness with diagnostic instrumentation
compiled in (gated behind `-DRESQLITE_PROFILE=true`).

Current experiments:

- [checkpoint_policy.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/checkpoint_policy.dart)
- [db_status_probe.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/db_status_probe.dart)
- [ffi_overhead.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/ffi_overhead.dart)
- [json1_bulk_shapes.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/json1_bulk_shapes.dart)
- [pool_size.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/pool_size.dart)
- [pool_vs_exit.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/pool_vs_exit.dart)
- [row_map_facade.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments/row_map_facade.dart)

Use these when tuning internals, not when producing the headline package comparison.
