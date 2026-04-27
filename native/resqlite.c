#include "resqlite.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>

// Forward declarations.
static int bind_params(sqlite3_stmt* stmt, const resqlite_param* params,
                       int param_count, int expected);

// ---------------------------------------------------------------------------
// Growable buffer
// ---------------------------------------------------------------------------

typedef struct {
    unsigned char* data;
    int len;
    int cap;
} resqlite_buf;

static int buf_init(resqlite_buf* b, int initial_cap) {
    b->data = (unsigned char*)malloc(initial_cap);
    if (!b->data) { b->len = 0; b->cap = 0; return -1; }
    b->len = 0;
    b->cap = initial_cap;
    return 0;
}

__attribute__((hot)) static int buf_ensure(resqlite_buf* b, int extra) {
    if (__builtin_expect(b->len + extra <= b->cap, 1)) return 0;
    int new_cap = b->cap;
    while (new_cap < b->len + extra) new_cap *= 2;
    unsigned char* p = (unsigned char*)realloc(b->data, new_cap);
    if (!p) return -1;
    b->data = p;
    b->cap = new_cap;
    return 0;
}

__attribute__((hot)) static int buf_write(resqlite_buf* __restrict b, const void* __restrict src, int n) {
    if (buf_ensure(b, n) != 0) return -1;
    memcpy(b->data + b->len, src, n);
    b->len += n;
    return 0;
}

static int buf_write_byte(resqlite_buf* b, unsigned char v) {
    if (buf_ensure(b, 1) != 0) return -1;
    b->data[b->len++] = v;
    return 0;
}

static int buf_write_i32(resqlite_buf* b, int v) {
    unsigned char tmp[4];
    tmp[0] = (unsigned char)(v & 0xff);
    tmp[1] = (unsigned char)((v >> 8) & 0xff);
    tmp[2] = (unsigned char)((v >> 16) & 0xff);
    tmp[3] = (unsigned char)((v >> 24) & 0xff);
    return buf_write(b, tmp, 4);
}

static int buf_write_i64(resqlite_buf* b, long long v) {
    unsigned char tmp[8];
    for (int i = 0; i < 8; i++) {
        tmp[i] = (unsigned char)((v >> (i * 8)) & 0xff);
    }
    return buf_write(b, tmp, 8);
}

static int buf_write_f64(resqlite_buf* b, double v) {
    unsigned char tmp[8];
    memcpy(tmp, &v, 8);
    return buf_write(b, tmp, 8);
}

static int buf_write_char(resqlite_buf* b, char c) {
    return buf_write_byte(b, (unsigned char)c);
}

static int buf_write_str(resqlite_buf* b, const char* s, int len) {
    return buf_write(b, s, len);
}

// ---------------------------------------------------------------------------
// Statement cache (per connection)
// ---------------------------------------------------------------------------

#define STMT_CACHE_MAX 32

// Experiment 106: column-level dependency tracking. Columns are stored as
// `"table.column"` strings to keep the table+column pair atomic across the
// dedup / intersection paths without introducing a nested data structure.
// `"table.*"` is the wildcard used for INSERT/DELETE writes and for
// authorizer events that arrive without a column name (triggers, views).

typedef struct {
    char* sql;
    int sql_len;
    sqlite3_stmt* stmt;
    // Cached sqlite3_bind_parameter_count(stmt) — a property of the
    // prepared SQL that never changes across re-executions (experiment
    // 077). Stored here so bind_params can skip the FFI-internal call
    // on every query.
    int param_count;
    char* read_tables[RESQLITE_MAX_READ_TABLES];
    int read_table_count;
    // Experiment 106 polish: 1 if `read_tables[]` is the complete
    // dependency set captured by the authorizer; 0 if any read_set_add
    // during prepare overflowed / OOMed / strdup-failed, or if copying
    // the captured set into this cache entry failed.
    // When 0, `resqlite_get_read_tables` returns -1 (the unknown
    // sentinel) so the StreamEngine routes the stream into its
    // global "all tables" bucket.
    int read_tables_reliable;
    // Experiment 106: per-stmt column dependencies (reader: SELECT/WHERE
    // columns from authorizer SQLITE_READ events; writer: SET columns
    // from authorizer SQLITE_UPDATE events). Each entry is "table.column".
    // For writers, INSERT/DELETE leave a "table.*" sentinel because the
    // authorizer fires SQLITE_INSERT / SQLITE_DELETE without a column.
    char* dep_columns[RESQLITE_MAX_DEP_COLUMNS];
    int dep_column_count;
    // Experiment 106 polish: 1 if `dep_columns[]` is the complete
    // dependency set; 0 on any capture/copy failure. When 0, the
    // column getters return 0 entries — falling
    // through `_writeAffectsEntry`'s "table missing from column map"
    // branch into table-level re-query.
    int dep_columns_reliable;
} resqlite_cached_stmt;

typedef struct {
    resqlite_cached_stmt entries[STMT_CACHE_MAX];
    int count;
} resqlite_stmt_cache;

static void stmt_cache_init(resqlite_stmt_cache* c) {
    c->count = 0;
    memset(c->entries, 0, sizeof(c->entries));
}

// ---------------------------------------------------------------------------
// Bounded string-set helpers
// ---------------------------------------------------------------------------
//
// Dependency tracking uses fixed-size, linear-scan sets because the hot
// cases are tiny (usually single-digit table/column counts) and the cap is
// part of the correctness contract: overflow marks the set unreliable so
// higher layers fall back conservatively instead of silently truncating.

static void bounded_string_set_init(int* count, int* allocated, int* reliable) {
    *count = 0;
    *allocated = 0;
    *reliable = 1;
}

static void bounded_string_set_reset(int* count, int* reliable) {
    *count = 0;
    *reliable = 1;
}

static void bounded_string_set_free(char** names, int* count, int* allocated) {
    for (int i = 0; i < *allocated; i++) {
        free(names[i]);
        names[i] = NULL;
    }
    *count = 0;
    *allocated = 0;
}

static void bounded_string_set_add(
    char** names,
    int capacity,
    int* count,
    int* allocated,
    int* reliable,
    const char* value,
    int owns_value
) {
    if (!value) {
        if (owns_value) free((void*)value);
        return;
    }
    if (!*reliable) {
        if (owns_value) free((void*)value);
        return;
    }

    for (int i = 0; i < *count; i++) {
        if (strcmp(names[i], value) == 0) {
            if (owns_value) free((void*)value);
            return;
        }
    }

    if (*count >= capacity) {
        *reliable = 0;
        if (owns_value) free((void*)value);
        return;
    }

    if (*count < *allocated) {
        free(names[*count]);
        names[*count] = NULL;
    }

    char* stored = owns_value ? (char*)value : strdup(value);
    if (!stored) {
        *reliable = 0;
        return;
    }

    names[*count] = stored;
    (*count)++;
    if (*count > *allocated) *allocated = *count;
}

static void cached_string_array_clear(char** names, int* count) {
    for (int i = 0; i < *count; i++) {
        free(names[i]);
        names[i] = NULL;
    }
    *count = 0;
}

static int cached_string_array_copy(
    char** dest,
    int capacity,
    int* dest_count,
    char* const* src,
    int src_count
) {
    *dest_count = 0;
    if (src_count > capacity) return -1;

    for (int i = 0; i < src_count; i++) {
        if (!src[i]) {
            cached_string_array_clear(dest, dest_count);
            return -1;
        }
        char* dup = strdup(src[i]);
        if (!dup) {
            cached_string_array_clear(dest, dest_count);
            return -1;
        }
        dest[*dest_count] = dup;
        (*dest_count)++;
    }
    return 0;
}

static void stmt_cache_entry_clear_read_tables(resqlite_cached_stmt* entry) {
    cached_string_array_clear(entry->read_tables, &entry->read_table_count);
}

static void stmt_cache_entry_clear_dep_columns(resqlite_cached_stmt* entry) {
    cached_string_array_clear(entry->dep_columns, &entry->dep_column_count);
}

static void stmt_cache_entry_dispose(resqlite_cached_stmt* entry) {
    if (entry->stmt) sqlite3_finalize(entry->stmt);
    free(entry->sql);
    stmt_cache_entry_clear_read_tables(entry);
    stmt_cache_entry_clear_dep_columns(entry);
    memset(entry, 0, sizeof(*entry));
}

static void stmt_cache_entry_init(resqlite_cached_stmt* entry,
                                  char* sql_copy,
                                  int sql_len,
                                  sqlite3_stmt* stmt) {
    memset(entry, 0, sizeof(*entry));
    entry->sql = sql_copy;
    entry->sql_len = sql_len;
    entry->stmt = stmt;
    entry->param_count = sqlite3_bind_parameter_count(stmt);
    entry->read_tables_reliable = 1;
    entry->dep_columns_reliable = 1;
}

static resqlite_cached_stmt* stmt_cache_lookup_entry(resqlite_stmt_cache* c,
                                                    const char* sql,
                                                    int sql_len) {
    for (int i = 0; i < c->count; i++) {
        if (c->entries[i].sql_len == sql_len &&
            memcmp(c->entries[i].sql, sql, sql_len) == 0) {
            if (i != c->count - 1) {
                resqlite_cached_stmt tmp = c->entries[i];
                c->entries[i] = c->entries[c->count - 1];
                c->entries[c->count - 1] = tmp;
            }
            return &c->entries[c->count - 1];
        }
    }
    return NULL;
}

static sqlite3_stmt* stmt_cache_lookup(resqlite_stmt_cache* c,
                                        const char* sql, int sql_len) {
    resqlite_cached_stmt* entry = stmt_cache_lookup_entry(c, sql, sql_len);
    return entry ? entry->stmt : NULL;
}

static resqlite_cached_stmt* stmt_cache_insert(resqlite_stmt_cache* c,
                                              const char* sql,
                                              int sql_len,
                                              sqlite3_stmt* stmt) {
    if (c->count >= STMT_CACHE_MAX) {
        stmt_cache_entry_dispose(&c->entries[0]);
        memmove(&c->entries[0], &c->entries[1],
                (STMT_CACHE_MAX - 1) * sizeof(resqlite_cached_stmt));
        c->count = STMT_CACHE_MAX - 1;
    }
    char* sql_copy = (char*)malloc(sql_len + 1);
    if (!sql_copy) return NULL;
    memcpy(sql_copy, sql, sql_len);
    sql_copy[sql_len] = '\0';

    stmt_cache_entry_init(&c->entries[c->count], sql_copy, sql_len, stmt);
    c->count++;
    return &c->entries[c->count - 1];
}

