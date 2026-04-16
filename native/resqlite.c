#include "resqlite.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include "ryu/ryu.h"

// Forward declarations.
static int bind_params(sqlite3_stmt* stmt, const resqlite_param* params,
                       int param_count);

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

typedef struct {
    char* sql;
    int sql_len;
    sqlite3_stmt* stmt;
    char* read_tables[RESQLITE_MAX_READ_TABLES];
    int read_table_count;
} resqlite_cached_stmt;

typedef struct {
    resqlite_cached_stmt entries[STMT_CACHE_MAX];
    int count;
} resqlite_stmt_cache;

static void stmt_cache_init(resqlite_stmt_cache* c) {
    c->count = 0;
    memset(c->entries, 0, sizeof(c->entries));
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
        sqlite3_finalize(c->entries[0].stmt);
        free(c->entries[0].sql);
        for (int i = 0; i < c->entries[0].read_table_count; i++) {
            free(c->entries[0].read_tables[i]);
        }
        memmove(&c->entries[0], &c->entries[1],
                (STMT_CACHE_MAX - 1) * sizeof(resqlite_cached_stmt));
        c->count = STMT_CACHE_MAX - 1;
    }
    char* sql_copy = (char*)malloc(sql_len + 1);
    if (!sql_copy) return NULL;
    memcpy(sql_copy, sql, sql_len);
    sql_copy[sql_len] = '\0';

    c->entries[c->count].sql = sql_copy;
    c->entries[c->count].sql_len = sql_len;
    c->entries[c->count].stmt = stmt;
    c->entries[c->count].read_table_count = 0;
    memset(c->entries[c->count].read_tables, 0, sizeof(c->entries[c->count].read_tables));
    c->count++;
    return &c->entries[c->count - 1];
}

static void stmt_cache_clear(resqlite_stmt_cache* c) {
    for (int i = 0; i < c->count; i++) {
        sqlite3_finalize(c->entries[i].stmt);
        free(c->entries[i].sql);
        for (int j = 0; j < c->entries[i].read_table_count; j++) {
            free(c->entries[i].read_tables[j]);
        }
    }
    c->count = 0;
}

// ---------------------------------------------------------------------------
// Reader connection
// ---------------------------------------------------------------------------

// Read table tracking (per-reader, for stream dependency capture).
typedef struct {
    char* names[RESQLITE_MAX_READ_TABLES];
    int count;      // number of active entries
    int allocated;  // number of slots with strdup'd strings (>= count)
} resqlite_read_set;

static void read_set_init(resqlite_read_set* s) {
    s->count = 0;
    s->allocated = 0;
}

static void read_set_add(resqlite_read_set* s, const char* table_name) {
    if (!table_name) return;
    // Deduplicate.
    for (int i = 0; i < s->count; i++) {
        if (strcmp(s->names[i], table_name) == 0) return;
    }
    if (s->count >= RESQLITE_MAX_READ_TABLES) return;
    // Free old string in this slot if one exists from a previous cycle.
    if (s->count < s->allocated) {
        free(s->names[s->count]);
    }
    s->names[s->count] = strdup(table_name);
    s->count++;
    if (s->count > s->allocated) s->allocated = s->count;
}

static void read_set_reset(resqlite_read_set* s) {
    // Reset active count. Strings stay valid (Dart reads them after
    // resqlite_get_read_tables returns pointers). They'll be freed
    // on the next read_set_add when their slots are reused.
    s->count = 0;
}

static void read_set_free(resqlite_read_set* s) {
    for (int i = 0; i < s->allocated; i++) {
        free(s->names[i]);
    }
    s->count = 0;
    s->allocated = 0;
}

static void stmt_cache_entry_set_read_tables(resqlite_cached_stmt* entry,
                                             const resqlite_read_set* read_tables) {
    for (int i = 0; i < entry->read_table_count; i++) {
        free(entry->read_tables[i]);
        entry->read_tables[i] = NULL;
    }
    entry->read_table_count = 0;

    for (int i = 0; i < read_tables->count && i < RESQLITE_MAX_READ_TABLES; i++) {
        entry->read_tables[i] = strdup(read_tables->names[i]);
        entry->read_table_count++;
    }
}

static void read_set_load_from_cache_entry(resqlite_read_set* read_set,
                                           const resqlite_cached_stmt* entry) {
    read_set_reset(read_set);
    for (int i = 0; i < entry->read_table_count; i++) {
        read_set_add(read_set, entry->read_tables[i]);
    }
}

typedef struct {
    sqlite3* db;
    resqlite_stmt_cache cache;
    resqlite_read_set read_tables;
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
} resqlite_dirty_set;

static void dirty_set_init(resqlite_dirty_set* s) {
    s->count = 0;
    s->allocated = 0;
}

