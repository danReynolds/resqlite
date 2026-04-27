#ifndef RESQLITE_H
#define RESQLITE_H

#include "../third_party/sqlite3mc/sqlite3.h"
#include <stdint.h>

// ---------------------------------------------------------------------------
// Connection pool with per-connection statement caches
// ---------------------------------------------------------------------------

typedef struct resqlite_db resqlite_db;

// Dependency getters return this sentinel when table-level metadata is
// unavailable. Callers must treat it as "unknown dependencies" and choose the
// conservative all-tables invalidation path. Column metadata uses a different
// fallback: 0 column entries means "no precise column optimization available"
// while table metadata remains the correctness source.
#define RESQLITE_DEPENDENCY_COUNT_UNKNOWN (-1)

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

// Transaction-control fast path (experiment 101).
//
// These run pre-prepared `BEGIN IMMEDIATE`, `COMMIT`, `ROLLBACK` stmts
// via sqlite3_reset + sqlite3_step, skipping sqlite3_exec's per-call
// prepare+finalize. Each call takes the writer mutex for the duration
// of the step, matching `resqlite_exec`'s locking discipline. Return
// SQLITE_OK on success or an SQLite error code.
int resqlite_tx_begin_immediate(resqlite_db* db);
int resqlite_tx_commit(resqlite_db* db);
int resqlite_tx_rollback(resqlite_db* db);

// Execute a write statement. Returns result info.
// Supports both parameterized (param_count > 0) and unparameterized
// (param_count == 0) writes. For unparameterized calls, automatically
// detects multi-statement SQL via pzTail and falls back to sqlite3_exec.
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
// Returns:
//   * `>= 0` — count of dirty table names written to out_tables; the
//     dirty set is cleared after reading.
//   * `RESQLITE_DEPENDENCY_COUNT_UNKNOWN` — the dirty set is unreliable
//     (overflow / OOM during the transaction). Caller must treat this as
//     "all tables potentially dirty" and invalidate every dependent stream.
//     The dirty set is reset before returning so the next transaction starts
//     fresh.
// Strings are owned by the dirty set (freed on next add or close);
// callers must copy before further writer activity.
int resqlite_get_dirty_tables(
    resqlite_db* db,
    const char** out_tables,  // array of at least RESQLITE_MAX_DIRTY_TABLES pointers
    int max_tables
);

// ---------------------------------------------------------------------------
// Read dependency tracking (authorizer hook on readers)
// ---------------------------------------------------------------------------

#define RESQLITE_MAX_READ_TABLES 64

// Get the set of tables read by the most recent prepared statement on
// the given reader. Served directly from the cached stmt entry's
// `read_tables` (no per-call strdup; the entry's strings outlive this
// call until cache eviction).
//
// Returns:
//   * `>= 0` — count of table names written to out_tables. Caller must
//     copy strings before the next query on this reader (cache
//     eviction may free the entry's storage).
//   * `RESQLITE_DEPENDENCY_COUNT_UNKNOWN` — the cached entry's read-table
//     set is unreliable (the authorizer overflowed `RESQLITE_MAX_READ_TABLES`
//     or hit OOM during prepare). Caller must treat this as "depends on every
//     table" and route the stream into the all-tables bucket.
//   * `0`    — no entry yet (no query has been prepared on this
//     reader).
int resqlite_get_read_tables(
    resqlite_db* db,
    int reader_id,
    const char** out_tables,
    int max_tables
);

// ---------------------------------------------------------------------------
// Column dependency tracking (experiment 106)
// ---------------------------------------------------------------------------

// Hard cap on the number of distinct columns tracked per dependency set.
// Sets that exceed this cap during capture flip their `reliable` flag
// to 0 (rather than silently truncating); the corresponding getter
// then returns 0 entries to signal "no precise column metadata
// available" — Dart falls back to table-level invalidation for the
// known dirty tables.
#define RESQLITE_MAX_DEP_COLUMNS 64

// Get the table/column pairs read by the most recent prepared statement on
// the given reader. Served directly from the cached stmt entry's structured
// dependency pairs.
//
// Returns:
//   * `>= 0` — count of pairs written to out_tables/out_columns. Caller must
//     copy strings before the next query on this reader.
//   * `0`    — either no entry yet, OR the cached entry's column set is
//     unreliable (overflow / OOM during prepare). In both cases the
//     Dart side treats the (known) read tables as "any column matters"
//     and falls back to table-level invalidation. Tables remain the
//     correctness layer; columns are an optimization that gracefully
//     degrades.
int resqlite_get_read_columns(
    resqlite_db* db,
    int reader_id,
    const char** out_tables,
    const char** out_columns,
    int max_columns
);

// Get the table/column pairs modified by writer activity since the last
// drain. Strings live until the next dirty-set update; callers must copy
// before further writer activity. The dirty set is reset after reading.
//
// INSERT and DELETE writes leave a `"*"` wildcard column sentinel (column
// information is unavailable from the SQLite authorizer for those actions).
//
// Returns:
//   * `>= 0` — count of pairs written to out_tables/out_columns.
//   * `0`    — either no writes since the last drain, OR the column
//     set's `reliable` flag was cleared during capture (overflow /
//     OOM). In the unreliable case the corresponding `dirty_tables`
//     getter still reports the dirty tables (or returns
//     RESQLITE_DEPENDENCY_COUNT_UNKNOWN itself if it overflowed); Dart falls
//     back to table-level invalidation.
int resqlite_get_dirty_columns(
    resqlite_db* db,
    const char** out_tables,
    const char** out_columns,
    int max_columns
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

int resqlite_step_row_hash(
    sqlite3_stmt* stmt,
    int col_count,
    resqlite_cell* cells,
    uint64_t* hash
);

// Step-to-completion + hash all cells. Resets the statement at both
// ends, so the caller can invoke this on a freshly-bound stmt OR on
// one that was just drained by decodeQuery — either way works.
//
// `last_row_count` is the caller's cached row count from the last
// emission (or -1 on the initial-query path). When set, experiment 077
// short-circuits: if the fresh step count exceeds `last_row_count` the
// final hash can't possibly match, so we stop folding cell bytes and
// just drain the remaining rows to report the new count. `out_row_count`
// always receives the fresh count on success, so the caller can update
// its cache.
//
// Returns the final hash, or -1 on step error.
//
// Used for:
//   - selectIfChanged's fast-path pre-check (hash-only, compare to
//     baseline, bail without Dart decode if matched).
//   - the initial stream query's baseline hash (called after
//     decodeQuery has already produced the rows for the subscriber;
//     SQLite replays the read-only query to compute the hash).
long long resqlite_query_hash(
    sqlite3_stmt* stmt, int last_row_count, int* out_row_count);

#endif // RESQLITE_H
