#include "sqlite3.h"

extern int tlt_sqlite3_open(const char*, sqlite3**);
extern int tlt_sqlite3_open_v2(const char*, sqlite3**, int, const char*);
extern int tlt_sqlite3_close(sqlite3*);
extern int tlt_sqlite3_close_v2(sqlite3*);
extern int tlt_sqlite3_prepare_v2(sqlite3*, const char*, int, sqlite3_stmt**,
                                  const char**);
extern int tlt_sqlite3_prepare_v3(sqlite3*, const char*, int, unsigned int,
                                  sqlite3_stmt**, const char**);
extern int tlt_sqlite3_finalize(sqlite3_stmt*);
extern int tlt_sqlite3_step(sqlite3_stmt*);
extern int tlt_sqlite3_reset(sqlite3_stmt*);
extern int tlt_sqlite3_bind_null(sqlite3_stmt*, int);
extern int tlt_sqlite3_bind_int(sqlite3_stmt*, int, int);
extern int tlt_sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
extern int tlt_sqlite3_bind_double(sqlite3_stmt*, int, double);
extern int tlt_sqlite3_bind_text(sqlite3_stmt*, int, const char*, int,
                                 void (*)(void*));
extern int tlt_sqlite3_bind_blob(sqlite3_stmt*, int, const void*, int,
                                 void (*)(void*));
extern int tlt_sqlite3_bind_blob64(sqlite3_stmt*, int, const void*,
                                   sqlite3_uint64, void (*)(void*));
extern int tlt_sqlite3_clear_bindings(sqlite3_stmt*);
extern int tlt_sqlite3_column_count(sqlite3_stmt*);
extern int tlt_sqlite3_column_int(sqlite3_stmt*, int);
extern sqlite3_int64 tlt_sqlite3_column_int64(sqlite3_stmt*, int);
extern double tlt_sqlite3_column_double(sqlite3_stmt*, int);
extern const unsigned char* tlt_sqlite3_column_text(sqlite3_stmt*, int);
extern const void* tlt_sqlite3_column_blob(sqlite3_stmt*, int);
extern int tlt_sqlite3_column_bytes(sqlite3_stmt*, int);
extern int tlt_sqlite3_exec(sqlite3*, const char*, sqlite3_callback, void*,
                            char**);
extern int tlt_sqlite3_changes(sqlite3*);
extern int tlt_sqlite3_total_changes(sqlite3*);
extern sqlite3_int64 tlt_sqlite3_last_insert_rowid(sqlite3*);
extern int tlt_sqlite3_errcode(sqlite3*);
extern const char* tlt_sqlite3_errmsg(sqlite3*);

int sqlite3_open(const char* filename, sqlite3** ppDb) {
  return tlt_sqlite3_open(filename, ppDb);
}

int sqlite3_open_v2(const char* filename, sqlite3** ppDb, int flags,
                    const char* zVfs) {
  return tlt_sqlite3_open_v2(filename, ppDb, flags, zVfs);
}

int sqlite3_close(sqlite3* db) { return tlt_sqlite3_close(db); }

int sqlite3_close_v2(sqlite3* db) { return tlt_sqlite3_close_v2(db); }

int sqlite3_prepare_v2(sqlite3* db, const char* zSql, int nByte,
                       sqlite3_stmt** ppStmt, const char** pzTail) {
  return tlt_sqlite3_prepare_v2(db, zSql, nByte, ppStmt, pzTail);
}

int sqlite3_prepare_v3(sqlite3* db, const char* zSql, int nByte,
                       unsigned int prepFlags, sqlite3_stmt** ppStmt,
                       const char** pzTail) {
  return tlt_sqlite3_prepare_v3(db, zSql, nByte, prepFlags, ppStmt, pzTail);
}

int sqlite3_finalize(sqlite3_stmt* pStmt) {
  return tlt_sqlite3_finalize(pStmt);
}

int sqlite3_step(sqlite3_stmt* pStmt) { return tlt_sqlite3_step(pStmt); }

int sqlite3_reset(sqlite3_stmt* pStmt) { return tlt_sqlite3_reset(pStmt); }

int sqlite3_bind_null(sqlite3_stmt* pStmt, int i) {
  return tlt_sqlite3_bind_null(pStmt, i);
}

int sqlite3_bind_int(sqlite3_stmt* pStmt, int i, int value) {
  return tlt_sqlite3_bind_int(pStmt, i, value);
}

int sqlite3_bind_int64(sqlite3_stmt* pStmt, int i, sqlite3_int64 value) {
  return tlt_sqlite3_bind_int64(pStmt, i, value);
}

int sqlite3_bind_double(sqlite3_stmt* pStmt, int i, double value) {
  return tlt_sqlite3_bind_double(pStmt, i, value);
}

int sqlite3_bind_text(sqlite3_stmt* pStmt, int i, const char* value, int n,
                      void (*xDel)(void*)) {
  return tlt_sqlite3_bind_text(pStmt, i, value, n, xDel);
}

int sqlite3_bind_blob(sqlite3_stmt* pStmt, int i, const void* value, int n,
                      void (*xDel)(void*)) {
  return tlt_sqlite3_bind_blob(pStmt, i, value, n, xDel);
}

int sqlite3_bind_blob64(sqlite3_stmt* pStmt, int i, const void* value,
                        sqlite3_uint64 n, void (*xDel)(void*)) {
  return tlt_sqlite3_bind_blob64(pStmt, i, value, n, xDel);
}

int sqlite3_clear_bindings(sqlite3_stmt* pStmt) {
  return tlt_sqlite3_clear_bindings(pStmt);
}

int sqlite3_column_count(sqlite3_stmt* pStmt) {
  return tlt_sqlite3_column_count(pStmt);
}

int sqlite3_column_int(sqlite3_stmt* pStmt, int iCol) {
  return tlt_sqlite3_column_int(pStmt, iCol);
}

sqlite3_int64 sqlite3_column_int64(sqlite3_stmt* pStmt, int iCol) {
  return tlt_sqlite3_column_int64(pStmt, iCol);
}

double sqlite3_column_double(sqlite3_stmt* pStmt, int iCol) {
  return tlt_sqlite3_column_double(pStmt, iCol);
}

const unsigned char* sqlite3_column_text(sqlite3_stmt* pStmt, int iCol) {
  return tlt_sqlite3_column_text(pStmt, iCol);
}

const void* sqlite3_column_blob(sqlite3_stmt* pStmt, int iCol) {
  return tlt_sqlite3_column_blob(pStmt, iCol);
}

int sqlite3_column_bytes(sqlite3_stmt* pStmt, int iCol) {
  return tlt_sqlite3_column_bytes(pStmt, iCol);
}

int sqlite3_exec(sqlite3* db, const char* sql, sqlite3_callback callback,
                 void* arg, char** errmsg) {
  return tlt_sqlite3_exec(db, sql, callback, arg, errmsg);
}

int sqlite3_changes(sqlite3* db) { return tlt_sqlite3_changes(db); }

int sqlite3_total_changes(sqlite3* db) {
  return tlt_sqlite3_total_changes(db);
}

sqlite3_int64 sqlite3_last_insert_rowid(sqlite3* db) {
  return tlt_sqlite3_last_insert_rowid(db);
}

int sqlite3_errcode(sqlite3* db) { return tlt_sqlite3_errcode(db); }

const char* sqlite3_errmsg(sqlite3* db) { return tlt_sqlite3_errmsg(db); }