static void dirty_set_add(resqlite_dirty_set* s, const char* table_name) {
    if (!table_name) return;

    // Check for duplicate.
    for (int i = 0; i < s->count; i++) {
        if (strcmp(s->names[i], table_name) == 0) return;
    }

    if (s->count >= RESQLITE_MAX_DIRTY_TABLES) return;  // overflow protection
    // Free old string in this slot if one exists from a previous cycle.
    if (s->count < s->allocated) {
        free(s->names[s->count]);
    }
    s->names[s->count] = strdup(table_name);
    s->count++;
    if (s->count > s->allocated) s->allocated = s->count;
}

static void dirty_set_reset(resqlite_dirty_set* s) {
    // Reset active count. Strings stay valid (Dart reads them after
    // resqlite_get_dirty_tables returns pointers). Freed on next add or close.
    s->count = 0;
}

static void dirty_set_free(resqlite_dirty_set* s) {
    for (int i = 0; i < s->allocated; i++) {
        free(s->names[i]);
    }
    s->count = 0;
    s->allocated = 0;
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

    // Dirty tables accumulated by the preupdate hook.
    resqlite_dirty_set dirty_tables;
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
// Authorizer callback — records read tables (for stream dependencies)
// ---------------------------------------------------------------------------

#define SQLITE_READ 20  // SQLite authorizer action code for column read

static int authorizer_callback(
    void* user_data,
    int action_code,
    const char* arg1,   // table name for SQLITE_READ
    const char* arg2,   // column name
    const char* arg3,   // database name
    const char* arg4    // trigger/view name
) {
    (void)arg2; (void)arg3; (void)arg4;
    if (action_code == SQLITE_READ && arg1 != NULL) {
        resqlite_read_set* rs = (resqlite_read_set*)user_data;
        read_set_add(rs, arg1);
    }
    return SQLITE_OK;  // allow all operations
}

// ---------------------------------------------------------------------------
// Preupdate hook callback — records dirty tables
// ---------------------------------------------------------------------------

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
    db->writer_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);
    db->pool_mutex = sqlite3_mutex_alloc(SQLITE_MUTEX_FAST);

    // Install preupdate hook on writer for dirty table tracking.
    sqlite3_preupdate_hook(writer, preupdate_hook, db);
    sqlite3_wal_hook(writer, writer_wal_hook, db);

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
        if (buf_init(&db->readers[idx].json_buf, 16384) != 0) {
            sqlite3_close_v2(rdb);
            db->readers[idx].db = NULL;
            continue;
        }
        db->readers[idx].in_use = 0;

        // Install authorizer to capture read dependencies.
        sqlite3_set_authorizer(rdb, authorizer_callback, &db->readers[idx].read_tables);

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
        if (db->readers[i].json_buf.data) free(db->readers[i].json_buf.data);
        sqlite3_close_v2(db->readers[i].db);
    }

    // Close writer.
    sqlite3_mutex_enter(db->writer_mutex);
    stmt_cache_clear(&db->writer_cache);
    dirty_set_free(&db->dirty_tables);
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

