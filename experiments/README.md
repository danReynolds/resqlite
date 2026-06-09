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
| [106](106-column-level-deps.md) | Column-level dependency tracking (re-attempt of 052 under A11c) | **+82 %** on A11c disjoint writer throughput (3,956 → 7,201 w/s); overlap unchanged (4,477 → 4,581 w/s); overlap/disjoint ratio drops 1.132 → 0.636, the direct signature of writer-side dispatch elision |  |
| [109](109-inline-param-buffer.md) | Inline-packed parameter buffer | **−10 % to −16 %** on text-param INSERT workloads (Single Inserts, Batch Insert, No-Streams Write Throughput) by collapsing per-text/blob `calloc` into the reusable param-struct buffer and passing actual UTF-8 byte length so `sqlite3_bind_text` skips its internal `strlen` |  |
| [115](115-dispatcher-park-counters.md) | Dispatcher park counters for `ReaderPool` | Measurement-only: profile-mode counters (park-total, wake-retry-total, max-parked-concurrent) that quantify the parked-dispatcher path exp 105 / exp 114 targeted indirectly. Wake-retry/park ratio reaches 93 % at concurrency=32 (pool=4), the direct wake-amplification signal. Tree-shaken from release builds. Unblocks future dispatch-area experiments with a non-wall-time evaluation gate |  |

## In Review

Recent or pending-acceptance experiments. An entry sits here either
because the PR is still open, or because the experiment has merged but
is in its post-merge soak window — typically two weeks, longer if a
release-cycle metric has not run yet. Soak is for catching regressions
that only surface under realistic workloads or downstream rebases (see
the journal entry on exp 114 for the canonical example). Promote rows
to **Accepted** once the soak window closes and no new evidence has
moved them.

