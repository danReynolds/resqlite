---
component: api
title: Public API & streams
kicker: main isolate
zone: main
order: 2
directions: [stream-rerun-dispatch, long-text-stream-hashing]
---

The public surface is deliberately small — select, selectBytes, execute, executeBatch, transaction, stream — and every call is exactly one message to a worker. The stream engine is where most of the machinery lives: each watched query re-runs through selectIfChanged, which compares a C-computed hash of the fresh result against the last emission and skips the decode entirely when nothing changed.

## Where the time goes

Hashing moved into C early and stayed there: computing the result hash inside the native step loop was a −39% win with no regression [[075.1]], and the 8-byte FNV fold has survived every attempt to beat it — wider unrolls are below noise at 4 KB, 32 KB, even single-stream 64 KB payloads [[110.1]] [[173.1]] [[181.1]]. Dispatch is settled too: the parked-dispatcher pathology that once looked like pool starvation was over-dispatch upstream in the flush queue, fixed by snapshotting worker availability once per flush [[120.1]]. What remains on the main isolate is the reader-reply port handler — measured at ~28% of burst wall on the heaviest stream workload — not subscriber fan-out, which is under 1% [[136.1]] [[147.1]].

## Held in reserve

Two proven mechanisms stay deliberately unshipped: row-level dirty precision, which eliminated the keyed-PK miss path in prototype but costs more complexity than current workloads justify [[134.1]], and off-writer checkpointing, whose storm turned out to be a trigger-policy bug rather than a flaw in the idea [[250.1]]. Both are recorded as potential, waiting for the workload that calls for them.
