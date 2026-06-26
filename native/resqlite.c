#include "resqlite.h"
#include "resqlite_deps.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include <math.h>

#if defined(_MSC_VER)
#define RESQLITE_HOT
#else
#define RESQLITE_HOT __attribute__((hot))
#endif

#if defined(__GNUC__) || defined(__clang__)
#define RESQLITE_LIKELY(expr) __builtin_expect(!!(expr), 1)
#define RESQLITE_UNLIKELY(expr) __builtin_expect(!!(expr), 0)
#else
#define RESQLITE_LIKELY(expr) (expr)
#define RESQLITE_UNLIKELY(expr) (expr)
#endif

// Forward declarations.
static int bind_params(sqlite3_stmt* stmt, const resqlite_param* params,
                       int param_count, int expected);
static int run_setup_sql(
    sqlite3* db,
    const char* sql,
    const resqlite_param* params,
    int param_count
);

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

RESQLITE_HOT static int buf_ensure(resqlite_buf* b, int extra) {
    if (RESQLITE_LIKELY(b->len + extra <= b->cap)) return 0;
    int new_cap = b->cap;
    while (new_cap < b->len + extra) new_cap *= 2;
    unsigned char* p = (unsigned char*)realloc(b->data, new_cap);
    if (!p) return -1;
    b->data = p;
    b->cap = new_cap;
    return 0;
}

RESQLITE_HOT static int buf_write(resqlite_buf* __restrict b, const void* __restrict src, int n) {
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

static char* resqlite_strdup(const char* s) {
    size_t len = strlen(s) + 1;
    char* copy = (char*)malloc(len);
    if (!copy) return NULL;
    memcpy(copy, s, len);
    return copy;
}

// ---------------------------------------------------------------------------
// Statement cache (per connection)
// ---------------------------------------------------------------------------

#define STMT_CACHE_MAX 32

// [EXP-106](../experiments/106-column-level-deps.md): column-level dependency
// tracking. Columns are stored as structured table/column pairs; the wildcard
// column `"*"` is used for INSERT/DELETE writes and for authorizer events that
// arrive without a column name (triggers, views).

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
    // [EXP-106](../experiments/106-column-level-deps.md) polish: 1 if
    // `read_tables[]` is the complete dependency set captured by the
    // authorizer; 0 if any resqlite_read_set_add during prepare overflowed /
    // OOMed / strdup-failed, or if copying the captured set into this cache
    // entry failed.
    // When 0, `resqlite_get_read_tables` returns
    // RESQLITE_DEPENDENCY_COUNT_UNKNOWN so the StreamEngine routes the stream
    // into its unknown-dependencies bucket.
    int read_tables_reliable;
    // [EXP-106](../experiments/106-column-level-deps.md): per-stmt column
    // dependencies (reader: SELECT/WHERE columns from authorizer SQLITE_READ
    // events; writer: SET columns from authorizer SQLITE_UPDATE events). For
    // writers, INSERT/DELETE leave a "*" column sentinel because the authorizer
    // fires SQLITE_INSERT / SQLITE_DELETE without a column.
    resqlite_column_dep dep_columns[RESQLITE_MAX_DEP_COLUMNS];
    int dep_column_count;
    // [EXP-106](../experiments/106-column-level-deps.md) polish: 1 if
    // `dep_columns[]` is the complete dependency set; 0 on any capture/copy
    // failure. When 0, the column getters return 0 entries, so Dart builds a
    // plain table-level dependency and skips column elision.
    int dep_columns_reliable;
    // [EXP-195] Cached JSON column-name tokens (extends exp 190's per-query
    // token amortization across re-executions of the same prepared SQL).
    // Built lazily on the first `write_json_to_buf` call against this entry;
    // each token is `"name":` for column 0 or `,"name":` for columns 1+.
    // Subsequent `selectBytes()` calls on the same cached stmt reuse this
    // buffer and skip exp 190's per-query `buf_init` + first-row pre-encode
    // loop. NULL until built; cleared in `stmt_cache_entry_dispose`.
    unsigned char* json_name_tokens_buf;
    int json_name_tokens_len;
    int* json_name_token_offsets;
    int* json_name_token_lens;
    // 0 until the tokens are built; otherwise equals the column count seen
    // at build time. The cached prepared stmt's column count never changes
    // across re-executions, so this also serves as a "tokens ready" flag.
    int json_name_tokens_col_count;
} resqlite_cached_stmt;

typedef struct {
    resqlite_cached_stmt entries[STMT_CACHE_MAX];
    int count;
} resqlite_stmt_cache;

static void stmt_cache_init(resqlite_stmt_cache* c) {
    c->count = 0;
    memset(c->entries, 0, sizeof(c->entries));
}

static void stmt_cache_entry_clear_read_tables(resqlite_cached_stmt* entry) {
    resqlite_string_array_clear(entry->read_tables, &entry->read_table_count);
}

static void stmt_cache_entry_clear_dep_columns(resqlite_cached_stmt* entry) {
    resqlite_column_dep_array_clear(entry->dep_columns, &entry->dep_column_count);
}

// [EXP-195] Free cached JSON column-name token buffers and reset the
// "tokens built" flag. Safe to call on a never-built entry — all three
// pointers default to NULL via memset in stmt_cache_entry_init.
static void stmt_cache_entry_clear_json_name_tokens(resqlite_cached_stmt* entry) {
    free(entry->json_name_tokens_buf);
    free(entry->json_name_token_offsets);
    free(entry->json_name_token_lens);
    entry->json_name_tokens_buf = NULL;
    entry->json_name_token_offsets = NULL;
    entry->json_name_token_lens = NULL;
    entry->json_name_tokens_len = 0;
    entry->json_name_tokens_col_count = 0;
}