static void stmt_cache_clear(resqlite_stmt_cache* c) {
    for (int i = 0; i < c->count; i++) {
        stmt_cache_entry_dispose(&c->entries[i]);
    }
    c->count = 0;
}

// ---------------------------------------------------------------------------
// Reader connection
// ---------------------------------------------------------------------------

// Read table tracking (per-reader, for stream dependency capture).
typedef struct resqlite_read_set_s {
    char* names[RESQLITE_MAX_READ_TABLES];
    int count;      // number of active entries
    int allocated;  // number of slots with strdup'd strings (>= count)
    // Experiment 106 polish: 1 by default; 0 after any overflow / OOM
    // / strdup failure. The FFI table getter returns -1 (the unknown
    // sentinel) when the cached entry inherits this state, forcing
    // the StreamEngine into its "all tables" fallback bucket. The
    // table side gets a sentinel — not a zero — because zero means
    // "no deps" / "no dirty tables", which would silently stick
    // streams that depend on overflowed tables.
    int reliable;
} resqlite_read_set;

static void read_set_init(resqlite_read_set* s) {
    bounded_string_set_init(&s->count, &s->allocated, &s->reliable);
}

static void read_set_add(resqlite_read_set* s, const char* table_name) {
    bounded_string_set_add(s->names, RESQLITE_MAX_READ_TABLES,
                           &s->count, &s->allocated, &s->reliable,
                           table_name, 0);
}

static void read_set_reset(resqlite_read_set* s) {
    // Per-prepare scratch reset. After each prepare, the authorizer's
    // captured tables are copied into the cached stmt entry's
    // read_tables[] (via stmt_cache_entry_set_read_tables) and Dart
    // serves from there via resqlite_get_read_tables — not from this
    // scratch directly. Allocated slots stay around to amortise strdup
    // across prepares; reliable resets to 1 for the next capture.
    bounded_string_set_reset(&s->count, &s->reliable);
}

static void read_set_free(resqlite_read_set* s) {
    bounded_string_set_free(s->names, &s->count, &s->allocated);
}

// ---------------------------------------------------------------------------
// Column dependency set (experiment 106)
// ---------------------------------------------------------------------------
//
// Stores `"table.column"` strings — both the table and column name in one
// allocation per entry, so set membership and intersection can use a single
// strcmp. The wildcard `"table.*"` means "all columns of <table>" and is
// emitted by the writer authorizer for INSERT/DELETE (which arrive without
// a column name) and used by the reader path when the authorizer fires
// without a column (e.g. inside a trigger / view).
//
// The set is small (typical query: 2-10 entries), so a linear-scan dedup
// outperforms a hash table for the workload sizes we care about.

typedef struct resqlite_column_set_s {
    char* names[RESQLITE_MAX_DEP_COLUMNS];
    int count;
    int allocated;
    // Experiment 106 polish: 1 by default; flipped to 0 on the first
    // overflow / OOM / strdup failure during a capture cycle. After
    // that, *_add becomes a no-op and the FFI getters return a
    // wildcard-equivalent sentinel (column getters: 0 entries; table
    // getters: -1) so dispatch always falls back to a more
    // conservative re-query rather than silently dropping a write.
    // `*_reset` re-initialises this flag to 1 on every cycle.
    int reliable;
} resqlite_column_set;

static void column_set_init(resqlite_column_set* s) {
    bounded_string_set_init(&s->count, &s->allocated, &s->reliable);
}

// Build "table.column" or "table.*" into a stack buffer; falls back to
// heap if the pair overflows. Returns 0 on success, -1 on OOM.
static int column_set_compose(const char* table, const char* column,
                              char* stack, int stack_cap, char** out_buf) {
    if (!table) return -1;
    int t_len = (int)strlen(table);
    const char* col = column ? column : "*";
    int c_len = (int)strlen(col);
    int total = t_len + 1 + c_len + 1;  // "table" + "." + "col" + "\0"
    if (total <= stack_cap) {
        memcpy(stack, table, t_len);
        stack[t_len] = '.';
        memcpy(stack + t_len + 1, col, c_len);
        stack[t_len + 1 + c_len] = '\0';
        *out_buf = stack;
        return 0;
    }
    char* heap = (char*)malloc(total);
    if (!heap) return -1;
    memcpy(heap, table, t_len);
    heap[t_len] = '.';
    memcpy(heap + t_len + 1, col, c_len);
    heap[t_len + 1 + c_len] = '\0';
    *out_buf = heap;
    return 0;
}

static void column_set_add(resqlite_column_set* s, const char* table,
                           const char* column) {
    if (!s->reliable) return;  // already unreliable; no-op
    char stack[256];
    char* key = NULL;
    if (column_set_compose(table, column, stack, sizeof(stack), &key) != 0) {
        // OOM in the heap-fallback path of column_set_compose.
        s->reliable = 0;
        return;
    }
    int key_on_heap = (key != stack);
    bounded_string_set_add(s->names, RESQLITE_MAX_DEP_COLUMNS,
                           &s->count, &s->allocated, &s->reliable,
                           key, key_on_heap);
}

static void column_set_reset(resqlite_column_set* s) {
    bounded_string_set_reset(&s->count, &s->reliable);
}

static void column_set_free(resqlite_column_set* s) {
    bounded_string_set_free(s->names, &s->count, &s->allocated);
}

static void stmt_cache_entry_set_read_tables(resqlite_cached_stmt* entry,
                                             const resqlite_read_set* read_tables) {
    stmt_cache_entry_clear_read_tables(entry);
    // Experiment 106 polish: source set reliability caps the entry's.
    // If unreliable, drop entries and mark the cache entry too — the
    // FFI getter will return -1 (the unknown sentinel) so StreamEngine
    // routes the stream into the all-tables bucket.
    entry->read_tables_reliable = read_tables->reliable;
    if (!read_tables->reliable) return;

    if (cached_string_array_copy(entry->read_tables, RESQLITE_MAX_READ_TABLES,
                                 &entry->read_table_count,
                                 (char* const*)read_tables->names,
                                 read_tables->count) != 0) {
        entry->read_tables_reliable = 0;
    }
}

static void stmt_cache_entry_set_dep_columns(resqlite_cached_stmt* entry,
                                             const resqlite_column_set* cols) {
    stmt_cache_entry_clear_dep_columns(entry);
    // Experiment 106 polish: the source set's reliability is the cap.
    // If it is already 0, the cache entry exposes no column metadata
    // and dispatching consumers route to the conservative re-query path.
    entry->dep_columns_reliable = cols->reliable;

    if (!cols->reliable) return;

    if (cached_string_array_copy(entry->dep_columns, RESQLITE_MAX_DEP_COLUMNS,
                                 &entry->dep_column_count,
                                 (char* const*)cols->names,
                                 cols->count) != 0) {
        entry->dep_columns_reliable = 0;
    }
}

// Authorizer context — bundles the read set (table+column captures) into
// one user_data pointer so the same callback can be installed on writer
// and readers without branching on connection identity. The authorizer
// callback definition (see below) does the actual SQLITE_READ /
// SQLITE_UPDATE etc. dispatch.
typedef struct resqlite_authz_ctx_s {
    resqlite_read_set* tables;
    resqlite_column_set* columns;
    // When non-zero, also capture writer-side dirty columns for
    // SQLITE_UPDATE / SQLITE_INSERT / SQLITE_DELETE actions. Reader
    // contexts leave this zero.
    int track_writes;
} resqlite_authz_ctx;

typedef struct {
    sqlite3* db;
    resqlite_stmt_cache cache;
    resqlite_read_set read_tables;
    // Experiment 106: per-reader column dependency capture. The
    // authorizer populates this set during prepare; on cache hit the
    // column getter reads directly from the cached stmt entry instead
    // of rehydrating per-call (avoids strdup-per-column on the read
    // hot path).
    resqlite_column_set read_columns;
    // Pointer to the cache entry of the most recent acquire on this
    // reader. Cleared on reset; set by `get_or_prepare_reader`. The
    // FFI getters (`resqlite_get_read_columns`, `_read_tables`) serve
    // directly from this entry's `read_tables` / `dep_columns` arrays,
    // so the read hot path pays no per-call strdup-into-scratch cost.
    resqlite_cached_stmt* last_entry;
    resqlite_authz_ctx authz_ctx;
    resqlite_buf json_buf;  // persistent buffer for resqlite_query_bytes
    int in_use;
} resqlite_reader;

// ---------------------------------------------------------------------------
// Connection pool
// ---------------------------------------------------------------------------

#define MAX_READERS 16

// ---------------------------------------------------------------------------
// Dirty table tracking
// ---------------------------------------------------------------------------

typedef struct {
    char* names[RESQLITE_MAX_DIRTY_TABLES];
    int count;
    int allocated;
    // Experiment 106 polish: 1 by default; 0 after any overflow / OOM
    // / strdup failure during a write cycle. The FFI getter
    // `resqlite_get_dirty_tables` returns -1 (unknown sentinel) when
    // this flag is 0 — every active stream then invalidates, since
    // we can't trust the partial dirty-table list to identify which
    // streams should fire.
    int reliable;
} resqlite_dirty_set;

static void dirty_set_init(resqlite_dirty_set* s) {
    bounded_string_set_init(&s->count, &s->allocated, &s->reliable);
}

static void dirty_set_add(resqlite_dirty_set* s, const char* table_name) {
    if (!table_name) {
        s->reliable = 0;
        return;
    }
    bounded_string_set_add(s->names, RESQLITE_MAX_DIRTY_TABLES,
                           &s->count, &s->allocated, &s->reliable,
                           table_name, 0);
}

static void dirty_set_reset(resqlite_dirty_set* s) {
    // Reset active count. Strings stay valid (Dart reads them after
    // resqlite_get_dirty_tables returns pointers). Freed on next add or close.
    bounded_string_set_reset(&s->count, &s->reliable);
}

