# Experiment 263: where a select()'s memory actually goes

Collected 2026-08-05 on arm64 macOS 26.2 (Apple M1 Pro) with Dart 3.12.2, from
`main` at `7225903`. Harness:
[`benchmark/experiments/select_memory_decomposition.dart`](../experiments/select_memory_decomposition.dart).

Every figure is `maxRss` with **one process per lane** (`--lane=`), per exp 261.

## Method

Exp 261 flagged the canonical 6-column product row at 10k rows peaking at ~95 MB
against a table holding ~1.5 MB, a ~60x ratio, and noted its own instrument could
not decompose it: process RSS cannot resolve below a doubling, and an AOT binary
has no VM service to ask for heap composition.

What RSS *can* do is separate fixed from marginal, if the only thing that varies
is the amount read. Every lane seeds the same 20,000-row table and differs only
in the timed statement's `LIMIT`, so the slope against row count is the per-row
marginal and the intercept is everything that does not scale with the read.

Two configurations, and the difference between them is the experiment's first
finding:

- `--warmup=5 --reads=21` — the shape exp 261 used. RSS never falls, so 26 reads
  accumulate up to 26 results' worth of retained garbage.
- `--warmup=0 --reads=1`, result held live across the sample — one result,
  which is what "what does a result cost" actually asks.

## Single live result (maxRss, MB)

| rows | `select` | `bytes` | `id` |
|---:|---:|---:|---:|
| 1,000 | 32.7 | 33.0 | 32.8 |
| 2,500 | 33.0 | 33.7 | 33.0 |
| 5,000 | 33.9 | 35.3 | 33.3 |
| 7,500 | 35.1 | 37.0 | 33.6 |
| 10,000 | 36.1 | 38.8 | 34.0 |
| 20,000 | 38.8 | 45.1 | 35.6 |

Marginal cost per row, over two spans:

| mode | 1k→10k | 1k→20k |
|---|---:|---:|
| `select` | 396 B/row | 337 B/row |
| `bytes` | 676 B/row | 668 B/row |
| `id` | 140 B/row | 155 B/row |

Average cell content in one seeded row: **142.9 bytes** — the UTF-8 length of
each TEXT cell plus 8 bytes per numeric, averaged over the whole 20,000-row
seeded range, sampled at a fixed stride. (An earlier revision reported 137.8 B,
averaged over the first 100 rows; `Item $i` and the description's `$i` both grow with the row index, so a
prefix undercounts what the lanes actually read.) Exact for this fixture — every
generated cell is ASCII, which the harness asserts, so UTF-16 code units and
UTF-8 bytes coincide — and deliberately not SQLite's on-disk record size, which
varint-encodes integers and carries a per-row header. Strided rather than
exhaustive on purpose: the average is computed before any lane runs, and building
all 20,000 rows to measure them would allocate megabytes of transient strings
ahead of an RSS measurement that cannot see them released. 200 samples land
within 0.01 B of the exact mean. The `open` lane reads 20.5-20.6 MB either way,
so this is a hazard removed rather than a number changed — and the sweep above
predates the denominator fix entirely, since that figure is an arithmetic
property of the fixture rather than an input to any measurement.

## Attributing the marginal

A one-column and a six-column read of the same table make the same btree leaves
resident, so `id`'s marginal is a per-row cost independent of the result's
representation. Differencing isolates the Dart side:

| | B/row |
|---|---:|
| `select` marginal (6 columns) | 396 |
| − `id` marginal (shared, storage-side) | 140 |
| = Dart representation, five non-key columns | **256** |
| their cell content (142.9 − 8 for the id) | 134.9 |
| representation overhead | **1.9x** |

First-principles accounting for those five columns: four `OneByteString`s at a
24 B header plus rounded data (~240 B), one boxed `_Double` (16 B), five slots in
the flat values list (40 B) = ~296 B. The measured 256 B/row is **below** it. The
`Row` facade contributes nothing to a retained result: the iterator creates those
objects transiently and only the `ResultSet` is held.

`select`'s 1k→20k span reads lower than 1k→10k because results above
`sacrificeSlotThreshold` (5,461 rows at 6 columns) return via `Isolate.exit`,
which ends the worker and returns its heap. The sub-linearity is a transport
artifact, not a representation one.

## Fixed floor

| stage | maxRss |
|---|---:|
| bare AOT Dart process (measured separately) | 14.0 MB |
| + resqlite open, pool spawned, one trivial read (`open` lane) | 20.5 MB |
| + seeding 20,000 rows via `executeBatch` (`id-1000` lane) | 32.8 MB |
| + one live 10,000-row `select()` result | 36.1 MB |

## Repeatability

Three runs per lane, isolated processes, maxRss MB:

| lane | runs |
|---|---|
| `open` | 20.5, 20.5, 20.5 |
| `select-1000` | 32.8, 32.9, 32.8 |
| `select-10000` | 36.8, 36.4, 36.8 |
| `select-20000` | 38.9, 42.1, 38.9 |

## Accumulated-retention configuration, for contrast

The same lanes under `--warmup=5 --reads=21` (26 reads, nothing released):

| rows | `select` | `bytes` | `id` |
|---:|---:|---:|---:|
| 1,000 | 33.9 | 39.4 | 33.3 |
| 5,000 | 99.4 | 51.3 | 35.6 |
| 10,000 | 99.0 | 74.5 | 38.4 |
| 20,000 | 105.0 | 97.8 | 45.2 |

This is the configuration exp 261 measured, and it is ~2.7x the single-result
figure at 10,000 rows. It answers a real question — what a process doing
repeated reads holds — but not the one the 60x ratio was posed against.
