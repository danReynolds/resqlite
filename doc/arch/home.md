---
layout: home
title: resqlite
tagline: High-performance, reactive SQLite for Dart and Flutter.
---

resqlite is a SQLite library built around a single constraint: **the main isolate must never block.** Every read, every write, and every reactive re-query runs on a persistent worker isolate. The main isolate receives finished results and nothing else.

You write plain SQL. There is no ORM, no query builder, and no code generation.

## What using it looks like

```dart
final db = await Database.open('app.db');

// Reads and writes stay off the UI thread.
final users = await db.select('SELECT * FROM users WHERE active = ?', [1]);
await db.execute('INSERT INTO users(name) VALUES (?)', ['Ada']);

// Reactive queries. Dependencies are detected from the SQL itself —
// JOINs, subqueries, views and CTEs all work, with no table lists to maintain.
db.stream('SELECT * FROM users WHERE active = ?', [1]).listen((users) {
  setState(() => this.users = users);
});
```

That is close to the entire public surface: `select`, `selectBytes`, `execute`, `executeBatch`, `stream`, and `transaction`. Everything in the pages that follow exists to make those six calls cheap.

## The shape of the system

Work moves through three zones. Your code calls `Database` on the main isolate; that call is routed to a worker; the worker talks to SQLite through C; the result travels back across the isolate boundary.

The interesting part is the boundary itself. Dart isolates share no mutable state, so *nothing crosses for free* — and the cost of crossing differs by orders of magnitude depending on what is being moved. Most of this library's design is a consequence of that one fact.

## The two constraints

Almost every decision documented here follows from two forces. If you internalise them, you can usually predict what the code does in places these pages never mention.

**Main-isolate time is the scarce resource.** Wall-clock time matters, but a frame budget is 16ms and anything the main isolate does inside that window competes with rendering. A design that is slower overall but moves work off the main isolate is usually the better trade — which is why results are decoded on workers, and why the API is asynchronous even where a synchronous version would be faster end-to-end.

**Isolates share no mutable state.** Dart's data-race-free guarantee means every result must be *transferred*, not shared. Sending a message shares immutable objects like strings and numbers by reference, but copies mutable ones slot by slot. So the price of a query result tracks the number of cells in it, not the number of bytes — a fact that took several experiments to establish and that quietly determines the shape of the read path, the write path, and the stream engine alike.

## Explore the architecture

## How we know any of this

The claims on these pages are not opinions. Each one is attached to a numbered experiment with a recorded date, hardware, and method, and the citation chips throughout the prose expand to show that provenance in place.

The system is deliberately biased toward recording failure. Most performance ideas do not survive measurement, and an idea that was tried and rejected is more valuable to write down than one that worked — it is the thing that stops the same week being spent twice. Rejected experiments are kept, numbered, and cited exactly like accepted ones.

Beliefs are also allowed to die. When a later experiment supersedes or refutes an earlier one, the relationship is recorded as an edge rather than an edit, so the page can show what was believed at any past date and what changed it.