static void stmt_cache_entry_dispose(resqlite_cached_stmt* entry) {
    if (entry->stmt) sqlite3_finalize(entry->stmt);
    free(entry->sql);
    stmt_cache_entry_clear_read_tables(entry);
    stmt_cache_entry_clear_dep_columns(entry);
    stmt_cache_entry_clear_json_name_tokens(entry);
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

static void stmt_cache_entry_set_read_tables(resqlite_cached_stmt* entry,
                                             const resqlite_read_set* read_tables) {
    stmt_cache_entry_clear_read_tables(entry);
    // [EXP-106](../experiments/106-column-level-deps.md) polish: source set
    // reliability caps the entry's.
    // If unreliable, drop entries and mark the cache entry too — the
    // FFI getter will return RESQLITE_DEPENDENCY_COUNT_UNKNOWN so StreamEngine
    // routes the stream into the unknown-dependencies bucket.
    entry->read_tables_reliable = read_tables->reliable;
    if (!read_tables->reliable) return;

    if (resqlite_string_array_copy(entry->read_tables, RESQLITE_MAX_READ_TABLES,
                                   &entry->read_table_count,
                                   (char* const*)read_tables->names,
                                   read_tables->count) != 0) {
        entry->read_tables_reliable = 0;
    }
}

static void stmt_cache_entry_set_dep_columns(resqlite_cached_stmt* entry,
                                             const resqlite_column_set* cols) {
    stmt_cache_entry_clear_dep_columns(entry);
    // [EXP-106](../experiments/106-column-level-deps.md) polish: the source
    // set's reliability is the cap.
    // If it is already 0, the cache entry exposes no column metadata
    // and dispatching consumers route to the conservative re-query path.
    entry->dep_columns_reliable = cols->reliable;

    if (!cols->reliable) return;

    if (resqlite_column_dep_array_copy_from_set(
            entry->dep_columns, RESQLITE_MAX_DEP_COLUMNS,
            &entry->dep_column_count, cols) != 0) {
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
    // [EXP-106](../experiments/106-column-level-deps.md): per-reader column
    // dependency capture. The authorizer populates this set during prepare; on
    // cache hit the column getter reads directly from the cached stmt entry
    // instead of rehydrating per-call (avoids strdup-per-column on the read hot
    // path).
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
    // Set by the reader's worker isolate around each request
    // (resqlite_reader_set_busy) so resqlite_db_status_total never reads
    // this NOMUTEX connection while the worker is using it. The legacy
    // acquire-path `in_use` is dead under dedicated assignment (exp 030).
    atomic_int worker_busy;
} resqlite_reader;

// ---------------------------------------------------------------------------
// Connection pool
// ---------------------------------------------------------------------------

#define MAX_READERS 16

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

    // Persistently prepared transaction-control statements
    // ([EXP-101](../experiments/101-tx-stmt-cache.md)).
    // The writer fires these on every transaction boundary; preparing them
    // once eliminates the prepare+step+finalize cost of `sqlite3_exec` for
    // each call. Held outside writer_cache so they never compete with user
    // statements for cache slots.
    sqlite3_stmt* tx_begin_stmt;
    sqlite3_stmt* tx_commit_stmt;
    sqlite3_stmt* tx_rollback_stmt;

    // Dirty tables accumulated by the preupdate hook.
    resqlite_dirty_set dirty_tables;
    // [EXP-106](../experiments/106-column-level-deps.md): dirty columns
    // accumulated alongside dirty tables.
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

    char setup_error[512];
    char* path;
};

#define RESQLITE_WRITER_PASSIVE_CHECKPOINT_PAGES 500

// ---------------------------------------------------------------------------
// Authorizer callback — records read tables/columns (stream deps) or, on
// the writer, modified tables/columns (dispatch elision in
// [EXP-106](../experiments/106-column-level-deps.md))
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
                if (ctx->tables) resqlite_read_set_add(ctx->tables, arg1);
                // Only reader contexts care about the read-column set —
                // the writer authorizer collects dirty columns for
                // SQLITE_UPDATE/INSERT/DELETE only. Capturing reads on
                // the writer would pollute its scratch with the columns
                // touched by tx-scoped SELECTs.
                if (ctx->columns && !ctx->track_writes) {
                    resqlite_column_set_add(ctx->columns, arg1, arg2);
                }
            }
            break;
        case SQLITE_UPDATE:
            if (ctx->track_writes && arg1 != NULL && ctx->columns) {
                // arg2 is the column being SET; capture exactly that.
                resqlite_column_set_add(ctx->columns, arg1, arg2);
            }
            break;
        case SQLITE_INSERT:
        case SQLITE_DELETE:
            if (ctx->track_writes && arg1 != NULL && ctx->columns) {
                // No column info from SQLite for INSERT/DELETE — emit a
                // wildcard sentinel so the dispatch path knows to skip
                // the column-intersection optimisation for this table.
                resqlite_column_set_add(ctx->columns, arg1, "*");
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

static void dirty_columns_add_for_active_stmt(resqlite_db* sdb,
                                              const char* table_name) {
    if (!table_name) {
        sdb->dirty_columns.reliable = 0;
        return;
    }

    resqlite_cached_stmt* entry = sdb->writer_active_entry;
    if (!entry) {
        resqlite_column_set_add(&sdb->dirty_columns, table_name, "*");
        return;
    }

    if (!entry->dep_columns_reliable) {
        sdb->dirty_columns.reliable = 0;
        return;
    }

    int table_name_len = (int)strlen(table_name);
    for (int i = 0; i < entry->dep_column_count; i++) {
        const char* column = NULL;
        if (resqlite_column_dep_belongs_to_table(&entry->dep_columns[i],
                                                 table_name, table_name_len,
                                                 &column)) {
            resqlite_column_set_add(&sdb->dirty_columns, table_name, column);
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
    resqlite_dirty_set_add(&sdb->dirty_tables, table_name);
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
    // FKs default off in SQLite. Turn on for every connection so cascades
    // and constraints behave as users coming from other ORMs expect. Users
    // who need it off (e.g. mid-migration) can run
    // `PRAGMA foreign_keys = OFF` on the writer.
    sqlite3_exec(db, "PRAGMA foreign_keys = ON", NULL, NULL, NULL);
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

static resqlite_db* resqlite_open_impl(const char* path, int max_readers,
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
    db->path = resqlite_strdup(path);
    stmt_cache_init(&db->writer_cache);
    resqlite_dirty_set_init(&db->dirty_tables);
    resqlite_column_set_init(&db->dirty_columns);
    resqlite_column_set_init(&db->writer_authz_scratch);
    db->writer_active_entry = NULL;
    db->writer_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);
    db->pool_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);

    // Pre-prepare transaction-control stmts
    // ([EXP-101](../experiments/101-tx-stmt-cache.md)). These are
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

    // [EXP-106](../experiments/106-column-level-deps.md): install authorizer on
    // the writer to capture which columns each prepared DML stmt could modify.
    // The authorizer fires inside `sqlite3_prepare_v3`; we drain
    // `writer_authz_scratch` into the cached stmt entry as soon as prepare
    // returns. With `track_writes` set on the writer, SQLITE_READ events are
    // ignored; read dependencies are captured by the reader authorizers below.
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
        resqlite_read_set_init(&db->readers[idx].read_tables);
        resqlite_column_set_init(&db->readers[idx].read_columns);
        db->readers[idx].last_entry = NULL;
        if (buf_init(&db->readers[idx].json_buf, 16384) != 0) {
            sqlite3_close_v2(rdb);
            db->readers[idx].db = NULL;
            continue;
        }
        db->readers[idx].in_use = 0;
        atomic_init(&db->readers[idx].worker_busy, 0);

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

resqlite_db* resqlite_open(const char* path, int max_readers,
                           const char* encryption_key_hex) {
    return resqlite_open_with_extensions(
        path, max_readers, encryption_key_hex, NULL, 0);
}

resqlite_db* resqlite_open_with_extensions(
    const char* path,
    int max_readers,
    const char* encryption_key_hex,
    void** extension_entrypoints,
    int extension_count
) {
    if (extension_count < 0) return NULL;
    if (extension_count == 0) {
        return resqlite_open_impl(path, max_readers, encryption_key_hex);
    }
    if (!extension_entrypoints) return NULL;

    void** unique_entrypoints = (void**)calloc(
        (size_t)extension_count,
        sizeof(void*)
    );
    if (!unique_entrypoints) return NULL;

    // Required when compiled with SQLITE_OMIT_AUTOINIT. We also need SQLite's
    // mutex subsystem before taking the application mutex below.
    sqlite3_initialize();

    // sqlite3_auto_extension() is process-global for this SQLite image. Hold
    // an application mutex across register/open/cancel so concurrent resqlite
    // opens cannot observe each other's temporary extension list.
    sqlite3_mutex* mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_STATIC_APP1);
    if (mutex) sqlite3_mutex_enter(mutex);

    int rc = SQLITE_OK;
    int unique_count = 0;
    for (int i = 0; i < extension_count; i++) {
        if (!extension_entrypoints[i]) {
            rc = SQLITE_MISUSE;
            break;
        }
        int seen = 0;
        for (int j = 0; j < unique_count; j++) {
            if (unique_entrypoints[j] == extension_entrypoints[i]) {
                seen = 1;
                break;
            }
        }
        if (seen) continue;
        rc = sqlite3_auto_extension((void(*)(void))extension_entrypoints[i]);
        if (rc != SQLITE_OK) break;
        // Keep a private scratch list so direct C callers retain ownership of
        // their pointer array unchanged.
        unique_entrypoints[unique_count] = extension_entrypoints[i];
        unique_count++;
    }

    resqlite_db* db = NULL;
    if (rc == SQLITE_OK) {
        db = resqlite_open_impl(path, max_readers, encryption_key_hex);
    }

    for (int i = 0; i < unique_count; i++) {
        sqlite3_cancel_auto_extension(
            (void(*)(void))unique_entrypoints[i]);
    }

    if (mutex) sqlite3_mutex_leave(mutex);
    free(unique_entrypoints);
    return rc == SQLITE_OK ? db : NULL;
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
        resqlite_read_set_free(&db->readers[i].read_tables);
        resqlite_column_set_free(&db->readers[i].read_columns);
        if (db->readers[i].json_buf.data) free(db->readers[i].json_buf.data);
        sqlite3_close_v2(db->readers[i].db);
    }

    // Close writer.
    sqlite3_mutex_enter(db->writer_mutex);
    stmt_cache_clear(&db->writer_cache);
    if (db->tx_begin_stmt) sqlite3_finalize(db->tx_begin_stmt);
    if (db->tx_commit_stmt) sqlite3_finalize(db->tx_commit_stmt);
    if (db->tx_rollback_stmt) sqlite3_finalize(db->tx_rollback_stmt);
    resqlite_dirty_set_free(&db->dirty_tables);
    resqlite_column_set_free(&db->dirty_columns);
    resqlite_column_set_free(&db->writer_authz_scratch);
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
    if (db->setup_error[0] != '\0') {
        return db->setup_error;
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

static void set_setup_error(
    resqlite_db* db,
    const char* role,
    int index,
    sqlite3* connection
) {
    const char* detail = sqlite3_errmsg(connection);
    if (index >= 0) {
        snprintf(db->setup_error, sizeof(db->setup_error),
                 "%s connection %d: %s", role, index, detail);
    } else {
        snprintf(db->setup_error, sizeof(db->setup_error),
                 "%s connection: %s", role, detail);
    }
}

static void set_setup_error_message(
    resqlite_db* db,
    const char* role,
    int index,
    const char* detail
) {
    if (index >= 0) {
        snprintf(db->setup_error, sizeof(db->setup_error),
                 "%s connection %d: %s", role, index, detail);
    } else {
        snprintf(db->setup_error, sizeof(db->setup_error),
                 "%s connection: %s", role, detail);
    }
}

int resqlite_run_connection_setup(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* params,
    int param_count,
    int scope
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire) || !sql) {
        return SQLITE_MISUSE;
    }
    if (param_count < 0) return SQLITE_MISUSE;
    if (param_count > 0 && !params) return SQLITE_MISUSE;

    switch (scope) {
        case RESQLITE_SETUP_SCOPE_ALL:
        case RESQLITE_SETUP_SCOPE_WRITER:
        case RESQLITE_SETUP_SCOPE_READERS:
            break;
        default:
            return SQLITE_MISUSE;
    }

    db->setup_error[0] = '\0';
    int rc = SQLITE_OK;
    if (scope == RESQLITE_SETUP_SCOPE_ALL ||
        scope == RESQLITE_SETUP_SCOPE_WRITER) {
        sqlite3_mutex_enter(db->writer_mutex);
        rc = run_setup_sql(db->writer, sql, params, param_count);
        sqlite3_mutex_leave(db->writer_mutex);
        if (rc != SQLITE_OK) {
            if (rc == SQLITE_MISUSE) {
                set_setup_error_message(
                    db, "writer", -1,
                    "setup SQL must contain exactly one statement");
            } else {
                set_setup_error(db, "writer", -1, db->writer);
            }
            return rc;
        }
        // Setup happens before Dart workers and streams exist. Do not let
        // setup DDL/DML leak into the first user-visible write invalidation.
        resqlite_dirty_set_reset(&db->dirty_tables);
        resqlite_column_set_reset(&db->dirty_columns);
        resqlite_column_set_reset(&db->writer_authz_scratch);
        db->writer_active_entry = NULL;
    }

    if (scope == RESQLITE_SETUP_SCOPE_ALL ||
        scope == RESQLITE_SETUP_SCOPE_READERS) {
        for (int i = 0; i < db->reader_count; i++) {
            rc = run_setup_sql(db->readers[i].db, sql, params, param_count);
            if (rc != SQLITE_OK) {
                if (rc == SQLITE_MISUSE) {
                    set_setup_error_message(
                        db, "reader", i,
                        "setup SQL must contain exactly one statement");
                } else {
                    set_setup_error(db, "reader", i, db->readers[i].db);
                }
                return rc;
            }
        }
    }

    db->setup_error[0] = '\0';
    return SQLITE_OK;
}

// Run one of the cached transaction-control statements on the writer
// ([EXP-101](../experiments/101-tx-stmt-cache.md)). Caller is responsible for
// any required mutex.
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
// expected count ([EXP-077](../experiments/077-cheap-check-first-sweep.md)).
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

    // [EXP-106](../experiments/106-column-level-deps.md): reset the authorizer
    // scratch column set so this prepare's authorizer events accumulate
    // cleanly. The writer mutex serialises this access.
    resqlite_column_set_reset(&db->writer_authz_scratch);

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

    // [EXP-106](../experiments/106-column-level-deps.md): tag the active stmt
    // entry so the preupdate hook can merge its pre-captured column set into
    // `dirty_columns` on each per-row firing. Cleared after step so unrelated
    // callers (e.g. trigger bodies driven by sqlite3_exec) fall back to the
    // wildcard path.
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
        resqlite_column_set_reset(&db->writer_authz_scratch);
        int rc = sqlite3_prepare_v3(
            db->writer, sql, -1, SQLITE_PREPARE_PERSISTENT, &stmt, NULL);
        if (rc != SQLITE_OK) return rc;
        entry =
            stmt_cache_insert(&db->writer_cache, sql, (int)strlen(sql), stmt);
        if (!entry) {
            sqlite3_finalize(stmt);
            return SQLITE_NOMEM;
        }
        // [EXP-106](../experiments/106-column-level-deps.md): drain authz
        // scratch into the cache entry once prepare returns. The per-set step
        // loop below benefits from the pre-captured column set on every row.
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

        // [EXP-106](../experiments/106-column-level-deps.md): tag the active
        // entry so the preupdate hook can merge cached columns. Cleared after
        // step on every iteration.
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
    // ([EXP-101](../experiments/101-tx-stmt-cache.md)).
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

// Polish (post-2026-04): returns RESQLITE_DEPENDENCY_COUNT_UNKNOWN when
// the dirty-table set is unreliable (overflow / OOM during the write cycle).
// Zero would mean "no tables dirty" — invalidations would be silently missed;
// the negative sentinel forces the StreamEngine to invalidate every active
// entry.
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
        resqlite_dirty_set_reset(&db->dirty_tables);
        return RESQLITE_DEPENDENCY_COUNT_UNKNOWN;
    }

    int count = db->dirty_tables.count;
    if (count > max_tables) count = max_tables;

    // Copy pointers — caller must read strings before the next call.
    for (int i = 0; i < count; i++) {
        out_tables[i] = db->dirty_tables.names[i];
    }

    // Reset active count. Strings stay valid — out_tables still points to them.
    // They'll be freed on the next resqlite_dirty_set_add when slots are reused.
    resqlite_dirty_set_reset(&db->dirty_tables);

    return count;
}

