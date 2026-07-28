---
component: native
title: SQLite · encoders · WAL
kicker: native layer
zone: native
order: 6
directions: [sqlite-version-and-build-config]
extraClaims: [229.1, 250.1, 110.1, 183.1]
---

Underneath everything sits a vendored, encryption-capable SQLite (sqlite3mc) with tuned compile flags, a per-connection statement cache, and C-side result encoding — the layer where resqlite is allowed to spend real machine code.

## Held positions

Version policy is conservative by evidence, not temperament: track sqlite3mc point releases, never a fresh .0 [[090.1]] — and the one known 3.53 rounding hazard cannot reach our output because REAL values never pass through column_text [[144.1]]. Compile flags and batch-atomic-write support are settled, zero-risk wins [[016.1]] [[044.1]]. The base64 encoder earned NEON SIMD (~2× on payload lanes) behind an architecture gate with the scalar LUT as fallback — kept noinline so the small-blob path’s code generation stays untouched [[229.1]]. Checkpointing remains inline on the writer: the off-writer variant works, but stays parked with its trigger policy documented [[250.1]].
