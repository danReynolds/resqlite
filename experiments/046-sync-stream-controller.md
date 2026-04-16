# Experiment 046: Synchronous StreamController

**Date:** 2026-04-15
**Status:** Rejected

## Problem

Each `controller.add(event)` in `StreamEngine._subscribe` schedules a microtask for async delivery. For N subscribers, that's N microtask schedulings per invalidation cycle. `StreamController(sync: true)` fires events immediately in the current microtask, eliminating the scheduling overhead.

## Hypothesis

Switching from async to sync controllers should reduce stream delivery latency by ~10-50μs per event per subscriber, with no reentrancy issues since events are added from async pool callbacks, not from within listener callbacks.

## Approach

Single-line change:

```dart
final controller = StreamController<List<Map<String, Object?>>>(sync: true);
```

## Results

**Crashed with `ConcurrentModificationException`** during the streaming benchmark:

```
Concurrent modification during iteration: Instance(length:0) of '_GrowableList'.
#0      ListIterator.moveNext (dart:_internal/iterable.dart:365:7)
#1      StreamEngine._createStream.<anonymous closure>
```

The reentrancy assumption was wrong. When a sync controller fires an event, the listener receives it immediately in the same call stack. If the listener's callback triggers a `onCancel` (removing itself from `entry.subscribers`), this modifies the subscriber list while `_createStream` or `_flushDirtyTables` is iterating over it — classic concurrent modification.

With async controllers, the event delivery is deferred to a microtask, so the iteration completes before any listener callbacks fire.

## Decision

**Rejected.** The synchronous controller creates a reentrancy hazard that causes crashes in production-realistic scenarios. The async controller's microtask deferral is not just overhead — it's a correctness mechanism that prevents concurrent modification of the subscriber list during iteration.

Fixing this would require copying the subscriber list before iteration (defeating the purpose) or restructuring the event delivery to handle mid-iteration modifications.