static void dirty_set_free(resqlite_dirty_set* s) {
    bounded_string_set_free(s->names, &s->count, &s->allocated);
}

// ---------------------------------------------------------------------------
// Connection pool + dirty tracking
// ---------------------------------------------------------------------------

struct resqlite_db {
    // Set atomically before freeing any resources in resqlite_close().
    // All public entry points check this flag and return SQLITE_MISUSE
    // without touching any other fields when it is set, preventing
    // use-after-free races during shutdown.
    atomic_int closed;

    // Write connection (used for exec, DDL, DML).
    sqlite3* writer;
    resqlite_stmt_cache writer_cache;
    sqlite3_mutex* writer_mutex;

    // Persistently prepared transaction-control statements (experiment 101).
    // The writer fires these on every transaction boundary; preparing them
    // once eliminates the prepare+step+finalize cost of `sqlite3_exec` for
    // each call. Held outside writer_cache so they never compete with user
    // statements for cache slots.
    sqlite3_stmt* tx_begin_stmt;
    sqlite3_stmt* tx_commit_stmt;
    sqlite3_stmt* tx_rollback_stmt;

    // Dirty tables accumulated by the preupdate hook.
    resqlite_dirty_set dirty_tables;
    // Experiment 106: dirty columns accumulated alongside dirty tables.
    // Populated at prepare-time via the writer authorizer (cached on the
    // stmt) and merged into this set on each execute by the preupdate
    // hook (per-row firing piggybacks on the existing dirty-table flow).
    // Drained by `resqlite_get_dirty_columns()` after the writer publishes
    // the dirty set to Dart at end-of-transaction.
    resqlite_column_set dirty_columns;
    // Per-prepare scratch space populated by the writer authorizer. The
    // authorizer fires inside `sqlite3_prepare_v3`, so this set is drained
    // into the cached stmt entry as soon as prepare returns and is reset
    // before the next prepare. The writer mutex serialises this access.
    resqlite_column_set writer_authz_scratch;
    resqlite_authz_ctx writer_authz_ctx;
    // Currently-executing stmt cache entry for the writer. Set just before
    // each `sqlite3_step` and cleared after, so the preupdate hook can
    // merge the stmt's pre-captured `dep_columns` into `dirty_columns`
    // whenever a row is actually modified. NULL outside of stepping.
    resqlite_cached_stmt* writer_active_entry;
    int writer_checkpoint_running;

    // Reader pool.
    resqlite_reader readers[MAX_READERS];
    int reader_count;
    sqlite3_mutex* pool_mutex;
    // No condition variable — Dart retries if no reader available.

    char* path;
};

#define RESQLITE_WRITER_PASSIVE_CHECKPOINT_PAGES 500

// ---------------------------------------------------------------------------
// Authorizer callback — records read tables/columns (stream deps) or, on
// the writer, modified tables/columns (dispatch elision in experiment 106)
// ---------------------------------------------------------------------------

#define SQLITE_READ 20    // authorizer action: SELECT-side column read
#define SQLITE_INSERT 18
#define SQLITE_DELETE 9
#define SQLITE_UPDATE 23  // authorizer action: UPDATE column write

static int authorizer_callback(
    void* user_data,
    int action_code,
    const char* arg1,
    const char* arg2,
    const char* arg3,
    const char* arg4
) {
    (void)arg3; (void)arg4;
    resqlite_authz_ctx* ctx = (resqlite_authz_ctx*)user_data;
    switch (action_code) {
        case SQLITE_READ:
            if (arg1 != NULL) {
                if (ctx->tables) read_set_add(ctx->tables, arg1);
                // Only reader contexts care about the read-column set —
                // the writer authorizer collects dirty columns for
                // SQLITE_UPDATE/INSERT/DELETE only. Capturing reads on
                // the writer would pollute its scratch with the columns
                // touched by tx-scoped SELECTs.
                if (ctx->columns && !ctx->track_writes) {
                    column_set_add(ctx->columns, arg1, arg2);
                }
            }
            break;
        case SQLITE_UPDATE:
            if (ctx->track_writes && arg1 != NULL && ctx->columns) {
                // arg2 is the column being SET; capture exactly that.
                column_set_add(ctx->columns, arg1, arg2);
            }
            break;
        case SQLITE_INSERT:
        case SQLITE_DELETE:
            if (ctx->track_writes && arg1 != NULL && ctx->columns) {
                // No column info from SQLite for INSERT/DELETE — emit a
                // wildcard sentinel so the dispatch path knows to skip
                // the column-intersection optimisation for this table.
                column_set_add(ctx->columns, arg1, "*");
            }
            break;
        default:
            break;
    }
    return SQLITE_OK;  // allow all operations
}

// ---------------------------------------------------------------------------
// Preupdate hook callback — records dirty tables/columns
// ---------------------------------------------------------------------------

static int dep_column_belongs_to_table(const char* dep_column,
                                       const char* table_name,
                                       int table_name_len,
                                       const char** out_column) {
    if (!dep_column) return 0;

    const char* dot = strchr(dep_column, '.');
    if (!dot) return 0;

    int table_len = (int)(dot - dep_column);
    if (table_name_len != table_len) return 0;
    if (memcmp(dep_column, table_name, table_len) != 0) return 0;

    *out_column = dot + 1;
    return 1;
}

static void dirty_columns_add_for_active_stmt(resqlite_db* sdb,
                                              const char* table_name) {
    if (!table_name) {
        sdb->dirty_columns.reliable = 0;
        return;
    }

    resqlite_cached_stmt* entry = sdb->writer_active_entry;
    if (!entry) {
        column_set_add(&sdb->dirty_columns, table_name, "*");
        return;
    }

    if (!entry->dep_columns_reliable) {
        sdb->dirty_columns.reliable = 0;
        return;
    }

    int table_name_len = (int)strlen(table_name);
    for (int i = 0; i < entry->dep_column_count; i++) {
        const char* column = NULL;
        if (dep_column_belongs_to_table(entry->dep_columns[i], table_name,
                                        table_name_len, &column)) {
            column_set_add(&sdb->dirty_columns, table_name, column);
        }
    }
}

static void preupdate_hook(
    void* user_data,
    sqlite3* db,
    int op,
    const char* db_name,
    const char* table_name,
    sqlite3_int64 old_rowid,
    sqlite3_int64 new_rowid
) {
    (void)db; (void)op; (void)db_name; (void)old_rowid; (void)new_rowid;
    resqlite_db* sdb = (resqlite_db*)user_data;
    dirty_set_add(&sdb->dirty_tables, table_name);
    dirty_columns_add_for_active_stmt(sdb, table_name);
}

static int writer_wal_hook(
    void* user_data,
    sqlite3* db,
    const char* db_name,
    int pages_in_wal
) {
    resqlite_db* sdb = (resqlite_db*)user_data;
    if (pages_in_wal < RESQLITE_WRITER_PASSIVE_CHECKPOINT_PAGES ||
        sdb->writer_checkpoint_running) {
        return SQLITE_OK;
    }

    sdb->writer_checkpoint_running = 1;
    int rc = sqlite3_wal_checkpoint_v2(
        db,
        db_name,
        SQLITE_CHECKPOINT_PASSIVE,
        NULL,
        NULL
    );
    sdb->writer_checkpoint_running = 0;

    // PASSIVE checkpoints can legitimately report BUSY if readers pin the WAL.
    // Treat that as "try again later" instead of surfacing an error from commit.
    if (rc == SQLITE_BUSY) return SQLITE_OK;
    return rc;
}

// sqlite3_exec callback for PRAGMA journal_mode — sets *arg to 1 if the
// returned mode is "wal" (case-insensitive first 3 chars).
static int _wal_check_cb(void* arg, int ncols, char** values, char** names) {
    (void)ncols; (void)names;
    if (values[0] && values[0][0] == 'w' && values[0][1] == 'a' && values[0][2] == 'l') {
        *(int*)arg = 1;
    }
    return 0;
}

// Open a connection with optional encryption.
// encryption_key_hex: hex string like "aabb01..." or NULL for no encryption.
static sqlite3* open_connection(const char* path, int read_only,
                                 const char* encryption_key_hex) {
    sqlite3* db = NULL;
    int flags = read_only
        ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX)
        : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX);

    int rc = sqlite3_open_v2(path, &db, flags, NULL);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close_v2(db);
        return NULL;
    }

    // Set encryption key before any other operations. The key must be set
    // immediately after opening — before any reads or PRAGMAs.
    if (encryption_key_hex != NULL && encryption_key_hex[0] != '\0') {
        // Validate hex-only to prevent PRAGMA injection.
        for (const char* p = encryption_key_hex; *p; p++) {
            char c = *p;
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                  (c >= 'A' && c <= 'F'))) {
                sqlite3_close_v2(db);
                return NULL;
            }
        }
        char pragma[256];
        snprintf(pragma, sizeof(pragma), "PRAGMA key = \"x'%s'\"", encryption_key_hex);
        rc = sqlite3_exec(db, pragma, NULL, NULL, NULL);
        if (rc != SQLITE_OK) {
            sqlite3_close_v2(db);
            return NULL;
        }

        // Probe to force page decryption and verify the key is correct.
        rc = sqlite3_exec(db, "SELECT count(*) FROM sqlite_master", NULL, NULL, NULL);
        if (rc != SQLITE_OK) {
            sqlite3_close_v2(db);
            return NULL;
        }
    }

    // WAL mode is required — the entire reader/writer architecture depends
    // on it for concurrent reads during writes. sqlite3_exec returns
    // SQLITE_OK even if the mode wasn't changed (the current mode is
    // returned as a result row), so we must verify the actual value.
    {
        int wal_ok = 0;
        rc = sqlite3_exec(db, "PRAGMA journal_mode = WAL", _wal_check_cb, &wal_ok, NULL);
        if (rc != SQLITE_OK || !wal_ok) {
            sqlite3_close_v2(db);
            return NULL;
        }
    }
    sqlite3_exec(db, "PRAGMA busy_timeout = 5000", NULL, NULL, NULL);
    sqlite3_exec(db, "PRAGMA mmap_size = 268435456", NULL, NULL, NULL);  // 256 MB
    sqlite3_exec(db, "PRAGMA cache_size = -8192", NULL, NULL, NULL);    // 8 MB
    sqlite3_exec(db, "PRAGMA temp_store = MEMORY", NULL, NULL, NULL);
    if (read_only) {
        // Readers should never trigger auto-checkpoints.
        sqlite3_exec(db, "PRAGMA wal_autocheckpoint = 0", NULL, NULL, NULL);
    } else {
        // Writer: resqlite installs its own passive checkpoint scheduler via
        // sqlite3_wal_hook() in resqlite_open(), so disable SQLite's built-in
        // autocheckpoint to avoid two independent schedulers fighting.
        sqlite3_exec(db, "PRAGMA wal_autocheckpoint = 0", NULL, NULL, NULL);
        sqlite3_exec(db, "PRAGMA journal_size_limit = 67108864", NULL, NULL, NULL);  // 64 MB
    }
    // synchronous=NORMAL is set automatically by SQLITE_DEFAULT_WAL_SYNCHRONOUS=1
    // for all connections in WAL mode — no PRAGMA needed.

    return db;
}