void resqlite_reader_set_busy(resqlite_db* db, int reader_id, int busy) {
    if (!db || reader_id < 0 || reader_id >= db->reader_count) return;
    atomic_store_explicit(&db->readers[reader_id].worker_busy, busy,
                          memory_order_release);
}

// [EXP-183] Total bytes currently retained by every reader's persistent
// `json_buf`. The buffer grows via `buf_ensure` (realloc-doubling, exp 022)
// to fit the largest result, and never shrinks under the current policy.
// Exposing the high-water lets `Database.diagnostics()` quantify the bounded
// RSS cost exp 174 left as a known trade-off (`selectBytes` view transfer
// stops sacrificing readers, so `json_buf` plateaus at the largest result's
// size per reader). A diagnostic-only read; safe to call concurrently with
// reader activity because `cap` is an `int` and tearing only widens an
// already-bounded summary number.
long long resqlite_reader_json_buf_total(resqlite_db* db) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
    long long total = 0;
    for (int i = 0; i < db->reader_count; i++) {
        total += (long long)db->readers[i].json_buf.cap;
    }
    return total;
}

// [EXP-183] High-threshold reclaim for the reader's persistent `json_buf`.
// Called by the reader worker isolate AFTER `eventPort.send` returns on a
// `SelectBytesRequest` — at that point `SendPort.send` has already
// snapshotted the bytes into the receiver, so the native buffer is safe to
// realloc. The caller passes `last_used_len` (this request's result size);
// the shrink fires only when the buffer is much larger than the last
// produced result, so back-to-back large queries don't churn realloc.
//
// Thresholds:
//   - SHRINK_TRIGGER_CAP  (>= 1 MB cap): below this, leave warm buffers alone
//   - LAST_LEN_GUARD      (< 256 KB result): above this the workload is
//                          actively using the larger capacity; keep it
//   - SHRINK_TARGET_CAP   (16 KB initial): the size the buffer started at;
//                          subsequent queries `buf_ensure`-grow from here
//
// Realloc failure leaves the existing buffer intact — the old (larger)
// capacity is still functional, just memory not reclaimed. Returns the
// post-call capacity for diagnostics.
#define RESQLITE_JSON_BUF_SHRINK_TRIGGER_CAP (1 << 20)   // 1 MB
#define RESQLITE_JSON_BUF_LAST_LEN_GUARD     (256 << 10) // 256 KB
#define RESQLITE_JSON_BUF_SHRINK_TARGET_CAP  (16 << 10)  // 16 KB (matches buf_init)
int resqlite_reader_maybe_shrink_json_buf(
    resqlite_db* db, int reader_id, int last_used_len
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
    if (reader_id < 0 || reader_id >= db->reader_count) return 0;
    resqlite_reader* reader = &db->readers[reader_id];
    if (reader->json_buf.cap <= RESQLITE_JSON_BUF_SHRINK_TRIGGER_CAP) {
        return reader->json_buf.cap;
    }
    if (last_used_len >= RESQLITE_JSON_BUF_LAST_LEN_GUARD) {
        return reader->json_buf.cap;
    }
    unsigned char* p = (unsigned char*)realloc(
        reader->json_buf.data, RESQLITE_JSON_BUF_SHRINK_TARGET_CAP
    );
    if (!p) return reader->json_buf.cap;
    reader->json_buf.data = p;
    reader->json_buf.cap = RESQLITE_JSON_BUF_SHRINK_TARGET_CAP;
    reader->json_buf.len = 0;
    return reader->json_buf.cap;
}

