/// Main-isolate result cache for `Database.select`
/// ([EXP-270](../../experiments/270-read-result-cache.md)).
///
/// Every read resqlite serves crosses to a reader isolate and back, and
/// [EXP-265](../../experiments/265-inline-main-isolate-select.md) measured that
/// hop to be most of a hot point read. [EXP-269](../../experiments/269-enforced-inline-reads.md)
/// tried to remove it by running the statement on the calling isolate and was
/// rejected because arbitrary SQLite work cannot be bounded there. A cache hit
/// runs no SQLite at all, so it is bounded by construction — it is the one way
/// to collect that measured headroom which exp 269's rejection does not forbid.
///
/// The cache exists only because resqlite already computes both halves of what
/// it needs. The C authorizer records, per prepared statement, which tables the
/// statement reads; the preupdate hook records, per write, which tables changed.
/// The stream engine has consumed both since exp 106. The bet this experiment
/// tests is whether that signal, which is good enough for streams — where a
/// missed invalidation means a late re-emit — is good enough for reads, where it
/// means a wrong answer.
///
/// Where the signal is not provably good enough, the cache refuses to store:
///
/// - a statement whose read tables are unreliable ([UnknownTableDependencies]);
/// - a statement with no table dependencies at all, which no write could ever
///   invalidate (`SELECT 1`, and every scalar-only query);
/// - a statement invoking a function outside the C-side deterministic allowlist,
///   so `random()`, `datetime('now')` and every caller-registered function are
///   excluded;
/// - a result larger than [maxCachedRows], which bounds retention.
///
/// And where a write's own signal is not provably complete, the cache drops
/// everything: an unknown dirty set, and — the case that matters — a write that
/// reports *no* dirty tables. DDL and virtual-table writes fire no preupdate
/// hook, so "nothing changed" and "we cannot see what changed" arrive as the
/// same empty set (exp 068). Streams read that as nothing to do; a read cache
/// cannot afford to.
///
/// What it still inherits is resqlite's process boundary: invalidation only ever
/// sees writes made through *this* [Database]. A second connection to the same
/// file — another `Database.open`, another process — commits without this cache
/// hearing about it. `stream()` has always had that limitation; `select()` has
/// not.
library;

import 'dart:collection';

import 'dependency_tracking.dart';

/// Compile-time kill switch. Off restores the pre-270 path exactly: no key is
/// built, no description is requested, nothing is stored.
const bool kReadCacheEnabled = bool.fromEnvironment(
  'RESQLITE_READ_CACHE',
  defaultValue: true,
);

/// Distinct (sql, parameters) results held at once.
const int readCacheMaxEntries = int.fromEnvironment(
  'RESQLITE_READ_CACHE_ENTRIES',
  defaultValue: 64,
);

/// SQL strings whose description is remembered. Bounded for the same reason the
/// statement caches are ([EXP-267](../../experiments/267-stmt-cache-capacity.md)):
/// an application generating SQL text would otherwise grow this map forever, and
/// the workload that does so is exactly the one that never gets a hit from it.
const int readCacheMaxDescriptions = int.fromEnvironment(
  'RESQLITE_READ_CACHE_DESCRIPTIONS',
  defaultValue: 128,
);

/// Rows a result may hold and still be worth retaining. Caching a large result
/// would trade the round trip this exists to remove against a retention cost the
/// hop never had.
const int maxCachedRows = int.fromEnvironment(
  'RESQLITE_READ_CACHE_MAX_ROWS',
  defaultValue: 256,
);

/// Identity of one cached result: the SQL text and the parameters bound to it.
///
/// Blob parameters compare by identity, because [Object.hashAll] and `==` do,
/// so a caller passing an equal-but-distinct [Uint8List] simply misses. A miss
/// is the safe direction.
final class ReadCacheKey {
  ReadCacheKey(this.sql, this.parameters)
    : _hash = Object.hash(sql, Object.hashAll(parameters));

  final String sql;
  final List<Object?> parameters;
  final int _hash;

