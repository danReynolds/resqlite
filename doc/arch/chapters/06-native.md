---
component: native
title: SQLite · encoders · WAL
kicker: native layer
zone: native
diagram: native
directions: [sqlite-version-and-build-config]
extraClaims: [229.1, 250.1, 110.1, 183.1, 016.1, 044.1]
---

Underneath every isolate sits `native/resqlite.c` and a vendored SQLite — specifically sqlite3mc, which adds encryption — compiled through Dart's native assets build hooks. The division of labour is the library's first principle: **C owns the state, Dart owns the orchestration.** Connections, prepared-statement caches, mutexes, and hooks live in C structs that outlive any particular Dart isolate, which is exactly why a sacrificed reader is cheap to replace.

## What C owns

The connection pool holds one write connection and N read connections, each with its own statement cache. Connections open with `NOMUTEX`: rather than SQLite locking around every individual API call, resqlite takes one lock around a whole query. On a large result that replaces tens of thousands of lock/unlock pairs with one acquire and one release.

Row decoding is batched across the FFI boundary. `resqlite_step_row` advances the statement and fills a pre-allocated cell buffer with every column's type and value in one call, so Dart reads a typed buffer instead of making an FFI call per column. Integers and doubles come back as direct native reads; text still becomes Dart strings, which is unavoidable for a map-shaped API — and is precisely the cost `selectBytes` exists to skip by encoding JSON in C and never building Dart objects at all.

Two hooks make reactivity work without SQL parsing: the authorizer on readers records what a query read, and the preupdate hook on the writer records what a write changed. SQLite reports the truth about joins, views, CTEs, triggers, and cascades so resqlite does not have to infer it.

## Compile-time positions

Build configuration is settled and deliberately conservative. The tuned flag set with `prepare_v3` is accepted — individually unmeasurable savings that stack [[016.1]] — as is `SQLITE_ENABLE_BATCH_ATOMIC_WRITE`, a zero-risk flag that activates through VFS capability detection on Android F2FS and does nothing elsewhere [[044.1]].

Version policy is evidence-driven rather than temperamental: track sqlite3mc point releases and never adopt a fresh `.0` [[090.1]]. When 3.53.0 shipped a default floating-point rounding change, the audit found it cannot reach resqlite's output at all, because REAL values never pass through `sqlite3_column_text` — so the proposed mitigation shim was unnecessary [[144.1]]. That is the pattern: check whether the hazard reaches *this* code path before paying for a defense.

## Where machine code earned its place

The JSON encoders are the one area where resqlite spends real instruction-level effort, because `selectBytes` makes them the whole cost of a read.

Base64 encoding for blobs went through scalar unrolling, then a 12-bit pair lookup table, then a NEON `vqtbl4q_u8` kernel gated on `__aarch64__` with the scalar LUT retained as fallback — roughly 2× on payload-throughput lanes [[229.1]]. One implementation detail is preserved as a rule: the SIMD kernel stays `noinline`, because inlining it degraded code generation on the small-input scalar path that most cells actually take.

Integer encoding is the counter-example, and the reason is structural rather than algorithmic. A byte-identical NEON i64-to-decimal kernel never beat the scalar two-digit itoa, because it pays an out-of-line call plus vector setup for a single integer with no cross-cell batching to amortize it — unlike base64, which amortizes across a whole blob. Per-cell integer SIMD is closed until some future architecture batches many integer cells into one call.

Hashing for stream re-queries also lives here: computing the result hash in C during the step loop was a −39% win, and the 8-byte FNV fold has survived every attempt to widen it [[110.1]].

## WAL and checkpointing

Checkpointing remains inline on the writer. Moving `PASSIVE` work off the writer is genuinely attractive — first threshold-crossing latency improves 53–64% — and an early attempt failed loudly with a checkpoint storm. The diagnosis matters more than the verdict: the storm was a re-arming policy bug, not an inherent property of moving the work, and observed-reset/high-water scheduling fixes it [[250.1]]. The mechanism is documented and parked rather than discarded.

Native memory is observable rather than opaque: the per-reader JSON buffer reclaims above a cap and reports its high-water mark through diagnostics [[183.1]].
