# Exp 242 — selectBytes TransferableTypedData A/B (rejected)

Harness: prototype behind `RESQLITE_SELECTBYTES_TTD` (reverted on the branch;
re-apply the one-line wrap in `read_worker.dart`'s selectBytes case +
`reader_pool.dart` materialize to reproduce). `selectBytes` end-to-end, JSON
sizes spanning the 256 KB new-space cap. Median µs over 9 samples × 20
round-trips, Apple M1 Pro / macOS.

| rows | JSON KiB | view (current) µs | ttd µs |
|---|---|---:|---:|
| 2000 | 142 | 297.3 | 305.3 |
| 5000 | 362 | 700.1 | 702.0 |
| 10000 | 731 | 1391.7 | 1742.3 |

TTD neutral-to-worse everywhere; ~25% slower at 731 KB. Both lanes showed the
same tiny `Scavenge(external)` stream under `--verbose_gc` (sub-0.2 ms pauses) —
no heap-pressure difference. selectBytes bytes are a native `json_buf` view, so
the single send-copy is already the floor; a TTD wrap relocates that copy and
adds malloc/finalizer machinery without removing it. Rejected — see
`experiments/242-selectbytes-ttd.md`.