static sqlite3_stmt* get_or_prepare_writer(resqlite_db* db, const char* sql,
                                            int sql_len, int* out_rc,
                                            const char** out_tail) {
    sqlite3_stmt* stmt = stmt_cache_lookup(&db->writer_cache, sql, sql_len);
    if (stmt) {
        sqlite3_reset(stmt);
        *out_rc = SQLITE_OK;
        // Cached statements are always single-statement (multi-statement SQL
        // is never prepared via this function), so signal "no trailing SQL".
        *out_tail = sql + sql_len;
        return stmt;
    }

    int rc = sqlite3_prepare_v3(db->writer, sql, sql_len, SQLITE_PREPARE_PERSISTENT,
                                &stmt, out_tail);
    if (rc != SQLITE_OK) {
        *out_rc = rc;
        return NULL;
    }

    if (!stmt_cache_insert(&db->writer_cache, sql, sql_len, stmt)) {
        // OOM — can't cache, and nobody else holds a reference to finalize
        // this stmt later. Finalize and fail the query.
        sqlite3_finalize(stmt);
        *out_rc = SQLITE_NOMEM;
        return NULL;
    }
    *out_rc = SQLITE_OK;
    return stmt;
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
    sqlite3_stmt* stmt = get_or_prepare_writer(db, sql, (int)strlen(sql), &rc,
                                               &tail);
    if (!stmt) {
        sqlite3_mutex_leave(db->writer_mutex);
        return rc;
    }

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
    rc = bind_params(stmt, params, param_count);
    if (rc != SQLITE_OK) {
        sqlite3_reset(stmt);
        sqlite3_mutex_leave(db->writer_mutex);
        return rc;
    }

    rc = sqlite3_step(stmt);
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
    sqlite3_stmt* stmt = stmt_cache_lookup(&db->writer_cache, sql, (int)strlen(sql));
    if (stmt) {
        sqlite3_reset(stmt);
    } else {
        int rc = sqlite3_prepare_v3(
            db->writer, sql, -1, SQLITE_PREPARE_PERSISTENT, &stmt, NULL);
        if (rc != SQLITE_OK) return rc;
        if (!stmt_cache_insert(&db->writer_cache, sql, (int)strlen(sql), stmt)) {
            sqlite3_finalize(stmt);
            return SQLITE_NOMEM;
        }
    }

    for (int i = 0; i < set_count; i++) {
        sqlite3_reset(stmt);

        int rc = bind_params(stmt, &param_sets[i * param_count], param_count);
        if (rc != SQLITE_OK) {
            sqlite3_reset(stmt);
            return rc;
        }

        rc = sqlite3_step(stmt);
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
    // lock-upgrade path since we know we're writing.
    int rc = sqlite3_exec(db->writer, "BEGIN IMMEDIATE", NULL, NULL, NULL);
    if (rc != SQLITE_OK) {
        sqlite3_mutex_leave(db->writer_mutex);
        return rc;
    }

    rc = run_batch_locked(db, sql, param_sets, param_count, set_count);
    if (rc != SQLITE_OK) {
        sqlite3_exec(db->writer, "ROLLBACK", NULL, NULL, NULL);
    } else {
        rc = sqlite3_exec(db->writer, "COMMIT", NULL, NULL, NULL);
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

int resqlite_get_dirty_tables(
    resqlite_db* db,
    const char** out_tables,
    int max_tables
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
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

int resqlite_get_read_tables(
    resqlite_db* db,
    int reader_id,
    const char** out_tables,
    int max_tables
) {
    if (!db || atomic_load_explicit(&db->closed, memory_order_acquire)) return 0;
    if (reader_id < 0 || reader_id >= db->reader_count) return 0;

    resqlite_read_set* rs = &db->readers[reader_id].read_tables;
    int count = rs->count;
    if (count > max_tables) count = max_tables;

    for (int i = 0; i < count; i++) {
        out_tables[i] = rs->names[i];
    }

    // Reset active count. Strings stay valid until next query on this reader.
    read_set_reset(rs);

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

static sqlite3_stmt* get_or_prepare_reader(resqlite_reader* reader,
                                            const char* sql, int sql_len,
                                            int* out_rc) {
    resqlite_cached_stmt* entry =
        stmt_cache_lookup_entry(&reader->cache, sql, sql_len);
    if (entry) {
        sqlite3_reset(entry->stmt);
        read_set_load_from_cache_entry(&reader->read_tables, entry);
        *out_rc = SQLITE_OK;
        return entry->stmt;
    }

    // The authorizer populates per-reader read tables during prepare.
    // Reset before preparing so this statement captures only its own deps.
    read_set_reset(&reader->read_tables);

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
    *out_rc = SQLITE_OK;
    return stmt;
}

// ---------------------------------------------------------------------------
// Internal: bind parameters
// ---------------------------------------------------------------------------

static int bind_params(sqlite3_stmt* stmt, const resqlite_param* params,
                       int param_count) {
    // Cached statements keep prior bindings until explicitly cleared. Without
    // this, reusing a statement with fewer params than the previous call can
    // step with stale freed TEXT/BLOB pointers from an earlier bind.
    sqlite3_clear_bindings(stmt);

    int expected = sqlite3_bind_parameter_count(stmt);
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
    sqlite3_stmt* stmt = get_or_prepare_reader(reader, sql, (int)strlen(sql), &rc);
    if (!stmt) {
        release_reader(db, reader_idx);
        *out_reader = -1;
        return NULL;
    }

    rc = bind_params(stmt, params, param_count);
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
    sqlite3_stmt* stmt = get_or_prepare_reader(reader, sql, (int)strlen(sql), &rc);
    if (!stmt) return NULL;

    rc = bind_params(stmt, params, param_count);
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
    sqlite3_stmt* stmt = get_or_prepare_writer(db, sql, (int)strlen(sql), &rc,
                                               &tail);
    if (!stmt) return NULL;

    rc = bind_params(stmt, params, param_count);
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
                    char num[25]; // Ryu needs at most 24 chars + NUL
                    int num_len = d2s_buffered_n(
                        sqlite3_column_double(stmt, i), num);
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
    sqlite3_stmt* stmt = get_or_prepare_reader(reader, sql, (int)strlen(sql), &rc);
    if (!stmt) {
        *out_buf = NULL;
        *out_len = 0;
        return rc;
    }

    rc = bind_params(stmt, params, param_count);
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

void resqlite_free(void* ptr) {
    free(ptr);
}