resqlite_db* resqlite_open(const char* path, int max_readers,
                          const char* encryption_key_hex) {
    // Required when compiled with SQLITE_OMIT_AUTOINIT — call once before
    // any other SQLite API. Subsequent calls are harmless no-ops.
    sqlite3_initialize();

    if (max_readers <= 0) max_readers = 8;
    if (max_readers > MAX_READERS) max_readers = MAX_READERS;

    // Open write connection.
    sqlite3* writer = open_connection(path, 0, encryption_key_hex);
    if (!writer) return NULL;

    resqlite_db* db = (resqlite_db*)calloc(1, sizeof(resqlite_db));
    atomic_init(&db->closed, 0);
    db->writer = writer;
    db->path = strdup(path);
    stmt_cache_init(&db->writer_cache);
    dirty_set_init(&db->dirty_tables);
    column_set_init(&db->dirty_columns);
    column_set_init(&db->writer_authz_scratch);
    db->writer_active_entry = NULL;
    db->writer_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);
    db->pool_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);

    // Pre-prepare transaction-control stmts (experiment 101). These are
    // hot-path statements fired on every transaction boundary, so we
    // prepare them once and re-use via sqlite3_reset + sqlite3_step
    // instead of paying sqlite3_exec's prepare+step+finalize each call.
    sqlite3_prepare_v3(writer, "BEGIN IMMEDIATE", -1,
                       SQLITE_PREPARE_PERSISTENT, &db->tx_begin_stmt, NULL);
    sqlite3_prepare_v3(writer, "COMMIT", -1,
                       SQLITE_PREPARE_PERSISTENT, &db->tx_commit_stmt, NULL);
    sqlite3_prepare_v3(writer, "ROLLBACK", -1,
                       SQLITE_PREPARE_PERSISTENT, &db->tx_rollback_stmt, NULL);

    // Install preupdate hook on writer for dirty table tracking.
    sqlite3_preupdate_hook(writer, preupdate_hook, db);
    sqlite3_wal_hook(writer, writer_wal_hook, db);

    // Experiment 106: install authorizer on the writer to capture which
    // columns each prepared DML stmt could modify. The authorizer fires
    // inside `sqlite3_prepare_v3`; we drain `writer_authz_scratch` into
    // the cached stmt entry as soon as prepare returns. With
    // `track_writes` set on the writer, SQLITE_READ events are ignored;
    // read dependencies are captured by the reader authorizers below.
    db->writer_authz_ctx.tables = NULL;
    db->writer_authz_ctx.columns = &db->writer_authz_scratch;
    db->writer_authz_ctx.track_writes = 1;
    sqlite3_set_authorizer(writer, authorizer_callback, &db->writer_authz_ctx);

    // Open reader connections with authorizer hooks for dependency tracking.
    // Use reader_count as the insertion index so successful readers are
    // packed contiguously — no gaps if an earlier open/init fails.
    db->reader_count = 0;
    for (int i = 0; i < max_readers; i++) {
        sqlite3* rdb = open_connection(path, 1, encryption_key_hex);
        if (!rdb) continue;

        int idx = db->reader_count;
        db->readers[idx].db = rdb;
        stmt_cache_init(&db->readers[idx].cache);
        read_set_init(&db->readers[idx].read_tables);
        column_set_init(&db->readers[idx].read_columns);
        db->readers[idx].last_entry = NULL;
        if (buf_init(&db->readers[idx].json_buf, 16384) != 0) {
            sqlite3_close_v2(rdb);
            db->readers[idx].db = NULL;
            continue;
        }
        db->readers[idx].in_use = 0;

        // Install authorizer to capture read dependencies (table + column).
        // The context lives inline on the reader so its address is stable
        // across the connection's lifetime — sqlite3_set_authorizer stores
        // the pointer for the duration of the connection.
        db->readers[idx].authz_ctx.tables = &db->readers[idx].read_tables;
        db->readers[idx].authz_ctx.columns = &db->readers[idx].read_columns;
        db->readers[idx].authz_ctx.track_writes = 0;
        sqlite3_set_authorizer(rdb, authorizer_callback,
                               &db->readers[idx].authz_ctx);

        db->reader_count++;
    }

    return db;
}

void resqlite_close(resqlite_db* db) {
    if (!db) return;

    // Mark closed BEFORE touching any resources. Any concurrent call to a
    // public entry point will see this flag and return SQLITE_MISUSE
    // instead of dereferencing freed memory.
    atomic_store_explicit(&db->closed, 1, memory_order_release);

    // Close all readers.
    for (int i = 0; i < db->reader_count; i++) {
        stmt_cache_clear(&db->readers[i].cache);
        read_set_free(&db->readers[i].read_tables);
        column_set_free(&db->readers[i].read_columns);
        if (db->readers[i].json_buf.data) free(db->readers[i].json_buf.data);
        sqlite3_close_v2(db->readers[i].db);
    }

    // Close writer.
    sqlite3_mutex_enter(db->writer_mutex);
    stmt_cache_clear(&db->writer_cache);
    if (db->tx_begin_stmt) sqlite3_finalize(db->tx_begin_stmt);
    if (db->tx_commit_stmt) sqlite3_finalize(db->tx_commit_stmt);
    if (db->tx_rollback_stmt) sqlite3_finalize(db->tx_rollback_stmt);
    dirty_set_free(&db->dirty_tables);
    column_set_free(&db->dirty_columns);
    column_set_free(&db->writer_authz_scratch);
    sqlite3_close_v2(db->writer);
    sqlite3_mutex_leave(db->writer_mutex);

    sqlite3_mutex_free(db->writer_mutex);
    sqlite3_mutex_free(db->pool_mutex);
    free(db->path);
    free(db);
}

const char* resqlite_errmsg(resqlite_db* db) {
    if (!db || !db->writer || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return "database not open";
    }
    return sqlite3_errmsg(db->writer);
}

sqlite3* resqlite_writer_handle(resqlite_db* db) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return NULL;
    return db->writer;
}

int resqlite_exec(resqlite_db* db, const char* sql) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }
    sqlite3_mutex_enter(db->writer_mutex);
    int rc = sqlite3_exec(db->writer, sql, NULL, NULL, NULL);
    sqlite3_mutex_leave(db->writer_mutex);
    return rc;
}

// Run one of the cached transaction-control statements on the writer
// (experiment 101). Caller is responsible for any required mutex.
// SQLite returns SQLITE_DONE on a successful no-result step; we
// translate that to SQLITE_OK so callers can use a single == 0 check.
static int run_cached_tx_stmt(sqlite3_stmt* stmt) {
    if (!stmt) return SQLITE_MISUSE;
    sqlite3_reset(stmt);
    int rc = sqlite3_step(stmt);
    sqlite3_reset(stmt);
    if (rc == SQLITE_DONE || rc == SQLITE_ROW) return SQLITE_OK;
    return rc;
}

int resqlite_tx_begin_immediate(resqlite_db* db) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }
    sqlite3_mutex_enter(db->writer_mutex);
    int rc = run_cached_tx_stmt(db->tx_begin_stmt);
    sqlite3_mutex_leave(db->writer_mutex);
    return rc;
}

int resqlite_tx_commit(resqlite_db* db) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }
    sqlite3_mutex_enter(db->writer_mutex);
    int rc = run_cached_tx_stmt(db->tx_commit_stmt);
    sqlite3_mutex_leave(db->writer_mutex);
    return rc;
}

int resqlite_tx_rollback(resqlite_db* db) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }
    sqlite3_mutex_enter(db->writer_mutex);
    int rc = run_cached_tx_stmt(db->tx_rollback_stmt);
    sqlite3_mutex_leave(db->writer_mutex);
    return rc;
}

// Returns the cached entry (which carries both the stmt pointer and
// the pre-computed param_count). Callers that only need the stmt read
// `entry->stmt`; bind_params callers pass `entry->param_count` as the
// expected count (experiment 077).
static resqlite_cached_stmt* get_or_prepare_writer(
    resqlite_db* db, const char* sql, int sql_len, int* out_rc,
    const char** out_tail
) {
    resqlite_cached_stmt* entry =
        stmt_cache_lookup_entry(&db->writer_cache, sql, sql_len);
    if (entry) {
        sqlite3_reset(entry->stmt);
        *out_rc = SQLITE_OK;
        // Cached statements are always single-statement (multi-statement SQL
        // is never prepared via this function), so signal "no trailing SQL".
        *out_tail = sql + sql_len;
        return entry;
    }

    // Experiment 106: reset the authorizer scratch column set so this
    // prepare's authorizer events accumulate cleanly. The writer mutex
    // serialises this access.
    column_set_reset(&db->writer_authz_scratch);

    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v3(db->writer, sql, sql_len, SQLITE_PREPARE_PERSISTENT,
                                &stmt, out_tail);
    if (rc != SQLITE_OK) {
        *out_rc = rc;
        return NULL;
    }

    entry = stmt_cache_insert(&db->writer_cache, sql, sql_len, stmt);
    if (!entry) {
        // OOM — can't cache, and nobody else holds a reference to finalize
        // this stmt later. Finalize and fail the query.
        sqlite3_finalize(stmt);
        *out_rc = SQLITE_NOMEM;
        return NULL;
    }
    // Persist the authorizer-captured columns onto the cache entry so
    // subsequent re-uses skip the prepare path entirely (the authorizer
    // does not refire on a cached stmt — only on the initial prepare).
    stmt_cache_entry_set_dep_columns(entry, &db->writer_authz_scratch);
    *out_rc = SQLITE_OK;
    return entry;
}

