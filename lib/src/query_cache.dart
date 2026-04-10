/// Query cache — shared result cache with table-based invalidation.
///
/// Stores query results keyed by SQL+params with automatic table dependency
/// tracking. Used by both [StreamEngine] (pinned entries that trigger
/// re-queries) and [Database.select] (evictable entries for cache hits).
///
/// Entries are either *pinned* (a stream is watching — never LRU-evicted)
/// or *unpinned* (one-shot select result — evicted when the cache is full
/// or when a write invalidates the entry's tables).
import 'result_hash.dart';

/// Maximum number of unpinned (one-shot) cache entries. Pinned entries
/// (streams) are not counted against this limit.
const int defaultMaxCacheSize = 64;

/// Maximum row count for a result to be eligible for one-shot caching.
/// Large results are not cached to avoid excessive memory use.
const int maxCacheableRows = 50;

/// Shared query result cache with table-based invalidation.
///
/// Thread-safe by design: runs entirely on the main isolate. Worker
/// isolates never touch this cache — they produce results that the
/// main isolate stores here.
final class QueryCache {
  QueryCache({int maxSize = defaultMaxCacheSize}) : _maxSize = maxSize;

  final int _maxSize;

  /// All cache entries, keyed by query key (hash of SQL+params).
  final Map<int, CacheEntry> _entries = {};

  /// Inverted index: table name → set of cache keys that read from it.
  final Map<String, Set<int>> _tableToKeys = {};

  /// LRU order for unpinned entries. Most recently accessed at end.
  final List<int> _lruOrder = [];

  /// Number of cache entries. Exposed for testing.
  int get length => _entries.length;

  /// Number of unpinned (evictable) entries.
  int get unpinnedCount => _lruOrder.length;

  /// Look up a cached result by query key. Returns null on cache miss.
  /// Updates LRU position for unpinned entries on hit.
  CacheEntry? get(int key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (!entry.pinned) _touchLru(key);
    return entry;
  }

  /// Store a query result in the cache with its table dependencies.
  ///
  /// If [pinned] is true (stream entry), the entry is never LRU-evicted.
  /// If [pinned] is false (one-shot select), the entry is subject to LRU
  /// eviction when the cache exceeds [_maxSize] unpinned entries.
  ///
  /// Returns the created [CacheEntry].
  CacheEntry put({
    required int key,
    required String sql,
    required List<Object?> params,
    required List<Map<String, Object?>> result,
    required int resultHash,
    required Set<String> readTables,
    bool pinned = false,
  }) {
    // Remove existing entry if present (cleans up inverted index).
    _remove(key);

    final entry = CacheEntry(
      key: key,
      sql: sql,
      params: params,
      result: result,
      resultHash: resultHash,
      readTables: readTables,
      pinned: pinned,
    );
    _entries[key] = entry;

    // Update inverted index.
    for (final table in readTables) {
      (_tableToKeys[table] ??= {}).add(key);
    }

    if (!pinned) {
      _lruOrder.add(key);
      _evictIfNeeded();
    }

    return entry;
  }

  /// Update the result for an existing cache entry (e.g., after re-query).
  void updateResult(int key, List<Map<String, Object?>> result, int hash) {
    final entry = _entries[key];
    if (entry == null) return;
    entry.result = result;
    entry.resultHash = hash;
  }

  /// Update the table dependencies for an existing cache entry.
  void updateReadTables(int key, List<String> readTables) {
    final entry = _entries[key];
    if (entry == null) return;

    // Remove old table mappings.
    for (final table in entry.readTables) {
      _tableToKeys[table]?.remove(key);
    }

    // Set new tables and update inverted index.
    final tables = Set<String>.unmodifiable(readTables.toSet());
    entry.readTables = tables;
    for (final table in tables) {
      (_tableToKeys[table] ??= {}).add(key);
    }
  }

  /// Pin an entry (stream is watching). Removes it from LRU tracking.
  void pin(int key) {
    final entry = _entries[key];
    if (entry == null || entry.pinned) return;
    entry.pinned = true;
    _lruOrder.remove(key);
  }

  /// Unpin an entry (last stream subscriber cancelled). Adds to LRU
  /// tracking, or removes entirely if not worth caching.
  void unpin(int key) {
    final entry = _entries[key];
    if (entry == null || !entry.pinned) return;
    entry.pinned = false;
    _lruOrder.add(key);
    _evictIfNeeded();
  }

  /// Handle dirty tables from a write. Removes unpinned entries that
  /// depend on the dirty tables and returns the set of *pinned* keys
  /// that need re-querying (streams).
  Set<int> handleDirtyTables(List<String> dirtyTables) {
    if (dirtyTables.isEmpty) return const {};

    final affected = <int>{};
    for (final table in dirtyTables) {
      final keys = _tableToKeys[table];
      if (keys != null) affected.addAll(keys);
    }
    if (affected.isEmpty) return const {};

    final pinnedAffected = <int>{};
    for (final key in affected) {
      final entry = _entries[key];
      if (entry == null) continue;
      if (entry.pinned) {
        // Stream entry — caller (StreamEngine) will re-query.
        pinnedAffected.add(key);
      } else {
        // One-shot cache entry — just evict it.
        _remove(key);
      }
    }
    return pinnedAffected;
  }

  /// Remove a cache entry and clean up all associated state.
  void _remove(int key) {
    final entry = _entries.remove(key);
    if (entry == null) return;

    for (final table in entry.readTables) {
      final keys = _tableToKeys[table];
      if (keys != null) {
        keys.remove(key);
        if (keys.isEmpty) _tableToKeys.remove(table);
      }
    }

    if (!entry.pinned) {
      _lruOrder.remove(key);
    }
  }

  /// Remove a cache entry by key. Used by StreamEngine when removing
  /// a stream entry.
  void remove(int key) => _remove(key);

  /// Clear all entries.
  void clear() {
    _entries.clear();
    _tableToKeys.clear();
    _lruOrder.clear();
  }

  /// Move a key to the end of the LRU list (most recently accessed).
  void _touchLru(int key) {
    _lruOrder.remove(key);
    _lruOrder.add(key);
  }

  /// Evict the least recently used unpinned entries if over capacity.
  void _evictIfNeeded() {
    while (_lruOrder.length > _maxSize) {
      final evictKey = _lruOrder.first;
      _remove(evictKey);
    }
  }
}

/// Compute a stable hash key for a query (SQL + params).
int queryKey(String sql, List<Object?> params) {
  return Object.hash(sql, Object.hashAll(params));
}

/// Hash a query result for change detection using shared FNV-1a.
int hashResult(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return 0;
  var hash = fnvOffsetBasis;
  hash = fnvCombine(hash, rows.length);
  for (final row in rows) {
    for (final value in row.values) {
      hash = fnvCombine(hash, value == null ? 0 : value.hashCode);
    }
  }
  return hash;
}

/// A single cached query result with metadata.
final class CacheEntry {
  CacheEntry({
    required this.key,
    required this.sql,
    required this.params,
    required this.result,
    required this.resultHash,
    required this.readTables,
    this.pinned = false,
  });

  final int key;
  final String sql;
  final List<Object?> params;
  List<Map<String, Object?>> result;
  int resultHash;
  Set<String> readTables;

  /// Whether this entry is pinned by a stream (not subject to LRU eviction).
  bool pinned;
}
