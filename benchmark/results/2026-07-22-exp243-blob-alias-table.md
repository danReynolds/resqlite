# Exp 243 — aliased blob param transport (table protocol)

Harness: `benchmark/experiments/alias_transfer_isolated.dart`
Box: Apple M1 Pro / macOS. One 300 KB buffer referenced N times in one message;
median transfer round-trip µs over 9 samples × 300 round-trips (40 warmup).

Three wrapping shapes:
- **census** — send the raw param list; the graph copier copies the shared HEAP
  blob once (chunked slow path) and aliases it N times.
- **baseline** — exp 234 per-occurrence: N `TransferableTypedData.fromList`
  calls, N external memcpys.
- **table** — one `TransferableTypedData` referenced N times; graph copier sends
  it once by identity, receiver materializes the unique wrapper once.

| N | census (1 graph copy) | baseline (N TTD) | table (1 TTD ×N) |
|---|---:|---:|---:|
| 1 | 196.2 | 44.4 | 32.9 |
| 2 | 179.6 | 49.6 | 27.0 |
| 4 | 171.6 | 70.8 | 28.2 |
| 8 | 190.9 | 132.0 | 33.8 |
| 32 | 209.0 | 1502.7 | 56.5 |

Table is flat and fastest at every N. Baseline scales linearly with N (the
aliasing regression). Census is flat but slow (heap slow-path copy). See
`experiments/243-blob-alias-table-protocol.md`.