int resqlite_execute(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* params,
    int param_count,
    resqlite_write_result* out_result
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }
    sqlite3_mutex_enter(db->writer_mutex);

    int rc;
    const char* tail = NULL;
    resqlite_cached_stmt* entry =
        get_or_prepare_writer(db, sql, (int)strlen(sql), &rc, &tail);
    if (!entry) {
        sqlite3_mutex_leave(db->writer_mutex);
        return rc;
    }
    sqlite3_stmt* stmt = entry->stmt;

    // Detect multi-statement SQL via pzTail. Skip whitespace and bare
    // semicolons — only real SQL text beyond the first statement counts.
    if (tail && param_count == 0) {
        const char* p = tail;
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r'
               || *p == ';') p++;
        if (*p != '\0') {
            // Multi-statement SQL with no parameters: fall back to
            // sqlite3_exec which walks the full string statement-by-
            // statement. The prepared stmt stays in the cache harmlessly
            // (it covers just the first statement).
            sqlite3_reset(stmt);
            rc = sqlite3_exec(db->writer, sql, NULL, NULL, NULL);
            if (out_result) {
                out_result->affected_rows = sqlite3_changes(db->writer);
                out_result->last_insert_id =
                    sqlite3_last_insert_rowid(db->writer);
            }
            sqlite3_mutex_leave(db->writer_mutex);
            return rc;
        }
    }

    // Single statement (or multi-statement with params — existing
    // behavior: only the first statement executes via prepare).
    rc = bind_params(stmt, params, param_count, entry->param_count);
    if (rc != SQLITE_OK) {
        sqlite3_reset(stmt);
        sqlite3_mutex_leave(db->writer_mutex);
        return rc;
    }

    // Experiment 106: tag the active stmt entry so the preupdate hook
    // can merge its pre-captured column set into `dirty_columns` on each
    // per-row firing. Cleared after step so unrelated callers (e.g. trigger
    // bodies driven by sqlite3_exec) fall back to the wildcard path.
    db->writer_active_entry = entry;
    rc = sqlite3_step(stmt);
    db->writer_active_entry = NULL;
    if (out_result) {
        out_result->affected_rows = sqlite3_changes(db->writer);
        out_result->last_insert_id = sqlite3_last_insert_rowid(db->writer);
    }
    sqlite3_reset(stmt);
    sqlite3_mutex_leave(db->writer_mutex);

    if (rc == SQLITE_DONE || rc == SQLITE_ROW) return SQLITE_OK;
    return rc;
}

// Shared batch loop: prepare (or reuse cached) the statement, then bind+step
// each param set. Assumes the caller holds writer_mutex and that any
// enclosing transaction control (BEGIN/COMMIT/SAVEPOINT) is managed externally.
// On error, leaves the statement reset and returns the sqlite error code.
static int run_batch_locked(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* param_sets,
    int param_count,
    int set_count
) {
    resqlite_cached_stmt* entry = stmt_cache_lookup_entry(
        &db->writer_cache, sql, (int)strlen(sql));
    sqlite3_stmt* stmt;
    if (entry) {
        stmt = entry->stmt;
        sqlite3_reset(stmt);
    } else {
        column_set_reset(&db->writer_authz_scratch);
        int rc = sqlite3_prepare_v3(
            db->writer, sql, -1, SQLITE_PREPARE_PERSISTENT, &stmt, NULL);
        if (rc != SQLITE_OK) return rc;
        entry =
            stmt_cache_insert(&db->writer_cache, sql, (int)strlen(sql), stmt);
        if (!entry) {
            sqlite3_finalize(stmt);
            return SQLITE_NOMEM;
        }
        // Experiment 106: drain authz scratch into the cache entry once
        // prepare returns. The per-set step loop below benefits from the
        // pre-captured column set on every row.
        stmt_cache_entry_set_dep_columns(entry, &db->writer_authz_scratch);
    }
    const int expected = entry->param_count;

    for (int i = 0; i < set_count; i++) {
        sqlite3_reset(stmt);

        int rc = bind_params(
            stmt, &param_sets[i * param_count], param_count, expected);
        if (rc != SQLITE_OK) {
            sqlite3_reset(stmt);
            return rc;
        }

        // Experiment 106: tag the active entry so the preupdate hook can
        // merge cached columns. Cleared after step on every iteration.
        db->writer_active_entry = entry;
        rc = sqlite3_step(stmt);
        db->writer_active_entry = NULL;
        if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
            sqlite3_reset(stmt);
            return rc;
        }
    }

    sqlite3_reset(stmt);
    return SQLITE_OK;
}

int resqlite_run_batch(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* param_sets,
    int param_count,
    int set_count
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }
    sqlite3_mutex_enter(db->writer_mutex);

    // BEGIN IMMEDIATE acquires the write lock upfront, avoiding the
    // lock-upgrade path since we know we're writing. The cached
    // prepared stmt skips sqlite3_exec's per-call prepare+finalize
    // (experiment 101).
    int rc = run_cached_tx_stmt(db->tx_begin_stmt);
    if (rc != SQLITE_OK) {
        sqlite3_mutex_leave(db->writer_mutex);
        return rc;
    }

    rc = run_batch_locked(db, sql, param_sets, param_count, set_count);
    if (rc != SQLITE_OK) {
        run_cached_tx_stmt(db->tx_rollback_stmt);
    } else {
        rc = run_cached_tx_stmt(db->tx_commit_stmt);
    }

    sqlite3_mutex_leave(db->writer_mutex);
    return rc;
}

int resqlite_run_batch_nested(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* param_sets,
    int param_count,
    int set_count
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }
    // Caller owns the enclosing transaction (BEGIN IMMEDIATE or SAVEPOINT),
    // so we do not start/commit/rollback here. On error we return the code
    // and the Dart-level caller decides whether to ROLLBACK (top-level tx)
    // or ROLLBACK TO a savepoint.
    sqlite3_mutex_enter(db->writer_mutex);
    int rc = run_batch_locked(db, sql, param_sets, param_count, set_count);
    sqlite3_mutex_leave(db->writer_mutex);
    return rc;
}

// Polish (post-2026-04): returns -1 when the dirty-table set is
// unreliable (overflow / OOM during the write cycle). Zero would mean
// "no tables dirty" — invalidations would be silently missed; the
// negative sentinel forces the StreamEngine to invalidate every
// active entry.
int resqlite_get_dirty_tables(
    resqlite_db* db,
    const char** out_tables,
    int max_tables
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
    int reliable = db->dirty_tables.reliable;
    if (!reliable) {
        // Reset before returning — caller has been signalled, future
        // writes start with a fresh reliability flag.
        dirty_set_reset(&db->dirty_tables);
        return -1;
    }

    int count = db->dirty_tables.count;
    if (count > max_tables) count = max_tables;

    // Copy pointers — caller must read strings before the next call.
    for (int i = 0; i < count; i++) {
        out_tables[i] = db->dirty_tables.names[i];
    }

    // Reset active count. Strings stay valid — out_tables still points to them.
    // They'll be freed on the next dirty_set_add when slots are reused.
    dirty_set_reset(&db->dirty_tables);

    return count;
}

// Polish (post-2026-04): returns -1 when the cached entry's read-table
// dependencies are unreliable (overflow / OOM during prepare). Zero
// would mean "stream has no table deps" → silent stuck stream; the
// negative sentinel forces the Dart-side StreamEngine to route the
// stream into the "all tables" bucket where every write invalidates it.
int resqlite_get_read_tables(
    resqlite_db* db,
    int reader_id,
    const char** out_tables,
    int max_tables
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
    if (reader_id < 0 || reader_id >= db->reader_count) return 0;

    resqlite_reader* reader = &db->readers[reader_id];
    // Experiment 106: serve directly from the cached stmt entry of the
    // most recent acquire so we don't pay the strdup-per-table cost
    // that the per-reader scratch incurred on every cache hit. The
    // entry's strings outlive this call (they're freed on stmt cache
    // eviction), so the caller's copy-before-next-query contract is
    // unchanged.
    resqlite_cached_stmt* entry = reader->last_entry;
    if (!entry) return 0;
    if (!entry->read_tables_reliable) return -1;
    int count = entry->read_table_count;
    if (count > max_tables) count = max_tables;
    for (int i = 0; i < count; i++) {
        out_tables[i] = entry->read_tables[i];
    }
    return count;
}

// Experiment 106: drain the read-column set for the most recent query
// on this reader. Each entry is a "table.column" string owned by the
// cached stmt entry; the caller MUST copy them before issuing the next
// query on this reader.
//
// Polish (post-2026-04): when the cached entry's column dependencies
// are unreliable (overflow / OOM during prepare), this returns 0 so
// the StreamEngine's "table absent from column map" branch falls
// through to a conservative table-level re-query. Zero is the load-
// bearing signal — table dependencies are still reliable on the same
// path; the column elision optimisation simply opts out for this stmt.
int resqlite_get_read_columns(
    resqlite_db* db,
    int reader_id,
    const char** out_columns,
    int max_columns
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
    if (reader_id < 0 || reader_id >= db->reader_count) return 0;

    resqlite_reader* reader = &db->readers[reader_id];
    resqlite_cached_stmt* entry = reader->last_entry;
    if (!entry) return 0;
    if (!entry->dep_columns_reliable) return 0;
    int count = entry->dep_column_count;
    if (count > max_columns) count = max_columns;
    for (int i = 0; i < count; i++) {
        out_columns[i] = entry->dep_columns[i];
    }
    return count;
}