| # | Experiment | Impact | PR |
|---|---|---|---|
| [083](083-stream-rerun-pre-dispatch-queue.md) | Stream rerun pre-dispatch queue | Eliminates the measured `A11` / `A11b` reader-pool wait bottleneck by coalescing reruns before pool admission | [#25](https://github.com/danReynolds/resqlite/pull/25) |
| [097](097-one-pass-initial-stream-hash.md) | One-pass initial stream decode and hash | 14-16% faster setup-heavy streaming benchmarks by avoiding the initial stream query replay |  |
| [110](110-long-text-fnv-8byte.md) | Long-text stream hash benchmark + 8-byte FNV | Adds a long-text unchanged-fanout benchmark and cuts its median latency by 76% with chunked byte-stream hashing | [#53](https://github.com/danReynolds/resqlite/pull/53) |
| [113](113-direct-batch-param-matrix.md) | Direct batch parameter matrix encoding | Avoids the temporary flat Dart parameter list; 10k-row wide batches improve 14-26% in the focused benchmark | [#70](https://github.com/danReynolds/resqlite/pull/70) |
| [116](116-wide-batch-release-coverage.md) | Wide batch insert release coverage | Adds a 10k-row x 20-parameter mixed-type batch insert to the release write suite so parameter-width regressions are visible on the public benchmark path |  |
| [118](118-fifo-dispatch-counter-gate.md) | FIFO dispatch waiters with counter gate | Replaces the shared reader-pool dispatch completer with FIFO one-shot waiters; exp 115 counters show wake retries drop to zero under overload |  |
| [119](119-dispatch-pressure-audit.md) | Post-FIFO dispatch pressure audit | Profile audit shows wake retries stay zero after FIFO, while A11c overlap and keyed-PK streams still produce parked dispatchers; next dispatch work should target stream admission/completion |  |
| [120](120-flush-admit-bound.md) | Bounded `_flushQueue` admission | Cap stream re-query admission at `ReaderPool.availableWorkerCount` per call so synchronous over-dispatch can no longer pile up against `_dispatchWaiters`. `dispatcherParkedTotal` drops from 3,590 → 0 (A11c overlap) and 1,198 → 0 (keyed-PK); `max_parked` 46 → 0. Release suite: 9 wins, 0 regressions, including neutral high-cardinality fan-out (the exp-100 killer) |  |
| [121](121-invalidation-traversal-audit.md) | Invalidation traversal cost audit | Measurement-only: profile-mode harness reports `invalidate_us` / `intersection_us` as a fraction of writer-side burst wall on A11c (baseline / disjoint / overlap) and keyed-PK. Overlap invalidation is 10–15% of wall (column intersection 2.5–5.7%); keyed-PK 13–14% (intersection ~4%); disjoint 22–23% only because column elision shrinks the denominator. Per-entry intersection probes are 80–200 ns. Extracts shared `audit_workloads.dart` so this audit and exp 119 stay structurally comparable. Removes invalidation traversal from the active candidate list — the structural ceiling on smarter dependency tracking is ~3 ms / 25k probes per overlap burst |  |
| [122](122-concrete-reader-pool-stream-admission.md) | Concrete reader-pool stream admission | Initializes `StreamEngine` with a concrete `ReaderPool` so `_flushQueue` stays synchronous and bounded by `availableWorkerCount`; tests now use diagnostics for stream registry size, and post-rebase profile counters stay at zero parks/retries/max-parked on A11c overlap and keyed-PK workloads |  |
| [125](125-wide-ascii-batch-params.md) | Wide ASCII batch parameter encoding | Direct ASCII payload packing skips temporary per-string UTF-8 lists in large wide batches; focused 10k x20 improves 17.199 → 12.760 ms and release Wide Batch Insert improves 18.201 → 13.031 ms |  |
| [126](126-wide-utf8-batch-packing.md) | Wide UTF-8 batch parameter packing | Direct UTF-8 payload packing extends exp 125's allocation win to guarded non-ASCII wide batches; focused Unicode 10k x20 improves 21.945 → 18.988 ms and emoji 10k x20 improves 24.187 → 17.458 ms while release write-suite guardrails remain neutral |  |
| [136](136-completion-microtask-counter.md) | Completion-side reader-handler counter | Measurement-only: profile-mode counters (`completion_handler_us`, `stream_emit_us`) expose the main-isolate reader worker port handler chain on A11c overlap as 28.57% of total wall (burst + drain) at ~18 µs per call across 4,228 calls/burst, with subscriber emit only 0.35% of the chain. Reader-reply batching is the natural bounded implementation candidate. Closes the `completion-side microtask scheduling cost counter` entry in `signals.json#stream-rerun-dispatch.blockedOnMeasurement` |  |
| [143](143-tracelite-profile-insights.md) | Tracelite profile insight audit | Measurement-only: pinned Tracelite profile runs show stable dispatch floors (reader 12 us, writer 16 us), point queries at the dispatch floor, merge rounds with 77 us of floor-subtracted work, and memory/allocation signal that wall time alone hides; current `tracelite explain` only reports coverage, so richer workload-summary insight rules are the next measurement-system improvement |  |
| [144](144-sqlite3mc-bump-2-3-5.md) | sqlite3mc 2.3.2 → 2.3.5 bump (SQLite 3.51.3 → 3.53.2) | Satisfies exp 090's revisit trigger (SQLite `.2`+ point release with sqlite3mc tracking it); tests stay green including embedded-NUL + Unicode bind regression suite; release-suite single-pass A/Bs swing between 19/18/124 and 30/2/129 — Concurrent Reads 8× is the only metric that flags consistently across reruns (+~20% on a sub-ms metric) and is the focus of the soak window; FP-rounding hazard skipped because resqlite never serialises REAL via `sqlite3_column_text` |  |
| [147](147-writer-sqlite-wall-split.md) | Writer SQLite wall split | Measurement-only: profile-mode writer responses now report SQLite-facing write time back into `ProfileCounters`; on A11c overlap, SQLite is 15.7 ms / 166.8 ms (9.4%), invalidation is 18.8%, and residual writer/request wall is 71.8%. Keyed-PK shows the same shape (18.1% SQLite, 18.7% invalidation, 63.3% residual). Clears the writer-wall-vs-SQLite-wall blocker; next stream work should reduce completion/reply scheduling or residual writer/request wall rather than SQLite-step tuning |  |
| [149](149-six-param-batch-packing.md) | Six-parameter batch packing | Lowers the guarded ASCII batch-packing threshold to the Tracelite merge-round shape; profile `merge_rounds` improves executeBatch p50 88 → 75 us and writer SQLite time 87,895 → 75,947 us while keeping 2-3 parameter batches generic |  |
| [150](150-nullable-batch-packing.md) | Nullable batch parameter packing | Makes the guarded packed batch encoder nullable-aware for first-row `NULL` text columns; focused nullable ASCII 10k x8 improves 13.552 → 11.152 ms and 10k x20 improves 25.738 → 21.723 ms while existing ASCII/Unicode wide guardrails stay neutral |  |
| [153](153-row-observer-keyed-pk.md) | Explicit row observer for keyed PK streams | Adds an explicit `RowIdentity` prototype for keyed streams and writes; focused keyed-PK write-loop median drops 78.72 → 10.55 ms and 40.16 → 10.57 ms across two local passes, while Tracelite stream guardrails stay neutral/inconclusive |  |

## Rejected

Experiments that didn't work out. Each has valuable context on *why* — check before revisiting similar ideas.

| # | Experiment | Why Rejected |
|---|---|---|
| [151](151-sync-writer-response.md) | Synchronous writer response resolution | Switching writer response futures to `Completer<T>.sync()` was a concrete request-resolution attempt against exp 147's residual writer/request bucket, but the formal Tracelite stream-dispatch A/B did not clear the primary gate. High-cardinality fanout changed +2.92%, keyed-PK subscriptions changed +18.5% with too-noisy evidence, and many-streams writer throughput changed +14.0%. No runtime code kept. |
| [148](148-reader-reply-batching.md) | Reader reply batching | Batching stream re-query replies reduced the exp 136 completion counter in a profile smoke (A11c overlap completion callbacks 4,527 → 1,425, completion wall 109.6 ms → 55.6 ms), but the formal Tracelite stream-dispatch A/B did not produce a measured-elapsed win. High-cardinality fanout changed +5.18%, many-streams writer throughput +3.28%, and keyed-PK subscriptions +13.5%. Do not merge worker-side reader-reply batching without a workload that turns the callback reduction into end-to-end wall improvement. |
| [146](146-lower-batch-pack-threshold.md) | Lower batch packing threshold | Tracelite A/B run over `narrow-batch-insert` collected clean baseline and candidate histories but produced no primary improvement: resqlite changed +1.45% with neutral verdict, while the sqlite_async guardrail was too noisy. Keep the exp 125 large-wide-batch guard; small/narrow batches stay generic until a new workload proves parameter encoding is material. |
| [145](145-stream-flush-inline-dequeue.md) | Inline stream flush dequeue | Replacing `_flushQueue`'s `take(...).toList()` dequeue and `availableWorkerCount`'s `where(...).length` with inline loops kept dispatch counters at zero but produced mixed wall-time signal: A11c overlap trended better, keyed-PK trended worse, and the active stream bottleneck remained elsewhere. No runtime code kept. |
| [142](142-single-row-text-direct-encoding.md) | Single-row text parameter direct encoding | Tracelite retest over `chat-sim` and `narrow-batch-insert` did not clear the primary gate: resqlite changed +6.86% and +16.4% with neutral/inconclusive verdicts. Do not carry the `allocateParams` direct UTF-8 path unless a future workload shows single-row string binding is material. |
| [134](134-keyed-pk-dirty-elision.md) | Keyed PK dirty rowid elision | Profile proof was real (keyed-PK writer-burst wall 25.54 → 12.45 ms; probes 10,000 → 3), but the mergeable implementation depended on internal SQL text recognition for `WHERE id = ?`. Keep as future evidence for explicit row-level observer APIs or a stronger dependency model; implementation preserved at `archive/exp-134`. |
| [117](117-named-parameters.md) | Named parameter support (`Map<String, Object?>`) | Functionally complete and correct; 5-run focused harness showed wide-batch within noise (+2.7%). Deferred for v0.x launch: 12K-LOC change touching the entire write path for an ergonomics nice-to-have, with 6/7 write-path benchmarks trending slightly slower (monotonic direction = weaker than independent noise). Reopen if (a) community feedback shows named params are a real adoption barrier and a 5-run release suite confirms neutral, or (b) someone redesigns dispatch as two top-level branches in `run_batch_locked` instead of per-row inline dispatch. Implementation lives on the `exp-117-named-parameters` branch. |
| [114](114-fifo-waiter-queue.md) | FIFO waiter queue for `ReaderPool` dispatch | First A/B pass (against pre-exp-106 baseline) showed −10 % to −32 % on streaming fan-out paths; rebasing onto main with exp 106 polish merged collapsed all targeted wins into noise. Exp 106 elides stream re-queries on the writer side before they reach the reader pool, so the parked-dispatcher contention this change targeted no longer fires under any release-suite workload. Implementation reverted; doc + benchmark artifacts retained as the durable record. Cherry-pickable from PR git history if a workload re-introduces sustained pool parking |
| [112](112-fixed-length-batch-param-flatten.md) | Fixed-length batch parameter flattening | Focused benchmark medians overlapped after repeated A/B passes; any large-batch improvement was below the current decision threshold, so the simpler growable-list flattening stays |
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
| [111](111-nested-tx-benchmark-savepoint-cache.md) | Nested-tx benchmark + revisit savepoint string cache | Built the missing nested-transaction workload (shipped) and re-tested exp 102's archived cached-savepoint-string pattern against it. Even on the worst-case 50×-shallow-fan-out shape the cache landed at -9 % (below the ±17 % decision threshold); deep-5-chain was flat. Confirms exp 102 across a maximally stressing workload — per-isolate-round-trip cost dominates per-call savepoint allocations |

## Conventions

- **Experiment number:** Monotonically increasing, never reused
- **Date:** When the experiment was run (full timestamp preferred: `2026-04-14T12:30:00`)
- **Status:** `Accepted` (merged + soak window closed), `In Review` (PR open or in post-merge soak window — typically two weeks), or `Rejected` (abandoned, with explanation). New experiments start at `In Review` and graduate after the soak.
- **Commit:** Git hash of the implementing commit (added to header of each accepted experiment)

### Research Map

Scheduled experimenters should use
[`RUNNER_INSTRUCTIONS.md`](RUNNER_INSTRUCTIONS.md) as the copyable instruction
block for recurring experiment systems. Those instructions point runners at
this README, [`signals.json`](signals.json), [`JOURNAL.md`](JOURNAL.md), and
the project [`stories`](../doc/stories/) before choosing work.

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
- leave `../doc/stories/` alone — story posts are updated on maintainer
  request, not per experiment

`signals.json` per-direction fields (see the inline `schemaNotes` block at
the top of the file for the canonical descriptions):

- `keyPriors` (required, max 6) — experiments a future runner must read.
- `archive` (optional) — older or superseded evidence; not required reading.
  Curate from `keyPriors` when a new accepted experiment supersedes an
  older one.
- `openCandidates` (optional) — dated candidate ideas waiting for the
  right workload, signal, or runner. Each item is `{idea, addedDate,
  addedAfter?, blockedOn?}`. Prune entries older than ~3 months that
  nobody picked up.
- `blockedOnMeasurement` (optional) — measurements that must land before
  the next implementation experiment in this direction is worth
  attempting. Empty if no measurement is gating new work.

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
