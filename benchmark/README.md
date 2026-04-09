# resqlite Benchmarks

This folder has two distinct purposes:

1. package-local `resqlite` performance exploration via [run_all.dart](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/run_all.dart)
2. cross-library comparison via the shared verifier harness in [`sqlite_reactive_verifier`](/Users/dan/Coding/dune_gemini/packages/sqlite_reactive_verifier)

The second path is the canonical comparison flow.

## Local resqlite Suite

From [`packages/resqlite`](/Users/dan/Coding/dune_gemini/packages/resqlite):

```bash
dart run benchmark/run_all.dart my-label
```

Useful options:

```bash
dart run benchmark/run_all.dart my-label --repeat=5
dart run benchmark/run_all.dart my-label --repeat=5 --compare-to=benchmark/results/2026-04-08T14-44-58-final.md
```

`run_all.dart` now:
- accepts an explicit `--compare-to=...` baseline instead of always diffing against the latest file
- supports `--repeat=N` to rerun the full package-local suite multiple times
- emits a `Repeat Stability` section for resqlite medians
- uses a noise-aware comparison threshold of `max(10%, 3 × current MAD%)` with a `±0.02 ms` absolute floor for ultra-fast cases

That runs the package-local suites:

- select maps
- select bytes
- schema shapes
- scaling
- concurrent reads
- parameterized queries
- writes

Experiment-only scripts live under [benchmark/experiments](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/experiments) and are intentionally not part of the default suite.

Recommended workflow for performance decisions:

1. Pick a pinned baseline with `--compare-to=...`
2. Run at least `--repeat=5`
3. Trust stable cases first; treat `Repeat Stability: noisy` rows as advisory

## Main-only Four-Way Comparison

Run `resqlite` in its own process, then run the verifier for the peer libraries.

### 1. Run resqlite

From [`packages/resqlite`](/Users/dan/Coding/dune_gemini/packages/resqlite):

```bash
dart run benchmark/head_to_head_worker.dart \
  --out=/tmp/resqlite_main_h2h.json
```

### 2. Run verifier core cases

From [`packages/sqlite_reactive_verifier`](/Users/dan/Coding/dune_gemini/packages/sqlite_reactive_verifier):

```bash
flutter pub run bin/sqlite_reactive_benchmark.dart \
  --libraries=sqlite_reactive,sqlite_async,sqlite3 \
  --benchmarks=open_only,cold_open,single_row_crud,batch_write_transaction,read_under_write,large_result_read,large_result_read_large,repeated_point_query \
  --db-root=/tmp/resqlite_main_rebench \
  --out-json=/tmp/resqlite_main_rebench_core.json
```

### 3. Run verifier reactive cases

From [`packages/sqlite_reactive_verifier`](/Users/dan/Coding/dune_gemini/packages/sqlite_reactive_verifier):

```bash
flutter pub run bin/sqlite_reactive_benchmark.dart \
  --libraries=sqlite_reactive,sqlite_async \
  --benchmarks=stream_invalidation_latency,burst_coalescing,reactive_fanout_shared_query,reactive_fanout_unique_queries \
  --db-root=/tmp/resqlite_main_rebench \
  --out-json=/tmp/resqlite_main_rebench_reactive.json
```

### 4. Read the outputs

The generated files are:

- `/tmp/resqlite_main_h2h.json`
- `/tmp/resqlite_main_rebench_core.json`
- `/tmp/resqlite_main_rebench_reactive.json`

`resqlite` and the verifier are intentionally run as separate commands because loading them into the same VM can hit native asset / SQLite symbol conflicts.

This is the preferred way to compare `resqlite` against:

- `sqlite_reactive`
- `sqlite_async`
- `sqlite3`

## Current Main Baseline

Latest checked-in main-only baseline:

- [2026-04-08-codex-main-four-way.md](/Users/dan/Coding/dune_gemini/packages/resqlite/benchmark/results/2026-04-08-codex-main-four-way.md)