// Experiment 106: drain the dirty-columns accumulator alongside dirty
// tables. Returns the number of "table.column" entries written. Like
// `resqlite_get_dirty_tables`, the strings stay valid until the next
// `column_set_add` reuses their slot — caller must copy before further
// writer activity.
//
// Polish (post-2026-04): when the dirty-columns set is unreliable
// (overflow / OOM during preupdate hook merge), returns 0 so the
// StreamEngine sees "no precise column metadata" and falls back to
// dispatching on the (still-reliable) dirty table set.
int resqlite_get_dirty_columns(
    resqlite_db* db,
    const char** out_columns,
    int max_columns
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;

    int reliable = db->dirty_columns.reliable;
    int count = reliable ? db->dirty_columns.count : 0;
    if (count > max_columns) count = max_columns;

    for (int i = 0; i < count; i++) {
        out_columns[i] = db->dirty_columns.names[i];
    }

    column_set_reset(&db->dirty_columns);

    return count;
}

int resqlite_db_status_total(
    resqlite_db* db,
    int op,
    int reset,
    int* out_current,
    int* out_highwater
) {
    if (!db || !out_current || !out_highwater
        || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        return SQLITE_MISUSE;
    }

    int total_current = 0;
    int total_highwater = 0;
    int rc = SQLITE_OK;

    sqlite3_mutex_enter(db->writer_mutex);
    int current = 0;
    int highwater = 0;
    int writer_rc = sqlite3_db_status(db->writer, op, &current, &highwater, reset);
    sqlite3_mutex_leave(db->writer_mutex);
    if (writer_rc != SQLITE_OK) {
        rc = writer_rc;
    } else {
        total_current += current;
        total_highwater += highwater;
    }

    sqlite3_mutex_enter(db->pool_mutex);
    for (int i = 0; i < db->reader_count; i++) {
        if (db->readers[i].in_use) {
            if (rc == SQLITE_OK) rc = SQLITE_BUSY;
            continue;
        }

        current = 0;
        highwater = 0;
        int reader_rc = sqlite3_db_status(
            db->readers[i].db, op, &current, &highwater, reset);
        if (reader_rc != SQLITE_OK) {
            if (rc == SQLITE_OK) rc = reader_rc;
            continue;
        }
        total_current += current;
        total_highwater += highwater;
    }
    sqlite3_mutex_leave(db->pool_mutex);

    *out_current = total_current;
    *out_highwater = total_highwater;
    return rc;
}

// ---------------------------------------------------------------------------
// Reader pool: acquire / release
// ---------------------------------------------------------------------------

// Find an idle reader. Returns reader index, or -1 if none available.
static int find_idle_reader(resqlite_db* db) {
    for (int i = 0; i < db->reader_count; i++) {
        if (!db->readers[i].in_use) return i;
    }
    return -1;
}

// Acquire an idle reader, spinning briefly if all are busy.
// Uses sqlite3_sleep (cross-platform) instead of pthread_cond_wait.
static int acquire_reader(resqlite_db* db) {
    for (int attempt = 0; attempt < 1000; attempt++) {
        sqlite3_mutex_enter(db->pool_mutex);
        int idx = find_idle_reader(db);
        if (idx >= 0) {
            db->readers[idx].in_use = 1;
            sqlite3_mutex_leave(db->pool_mutex);
            return idx;
        }
        sqlite3_mutex_leave(db->pool_mutex);
        // Brief sleep — sqlite3_sleep is cross-platform (ms).
        sqlite3_sleep(1);
    }
    return -1;  // Timed out after ~1 second.
}

// Release a reader back to the pool.
static void release_reader(resqlite_db* db, int idx) {
    sqlite3_mutex_enter(db->pool_mutex);
    db->readers[idx].in_use = 0;
    sqlite3_mutex_leave(db->pool_mutex);
}

// ---------------------------------------------------------------------------
// Internal: get or prepare on a specific reader
// ---------------------------------------------------------------------------

// Returns the cached entry (stmt + param_count + read-tables).
// Callers that only need the stmt read `entry->stmt`; bind_params
// callers pass `entry->param_count` as the expected count (exp 077).
static resqlite_cached_stmt* get_or_prepare_reader(
    resqlite_reader* reader, const char* sql, int sql_len, int* out_rc
) {
    resqlite_cached_stmt* entry =
        stmt_cache_lookup_entry(&reader->cache, sql, sql_len);
    if (entry) {
        sqlite3_reset(entry->stmt);
        // Experiment 106: tag the active entry so the FFI getters can
        // serve table/column dependencies straight from the cache (no
        // strdup-per-column rehydrate on the read hot path). Avoids
        // the wide-schema main-thread regression spotted on first run.
        reader->last_entry = entry;
        *out_rc = SQLITE_OK;
        return entry;
    }

    // The authorizer populates per-reader read tables during prepare.
    // Reset before preparing so this statement captures only its own deps.
    read_set_reset(&reader->read_tables);
    column_set_reset(&reader->read_columns);

    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v3(reader->db, sql, sql_len, SQLITE_PREPARE_PERSISTENT, &stmt, NULL);
    if (rc != SQLITE_OK) {
        *out_rc = rc;
        return NULL;
    }

    entry = stmt_cache_insert(&reader->cache, sql, sql_len, stmt);
    if (!entry) {
        sqlite3_finalize(stmt);
        *out_rc = SQLITE_NOMEM;
        return NULL;
    }
    stmt_cache_entry_set_read_tables(entry, &reader->read_tables);
    stmt_cache_entry_set_dep_columns(entry, &reader->read_columns);
    reader->last_entry = entry;
    *out_rc = SQLITE_OK;
    return entry;
}

// ---------------------------------------------------------------------------
// Internal: bind parameters
// ---------------------------------------------------------------------------

// Caller provides `expected` — it's a property of the prepared SQL and
// the cache tracks it alongside the stmt (experiment 077). Saves one
// sqlite3_bind_parameter_count FFI-internal call per query.
static int bind_params(sqlite3_stmt* stmt, const resqlite_param* params,
                       int param_count, int expected) {
    if (expected != param_count) {
        // Force SQLite to populate the connection error state with the same
        // bind-range error it would use for an out-of-range parameter index.
        (void)sqlite3_bind_null(stmt, expected + 1);
        return SQLITE_RANGE;
    }

    for (int i = 0; i < param_count; i++) {
        int idx = i + 1;
        int rc;
        switch (params[i].type) {
            case RESQLITE_TYPE_NULL:
                rc = sqlite3_bind_null(stmt, idx);
                break;
            case RESQLITE_TYPE_INT64:
                rc = sqlite3_bind_int64(stmt, idx, params[i].int_val);
                break;
            case RESQLITE_TYPE_FLOAT64:
                rc = sqlite3_bind_double(stmt, idx, params[i].float_val);
                break;
            case RESQLITE_TYPE_TEXT:
                rc = sqlite3_bind_text(stmt, idx,
                                       params[i].text.data,
                                       params[i].text.len,
                                       SQLITE_STATIC);
                break;
            case RESQLITE_TYPE_BLOB:
                rc = sqlite3_bind_blob64(stmt, idx,
                                          params[i].blob.data,
                                          params[i].blob.len,
                                          SQLITE_STATIC);
                break;
            default:
                rc = sqlite3_bind_null(stmt, idx);
                break;
        }
        if (rc != SQLITE_OK) return rc;
    }
    return SQLITE_OK;
}

// ---------------------------------------------------------------------------
// Public: stmt acquire/release (for Dart per-cell stepping)
// ---------------------------------------------------------------------------

sqlite3_stmt* resqlite_stmt_acquire(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* params,
    int param_count,
    int* out_reader
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        *out_reader = -1;
        return NULL;
    }
    int reader_idx = acquire_reader(db);
    if (reader_idx < 0) {
        *out_reader = -1;
        return NULL;
    }
    resqlite_reader* reader = &db->readers[reader_idx];

    int rc;
    resqlite_cached_stmt* entry =
        get_or_prepare_reader(reader, sql, (int)strlen(sql), &rc);
    if (!entry) {
        release_reader(db, reader_idx);
        *out_reader = -1;
        return NULL;
    }
    sqlite3_stmt* stmt = entry->stmt;

    rc = bind_params(stmt, params, param_count, entry->param_count);
    if (rc != SQLITE_OK) {
        sqlite3_reset(stmt);
        release_reader(db, reader_idx);
        *out_reader = -1;
        return NULL;
    }

    *out_reader = reader_idx;
    return stmt;
}

void resqlite_stmt_release(resqlite_db* db, int reader_id) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return;
    if (reader_id >= 0 && reader_id < db->reader_count) {
        release_reader(db, reader_id);
    }
}

// Acquire a statement on a specific reader without pool mutex.
// The caller guarantees exclusive access to this reader (dedicated worker).
sqlite3_stmt* resqlite_stmt_acquire_on(
    resqlite_db* db,
    int reader_id,
    const char* sql,
    const resqlite_param* params,
    int param_count
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return NULL;
    if (reader_id < 0 || reader_id >= db->reader_count) return NULL;
    resqlite_reader* reader = &db->readers[reader_id];

    int rc;
    resqlite_cached_stmt* entry =
        get_or_prepare_reader(reader, sql, (int)strlen(sql), &rc);
    if (!entry) return NULL;
    sqlite3_stmt* stmt = entry->stmt;

    rc = bind_params(stmt, params, param_count, entry->param_count);
    if (rc != SQLITE_OK) {
        sqlite3_reset(stmt);
        return NULL;
    }

    return stmt;
}

// Acquire a statement on the writer connection without mutex.
// The caller (writer isolate) guarantees exclusive access.
sqlite3_stmt* resqlite_stmt_acquire_writer(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* params,
    int param_count
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return NULL;
    int rc;
    const char* tail;
    resqlite_cached_stmt* entry =
        get_or_prepare_writer(db, sql, (int)strlen(sql), &rc, &tail);
    if (!entry) return NULL;
    sqlite3_stmt* stmt = entry->stmt;

    rc = bind_params(stmt, params, param_count, entry->param_count);
    if (rc != SQLITE_OK) {
        sqlite3_reset(stmt);
        return NULL;
    }

    return stmt;
}

// ---------------------------------------------------------------------------
// Fast int64-to-string (avoids snprintf format parsing overhead)
// ---------------------------------------------------------------------------

