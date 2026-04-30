---
title: Debugging a Dart VM Service Deadlock
slug: 2026-04-27-dart-vm-deadlock
date: 2026-04-27
summary: A cold-launch freeze first looked like a database migration hang, but native stack sampling showed the process blocked inside a Dart VM service deadlock.
tags: Dart VM, macOS, upstream fix
tone: rose
---

# Debugging a Dart VM Service Deadlock

## Problem Statement

By this point, resqlite had enough machinery that a real application failure could plausibly be its fault: reader workers, a writer isolate, migrations, stream invalidation, and native SQLite all sat under startup. That made the next challenge less like a benchmark and more like production engineering.

A Flutter macOS app occasionally froze on cold launch. The last application log line was `Migrate DB started`, so the first visible suspect was resqlite's migration path. The failure looked like a database hang, but the real problem was that the Dart VM stopped making progress.

This story is not a performance experiment. It is included because it documents an engineering investigation pattern that mattered for resqlite: when the runtime is stuck, Dart-level observability can become part of the failure surface.

## Background

The migration was simple: read `PRAGMA user_version`, create schema if needed, and write the new version. It had succeeded many times. Hot-reload state and stale database locks were plausible first theories, because they fit the last visible log line. They did not fit cold-launch reproductions.

The first migration read used the reader pool, so the investigation added logs around worker startup:

```text
[ReaderPool] reader 0: Isolate.spawn done, awaiting SendPort...
[ReaderPool] reader 1: Isolate.spawn done, awaiting SendPort...
[ReaderPool] reader 2: Isolate.spawn done, awaiting SendPort...
[ReaderPool] reader 3: Isolate.spawn done, awaiting SendPort...
```

The spawn futures resolved, but no worker entrypoint log appeared. A `Timer.periodic` on the main isolate did not fire either. That ruled out a simple SQLite lock wait: the event loop itself was not advancing.

Two runtime concepts explain why this investigation left the database layer. Isolates are Dart's independent units of execution and communicate by message passing, but they still run inside one Dart VM process. The [VM service protocol](https://dart.googlesource.com/sdk.git/+/refs/tags/3.9.0-2.0.dev/runtime/vm/service/service.md) is the debugging and inspection protocol used by tools; its `getStack` RPC asks the VM for an isolate stack and message queue. If that machinery participates in the deadlock, Dart-level tools can become unreliable evidence rather than neutral observers.

## Working Hypotheses

The investigation moved through three hypotheses:

1. A stale SQLite writer or migration lock blocked the first read.
2. The reader-pool workers spawned but could not start because of a resqlite isolate bug.
3. The Dart VM or Flutter embedding was blocked below application code.

The evidence pushed the investigation toward the third hypothesis.

## What We Tried

Dart-level tools were not enough. DevTools and the VM service both depend on a responsive VM. macOS `sample(1)` snapshots native thread stacks from outside the process runtime, so it became the useful tool.

The main thread was parked in the Dart VM safepoint handler:

```text
dart::SafepointHandler::ExitSafepointLocked
  -> ConditionVariable::WaitMicros
    -> _pthread_cond_wait
```

Above it was Flutter lifecycle dispatch from a macOS window occlusion notification:

```text
CGSDatagramReadStream::dispatchMainQueueDatagrams
  -> NSNotificationCenter
    -> FlutterAppLifecycleRegistrar.handleDidChangeOcclusionState
      -> FlutterEngine setApplicationState
        -> Dart_EnterIsolate
          -> Thread::ExitSafepoint
```

That shifted the investigation. The database migration was where logs stopped, but the process was blocked in a Dart VM safepoint while Flutter tried to enter the isolate from the main thread.

## Results

The result was a root-cause handoff rather than a resqlite patch:

| Observation | Interpretation |
|---|---|
| 4 reader spawn futures resolved | isolate creation was not the failing step |
| 0 worker entrypoint logs after spawn | workers did not begin Dart execution |
| 0 periodic timer ticks on main isolate | the main isolate was not processing events |
| main thread sampled in VM safepoint wait | failure was below SQLite and Dart application code |
| upstream fix landed 6 days after filing | root cause was in the Dart VM service path |

The first theory about Flutter's merged platform/UI thread mode on macOS was incomplete. Merged threads made the failure visible by pulling the main thread into the wait, but the underlying cycle involved Dart worker threads, debugger breakpoint synchronization, VM service requests, safepoints, `PortMap::mutex_`, and a message handler monitor.

The missing piece was identified upstream. `Service::InvokeMethod`, while handling a `GetStack` request, entered an `AcquiredQueues` scope that held a message queue monitor. Formatting queued messages could trigger JIT compilation. Leaving that compilation scope could post an out-of-band reload check back to the same isolate, which tried to acquire the same monitor already held by the current thread.

One thread waited for a monitor it already held. The rest of the VM accumulated behind that self-deadlock.

## Outcome

The Dart SDK fix was subtractive: stop returning the old `Stack.messages` queue dump from `GetStack`. DevTools did not use it. Removing that field removed the lock-then-run-Dart path that allowed recursive monitor acquisition.

resqlite's role was indirect. The project provided the reproducible pressure, the ruled-out database theories, the native sample, and enough thread evidence for VM maintainers to finish the diagnosis.

The engineering lesson is specific: when the runtime is not making progress, use observability outside the runtime. In this case, a database-looking hang became a VM service deadlock only because the investigation moved below Dart-level tooling. It is a fitting end to this first run of stories: building the library required benchmarks, but trusting it in real apps also required knowing when the evidence had left the library.

## Related Records

There is no resqlite experiment file for this story because no resqlite code change was accepted or rejected. The relevant artifact is the native sampling evidence summarized above, and the upstream fix in the Dart VM service implementation.

## Reference Docs

- [Dart isolates](https://dart.dev/language/isolates)
- [Dart VM service protocol](https://dart.googlesource.com/sdk.git/+/refs/tags/3.9.0-2.0.dev/runtime/vm/service/service.md)
- [Dart `vm_service` package](https://pub.dev/packages/vm_service)
