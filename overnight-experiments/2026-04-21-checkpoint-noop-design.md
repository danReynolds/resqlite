# Checkpoint NOOP refinement — design report

**Date:** 2026-04-21
**Verdict:** **Skip.** The premise in the daily-research note doesn't match the actual exp-029 implementation.

## Summary

The daily-research note assumed exp-029 is a periodic timer that unconditionally calls PASSIVE each tick. It isn't. The shipped implementation is a `sqlite3_wal_hook` callback ([`native/resqlite.c:377-403`](../native/resqlite.c)) that fires only on commit, receives `pages_in_wal` directly from SQLite as its 4th argument, and already short-circuits when `pages_in_wal < 500`. `SQLITE_CHECKPOINT_NOOP` exists precisely to obtain `pnLog`/`pnCkpt` outside a hook — we already have `pnLog`-equivalent for free on every commit, so NOOP is strictly extra work here.

## Current exp-029 logic (corrected)

The accepted implementation (contra the markdown's "every 500 writes" sketch) lives in `writer_wal_hook` and is triggered by SQLite itself after each WAL commit, with the writer's auto-checkpoint disabled to prevent dual scheduling ([`resqlite.c:481`](../native/resqlite.c)). Logic:

```c
if (pages_in_wal < 500 || writer_checkpoint_running) return SQLITE_OK;
writer_checkpoint_running = 1;
rc = sqlite3_wal_checkpoint_v2(db, db_name, SQLITE_CHECKPOINT_PASSIVE, NULL, NULL);
writer_checkpoint_running = 0;
```

No timer. No "tick paid even when there's nothing to checkpoint." PASSIVE is only invoked when SQLite has already told us the WAL crossed the 500-frame threshold.

## NOOP semantics (from [sqlite3mc_amalgamation.c:71200-71327](../third_party/sqlite3mc/sqlite3mc_amalgamation.c) and [sqlite3.h:9986-9995](../third_party/sqlite3mc/sqlite3.h))

| Property | PASSIVE | NOOP |
|---|---|---|
| Acquires `WAL_CKPT_LOCK` (exclusive) | yes (line 71237) | **no** — gated by `if (eMode != NOOP)` |
| Reads wal-index header | yes | yes (line 71277) |
| Invokes busy-handler | never (docs R-62920-47450) | never |
| Populates `pnLog` / `pnCkpt` | yes | yes (lines 71295, 71297) — stated purpose of NOOP |
| Actually copies frames | yes (`walCheckpoint` at 71290) | no (gated by `eMode2 != NOOP`) |

Our vendored SQLite is **3.51.3** (`sqlite3.h:149`), so NOOP is available — no version-bump dependency.

## PASSIVE-on-empty cost estimate

The relevant question is moot because the hook already has `pages_in_wal`, but for completeness: `sqlite3_wal_checkpoint_v2(PASSIVE)` on an empty/small WAL still:

1. Takes the exclusive `WAL_CKPT_LOCK` (briefly — uncontended on the writer connection because readers never checkpoint per exp-022).
2. Reads the wal-index header.
3. Calls `walCheckpoint()` which inspects `pWal->hdr.mxFrame` vs `pInfo->nBackfill` and returns without copying frames if they're equal.
4. Releases the lock.

This is a few dozen locked instructions plus a header read — almost certainly < 1 µs on the writer connection. The 11.26 ms p95 checkpoint cost in exp-029's table was measured with 500+ frames to drain; the empty-WAL case is nowhere near that.

If exp-029 *were* a blind-timer design, NOOP could save that sub-µs lock-plus-header-read on empty ticks. But exp-029 is hook-driven and already pre-filters on `pages_in_wal`, so there is no empty-tick cost to amortize.

## Why the NOOP refinement doesn't apply

`sqlite3_wal_hook`'s 4th arg is the exact counter NOOP exists to expose. Calling NOOP from inside the hook to learn what the hook was already told would be a strictly additive header read. The only scenario where NOOP helps is when you *don't* have the frame count — e.g. a Dart-side periodic timer with no wal-hook context. The exp-029 impl deliberately moved *away* from that shape.

## Risks of pursuing anyway

- **Extra header read per commit.** NOOP still calls `walIndexReadHdr`; PASSIVE-skip already does too when we do call it. We'd double the header-read traffic on hot commits for no semantic gain.
- **Divergence between NOOP-reported and hook-reported frame counts.** The hook's `pages_in_wal` is computed at commit; NOOP from the same callback would re-read the header immediately after — same value in practice, but adding a second source of truth invites future bugs.

## What *would* be worth doing instead

Two adjacent ideas surfaced while reading the code but are out of scope for this report:

1. **Threshold tuning.** 500 is a magic number; revisit against exp-022's 10000-page autocheckpoint baseline and measure the sweet spot for p95/p99. This is an exp-029 refinement that doesn't need NOOP.
2. **Surface `pnCkpt` to telemetry.** If we ever want to answer "how far behind is the checkpointer?" in profile mode, capture the `pnLog` / `pnCkpt` out-params on the existing PASSIVE call — no NOOP needed.

## Verdict

**Skip.** The shipped exp-029 is already hook-gated on the same counter NOOP would re-derive; there is no empty-tick cost for NOOP to eliminate. Daily-research note was written against the prototype-as-documented, not the accepted implementation — worth correcting the note.