__attribute__((hot)) static int fast_i64_to_str(long long val, char* buf) {
    if (val == 0) { buf[0] = '0'; return 1; }

    char tmp[21]; // max int64 is 20 digits + sign
    int pos = 0;
    int negative = 0;
    unsigned long long uval;

    if (val < 0) {
        negative = 1;
        uval = (unsigned long long)(-(val + 1)) + 1; // avoid UB on LLONG_MIN
    } else {
        uval = (unsigned long long)val;
    }

    while (uval > 0) {
        tmp[pos++] = '0' + (char)(uval % 10);
        uval /= 10;
    }

    int len = 0;
    if (negative) buf[len++] = '-';
    for (int i = pos - 1; i >= 0; i--) {
        buf[len++] = tmp[i];
    }
    return len;
}

// ---------------------------------------------------------------------------
// JSON output
// ---------------------------------------------------------------------------

static const char b64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Write a base64-encoded blob as a quoted JSON string.
__attribute__((hot)) static int json_write_base64(resqlite_buf* __restrict b,
                                                   const unsigned char* data,
                                                   int len) {
    // Output size: 4 chars per 3 bytes, rounded up, plus quotes.
    int encoded_len = ((len + 2) / 3) * 4;
    if (buf_write_char(b, '"') != 0) return -1;
    if (buf_ensure(b, encoded_len) != 0) return -1;

    unsigned char* out = b->data + b->len;
    int i = 0;

    // Process 3-byte groups.
    for (; i + 2 < len; i += 3) {
        unsigned int v = ((unsigned int)data[i] << 16) |
                         ((unsigned int)data[i + 1] << 8) |
                          (unsigned int)data[i + 2];
        *out++ = b64_table[(v >> 18) & 0x3F];
        *out++ = b64_table[(v >> 12) & 0x3F];
        *out++ = b64_table[(v >> 6)  & 0x3F];
        *out++ = b64_table[ v        & 0x3F];
    }

    // Remaining 1 or 2 bytes with padding.
    if (i < len) {
        unsigned int v = (unsigned int)data[i] << 16;
        if (i + 1 < len) v |= (unsigned int)data[i + 1] << 8;
        *out++ = b64_table[(v >> 18) & 0x3F];
        *out++ = b64_table[(v >> 12) & 0x3F];
        *out++ = (i + 1 < len) ? b64_table[(v >> 6) & 0x3F] : '=';
        *out++ = '=';
    }

    b->len += encoded_len;
    return buf_write_char(b, '"');
}

// Lookup table: maps each byte to its JSON escape string length (0 = safe).
// Entries: 2 = two-char escape (\", \\, \b, \f, \n, \r, \t), 6 = \uXXXX.
static const unsigned char json_esc_len[256] = {
    // 0x00-0x1F: control chars
    6,6,6,6,6,6,6,6, 2,2,2,6,2,2,6,6, // \b=08, \t=09, \n=0A, \f=0C, \r=0D
    6,6,6,6,6,6,6,6, 6,6,6,6,6,6,6,6,
    // 0x20-0x7F
    0,0,2,0,0,0,0,0, 0,0,0,0,0,0,0,0, // '"'=0x22 -> 2
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,2,0,0,0, // '\\'=0x5C -> 2
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    // 0x80-0xFF: all safe (UTF-8 continuation/lead bytes)
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
};

// Lookup table: maps escapable byte to its 2-char escape suffix.
static const char json_esc_char[256] = {
    ['"']  = '"',
    ['\\'] = '\\',
    ['\b'] = 'b',
    ['\f'] = 'f',
    ['\n'] = 'n',
    ['\r'] = 'r',
    ['\t'] = 't',
};

__attribute__((hot)) static int json_write_string(resqlite_buf* __restrict b, const char* s, int len) {
    if (buf_write_char(b, '"') != 0) return -1;

    int start = 0;
    int i = 0;

    // SWAR: scan 8 bytes at a time for the common case (no escapes needed).
    // Check if any byte < 0x20, == '"' (0x22), or == '\\' (0x5C).
    // Uses the standard "has zero byte" SWAR trick: for each target, XOR the
    // word with the repeated target byte, then detect zero bytes via
    // (v - 0x01..01) & ~v & 0x80..80. Pure portable C, no SIMD intrinsics.
    while (i + 8 <= len) {
        uint64_t word;
        memcpy(&word, s + i, 8);

        // Bytes < 0x20: subtract 0x20 from each byte, check for underflow.
        uint64_t below_space = (word - 0x2020202020202020ULL) & ~word & 0x8080808080808080ULL;
        // Bytes == '"' (0x22):
        uint64_t xor_quote = word ^ 0x2222222222222222ULL;
        uint64_t has_quote = (xor_quote - 0x0101010101010101ULL) & ~xor_quote & 0x8080808080808080ULL;
        // Bytes == '\\' (0x5C):
        uint64_t xor_bslash = word ^ 0x5C5C5C5C5C5C5C5CULL;
        uint64_t has_bslash = (xor_bslash - 0x0101010101010101ULL) & ~xor_bslash & 0x8080808080808080ULL;

        if ((below_space | has_quote | has_bslash) == 0) {
            i += 8; // All 8 bytes safe — skip.
            continue;
        }
        break; // Found something to escape — fall through to byte-by-byte.
    }

    // Byte-by-byte with lookup table for remaining bytes or after SWAR hit.
    for (; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        unsigned char elen = json_esc_len[c];

        if (__builtin_expect(elen == 0, 1)) continue; // Common case: safe byte.

        // Flush unescaped span before this character.
        if (i > start && buf_write(b, s + start, i - start) != 0) return -1;

        if (elen == 2) {
            // Named two-char escape: \X
            char pair[2] = { '\\', json_esc_char[c] };
            if (buf_write(b, pair, 2) != 0) return -1;
        } else {
            // \uXXXX for control chars without named escapes.
            char ubuf[7];
            snprintf(ubuf, sizeof(ubuf), "\\u%04x", c);
            if (buf_write(b, ubuf, 6) != 0) return -1;
        }
        start = i + 1;
    }

    // Flush remaining unescaped span.
    if (start < len && buf_write(b, s + start, len - start) != 0) return -1;

    return buf_write_char(b, '"');
}

// Macro to bail out of write_json_to_buf on OOM without leaking.
#define JSON_CHECK(expr) do { if ((expr) != 0) { rc = SQLITE_NOMEM; goto cleanup; } } while (0)

__attribute__((hot)) static int write_json_to_buf(sqlite3_stmt* stmt, resqlite_buf* b) {
    int col_count = sqlite3_column_count(stmt);

    // Stack-allocate for typical column counts (<=64), heap for larger.
    const char* _col_names_stack[64];
    int _col_name_lens_stack[64];
    const char** col_names = (col_count <= 64) ? _col_names_stack : NULL;
    int* col_name_lens = (col_count <= 64) ? _col_name_lens_stack : NULL;
    int col_names_init = 0;
    int row_index = 0;
    int rc;

    JSON_CHECK(buf_write_char(b, '['));
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (!col_names_init) {
            if (col_count > 64) {
                col_names = (const char**)malloc(col_count * sizeof(const char*));
                col_name_lens = (int*)malloc(col_count * sizeof(int));
                if (!col_names || !col_name_lens) {
                    rc = SQLITE_NOMEM;
                    goto cleanup;
                }
            }
            col_names_init = 1;
            for (int i = 0; i < col_count; i++) {
                col_names[i] = sqlite3_column_name(stmt, i);
                col_name_lens[i] = (int)strlen(col_names[i]);
            }
        }

        if (row_index > 0) JSON_CHECK(buf_write_char(b, ','));
        JSON_CHECK(buf_write_char(b, '{'));

        for (int i = 0; i < col_count; i++) {
            if (i > 0) JSON_CHECK(buf_write_char(b, ','));

            JSON_CHECK(json_write_string(b, col_names[i], col_name_lens[i]));
            JSON_CHECK(buf_write_char(b, ':'));

            int type = sqlite3_column_type(stmt, i);
            switch (type) {
                case SQLITE_NULL:
                    JSON_CHECK(buf_write_str(b, "null", 4));
                    break;
                case SQLITE_INTEGER: {
                    char num[24];
                    int num_len = fast_i64_to_str(
                        sqlite3_column_int64(stmt, i), num);
                    JSON_CHECK(buf_write_str(b, num, num_len));
                    break;
                }
                case SQLITE_FLOAT: {
                    char num[32];
                    int num_len = snprintf(num, sizeof(num), "%.17g",
                                           sqlite3_column_double(stmt, i));
                    JSON_CHECK(buf_write_str(b, num, num_len));
                    break;
                }
                case SQLITE_TEXT: {
                    // column_text MUST be called before column_bytes — calling
                    // bytes first can trigger an implicit type conversion that
                    // invalidates the text pointer.
                    const char* text = (const char*)sqlite3_column_text(stmt, i);
                    int text_len = sqlite3_column_bytes(stmt, i);
                    JSON_CHECK(json_write_string(b, text, text_len));
                    break;
                }
                case SQLITE_BLOB: {
                    int blob_len = sqlite3_column_bytes(stmt, i);
                    const unsigned char* blob =
                        (const unsigned char*)sqlite3_column_blob(stmt, i);
                    JSON_CHECK(json_write_base64(b, blob, blob_len));
                    break;
                }
                default:
                    JSON_CHECK(buf_write_str(b, "null", 4));
                    break;
            }
        }

        JSON_CHECK(buf_write_char(b, '}'));
        row_index++;
    }

    JSON_CHECK(buf_write_char(b, ']'));

cleanup:
    sqlite3_reset(stmt);
    if (col_count > 64) {
        free(col_names);
        free(col_name_lens);
    }

    if (rc == SQLITE_NOMEM) return rc;
    if (rc != SQLITE_DONE) return rc;

    return SQLITE_OK;
}

#undef JSON_CHECK