  @override
  int get hashCode => _hash;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReadCacheKey) return false;
    if (_hash != other._hash) return false;
    if (sql != other.sql) return false;
    final a = parameters;
    final b = other.parameters;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// What one SQL string reads, learned once from its first execution.
///
/// Keyed by SQL rather than by (sql, parameters) because both facts are
/// properties of the prepared statement: the same text with different bindings
/// reads the same tables through the same functions.
final class ReadCacheDescription {
  const ReadCacheDescription.cacheable(this.tables);
  const ReadCacheDescription.refused() : tables = const [];

  /// Tables this statement reads. Empty means the statement is refused.
  ///
  /// Deliberately table-level, with none of the column precision the stream
  /// engine uses. Column elision would have to be re-checked against every
  /// retained entry on every write, which is the index walk the version stamps
  /// exist to avoid; over-invalidating is both cheaper and safer.
  final List<String> tables;

  bool get cacheable => tables.isNotEmpty;
}


/// One retained result, stamped with the table versions it was read at.
///
/// Validity is checked when the entry is *read*, not when a write lands. A
/// write therefore never walks an index of dependent queries — it bumps a
/// counter per dirty table, which is the whole of its cost. The trade is that a
/// stale entry occupies its slot until something looks at it or eviction reaches
/// it; retention is already bounded by [readCacheMaxEntries], so nothing grows.
final class _CachedResult {
  _CachedResult(this.rows, this.tables, this.versions, this.epoch);

  final List<Map<String, Object?>> rows;

  /// Tables the statement reads, parallel to [versions].
  final List<String> tables;

  /// [ReadCache._versions] for each of [tables] at the moment the read that
  /// produced [rows] was *dispatched* — not when it returned. A write that
  /// landed while the read was in flight therefore invalidates this entry even
  /// though the rows it produced may already include that write. Wrong in the
  /// direction of re-reading.
  final List<int> versions;

  /// [ReadCache._epoch] at dispatch, so a whole-cache flush costs one increment
  /// rather than a walk.
  final int epoch;
}

/// Read-through result cache invalidated by write dependencies.
final class ReadCache {
  /// Results served without dispatching to a reader isolate, and reads that
  /// went to a worker, since process start.
  ///
  /// Static because the only consumers are tests and the focused harness, both
  /// of which observe a process they own end to end and neither of which can
  /// reach a [Database]'s pool. Two unconditional increments per read; if this
  /// experiment ships, they move behind `kProfileMode` or go away.
  static int hits = 0;
  static int misses = 0;

  static void resetStats() {
    hits = 0;
    misses = 0;
  }

  /// What each SQL string reads. Retained for refused statements too — that
  /// negative answer is what keeps an uncacheable read down to one map lookup.
  final LinkedHashMap<String, ReadCacheDescription> _descriptions =
      LinkedHashMap();

  /// Cached results in insertion order, so eviction can drop the oldest.
  final LinkedHashMap<ReadCacheKey, _CachedResult> _results = LinkedHashMap();

  /// How many times each table has been written through this [Database].
  final Map<String, int> _versions = {};

  /// Bumped when a write's dependency set cannot be trusted, retiring every
  /// entry at once without touching [_results].
  int _epoch = 0;

  /// Writes this cache has been told about, of any kind.
  ///
  /// Needed only by the describe path, which cannot stamp a result with table
  /// versions until the round trip tells it which tables to read: it captures
  /// this before dispatching and refuses to store if it moved.
  int _writes = 0;

  /// Entries currently held, stale ones included. For tests asserting eviction.
  int get length => _results.length;

  /// The description learned for [sql], or null when it has never been
  /// described.
  ReadCacheDescription? describe(String sql) => _descriptions[sql];

  /// The versions [description]'s tables are at right now, for stamping onto a
  /// result about to be fetched. Captured before dispatch so a write that races
  /// the read cannot be mistaken for one the read already saw.
  List<int> versionsOf(ReadCacheDescription description) {
    final tables = description.tables;
    final out = List<int>.filled(tables.length, 0);
    for (var i = 0; i < tables.length; i++) {
      out[i] = _versions[tables[i]] ?? 0;
    }
    return out;
  }

  int get epoch => _epoch;

