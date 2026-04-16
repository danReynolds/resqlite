# Experiment 044: SQLITE_ENABLE_BATCH_ATOMIC_WRITE

**Date:** 2026-04-15
**Status:** Accepted

## Problem

On Android devices running F2FS (the default filesystem since Android 9), SQLite writes both journal + database pages (2x I/O) for every transaction. F2FS supports batch atomic writes, which allows SQLite to eliminate the rollback journal entirely — writing only the database pages in a single atomic batch.

## Hypothesis

Enabling `SQLITE_ENABLE_BATCH_ATOMIC_WRITE` at compile time activates F2FS detection at runtime. When the filesystem reports `SQLITE_IOCAP_BATCH_ATOMIC`, SQLite skips journal writes, yielding 2-3x write throughput improvement on Android. The flag is inert on filesystems that don't support batch atomics (macOS APFS, Linux ext4, Windows NTFS).

## Approach

Single define in `hook/build.dart`:

```dart
defines: {
  'SQLITE_ENABLE_BATCH_ATOMIC_WRITE': null,
  ...
}
```

Research references:
- [SQLite F2FS documentation](https://github.com/sqlite/sqlite/blob/master/doc/F2FS.txt)
- ACM paper on multi-block atomic write: 487% insert throughput increase on F2FS vs ext4 PERSIST mode, 67% write volume decrease.

## Results

**Verified: 0 regressions on macOS.** As expected, the flag has no runtime effect on non-F2FS filesystems. The 21 "wins" in the benchmark are run-to-run variance — the flag does not activate on APFS.

The expected impact on Android F2FS (based on published research):
- 2-3x write throughput for transactions
- ~50% reduction in write amplification (no journal I/O)
- Reduced SSD wear from eliminated journal writes

## Decision

**Accepted.** Zero-risk compile flag that enables a significant write optimization on Android F2FS. No effect on other platforms. The optimization activates automatically via VFS capability detection — no API changes, no user configuration needed.