int resqlite_query_bytes(
    resqlite_db* db,
    int reader_id,
    const char* sql,
    const resqlite_param* params,
    int param_count,
    unsigned char** out_buf,
    int* out_len
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        *out_buf = NULL;
        *out_len = 0;
        return SQLITE_MISUSE;
    }
    if (reader_id < 0 || reader_id >= db->reader_count) {
        *out_buf = NULL;
        *out_len = 0;
        return SQLITE_BUSY;
    }
    resqlite_reader* reader = &db->readers[reader_id];

    int rc;
    resqlite_cached_stmt* entry =
        get_or_prepare_reader(reader, sql, (int)strlen(sql), &rc);
    if (!entry) {
        *out_buf = NULL;
        *out_len = 0;
        return rc;
    }
    sqlite3_stmt* stmt = entry->stmt;

    rc = bind_params(stmt, params, param_count, entry->param_count);
    if (rc != SQLITE_OK) {
        sqlite3_reset(stmt);
        *out_buf = NULL;
        *out_len = 0;
        return rc;
    }

    // Use persistent reader buffer — reset, no malloc/free per query.
    reader->json_buf.len = 0;

    rc = write_json_to_buf(stmt, &reader->json_buf);

    if (rc != SQLITE_OK) {
        *out_buf = NULL;
        *out_len = 0;
        return rc;
    }

    // Caller copies before next query. Dedicated reader guarantees this.
    *out_buf = reader->json_buf.data;
    *out_len = reader->json_buf.len;
    return SQLITE_OK;
}

// ---------------------------------------------------------------------------
// Batch row reader
// ---------------------------------------------------------------------------

__attribute__((hot)) int resqlite_step_row(
    sqlite3_stmt* stmt,
    int col_count,
    resqlite_cell* cells
) {
    int rc = sqlite3_step(stmt);
    if (__builtin_expect(rc != SQLITE_ROW, 0)) return rc;

    for (int i = 0; i < col_count; i++) {
        int type = sqlite3_column_type(stmt, i);
        cells[i].type = type;
        switch (type) {
            case SQLITE_INTEGER:
                cells[i].i = sqlite3_column_int64(stmt, i);
                break;
            case SQLITE_FLOAT:
                cells[i].d = sqlite3_column_double(stmt, i);
                break;
            case SQLITE_TEXT:
                cells[i].p = sqlite3_column_text(stmt, i);
                cells[i].len = sqlite3_column_bytes(stmt, i);
                break;
            case SQLITE_BLOB:
                cells[i].p = sqlite3_column_blob(stmt, i);
                cells[i].len = sqlite3_column_bytes(stmt, i);
                break;
            default:
                // SQLITE_NULL or unknown
                break;
        }
    }

    return SQLITE_ROW;
}

// ---------------------------------------------------------------------------
// Stream-hash helpers (experiment 075, was 053 on worktree)
//
// Hashing raw cell bytes in C using FNV-1a (63-bit masked) lets reactive
// streams short-circuit the "unchanged re-query" case without paying any
// Dart-side decode or allocation cost. Dart stores the hash as a plain
// int; on re-query, we hash-only, compare, and bail if matched.
//
// The hash lives entirely in C. Dart never touches a byte of the
// accumulator — it only gets the final int64 back through the return
// value. That's the contract.
// ---------------------------------------------------------------------------

#define RESQLITE_FNV_OFFSET_BASIS 0x4bf29ce484222325ULL  // 0xcbf29ce484222325 & 0x7FFF...
#define RESQLITE_FNV_MASK         0x7FFFFFFFFFFFFFFFULL
#define RESQLITE_FNV_PRIME        0x100000001B3ULL

static inline uint64_t fnv_combine_u64(uint64_t h, uint64_t v) {
    h ^= v;
    h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
    return h;
}

// Fold a byte buffer into the running hash.
static inline uint64_t fnv_combine_bytes(uint64_t h, const void* p, int len) {
    const unsigned char* b = (const unsigned char*)p;
    for (int i = 0; i < len; i++) {
        h ^= (uint64_t)b[i];
        h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
    }
    return h;
}

// Step-to-completion + hash every cell. Does NOT populate a Dart-visible
// cell buffer — hashing is the entire job. Resets the statement at both
// ends so the caller can invoke this whether the stmt was just bound
// (initial step) or had already been stepped through by decodeQuery.
//
// `last_row_count` is the caller's cached row count from the previous
// emission, or -1 if unknown (initial-query path; or when row_count is
// not being tracked). When set, experiment 077 short-circuits: if we
// step past `last_row_count` rows, the hashes CANNOT match regardless
// of content, so we stop hashing cell bytes and just count remaining
// rows to report the final size. `out_row_count` is written in all
// success paths so the caller can update its cached value.
//
// Returns the final hash (or -1 error sentinel). `row_count` is always
// folded LAST into the accumulator before return. On the fast-reject
// path the accumulator already holds per-cell fold work for the first
// `last_row_count` rows (everything seen before skip_hash flipped) —
// we still fold the fresh `row_count` on top, which by itself
// differentiates from the previous hash whenever the counts differ.
// Zero-row results return 0 directly (no row_count fold).
long long resqlite_query_hash(
    sqlite3_stmt* stmt, int last_row_count, int* out_row_count
) {
    // Start from a known state so callers don't have to coordinate:
    // - After stmt_acquire_on: reset is a no-op.
    // - After decodeQuery drained the stmt to SQLITE_DONE: real reset.
    // - After a prior call to this function (which also resets at end):
    //   no-op. Safe either way.
    sqlite3_reset(stmt);

    uint64_t h = RESQLITE_FNV_OFFSET_BASIS;
    int col_count = sqlite3_column_count(stmt);
    int row_count = 0;
    int rc;
    int skip_hash = 0;  // flips to 1 once we know count-differ is guaranteed

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        row_count++;
        // Experiment 077: once row_count exceeds last_row_count, the
        // final hash cannot possibly match (row_count is folded in at
        // the end). Stop hashing cell bytes; just drain rows for count.
        if (!skip_hash && last_row_count >= 0 && row_count > last_row_count) {
            skip_hash = 1;
        }
        if (skip_hash) continue;
        for (int i = 0; i < col_count; i++) {
            int type = sqlite3_column_type(stmt, i);
            h = fnv_combine_u64(h, (uint64_t)type);
            switch (type) {
                case SQLITE_INTEGER:
                    h = fnv_combine_u64(h, (uint64_t)sqlite3_column_int64(stmt, i));
                    break;
                case SQLITE_FLOAT: {
                    double d = sqlite3_column_double(stmt, i);
                    uint64_t bits; memcpy(&bits, &d, 8);
                    h = fnv_combine_u64(h, bits);
                    break;
                }
                case SQLITE_TEXT: {
                    const unsigned char* p = sqlite3_column_text(stmt, i);
                    int len = sqlite3_column_bytes(stmt, i);
                    h = fnv_combine_u64(h, (uint64_t)len);
                    h = fnv_combine_bytes(h, p, len);
                    break;
                }
                case SQLITE_BLOB: {
                    // sqlite3_column_blob returns const void*. Pass it
                    // through as-is — fnv_combine_bytes reinterprets
                    // internally; avoiding the const-qualified pointer
                    // cast keeps this clean under strict compiler flags.
                    const void* p = sqlite3_column_blob(stmt, i);
                    int len = sqlite3_column_bytes(stmt, i);
                    h = fnv_combine_u64(h, (uint64_t)len);
                    h = fnv_combine_bytes(h, p, len);
                    break;
                }
            }
        }
    }

    sqlite3_reset(stmt);
    *out_row_count = row_count;

    if (rc != SQLITE_DONE) {
        // Error sentinel. Chosen negative so it lives outside the 63-bit
        // non-negative domain of real hashes — guaranteed not to collide
        // with any `lastResultHash` a caller might store, which would
        // otherwise (vanishingly-rarely) take the "unchanged" fast-path
        // and swallow the error silently.
        return -1;
    }
    // Fold row_count into the accumulator before returning. This keeps
    // results with identical per-row content but different row counts
    // from colliding, covering both the fast-reject path (more rows
    // than last time — `h` contains fold work for just the first
    // `last_row_count` rows) and the under-count case (fewer rows
    // than last time — `h` contains fold work for every row we saw).
    // In both cases the differing `row_count` fold at the tail pushes
    // the hash away from the previous emission's value, so the
    // caller's `hash != last_hash` check fires and the decode path
    // runs. Zero-row result is the special case: returns 0 directly.
    if (row_count == 0) return 0;
    h = fnv_combine_u64(h, (uint64_t)row_count);
    return (long long)h;
}

__attribute__((hot)) int resqlite_step_row_hash(
    sqlite3_stmt* stmt,
    int col_count,
    resqlite_cell* cells,
    uint64_t* hash
) {
    int rc = sqlite3_step(stmt);
    if (__builtin_expect(rc != SQLITE_ROW, 0)) return rc;

    uint64_t h = *hash;
    for (int i = 0; i < col_count; i++) {
        int type = sqlite3_column_type(stmt, i);
        cells[i].type = type;
        h = fnv_combine_u64(h, (uint64_t)type);
        switch (type) {
            case SQLITE_INTEGER: {
                sqlite3_int64 v = sqlite3_column_int64(stmt, i);
                cells[i].i = v;
                h = fnv_combine_u64(h, (uint64_t)v);
                break;
            }
            case SQLITE_FLOAT: {
                double d = sqlite3_column_double(stmt, i);
                uint64_t bits; memcpy(&bits, &d, 8);
                cells[i].d = d;
                h = fnv_combine_u64(h, bits);
                break;
            }
            case SQLITE_TEXT: {
                const unsigned char* p = sqlite3_column_text(stmt, i);
                int len = sqlite3_column_bytes(stmt, i);
                cells[i].p = p;
                cells[i].len = len;
                h = fnv_combine_u64(h, (uint64_t)len);
                h = fnv_combine_bytes(h, p, len);
                break;
            }
            case SQLITE_BLOB: {
                const void* p = sqlite3_column_blob(stmt, i);
                int len = sqlite3_column_bytes(stmt, i);
                cells[i].p = p;
                cells[i].len = len;
                h = fnv_combine_u64(h, (uint64_t)len);
                h = fnv_combine_bytes(h, p, len);
                break;
            }
            default:
                // SQLITE_NULL or unknown.
                break;
        }
    }
    *hash = h;
    return SQLITE_ROW;
}

void resqlite_free(void* ptr) {
    free(ptr);
}
