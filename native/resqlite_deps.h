#ifndef RESQLITE_DEPS_H
#define RESQLITE_DEPS_H

#include "resqlite.h"

// Internal dependency-tracking primitives. Tables are tracked as bounded
// string sets. Columns are tracked as structured table/column pairs backed by
// one allocation containing "table\0column\0"; this keeps storage compact and
// avoids parsing "table.column" strings across the FFI boundary.

typedef struct {
    char* names[RESQLITE_MAX_READ_TABLES];
    int count;
    int allocated;
    int reliable;
} resqlite_read_set;

typedef struct {
    char* names[RESQLITE_MAX_DIRTY_TABLES];
    int count;
    int allocated;
    int reliable;
} resqlite_dirty_set;

typedef struct {
    char* storage;
    const char* table;
    const char* column;
} resqlite_column_dep;

typedef struct {
    resqlite_column_dep deps[RESQLITE_MAX_DEP_COLUMNS];
    int count;
    int allocated;
    int reliable;
} resqlite_column_set;

void resqlite_read_set_init(resqlite_read_set* s);
void resqlite_read_set_add(resqlite_read_set* s, const char* table_name);
void resqlite_read_set_reset(resqlite_read_set* s);
void resqlite_read_set_free(resqlite_read_set* s);

void resqlite_dirty_set_init(resqlite_dirty_set* s);
void resqlite_dirty_set_add(resqlite_dirty_set* s, const char* table_name);
void resqlite_dirty_set_reset(resqlite_dirty_set* s);
void resqlite_dirty_set_free(resqlite_dirty_set* s);

void resqlite_column_set_init(resqlite_column_set* s);
void resqlite_column_set_add(resqlite_column_set* s,
                             const char* table,
                             const char* column);
void resqlite_column_set_reset(resqlite_column_set* s);
void resqlite_column_set_free(resqlite_column_set* s);

void resqlite_string_array_clear(char** names, int* count);
int resqlite_string_array_copy(char** dest,
                               int capacity,
                               int* dest_count,
                               char* const* src,
                               int src_count);

void resqlite_column_dep_array_clear(resqlite_column_dep* deps, int* count);
int resqlite_column_dep_array_copy_from_set(resqlite_column_dep* dest,
                                            int capacity,
                                            int* dest_count,
                                            const resqlite_column_set* src);

int resqlite_column_dep_belongs_to_table(const resqlite_column_dep* dep,
                                         const char* table_name,
                                         int table_name_len,
                                         const char** out_column);

#ifdef RESQLITE_DEPS_TEST
void resqlite_deps_test_fail_alloc_after(int remaining_successes);
void resqlite_deps_test_reset_alloc(void);
#endif

#endif // RESQLITE_DEPS_H
