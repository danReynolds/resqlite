#ifndef RESQLITE_DEPS_H
#define RESQLITE_DEPS_H

#include "resqlite.h"

// Internal dependency-tracking primitives used by the SQLite authorizer and
// preupdate hook.
//
// Reliability contract:
//   * These sets are bounded and best-effort while `reliable == 1`.
//   * Any uncertainty (NULL required input, allocation failure, or capacity
//     overflow) flips `reliable` to 0.
//   * Once unreliable, add calls are no-ops until reset.
//   * Callers must treat an unreliable table set as "unknown tables" and an
//     unreliable column set as "unknown columns"; both fall back to broader
//     invalidation at the Dart layer.
//
// Ownership contract:
//   * Add/copy functions duplicate their string inputs.
//   * Reset keeps allocated slots for reuse and resets `count` + `reliable`;
//     it does not free retained storage.
//   * Free/clear functions release owned storage and null cleared slots.
//
// Columns are tracked as structured table/column pairs backed by one allocation
// containing "table\0column\0". This keeps storage compact and avoids parsing
// "table.column" strings across the FFI boundary.

// Bounded set of read table names captured while preparing a reader statement.
// If `reliable == 0`, the stream must subscribe to the all-tables fallback.
typedef struct {
    char* names[RESQLITE_MAX_READ_TABLES];
    int count;
    int allocated;
    int reliable;
} resqlite_read_set;

// Bounded set of dirty table names captured by the writer preupdate hook.
// If `reliable == 0`, the write must invalidate every active stream.
typedef struct {
    char* names[RESQLITE_MAX_DIRTY_TABLES];
    int count;
    int allocated;
    int reliable;
} resqlite_dirty_set;

// One table/column dependency. `storage` owns both strings; `table` and
// `column` point inside `storage`. A wildcard column is represented as "*".
typedef struct {
    char* storage;
    const char* table;
    const char* column;
} resqlite_column_dep;

// Bounded set of structured table/column dependencies.
// For readers, entries are columns read by a statement. For writers, entries
// are columns modified by a statement/write cycle. If `reliable == 0`, Dart
// receives no column entries and falls back to table-level invalidation.
typedef struct {
    resqlite_column_dep deps[RESQLITE_MAX_DEP_COLUMNS];
    int count;
    int allocated;
    int reliable;
} resqlite_column_set;

// Initialize an empty table set. Must be called before add/reset/free.
void resqlite_read_set_init(resqlite_read_set* s);

// Add `table_name` to the set. Duplicate names are ignored. NULL, overflow,
// or allocation failure marks the set unreliable.
void resqlite_read_set_add(resqlite_read_set* s, const char* table_name);

// Reuse the set for a new capture cycle. Retained strings may be overwritten by
// later adds; callers must copy out any data they need before reset.
void resqlite_read_set_reset(resqlite_read_set* s);

// Release all retained table-name storage.
void resqlite_read_set_free(resqlite_read_set* s);

// Same lifecycle and reliability semantics as resqlite_read_set, but with the
// dirty-table capacity used by the writer preupdate hook.
void resqlite_dirty_set_init(resqlite_dirty_set* s);
void resqlite_dirty_set_add(resqlite_dirty_set* s, const char* table_name);
void resqlite_dirty_set_reset(resqlite_dirty_set* s);
void resqlite_dirty_set_free(resqlite_dirty_set* s);

// Initialize an empty column set. Must be called before add/reset/free.
void resqlite_column_set_init(resqlite_column_set* s);

// Add a table/column pair. Duplicate pairs are ignored. NULL `column` is stored
// as wildcard "*" (all columns for the table). NULL `table`, overflow, or
// allocation failure marks the set unreliable.
void resqlite_column_set_add(resqlite_column_set* s,
                             const char* table,
                             const char* column);

// Reuse the set for a new capture cycle. Retained dependency slots may be
// overwritten by later adds; callers must copy out any data they need first.
void resqlite_column_set_reset(resqlite_column_set* s);

// Release all retained dependency storage.
void resqlite_column_set_free(resqlite_column_set* s);

// Clear a cache-entry string array produced by resqlite_string_array_copy.
void resqlite_string_array_clear(char** names, int* count);

// Deep-copy `src` into a cache-entry array. Returns 0 on success, -1 on NULL
// source element, capacity overflow, or allocation failure. On failure, any
// partially-copied destination strings are cleared and `*dest_count` is 0.
int resqlite_string_array_copy(char** dest,
                               int capacity,
                               int* dest_count,
                               char* const* src,
                               int src_count);

// Clear a cache-entry column dependency array produced by
// resqlite_column_dep_array_copy_from_set.
void resqlite_column_dep_array_clear(resqlite_column_dep* deps, int* count);

// Deep-copy a column set into a cache-entry array. Returns 0 on success, -1 on
// malformed source entry, capacity overflow, or allocation failure. On failure,
// any partially-copied destination dependencies are cleared and `*dest_count`
// is 0. Caller should only copy from a reliable source set.
int resqlite_column_dep_array_copy_from_set(resqlite_column_dep* dest,
                                            int capacity,
                                            int* dest_count,
                                            const resqlite_column_set* src);

// Return 1 when `dep` belongs to `table_name`, writing the dependency's column
// pointer to `*out_column`. The output pointer is borrowed from `dep` and is
// valid only until the owning dependency array is cleared or freed.
int resqlite_column_dep_belongs_to_table(const resqlite_column_dep* dep,
                                         const char* table_name,
                                         int table_name_len,
                                         const char** out_column);

#ifdef RESQLITE_DEPS_TEST
// Test-only allocation fault injection. `remaining_successes == 0` makes the
// next dependency allocation fail; positive values count down first; reset
// restores normal allocation.
void resqlite_deps_test_fail_alloc_after(int remaining_successes);
void resqlite_deps_test_reset_alloc(void);
#endif

#endif // RESQLITE_DEPS_H
