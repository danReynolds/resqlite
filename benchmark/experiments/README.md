# resqlite Benchmark Experiments

These scripts are for exploratory benchmarking and architecture tuning.

They are intentionally separate from the main release suite in
[benchmark/run_release.dart](../run_release.dart)
because they are narrower, more hypothesis-driven, or less apples-to-apples.

For A/B comparisons across an experiment branch vs baseline, see
[benchmark/run_profile.dart](../run_profile.dart)
and [benchmark/EXPERIMENTS.md](../EXPERIMENTS.md)
— that's the profile-mode harness with diagnostic instrumentation
compiled in (gated behind `-DRESQLITE_PROFILE=true`).

Current experiments:

- [batch_param_flatten.dart](batch_param_flatten.dart)
- [checkpoint_policy.dart](checkpoint_policy.dart)
- [db_status_probe.dart](db_status_probe.dart)
- [ffi_overhead.dart](ffi_overhead.dart)
- [json1_bulk_shapes.dart](json1_bulk_shapes.dart)
- [pool_size.dart](pool_size.dart)
- [pool_vs_exit.dart](pool_vs_exit.dart)
- [row_map_facade.dart](row_map_facade.dart)
- [stream_scheduler.dart](stream_scheduler.dart)
- [sync_invalidate_entrypoint.dart](sync_invalidate_entrypoint.dart)

Use these when tuning internals, not when producing the headline package comparison.
