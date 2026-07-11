# Exp 222 - `malloc` for large one-shot parameter arenas

Focused `benchmark/experiments/single_row_large_text_bind.dart` A/B against
`origin/main` at `44a6d39`. The candidate changes parameter arenas above the
64 KiB reuse cap from `calloc` / `calloc.free` to `malloc` / `malloc.free`.
The parameter packer already overwrites every field and payload byte that C
reads before the FFI call; only struct padding and inactive union fields remain
untouched.

The harness reports median milliseconds per 100 sequential inserts. Lower is
better. The 64 KiB payload rows also cross the allocator threshold because the
24-byte `resqlite_param` struct is part of the same arena.

## Pair 1 - baseline then candidate

| Payload | Baseline ms/100 | Candidate ms/100 | Delta |
|---|---:|---:|---:|
| ASCII 1 KB | 4.26 | 5.77 | +35.4% |
| ASCII 16 KB | 8.61 | 9.82 | +14.1% |
| ASCII 64 KB | 23.64 | 25.16 | +6.4% |
| ASCII 256 KB | 86.93 | 92.08 | +5.9% |
| ASCII 1 MB | 342.39 | 345.06 | +0.8% |
| CJK 1 KB | 3.18 | 2.55 | -19.8% |
| CJK 16 KB | 7.60 | 8.15 | +7.2% |
| CJK 64 KB | 26.26 | 26.29 | +0.1% |
| CJK 256 KB | 93.85 | 95.25 | +1.5% |
| CJK 1 MB | 352.31 | 360.19 | +2.2% |

## Pair 2 - candidate then baseline

| Payload | Candidate ms/100 | Baseline ms/100 | Delta (candidate vs baseline) |
|---|---:|---:|---:|
| ASCII 1 KB | 4.32 | 4.07 | +6.1% |
| ASCII 16 KB | 8.62 | 9.02 | -4.4% |
| ASCII 64 KB | 23.55 | 24.05 | -2.1% |
| ASCII 256 KB | 88.61 | 88.47 | +0.2% |
| ASCII 1 MB | 343.09 | 351.38 | -2.4% |
| CJK 1 KB | 2.10 | 3.04 | -30.9% |
| CJK 16 KB | 7.03 | 7.68 | -8.5% |
| CJK 64 KB | 25.28 | 27.42 | -7.8% |
| CJK 256 KB | 94.55 | 100.63 | -6.0% |
| CJK 1 MB | 360.76 | 369.87 | -2.5% |

## Interpretation

The large rows do not reproduce a candidate-faster effect. ASCII 256 KiB is
candidate-slower in both orderings (`+5.9% / +0.2%`), while ASCII 1 MiB flips
from `+0.8%` to `-2.4%`. CJK 256 KiB flips from `+1.5%` to `-6.0%`, and CJK
1 MiB flips from `+2.2%` to `-2.5%`. The smaller unchanged rows also swing
widely, confirming meaningful machine drift during the pair rather than an
allocator-shaped result.

The result is consistent with modern allocator behavior: replacing zero-filled
allocation does not remove a stable, material part of end-to-end bind wall once
the parameter packer immediately writes nearly the entire arena. The candidate
therefore fails the predeclared gate of a same-direction improvement above 5%
on the 256 KiB or 1 MiB rows.