// Polish (post-2026-04): returns RESQLITE_DEPENDENCY_COUNT_UNKNOWN when
// the cached entry's read-table dependencies are unreliable (overflow / OOM
// during prepare). Zero would mean "stream has no table deps" → silent stuck
// stream; the negative sentinel forces the Dart-side StreamEngine to route the
// stream into its unknown-dependencies bucket where every write invalidates it.
int resqlite_get_read_tables(
    resqlite_db* db,
    int reader_id,
    const char** out_tables,
    int max_tables
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
    if (reader_id < 0 || reader_id >= db->reader_count) return 0;

    resqlite_reader* reader = &db->readers[reader_id];
    // [EXP-106](../experiments/106-column-level-deps.md): serve directly from
    // the cached stmt entry of the most recent acquire so we don't pay the
    // strdup-per-table cost that the per-reader scratch incurred on every cache
    // hit. The entry's strings outlive this call (they're freed on stmt cache
    // eviction), so the caller's copy-before-next-query contract is unchanged.
    resqlite_cached_stmt* entry = reader->last_entry;
    if (!entry) return 0;
    if (!entry->read_tables_reliable) return RESQLITE_DEPENDENCY_COUNT_UNKNOWN;
    int count = entry->read_table_count;
    if (count > max_tables) count = max_tables;
    for (int i = 0; i < count; i++) {
        out_tables[i] = entry->read_tables[i];
    }
    return count;
}

