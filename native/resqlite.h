#ifndef RESQLITE_H
#define RESQLITE_H

#include "../third_party/sqlite3mc/sqlite3.h"

// ---------------------------------------------------------------------------
// Connection pool with per-connection statement caches
// ---------------------------------------------------------------------------

typedef struct resqlite_db resqlite_db;

// ---------------------------------------------------------------------------
// Parameter types for binding
// ---------------------------------------------------------------------------

#define RESQLITE_TYPE_NULL    0
#define RESQLITE_TYPE_INT64   1
#define RESQLITE_TYPE_FLOAT64 2
#define RESQLITE_TYPE_TEXT    3
#define RESQLITE_TYPE_BLOB    4

typedef struct {
    int type;
    union {
        long long int_val;
        double float_val;
        struct { const char* data; int len; } text;
        struct { const void* data; int len; } blob;
    };
} resqlite_param;

// ---------------------------------------------------------------------------
// Connection lifecycle
// ---------------------------------------------------------------------------

// Open a database with a connection pool.
// encryption_key_hex: hex-encoded encryption key, or NULL for no encryption.
// max_readers: number of read connections (0 = default 8).
resqlite_db* resqlite_open(const char* path, int max_readers, const char* encryption_key_hex);
void resqlite_close(resqlite_db* db);
const char* resqlite_errmsg(resqlite_db* db);

// Get the raw sqlite3* writer connection handle (for direct FFI calls).
sqlite3* resqlite_writer_handle(resqlite_db* db);

// ---------------------------------------------------------------------------
// Write operations (use writer connection)
// ---------------------------------------------------------------------------

// Write result returned by execute and batch functions.
typedef struct {
    int affected_rows;
    long long last_insert_id;
} resqlite_write_result;

// Execute a simple statement with no params (DDL, simple DML).
int resqlite_exec(resqlite_db* db, const char* sql);

// Like resqlite_exec but also fills in affected row count and last
// insert rowid. Enables the no-parameters execute path to return
// accurate WriteResult fields for statements like
// `DELETE FROM t WHERE x = 5` that don't have bound parameters.
int resqlite_exec_with_result(
    resqlite_db* db,
    const char* sql,
    resqlite_write_result* out_result
);

// Execute a parameterized write statement. Returns result info.
int resqlite_execute(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* params,
    int param_count,
    resqlite_write_result* out_result
);

// Execute a batch of parameterized writes: one SQL, many param sets.
// Runs in a transaction (BEGIN/COMMIT). Uses a single prepared statement.
// Returns SQLITE_OK on success. Automatically rolls back on error.
int resqlite_run_batch(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* param_sets,  // flat array: param_sets[i * param_count + j]
    int param_count,                   // params per statement
    int set_count                      // number of param sets
);

// Execute a batch inside a caller-managed transaction. Unlike resqlite_run_batch,
// this does NOT start or commit a transaction — the caller must have already
// opened one (BEGIN IMMEDIATE or SAVEPOINT). On error returns the sqlite code
// without rolling back; the caller is responsible for choosing the correct
// rollback scope (full ROLLBACK vs ROLLBACK TO savepoint).
int resqlite_run_batch_nested(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* param_sets,
    int param_count,
    int set_count
);

// ---------------------------------------------------------------------------
// Dirty table tracking (for stream invalidation)
// ---------------------------------------------------------------------------

#define RESQLITE_MAX_DIRTY_TABLES 64

// Get the set of tables modified since the last call to this function.
// Returns the number of dirty table names written to out_tables.
// Clears the dirty set after reading.
int resqlite_get_dirty_tables(
    resqlite_db* db,
    const char** out_tables,  // array of at least RESQLITE_MAX_DIRTY_TABLES pointers
    int max_tables
);

// ---------------------------------------------------------------------------
// Read dependency tracking (authorizer hook on readers)
// ---------------------------------------------------------------------------

#define RESQLITE_MAX_READ_TABLES 64

// Get the set of tables read by queries on the given reader since the
// last call to this function. Returns the count of table names written.
// Clears the set after reading.
int resqlite_get_read_tables(
    resqlite_db* db,
    int reader_id,
    const char** out_tables,
    int max_tables
);

int resqlite_db_status_total(
    resqlite_db* db,
    int op,
    int reset,
    int* out_current,
    int* out_highwater
);

// ---------------------------------------------------------------------------
// Read operations (use reader pool)
// ---------------------------------------------------------------------------

sqlite3_stmt* resqlite_stmt_acquire(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* params,
    int param_count,
    int* out_reader
);

void resqlite_stmt_release(resqlite_db* db, int reader_id);

// Dedicated reader variant — no pool mutex. Caller guarantees exclusive access.
sqlite3_stmt* resqlite_stmt_acquire_on(
    resqlite_db* db,
    int reader_id,
    const char* sql,
    const resqlite_param* params,
    int param_count
);

// Writer variant — no mutex. Caller (writer isolate) guarantees exclusive access.
sqlite3_stmt* resqlite_stmt_acquire_writer(
    resqlite_db* db,
    const char* sql,
    const resqlite_param* params,
    int param_count
);

int resqlite_query_bytes(
    resqlite_db* db,
    int reader_id,
    const char* sql,
    const resqlite_param* params,
    int param_count,
    unsigned char** out_buf,
    int* out_len
);

void resqlite_free(void* ptr);

// ---------------------------------------------------------------------------
// Batch row reader — one FFI call per row instead of ~16
// ---------------------------------------------------------------------------

typedef struct {
    int type;           // 4 bytes — SQLITE_INTEGER / FLOAT / TEXT / BLOB / NULL
    int len;            // 4 bytes — byte length for TEXT and BLOB
    union {
        long long i;    // 8 bytes — integer value
        double d;       // 8 bytes — float value
        const void* p;  // 8 bytes — pointer to text or blob data
    };
} resqlite_cell;         // 16 bytes total

int resqlite_step_row(
    sqlite3_stmt* stmt,
    int col_count,
    resqlite_cell* cells
);

#endif // RESQLITE_H