  int get writes => _writes;

  /// A cached result for [key] that is still current, or null.
  ///
  /// A stale entry is dropped here rather than left to be re-checked on every
  /// subsequent lookup.
  List<Map<String, Object?>>? lookup(ReadCacheKey key) {
    final entry = _results[key];
    if (entry == null) return null;
    if (entry.epoch != _epoch) {
      _results.remove(key);
      return null;
    }
    final tables = entry.tables;
    for (var i = 0; i < tables.length; i++) {
      if ((_versions[tables[i]] ?? 0) != entry.versions[i]) {
        _results.remove(key);
        return null;
      }
    }
    return entry.rows;
  }

  /// Record what a SQL string reads, from the one execution that described it.
  ///
  /// [deterministic] is the C-side allowlist verdict. Anything unproven —
  /// unreliable table capture, no tables, an unrecognised function — is stored
  /// as a refusal so the next execution of this SQL skips straight to dispatch.
  ReadCacheDescription record(
    String sql,
    TableDependencies dependencies,
    bool deterministic,
  ) {
    final description = _build(dependencies, deterministic);
    _remember(sql, description);
    return description;
  }

  void _remember(String sql, ReadCacheDescription description) {
    _descriptions[sql] = description;
    if (_descriptions.length > readCacheMaxDescriptions) {
      // Insertion order, not recency: promoting on every read would put a map
      // write on the hot path to save a re-describe that only costs one round
      // trip a statement was going to make anyway.
      _descriptions.remove(_descriptions.keys.first);
    }
  }

  static ReadCacheDescription _build(
    TableDependencies dependencies,
    bool deterministic,
  ) {
    if (!deterministic) return const ReadCacheDescription.refused();
    if (dependencies is! FixedTableDependencies) {
      return const ReadCacheDescription.refused();
    }
    final deps = dependencies.tables;
    if (deps.isEmpty) return const ReadCacheDescription.refused();
    return ReadCacheDescription.cacheable([
      for (final dep in deps) dep.table,
    ]);
  }

  /// Retain [rows] for [key], stamped with the [versions] captured before the
  /// read was dispatched.
  ///
  /// An oversized result retires the SQL instead: a statement that returned more
  /// than [maxCachedRows] once is assumed to do so again, so the next execution
  /// stops at the description lookup rather than hashing parameters to build a
  /// key for a result that would be refused anyway.
  void store(
    ReadCacheKey key,
    ReadCacheDescription description,
    List<Map<String, Object?>> rows,
    List<int> versions,
    int epoch,
  ) {
    if (rows.length > maxCachedRows) {
      _remember(key.sql, const ReadCacheDescription.refused());
      return;
    }
    if (_results.length >= readCacheMaxEntries) {
      _results.remove(_results.keys.first);
    }
    _results[key] = _CachedResult(rows, description.tables, versions, epoch);
  }

  /// Note what a write changed.
  ///
  /// One map write per dirty table, and nothing else — no index of dependent
  /// queries, no set arithmetic, no allocation. This runs on the write path
  /// whether or not anything is cached, so it is the cost every application
  /// pays regardless of whether the cache ever helps it.
  void onDependencyChanges(TableDependencies changes) {
    _writes++;
    switch (changes) {
      case UnknownTableDependencies():
        // Native dirty-table capture overflowed or failed. Nothing survives.
        _epoch++;
      case FixedTableDependencies(tables: final dirty):
        if (dirty.isEmpty) {
          // A write reporting no dirty table is either a write that changed
          // nothing or a write the preupdate hook cannot see — DDL, a virtual
          // table. The two are indistinguishable here and only one of them is
          // safe, so this retires the cache. The cost lands on no-op writes;
          // the alternative is serving rows from a dropped table.
          _epoch++;
          return;
        }
        for (final dep in dirty) {
          _versions[dep.table] = (_versions[dep.table] ?? 0) + 1;
        }
    }
  }

  /// Full reset, including learned descriptions. Used on close.
  void reset() {
    _results.clear();
    _versions.clear();
    _descriptions.clear();
    _epoch++;
    _writes++;
  }
}
