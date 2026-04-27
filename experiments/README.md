# resqlite Experiments

Each file documents a performance experiment: what we tried, what we measured, and whether it worked. These serve as institutional memory — before trying a new optimization, check here to see if we've already explored it.

## Accepted

Experiments that proved their value and were merged into the codebase.

| # | Experiment | Impact | Commit |
|---|---|---|---|
| [001](001-c-native-json-serialization.md) | C-native JSON serialization | 3.5x faster bytes path | [`4acfb57`](https://github.com/danReynolds/dune/commit/4acfb57) |
| [003](003-c-level-connection-and-statement-cache.md) | C-level connection + statement cache | ~0.7ms saved per query | [`4acfb57`](https://github.com/danReynolds/dune/commit/4acfb57) |
| [004](004-nomutex-per-query-locking.md) | NOMUTEX with per-query locking | Eliminated 60k mutex ops at 20k rows | [`4acfb57`](https://github.com/danReynolds/dune/commit/4acfb57) |
| [007](007-c-level-connection-pool.md) | C-level connection pool | 4.4x faster concurrent reads | [`3a08838`](https://github.com/danReynolds/dune/commit/3a08838) |
| [008](008-flat-list-lazy-resultset.md) | Flat value list + lazy ResultSet | The breakthrough — 10x fewer objects, beat sqlite3 | [`a18492c`](https://github.com/danReynolds/dune/commit/a18492c), [`666da73`](https://github.com/danReynolds/dune/commit/666da73) |
| [009](009-batch-ffi-step-row.md) | Batch FFI (resqlite_step_row) | 9-21% improvement across all benchmarks | [`4c18bb4`](https://github.com/danReynolds/dune/commit/4c18bb4) |
| [013](013-ffi-isleaf.md) | FFI isLeaf annotation | 12-19% on small results, 5-9% across the board | [`af2cfd0`](https://github.com/danReynolds/dune/commit/af2cfd0) |
| [014](014-writer-tuning.md) | BEGIN IMMEDIATE + remove clear_bindings | Correct but within noise (write I/O dominated) | [`4c368a6`](https://github.com/danReynolds/dune/commit/4c368a6) |
| [015](015-cell-buffer-union.md) | Cell buffer union (48 → 16 bytes) | Simplicity win, performance neutral | [`52f1e4b`](https://github.com/danReynolds/dune/commit/52f1e4b) |
| [016](016-sqlite-compile-flags.md) | SQLite compile flags + prepare_v3 | Correctness wins, performance within noise | [`b9c6b6d`](https://github.com/danReynolds/dune/commit/b9c6b6d) |
| [019](019-hybrid-reader-pool.md) | Hybrid reader pool (SendPort + sacrifice) | 64-83% faster small reads, 45k qps point queries | [`e07d95b`](https://github.com/danReynolds/dune/commit/e07d95b) |
| [028](028-static-bind-params.md) | Static bind for text/blob params | Improves targeted small-read and parameterized-query workloads | [`8822bd2`](https://github.com/danReynolds/dune/commit/8822bd2) |
| [029](029-periodic-passive-checkpointing.md) | Periodic PASSIVE checkpointing | Much lower burst write p95/p99/max via writer-side scheduling | [`8822bd2`](https://github.com/danReynolds/dune/commit/8822bd2) |
| [020](020-lookaside-allocator.md) | SQLITE_DEFAULT_LOOKASIDE tuning | Zero-cost compile flag improvement |  |
| [021](021-pcache-initsz.md) | SQLITE_DEFAULT_PCACHE_INITSZ=128 | Slight positive trend on larger result sets |  |
| [022](022-wal-autocheckpoint.md) | WAL autocheckpoint tuning | Correctness and reliability improvement |  |
| [023](023-fast-itoa.md) | Fast int64-to-string for JSON | Measurable win on the selectBytes hot path |  |
| [024](024-json-buffer-16k.md) | JSON buffer initial size 16KB | Sensible default, no measurable impact |  |
| [030](030-dedicated-reader-assignment.md) | Dedicated reader assignment | Removes per-query C pool mutex overhead and closes the point-query gap |  |
| [032](032-row-map-facade.md) | Row `Map` facade overrides | Keeps the fast transport shape intact while materially improving main-isolate `Map` operations |  |
| [033](033-fnv1a-hash.md) | FNV-1a hash for result change detection | Shared module for consistent stream result hashing |  |
| [034](034-schema-cache.md) | Per-worker schema cache | Eliminates FFI calls + string allocations for repeated queries |  |
| [035](035-cell-buffer-reuse.md) | Reuse cell buffer across queries | Eliminates per-query buffer allocations |  |
| [036](036-compiler-hints.md) | Compiler hints (Dart + C) | Zero-risk annotations, no behavioral changes |  |
| [037](037-persistent-json-buffer.md) | Persistent JSON buffer per reader | Eliminates syscall-class operations on the hot path |  |
| [038](038-stack-alloc-col-names.md) | Stack allocation for column name arrays | Eliminates unnecessary heap allocations |  |
| [039](039-byte-size-sacrifice-threshold.md) | Byte-size sacrifice threshold | Better proxy for SendPort copy cost than cell count |  |
| [040](040-reader-slot-event-port-cleanup.md) | Reader slot event-port cleanup | Simpler reader-worker protocol with a measured point-query and large-read win |  |
| [043](043-swar-escape-lookup-table.md) | SWAR escape scanning + lookup table | 8-byte-at-a-time escape detection + lookup table eliminates branch chains in JSON strings |  |
| [044](044-batch-atomic-write.md) | `SQLITE_ENABLE_BATCH_ATOMIC_WRITE` | Zero-risk compile flag enabling 2-3x write speedup on Android F2FS |  |
| [045](045-microtask-invalidation-coalescing.md) | Microtask invalidation coalescing | Batches rapid sequential writes into a single invalidation pass per microtask |  |
| [064](064-drop-clear-bindings.md) | Drop redundant `sqlite3_clear_bindings` | Provably-redundant call removed; simpler bind path with documented invariants |  |
| [070](070-zero-row-change-shortcircuit.md) | Zero-row-change short-circuit + persistent dirty buffer | Removes per-write calloc/free pair and short-circuits empty dirty set to a const empty list |  |
| [075](075-native-hash-selectifchanged.md) | Native-buffered hash for `selectIfChanged` | **−39 % on unchanged-fanout benchmark**. Worker-side C hash (`resqlite_query_hash`) short-circuits stream re-queries before any Dart decode when the result is unchanged |  |
| [077](077-cheap-check-first-sweep.md) | Cheap-check-first sweep (four small wins) | **−13 % to −23 % on write benchmarks** from cached `sqlite3_bind_parameter_count`; pairs with three correctness-neutral fast-rejects on invalidation, hash, and subscription paths |  |
| [101](101-tx-stmt-cache.md) | Cached BEGIN/COMMIT/ROLLBACK statements | **−13 % to −14 %** on Batched-Write-Inside-Transaction and Growing-Stream Invalidation by replacing `sqlite3_exec`'s per-call prepare+finalize with three persistently prepared transaction-control stmts |  |
| [109](109-inline-param-buffer.md) | Inline-packed parameter buffer | **−10 % to −16 %** on text-param INSERT workloads (Single Inserts, Batch Insert, No-Streams Write Throughput) by collapsing per-text/blob `calloc` into the reusable param-struct buffer and passing actual UTF-8 byte length so `sqlite3_bind_text` skips its internal `strlen` |  |

## In Review

Promising experiments with an active implementation or PR, but not yet
merged into the codebase.

| # | Experiment | Impact | PR |
|---|---|---|---|
| [083](083-stream-rerun-pre-dispatch-queue.md) | Stream rerun pre-dispatch queue | Eliminates the measured `A11` / `A11b` reader-pool wait bottleneck by coalescing reruns before pool admission | [#25](https://github.com/danReynolds/resqlite/pull/25) |
| [097](097-one-pass-initial-stream-hash.md) | One-pass initial stream decode and hash | 14-16% faster setup-heavy streaming benchmarks by avoiding the initial stream query replay |  |
| [110](110-long-text-fnv-8byte.md) | Long-text stream hash benchmark + 8-byte FNV | Adds a long-text unchanged-fanout benchmark and cuts its median latency by 76% with chunked byte-stream hashing | [#53](https://github.com/danReynolds/resqlite/pull/53) |

## Rejected

Experiments that didn't work out. Each has valuable context on *why* — check before revisiting similar ideas.

| # | Experiment | Why Rejected |
|---|---|---|
| [111](111-sql-len-passthrough-analysis.md) | SQL byte-length passthrough — pre-implementation analysis | Per-call `strlen(sql)` removal across every C entry point is ~3–6 ns/query (≤ 0.07 % of dispatch wall) — sits below the same noise floor that already rejected exps 071, 094, 095, 102, 108. Reopen if a workload arrives with long auto-generated SQL strings (1+ KB) or a second compounding per-call C-side saving lands first |
| [108](108-selectbytes-out-slots.md) | Persistent selectBytes out-parameter slots | Target selectBytes benchmarks stayed within noise, and memory/rss flags removed any case for permanent native scratch state |
| [103](103-native-nested-tx-depth-control.md) | Native nested transaction depth control | Focused nested-tx benchmark showed at best a small savepoint-only improvement; realistic nested write cases were flat or worse, so extra native API surface is not justified |
| [105](105-reader-pool-sizing.md) | Raise reader pool worker cap (4→8) | Regressed A11c writer throughput by ~31% under N=50 stream fan-out; the profile's reader-pool serialization bottleneck was actually throttling completion-side microtask churn. Cap=4 is correctly tuned. |
| [104](104-094-reeval-under-a11c.md) | Re-eval of exp 094 (dirty/read string reuse) under A11c | Even under A11c fan-out (~50× amplification of read-set/dirty-set add traffic), deltas were within noise on every workload the change targets (disjoint +4%, overlap −2%, concurrent reads ±10% — all inside MDE_ci). Empirically validates 094's original "below noise floor" rejection. |
| [100](100-bounded-stream-requery-scheduler.md) | Bounded stream re-query scheduler | Did not improve unrelated reads during fan-out and regressed high-cardinality stream fan-out by 103% |
| [025](025-pragma-optimize.md) | `PRAGMA optimize` | Right idea in principle, but no compelling or reliable benchmark win in the current suite |
| [026](026-db-status-probe.md) | `sqlite3_db_status()` probe | Near-perfect cache hit rates and zero spill mean a page-cache experiment is not justified |
| [027](027-transaction-query-writer-cache.md) | Transaction query writer cache | Did not move the target interactive transaction metric enough to justify merging |
| [031](031-json1-bulk-shapes.md) | JSON1 bulk shapes | Mixed and workload-specific; only compelling when the payload is already serialized as JSON |
| [002](002-c-binary-buffer-for-maps.md) | C binary buffer for maps | Double-pass overhead (C encode + Dart decode) negated FFI savings |
| [005](005-dart-binary-codec-transferable-typed-data.md) | Dart binary codec + TransferableTypedData | 5-7x slower than VM's native SendPort.send serializer |
| [006](006-string-interning.md) | String interning | Hash lookup cost exceeded dedup savings on mostly-unique data |
| [008b](008b-byte-backed-lazy-maps.md) | Byte-backed lazy maps | Moved decode work (utf8.decode) to main isolate — wrong trade-off |
| [010](010-ascii-fast-path-string-decode.md) | ASCII fast-path string decode | Marginal gain for ASCII, strictly worse for non-ASCII |
| [011](011-persistent-reader-pool.md) | Persistent reader pool | Equivalent to one-off isolates; pool overhead cancels messaging savings |
| [012](012-sendport-vs-spawn-deep-dive.md) | SendPort vs Isolate.spawn deep dive | Confirmed one-off isolates are optimal; persistent pools not faster |
| [014](014-writer-tuning.md) | locking_mode=EXCLUSIVE *(partial)* | Blocks all readers — incompatible with concurrent reader pool |
| [017](017-dart-postcobject.md) | Dart_PostCObject for reads | 2-5x slower — serialize/deserialize costs more than validation walk |
| [018](018-multi-row-step.md) | Multi-row step (64 rows/FFI call) | String copy overhead exceeds FFI crossing savings |
| [041](041-ryu-double-to-string.md) | Ryu double-to-string for JSON | Initially accepted but reverted after re-analysis: only -10% on one benchmark (text-heavy 1k rows) was actually attributable to 041; the claimed selectBytes wins were from 043. Not worth ~1500 lines of vendored third-party code + ~85-line format-compatibility wrapper |
| [042](042-lto-build-flag.md) | LTO build flag (`-flto`) | Four rounds tested (full, noinline, stacked, thin). Every config net negative — icache pressure from cross-unit inlining into the 250k-line SQLite amalgamation |
| [051](051-lock-free-reader-pool.md) | Lock-free reader pool with atomics | Mutex path is dead code since experiment 030 assigned dedicated readers; optimization target doesn't exist in the live path |
| [052](052-column-level-dependencies.md) | Column-level dependency tracking | Sound architecture (skip re-queries on writes to non-watched columns), but current streaming benchmarks have 0% disjoint-column rate — benchmark-invisible |
| [046](046-sync-stream-controller.md) | Synchronous StreamController | Reentrancy crash: sync delivery causes concurrent modification of subscriber list during iteration |
| [047](047-authorizer-opt-out.md) | Authorizer opt-out for non-stream queries | Shared statement cache stores empty dependency sets when tracking is off, breaking stream invalidation |
| [053](053-page-size-8192.md) | Page size 8192 | -16% select at 10k rows on new DBs but breaks existing DBs (requires VACUUM); should be exposed as `Database.open` option, not default |
| [054](054-pgo.md) | Profile-Guided Optimization | macOS dylib profraw flush doesn't fire from Dart VM host process; needs CI pipeline with standalone C binary |
| [055](055-columnar-typed-arrays.md) | Columnar typed arrays | Memory win confirmed (75% for numerics, 10000x fewer GC objects) but below time-based benchmark floor; requires memory profiling harness |
| [057](057-preupdate-batching.md) | Preupdate hook batching for batch inserts | Savings (~2ms in 50ms batch) below noise floor |
| [058](058-short-string-cache.md) | Short-string value cache | +134-256% regression. Dart's `String.fromCharCodes` is uncatchable with any Dart-level cache |
| [059](059-row-count-hint.md) | Row count hint in schema cache | Marginal wins (2/0/61) on repeated queries but below noise on primary paths |
| [060](060-combined-single-row-ffi.md) | Combined single-row FFI call | Text pointers invalidated by `sqlite3_reset` — required the inline-copy approach explored later |
| [063](063-select-one-fast-path.md) | SelectOne fast path API | +28-48% point query win measured but rejected to preserve lean API surface |
| [065](065-json1-reevaluation.md) | JSON1 re-evaluation (post-041/043) | Our custom path now ≥ JSON1 everywhere; confirms 031 with larger margin |
| [066](066-transparent-fast-path.md) | Transparent single-row fast path in `select()` | Insufficient headroom — most of 063's win came from return-type change (`Map` vs `List<Map>`) which can't be captured transparently |
| [067](067-shrink-initial-allocation.md) | Shrink initial values allocation (256→4) | Caused +40-44% regressions; Dart VM has a fast path for `List.filled` that shrinking bypasses |
| [068](068-ddl-schema-watchdog.md) | DDL schema_version watchdog | Deferred: initial implementation shipped + reverted after CI flakiness. Root cause is a C-level stmt cache race with SQLite's auto-reprepare — needs its own design pass to invalidate cached stmts on schema version bump |
| [069](069-sql-fingerprint.md) | SQL fingerprint in stmt cache | Deferred: proper normalization needs a ~300+-line SQL rewriter; `sqlite3_normalized_sql` takes a prepared stmt as input, not raw SQL |
| [071](071-stmt-cache-mru-scan.md) | MRU-first stmt cache scan + SQL hash filter | Structurally sound but unmeasurable: benchmark suite uses ≤ 10 distinct SQLs so the cache never stresses the scan path |
| [072](072-xxhash-for-fnv.md) | xxhash64 replacing FNV-1a for result change detection | +75 % regression on stream invalidation: xxhash mergeRound is ~2× more ops than FNV's xor+mul, and our inputs are pre-hashed 64-bit values rather than byte streams (where xxhash wins) |
| [073](073-schema-cache-fast-path.md) | Single-slot schema-cache fast-path | Within noise: Dart's cached `String.hashCode` already makes map lookups fast enough that a one-slot bypass is below the measurement floor for the current suite |
| [074](074-bulk-step-many.md) | Bulk `step_many` batched FFI for read path | Same wall as exp 018: memcpy-in-C cost exceeds FFI-crossing savings. Text-heavy workloads regressed +38 %. Dart already reads directly from SQLite's text buffer; adding a C-side copy before Dart decode is strictly worse |
| [076](076-prebound-stmt-cache-analysis.md) | Pre-bound statement cache | Rejected in pre-implementation analysis: bind is ~0.3 % of re-query wall time (~50 ns per call). No measurable headroom even for a perfect implementation |
| [081](081-binary-row-result-storage.md) | Binary row result storage | Transfer-side numeric scan wins collapsed once full main-isolate row consumption was measured; mixed rows regressed and point-query floor worsened |
| [082](082-message-graph-handoff.md) | Message-graph hand-off benchmark | Current `ResultSet` / `Row` shape is already near-optimal for the shipped `select()` contract; materialized maps and binary row facades both lose on end-to-end total |
| [084](084-late-dispatch-generation-stamp.md) | Late dispatch generation stamp | Real partial improvement, but materially weaker than 083 because reruns still pile up inside `ReaderPool` |
| [085](085-reserved-reader-slot-for-reruns.md) | Reserved reader slot for reruns | The queue is the real source of the `A11` / `A11b` win; removing the reserved reader regressed broader workload balance, especially `A7` |
| [088](088-setlk-timeout.md) | `SQLITE_ENABLE_SETLK_TIMEOUT` + `sqlite3_setlk_timeout` on every connection | Downgraded from Accepted after 5-run confirmation: original single-run p99/max wins were noise (baseline outlier that never reproduced). Multi-run median shows p99 +74 % to +172 % worse and max +29 % to +529 % worse on writes; noop regresses even though it has no lock contention. Needs a concurrent-reader harness + shorter timeout to be evaluable |
| [089](089-deeply-immutable-resultset.md) | Deeply-immutable `ResultSet` for zero-copy isolate transfer | Blocked upstream: Dart's `@pragma('vm:deeply-immutable')` requires all fields to be in a closed set that excludes `List<T>`, `Uint8List`, and any typed data. `ResultSet` / `RawQueryResult` are `List<Object?>`-centered and BLOB cells are `Uint8List`. Re-check when SDK #50068 (DI typed-data factory) ships |
| [090](090-sqlite3mc-bump-audit.md) | sqlite3mc dependency bump audit | No bump needed — we are already on the newest stable sqlite3mc (2.3.2 / SQLite 3.51.3, 37 days old). The only newer target (3.53.0) is a 12-day-old .0 release excluded by our known-regressions policy, and its changelog shows no hot-path wins. Revisit when 3.53.2+ ships |
| [092](092-wal-checkpoint-noop.md) | `wal_checkpoint=NOOP` probe in periodic checkpointer | Premise invalid — exp-029 is hook-gated on `pages_in_wal`, not timer-gated. NOOP exists to report the frame counter the wal-hook already receives; adding NOOP would be a strictly additive header read with no empty-tick cost to amortize |
| [093](093-alias-cache-entry-read-tables.md) | Alias cache entry's read tables instead of copying | Below the measurement floor — savings ceiling was one `strdup`/`free` pair per cached table name per reader query (~hundreds of ns on a 1–3 table query). Work medians unchanged in 3-run A/B; tail regressions pattern-matched run-to-run variance (`noop` regressed as much as `point_query`, but `noop` never touches the changed path). Same class as exp 076 |
| [094](094-dirty-read-string-reuse.md) | Dirty/read table string reuse | Focused dispatch was effectively flat and the full suite produced no wins; native branch/lifetime complexity is not justified |
| [095](095-writer-result-buffer.md) | Persistent writer result buffer | The removable 16-byte calloc/free pair did not produce reliable write-path wins |
| [096](096-direct-batch-param-encoding.md) | Direct batch parameter encoding | Large batch medians only trended down; no accepted-level harness win and too much duplicate parameter-encoding code |
| [099](099-fnv-8byte-bytestream.md) | 8-byte-chunked FNV for byte-stream cells | Structurally sound (folds 8 bytes per multiply on the long-text hash path) but benchmark-invisible — current streaming workloads carry only short cells (≤ 3–8 bytes) that bypass the new main loop. Same class as exp 071. Revisit when a long-text streaming benchmark exists |
| [102](102-savepoint-string-cache.md) | Cached SAVEPOINT/RELEASE/ROLLBACK TO strings on `_WriterState` | Theoretically removes per-nested-tx `toNativeUtf8` + `calloc.free` pair, but the benchmark suite has no nested-transaction workload — no directly attributable signal, only run-to-run drift on unrelated read paths. Pattern-matches exp 095. Revisit if a deeply-nested-tx benchmark exists |

## Conventions

- **Experiment number:** Monotonically increasing, never reused
- **Date:** When the experiment was run (full timestamp preferred: `2026-04-14T12:30:00`)
- **Status:** `Accepted` (merged into codebase), `In Review` (promising but not merged), or `Rejected` (abandoned, with explanation)
- **Commit:** Git hash of the implementing commit (added to header of each accepted experiment)

### Research Map

Scheduled experimenters should use
[`RUNNER_INSTRUCTIONS.md`](RUNNER_INSTRUCTIONS.md) as the copyable instruction
block for recurring experiment systems. Those instructions point runners at
this README, [`signals.json`](signals.json), [`JOURNAL.md`](JOURNAL.md), and
[`MILESTONES.md`](MILESTONES.md) before choosing work.

`signals.json` is the canonical research map. These files are steering context,
not an allowed list. They should make prior work easy to understand without
preventing creative experiments outside the current map. A strong new
experiment can follow an active direction, revisit an area that recently looked
weak, or open a new direction entirely. The important thing is to explain why
the attempt is worth a bounded pass in light of prior work.

When an experiment changes what future work should try, de-emphasize, measure,
or watch:

- update the experiment writeup with the record of what happened
- update `signals.json` with machine-readable direction context
- add to `JOURNAL.md` only when the run surfaced a transferable lesson a
  future runner could reapply elsewhere
- leave `MILESTONES.md` alone — it is updated on maintainer request, not per
  experiment

### Standard Template

Use these exact headings so the experiments page can extract content automatically:

```markdown
# Experiment NNN: Title

**Date:** 2026-04-14
**Status:** Accepted / Rejected
**Direction:** `direction-id`
**Commit:** [`abc1234`](https://github.com/danReynolds/resqlite/commit/abc1234)
**Archive:** [`archive/exp-NNN`](https://github.com/danReynolds/resqlite/compare/main...archive/exp-NNN)

## Problem

What performance issue or opportunity was identified.

## Hypothesis

The proposed optimization and why it should work.

## Approach

What was built or changed. Implementation details.

## Results

Benchmark measurements. Use markdown tables for comparisons.

## Decision

Why accepted or rejected. Trade-offs considered.

## Future Notes

Optional. Short notes for future experimenters: adjacent prior work, what would
make the area interesting again, or what to measure before revisiting.
```

Header fields:

- **Commit** — required for Accepted experiments; points at the merged
  implementation commit on main.
- **Archive** — added for Rejected experiments *whose implementation is
  worth preserving for future re-evaluation* (the common case when the
  rejection reason is "below noise floor, not worth the complexity").
  Points at a git tag (`archive/exp-NNN`) that pins the last commit of
  the experiment branch before it was deleted. See the
  `resqlite-experiment` skill for the tagging workflow. Skip this field
  for rejections of the form "implementation was broken" — there's
  nothing worth preserving.

Older experiments use varied headings (`What We Built`, `Changes`, `Benchmark`, `Why Accepted`, etc.) — those still work, but new experiments should follow this template.