// [EXP-106](../experiments/106-column-level-deps.md): return read-column
// metadata for the most recent acquired statement on this reader. Entries are
// structured table/column pairs owned by the cached stmt entry; the caller MUST
// copy them before issuing the next query on this reader.
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
    const char** out_tables,
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
        out_tables[i] = entry->dep_columns[i].table;
        out_columns[i] = entry->dep_columns[i].column;
    }
    return count;
}

// [EXP-106](../experiments/106-column-level-deps.md): drain the dirty-columns
// accumulator alongside dirty tables. Returns the number of table/column pairs
// written. Like
// `resqlite_get_dirty_tables`, the strings stay valid until the next
// `resqlite_column_set_add` reuses their slot — caller must copy before
// further writer activity.
//
// Polish (post-2026-04): when the dirty-columns set is unreliable
// (overflow / OOM during preupdate hook merge), returns 0 so the
// StreamEngine sees "no precise column metadata" and falls back to
// dispatching on the (still-reliable) dirty table set.
int resqlite_get_dirty_columns(
    resqlite_db* db,
    const char** out_tables,
    const char** out_columns,
    int max_columns
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;

    int reliable = db->dirty_columns.reliable;
    int count = reliable ? db->dirty_columns.count : 0;
    if (count > max_columns) count = max_columns;

    for (int i = 0; i < count; i++) {
        out_tables[i] = db->dirty_columns.deps[i].table;
        out_columns[i] = db->dirty_columns.deps[i].column;
    }

    resqlite_column_set_reset(&db->dirty_columns);

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
        if (db->readers[i].in_use ||
            atomic_load_explicit(&db->readers[i].worker_busy,
                                 memory_order_acquire)) {
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
// callers pass `entry->param_count` as the expected count
// ([EXP-077](../experiments/077-cheap-check-first-sweep.md)).
static resqlite_cached_stmt* get_or_prepare_reader(
    resqlite_reader* reader, const char* sql, int sql_len, int* out_rc
) {
    resqlite_cached_stmt* entry =
        stmt_cache_lookup_entry(&reader->cache, sql, sql_len);
    if (entry) {
        sqlite3_reset(entry->stmt);
        // [EXP-106](../experiments/106-column-level-deps.md): tag the active
        // entry so the FFI getters can serve table/column dependencies straight
        // from the cache (no strdup-per-column rehydrate on the read hot path).
        // Avoids the wide-schema main-thread regression spotted on first run.
        reader->last_entry = entry;
        *out_rc = SQLITE_OK;
        return entry;
    }

    // The authorizer populates per-reader read tables during prepare.
    // Reset before preparing so this statement captures only its own deps.
    resqlite_read_set_reset(&reader->read_tables);
    resqlite_column_set_reset(&reader->read_columns);

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

static int has_non_empty_tail(const char* tail) {
    if (!tail) return 0;
    while (*tail == ' ' || *tail == '\t' || *tail == '\n' ||
           *tail == '\r' || *tail == ';') {
        tail++;
    }
    return *tail != '\0';
}

static int run_setup_sql(
    sqlite3* db,
    const char* sql,
    const resqlite_param* params,
    int param_count
) {
    sqlite3_stmt* stmt = NULL;
    const char* tail = NULL;
    int rc = sqlite3_prepare_v3(db, sql, -1, 0, &stmt, &tail);
    if (rc != SQLITE_OK) return rc;
    if (!stmt) return SQLITE_MISUSE;

    if (has_non_empty_tail(tail)) {
        sqlite3_finalize(stmt);
        return SQLITE_MISUSE;
    }

    rc = bind_params(
        stmt, params, param_count, sqlite3_bind_parameter_count(stmt));
    if (rc != SQLITE_OK) {
        sqlite3_finalize(stmt);
        return rc;
    }

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {}

    int finalize_rc = sqlite3_finalize(stmt);
    if (rc != SQLITE_DONE) return rc;
    return finalize_rc == SQLITE_OK ? SQLITE_OK : finalize_rc;
}

// Caller provides `expected` — it's a property of the prepared SQL and
// the cache tracks it alongside the stmt
// ([EXP-077](../experiments/077-cheap-check-first-sweep.md)). Saves one
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

// Two-digit lookup table for the int64-to-string fast path: one division and
// one 2-byte memcpy per pair of output digits. Halves the division count vs
// the single-digit loop exp 023 introduced.
static const char kTwoDigits[200] =
    "0001020304050607080910111213141516171819"
    "2021222324252627282930313233343536373839"
    "4041424344454647484950515253545556575859"
    "6061626364656667686970717273747576777879"
    "8081828384858687888990919293949596979899";

RESQLITE_HOT static int fast_i64_to_str(long long val, char* buf) {
    if (val == 0) { buf[0] = '0'; return 1; }

    // Unsigned int64 magnitude fits in 20 decimal digits.
    char tmp[20];
    int pos = 20;
    int negative = 0;
    unsigned long long uval;

    if (val < 0) {
        negative = 1;
        uval = (unsigned long long)(-(val + 1)) + 1; // avoid UB on LLONG_MIN
    } else {
        uval = (unsigned long long)val;
    }

    while (uval >= 100) {
        unsigned d = (unsigned)(uval % 100);
        uval /= 100;
        pos -= 2;
        memcpy(tmp + pos, kTwoDigits + d * 2, 2);
    }
    if (uval >= 10) {
        unsigned d = (unsigned)uval;
        pos -= 2;
        memcpy(tmp + pos, kTwoDigits + d * 2, 2);
    } else {
        tmp[--pos] = (char)('0' + (unsigned)uval);
    }

    int digits = 20 - pos;
    int len = 0;
    if (negative) buf[len++] = '-';
    memcpy(buf + len, tmp + pos, digits);
    return len + digits;
}

RESQLITE_HOT static int fast_double_to_json_num(double val, char* buf, size_t buf_size) {
    // Keep snprintf for negative zero: JSON permits `-0`, and snprintf preserves
    // the sign bit while the integer fast path would collapse it to `0`.
    if (val == 0.0) {
        if (signbit(val)) {
            return snprintf(buf, buf_size, "%.17g", val);
        }
        buf[0] = '0';
        return 1;
    }

    // Only exact integer-valued doubles can reuse the integer encoder without
    // changing spelling. 2^53 is the largest range where every integer is exactly
    // representable as a double and where %.17g still chooses decimal notation.
    const double max_exact_int = 9007199254740992.0;
    if (isfinite(val) && val >= -max_exact_int && val <= max_exact_int) {
        long long as_int = (long long)val;
        if ((double)as_int == val) {
            return fast_i64_to_str(as_int, buf);
        }
    }

    return snprintf(buf, buf_size, "%.17g", val);
}

// Maximum bytes a JSON-encoded INTEGER cell can occupy: 20 digits + optional
// '-' sign. fast_i64_to_str never writes a NUL terminator.
#define RESQLITE_JSON_INT_MAX 24
// Maximum bytes a JSON-encoded FLOAT cell can occupy through
// fast_double_to_json_num. %.17g produces at most ~25 chars for finite
// doubles; round up and reserve one extra for snprintf's NUL terminator,
// which lands inside the buffer but is not counted toward the return length.
#define RESQLITE_JSON_FLOAT_MAX 32

// Write a SQLite INTEGER as JSON decimal digits directly into the output
// buffer. Avoids the per-cell stack-scratch + memcpy pair that
// `fast_i64_to_str` + `buf_write_str` used to do.
RESQLITE_HOT static int buf_write_int_json(resqlite_buf* b, long long val) {
    if (buf_ensure(b, RESQLITE_JSON_INT_MAX) != 0) return -1;
    int num_len = fast_i64_to_str(val, (char*)(b->data + b->len));
    b->len += num_len;
    return 0;
}

// Write a SQLite FLOAT as JSON number directly into the output buffer.
// Reserves one extra byte so the snprintf fallback's NUL terminator fits
// inside the buffer without growing it.
RESQLITE_HOT static int buf_write_double_json(resqlite_buf* b, double val) {
    if (buf_ensure(b, RESQLITE_JSON_FLOAT_MAX + 1) != 0) return -1;
    int num_len = fast_double_to_json_num(
        val, (char*)(b->data + b->len), (size_t)(RESQLITE_JSON_FLOAT_MAX + 1));
    b->len += num_len;
    return 0;
}

// ---------------------------------------------------------------------------
// JSON output
// ---------------------------------------------------------------------------

static const char b64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Write a base64-encoded blob as a quoted JSON string.
RESQLITE_HOT static int json_write_base64(resqlite_buf* __restrict b,
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

RESQLITE_HOT static int json_write_string(resqlite_buf* __restrict b, const char* s, int len) {
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

        if (RESQLITE_LIKELY(elen == 0)) continue; // Common case: safe byte.

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

// [EXP-195] Lazily build the cached JSON column-name tokens on `entry`.
// Returns SQLITE_OK once `entry->json_name_tokens_buf` and the per-column
// offset/length arrays are populated; safe to call on every query — subsequent
// calls observe `entry->json_name_tokens_col_count > 0` and return immediately.
//
// The token shape is identical to exp 190 (built into a `resqlite_buf` then
// detached): column 0 emits `"name":`, columns 1+ emit `,"name":`. Column
// names are stable for the lifetime of a prepared statement, so caching the
// tokens on the stmt-cache entry amortizes exp 190's per-query `buf_init` +
// first-row pre-encode walk across every re-execution of the same SQL.
static int ensure_json_name_tokens(
    resqlite_cached_stmt* entry, sqlite3_stmt* stmt, int col_count
) {
    if (entry->json_name_tokens_col_count > 0) return SQLITE_OK;
    if (col_count <= 0) {
        // No columns: nothing to cache, but flag as built so we don't retry
        // every call. Use a sentinel of -1 so a real 0-column statement (rare)
        // never accidentally re-enters the build path.
        entry->json_name_tokens_col_count = -1;
        return SQLITE_OK;
    }

    int* offsets = (int*)malloc(col_count * sizeof(int));
    int* lens = (int*)malloc(col_count * sizeof(int));
    if (!offsets || !lens) {
        free(offsets);
        free(lens);
        return SQLITE_NOMEM;
    }

    // Worst case per name: every byte escapes to \uXXXX (6 bytes), plus
    // leading `,` (col 1+), opening `"`, closing `"`, and `:` = +4.
    int tokens_cap = 0;
    for (int i = 0; i < col_count; i++) {
        int name_len = (int)strlen(sqlite3_column_name(stmt, i));
        tokens_cap += name_len * 6 + 4;
    }
    if (tokens_cap < 64) tokens_cap = 64;

    resqlite_buf tokens = {NULL, 0, 0};
    if (buf_init(&tokens, tokens_cap) != 0) {
        free(offsets);
        free(lens);
        return SQLITE_NOMEM;
    }

    for (int i = 0; i < col_count; i++) {
        offsets[i] = tokens.len;
        if (i > 0) {
            if (buf_write_char(&tokens, ',') != 0) goto fail;
        }
        const char* name = sqlite3_column_name(stmt, i);
        int name_len = (int)strlen(name);
        if (json_write_string(&tokens, name, name_len) != 0) goto fail;
        if (buf_write_char(&tokens, ':') != 0) goto fail;
        lens[i] = tokens.len - offsets[i];
    }

    entry->json_name_tokens_buf = tokens.data;
    entry->json_name_tokens_len = tokens.len;
    entry->json_name_token_offsets = offsets;
    entry->json_name_token_lens = lens;
    entry->json_name_tokens_col_count = col_count;
    return SQLITE_OK;

fail:
    free(tokens.data);
    free(offsets);
    free(lens);
    return SQLITE_NOMEM;
}

// Macro to bail out of write_json_to_buf on OOM without leaking.
#define JSON_CHECK(expr) do { if ((expr) != 0) { rc = SQLITE_NOMEM; goto cleanup; } } while (0)

// `out_row_count` receives the number of rows serialized into `b`. It is
// written on every exit path (including OOM/error) so the caller never reads
// an uninitialized value — on error it holds the count of rows fully written
// before the failure, which the caller discards along with the partial buffer.
RESQLITE_HOT static int write_json_to_buf(
    sqlite3_stmt* stmt, resqlite_cached_stmt* entry, resqlite_buf* b,
    int* out_row_count) {
    int col_count = sqlite3_column_count(stmt);
    int rc;
    // Declared before the first `goto cleanup` below so cleanup always reads
    // an initialized count, even when token setup fails before any row.
    int row_index = 0;

    // [EXP-195] Build the JSON column-name tokens once per cached stmt and
    // reuse them across every re-execution. Supersedes exp 190's per-query
    // `tokens_buf` + first-row pre-encode loop; the encoded tokens live on
    // the cache entry until the entry is evicted or the connection closes.
    rc = ensure_json_name_tokens(entry, stmt, col_count);
    if (rc != SQLITE_OK) goto cleanup;
    const unsigned char* tokens_data = entry->json_name_tokens_buf;
    const int* token_offsets = entry->json_name_token_offsets;
    const int* token_lens = entry->json_name_token_lens;
    int tokens_total = entry->json_name_tokens_len;

    // [EXP-199] Per-row capacity reservation. Pre-reserve at row start for the
    // brace/separator boilerplate, every column-name token, the trailing `}`,
    // and a per-cell upper bound that covers NULL/INTEGER/FLOAT directly
    // (`RESQLITE_JSON_FLOAT_MAX + 1` = 33 bytes; the FLOAT bound dominates the
    // 24-byte INT bound and the 4-byte "null" literal, so a single multiply
    // covers all three). NULL/INTEGER/FLOAT cells then write directly to
    // `b->data + b->len` without a per-cell `buf_ensure`. TEXT/BLOB cells go
    // through their existing helpers (`json_write_string` /
    // `json_write_base64`), which manage their own `buf_ensure`; after such
    // a cell we re-ensure headroom for the remaining tokens, fixed cells,
    // and the row-closing `}`. The per-query bracket `[` and `]` stay on the
    // existing per-call ensure path: they fire twice per query regardless of
    // shape, so the row-level reservation cannot subsume them.
    const int cell_max = RESQLITE_JSON_FLOAT_MAX + 1;
    int fixed_cell_bytes_total = col_count * cell_max;

    JSON_CHECK(buf_write_char(b, '['));
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        int prelude = 1 + (row_index > 0 ? 1 : 0); // '{' (+ optional ',')
        JSON_CHECK(buf_ensure(b, prelude + tokens_total
            + fixed_cell_bytes_total + 1)); // + '}'

        if (row_index > 0) b->data[b->len++] = ',';
        b->data[b->len++] = '{';

        for (int i = 0; i < col_count; i++) {
            memcpy(b->data + b->len, tokens_data + token_offsets[i],
                   (size_t)token_lens[i]);
            b->len += token_lens[i];

            int type = sqlite3_column_type(stmt, i);
            switch (type) {
                case SQLITE_NULL:
                    memcpy(b->data + b->len, "null", 4);
                    b->len += 4;
                    break;
                case SQLITE_INTEGER:
                    b->len += fast_i64_to_str(
                        sqlite3_column_int64(stmt, i),
                        (char*)(b->data + b->len));
                    break;
                case SQLITE_FLOAT:
                    b->len += fast_double_to_json_num(
                        sqlite3_column_double(stmt, i),
                        (char*)(b->data + b->len), (size_t)cell_max);
                    break;
                case SQLITE_TEXT: {
                    // column_text MUST be called before column_bytes — calling
                    // bytes first can trigger an implicit type conversion that
                    // invalidates the text pointer.
                    const char* text = (const char*)sqlite3_column_text(stmt, i);
                    int text_len = sqlite3_column_bytes(stmt, i);
                    JSON_CHECK(json_write_string(b, text, text_len));
                    // [EXP-199] json_write_string may have grown the buffer
                    // past the row-start reservation. Re-ensure headroom for
                    // the remaining tokens + fixed cells + '}' so subsequent
                    // direct writes stay in-bounds.
                    int remaining_tokens = tokens_total
                        - (token_offsets[i] + token_lens[i]);
                    int remaining_cells = (col_count - i - 1) * cell_max;
                    JSON_CHECK(buf_ensure(b,
                        remaining_tokens + remaining_cells + 1));
                    break;
                }
                case SQLITE_BLOB: {
                    int blob_len = sqlite3_column_bytes(stmt, i);
                    const unsigned char* blob =
                        (const unsigned char*)sqlite3_column_blob(stmt, i);
                    JSON_CHECK(json_write_base64(b, blob, blob_len));
                    int remaining_tokens = tokens_total
                        - (token_offsets[i] + token_lens[i]);
                    int remaining_cells = (col_count - i - 1) * cell_max;
                    JSON_CHECK(buf_ensure(b,
                        remaining_tokens + remaining_cells + 1));
                    break;
                }
                default:
                    memcpy(b->data + b->len, "null", 4);
                    b->len += 4;
                    break;
            }
        }

        b->data[b->len++] = '}';
        row_index++;
    }

    JSON_CHECK(buf_write_char(b, ']'));

cleanup:
    sqlite3_reset(stmt);
    *out_row_count = row_index;

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
    int* out_len,
    int* out_row_count
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) {
        *out_buf = NULL;
        *out_len = 0;
        *out_row_count = 0;
        return SQLITE_MISUSE;
    }
    if (reader_id < 0 || reader_id >= db->reader_count) {
        *out_buf = NULL;
        *out_len = 0;
        *out_row_count = 0;
        return SQLITE_BUSY;
    }
    resqlite_reader* reader = &db->readers[reader_id];

    int rc;
    resqlite_cached_stmt* entry =
        get_or_prepare_reader(reader, sql, (int)strlen(sql), &rc);
    if (!entry) {
        *out_buf = NULL;
        *out_len = 0;
        *out_row_count = 0;
        return rc;
    }
    sqlite3_stmt* stmt = entry->stmt;

    rc = bind_params(stmt, params, param_count, entry->param_count);
    if (rc != SQLITE_OK) {
        sqlite3_reset(stmt);
        *out_buf = NULL;
        *out_len = 0;
        *out_row_count = 0;
        return rc;
    }

    // Use persistent reader buffer — reset, no malloc/free per query.
    reader->json_buf.len = 0;

    rc = write_json_to_buf(stmt, entry, &reader->json_buf, out_row_count);

    if (rc != SQLITE_OK) {
        *out_buf = NULL;
        *out_len = 0;
        *out_row_count = 0;
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

RESQLITE_HOT int resqlite_step_row(
    sqlite3_stmt* stmt,
    int col_count,
    resqlite_cell* cells
) {
    int rc = sqlite3_step(stmt);
    if (RESQLITE_UNLIKELY(rc != SQLITE_ROW)) return rc;

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
// Stream-hash helpers
// ([EXP-075](../experiments/075-native-hash-selectifchanged.md), was 053 on
// worktree)
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
    int i = 0;
    for (; i + 8 <= len; i += 8) {
        uint64_t word;
        // Unaligned-safe load; compilers turn this into one native load.
        // The hash is in-process only, so host byte order is acceptable.
        memcpy(&word, b + i, 8);
        h ^= word;
        h = (h * RESQLITE_FNV_PRIME) & RESQLITE_FNV_MASK;
    }
    for (; i < len; i++) {
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
// not being tracked). When set,
// [EXP-077](../experiments/077-cheap-check-first-sweep.md) short-circuits: if we
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
        // [EXP-077](../experiments/077-cheap-check-first-sweep.md): once
        // row_count exceeds last_row_count, the
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

RESQLITE_HOT int resqlite_step_row_hash(
    sqlite3_stmt* stmt,
    int col_count,
    resqlite_cell* cells,
    uint64_t* hash
) {
    int rc = sqlite3_step(stmt);
    if (RESQLITE_UNLIKELY(rc != SQLITE_ROW)) return rc;

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
