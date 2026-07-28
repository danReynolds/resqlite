---
component: writer
title: Writer · binding & batching
kicker: worker isolate
zone: workers
order: 4
directions: [parameter-encoding-and-binding]
---

All writes serialize through a single writer isolate that owns the write connection. Concurrent standalone writes coalesce into one envelope per round-trip; executeBatch hands its whole parameter matrix to C in one call; and transactions hold the writer for their full body.

## Binding without waste

Parameter encoding writes UTF-8 payloads directly into the native arena with no intermediate Dart allocations — first for wide ASCII batches [[125.1]], then full Unicode with private surrogate handling [[126.1]], then the single-row path in both ASCII and CJK forms, worth 15–40% once bound text reaches tens of kilobytes [[186.1]] [[187.1]]. Large blob parameters take the boundary’s wrap route: one copy into external memory, identity-keyed across a coalesced group so aliased buffers never multiply [[234.1]] [[243.1]]. Batch blobs deliberately do not wrap — measured there, wrapping is a regression, not a win [[237.1]].
