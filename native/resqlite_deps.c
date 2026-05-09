#include "resqlite_deps.h"

#include <stdlib.h>
#include <string.h>

#ifdef RESQLITE_DEPS_TEST
static int deps_test_allocs_before_failure = -1;

void resqlite_deps_test_fail_alloc_after(int remaining_successes) {
    deps_test_allocs_before_failure = remaining_successes;
}

void resqlite_deps_test_reset_alloc(void) {
    deps_test_allocs_before_failure = -1;
}

static void* deps_malloc(size_t size) {
    if (deps_test_allocs_before_failure == 0) return NULL;
    if (deps_test_allocs_before_failure > 0) {
        deps_test_allocs_before_failure--;
    }
    return malloc(size);
}
#else
static void* deps_malloc(size_t size) {
    return malloc(size);
}
#endif

static void deps_free(void* ptr) {
    free(ptr);
}

static char* deps_strdup(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char* out = (char*)deps_malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, s, len + 1);
    return out;
}

// ---------------------------------------------------------------------------
// Bounded table string sets
// ---------------------------------------------------------------------------

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
        deps_free(names[i]);
        names[i] = NULL;
    }
    *count = 0;
    *allocated = 0;
}

static void bounded_string_set_add(char** names,
                                   int capacity,
                                   int* count,
                                   int* allocated,
                                   int* reliable,
                                   const char* value) {
    if (!value) {
        *reliable = 0;
        return;
    }
    if (!*reliable) return;

    for (int i = 0; i < *count; i++) {
        if (strcmp(names[i], value) == 0) return;
    }

    if (*count >= capacity) {
        *reliable = 0;
        return;
    }

    if (*count < *allocated) {
        deps_free(names[*count]);
        names[*count] = NULL;
    }

    char* stored = deps_strdup(value);
    if (!stored) {
        *reliable = 0;
        return;
    }

    names[*count] = stored;
    (*count)++;
    if (*count > *allocated) *allocated = *count;
}

void resqlite_read_set_init(resqlite_read_set* s) {
    bounded_string_set_init(&s->count, &s->allocated, &s->reliable);
}

void resqlite_read_set_add(resqlite_read_set* s, const char* table_name) {
    bounded_string_set_add(s->names, RESQLITE_MAX_READ_TABLES,
                           &s->count, &s->allocated, &s->reliable,
                           table_name);
}

void resqlite_read_set_reset(resqlite_read_set* s) {
    bounded_string_set_reset(&s->count, &s->reliable);
}

void resqlite_read_set_free(resqlite_read_set* s) {
    bounded_string_set_free(s->names, &s->count, &s->allocated);
}

void resqlite_dirty_set_init(resqlite_dirty_set* s) {
    bounded_string_set_init(&s->count, &s->allocated, &s->reliable);
}

void resqlite_dirty_set_add(resqlite_dirty_set* s, const char* table_name) {
    bounded_string_set_add(s->names, RESQLITE_MAX_DIRTY_TABLES,
                           &s->count, &s->allocated, &s->reliable,
                           table_name);
}

void resqlite_dirty_set_reset(resqlite_dirty_set* s) {
    bounded_string_set_reset(&s->count, &s->reliable);
}

void resqlite_dirty_set_free(resqlite_dirty_set* s) {
    bounded_string_set_free(s->names, &s->count, &s->allocated);
}

void resqlite_string_array_clear(char** names, int* count) {
    for (int i = 0; i < *count; i++) {
        deps_free(names[i]);
        names[i] = NULL;
    }
    *count = 0;
}

int resqlite_string_array_copy(char** dest,
                               int capacity,
                               int* dest_count,
                               char* const* src,
                               int src_count) {
    *dest_count = 0;
    if (src_count > capacity) return -1;

    for (int i = 0; i < src_count; i++) {
        if (!src[i]) {
            resqlite_string_array_clear(dest, dest_count);
            return -1;
        }
        char* dup = deps_strdup(src[i]);
        if (!dup) {
            resqlite_string_array_clear(dest, dest_count);
            return -1;
        }
        dest[*dest_count] = dup;
        (*dest_count)++;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Structured column dependencies
// ---------------------------------------------------------------------------

static void column_dep_clear(resqlite_column_dep* dep) {
    deps_free(dep->storage);
    dep->storage = NULL;
    dep->table = NULL;
    dep->column = NULL;
}

static int column_dep_set(resqlite_column_dep* dep,
                          const char* table,
                          const char* column) {
    if (!table) return -1;

    const char* col = column ? column : "*";
    size_t table_len = strlen(table);
    size_t column_len = strlen(col);
    char* storage = (char*)deps_malloc(table_len + 1 + column_len + 1);
    if (!storage) return -1;

    memcpy(storage, table, table_len + 1);
    memcpy(storage + table_len + 1, col, column_len + 1);

    dep->storage = storage;
    dep->table = storage;
    dep->column = storage + table_len + 1;
    return 0;
}

static int column_dep_equals(const resqlite_column_dep* dep,
                             const char* table,
                             const char* column) {
    const char* col = column ? column : "*";
    return dep->table && dep->column &&
           strcmp(dep->table, table) == 0 &&
           strcmp(dep->column, col) == 0;
}

void resqlite_column_set_init(resqlite_column_set* s) {
    s->count = 0;
    s->allocated = 0;
    s->reliable = 1;
    memset(s->deps, 0, sizeof(s->deps));
}

void resqlite_column_set_add(resqlite_column_set* s,
                             const char* table,
                             const char* column) {
    if (!table) {
        s->reliable = 0;
        return;
    }
    if (!s->reliable) return;

    for (int i = 0; i < s->count; i++) {
        if (column_dep_equals(&s->deps[i], table, column)) return;
    }

    if (s->count >= RESQLITE_MAX_DEP_COLUMNS) {
        s->reliable = 0;
        return;
    }

    if (s->count < s->allocated) {
        column_dep_clear(&s->deps[s->count]);
    }

    if (column_dep_set(&s->deps[s->count], table, column) != 0) {
        s->reliable = 0;
        return;
    }

    s->count++;
    if (s->count > s->allocated) s->allocated = s->count;
}

void resqlite_column_set_reset(resqlite_column_set* s) {
    s->count = 0;
    s->reliable = 1;
}

void resqlite_column_set_free(resqlite_column_set* s) {
    for (int i = 0; i < s->allocated; i++) {
        column_dep_clear(&s->deps[i]);
    }
    s->count = 0;
    s->allocated = 0;
}

// ---------------------------------------------------------------------------
// Structured rowid dependencies
// ---------------------------------------------------------------------------

static void rowid_dep_clear(resqlite_rowid_dep* dep) {
    dep->table = NULL;
    dep->rowid = 0;
}

void resqlite_rowid_set_init(resqlite_rowid_set* s) {
    s->count = 0;
    s->allocated = 0;
    s->reliable = 1;
    memset(s->deps, 0, sizeof(s->deps));
}

void resqlite_rowid_set_add(resqlite_rowid_set* s,
                            const char* table,
                            sqlite3_int64 rowid) {
    if (!table) {
        s->reliable = 0;
        return;
    }
    if (!s->reliable) return;

    for (int i = 0; i < s->count; i++) {
        if (s->deps[i].table &&
            s->deps[i].rowid == rowid &&
            strcmp(s->deps[i].table, table) == 0) {
            return;
        }
    }

    if (s->count >= RESQLITE_MAX_DEP_ROWIDS) {
        s->reliable = 0;
        return;
    }

    if (s->count < s->allocated) rowid_dep_clear(&s->deps[s->count]);
    s->deps[s->count].table = table;
    s->deps[s->count].rowid = rowid;
    s->count++;
    if (s->count > s->allocated) s->allocated = s->count;
}

void resqlite_rowid_set_reset(resqlite_rowid_set* s) {
    s->count = 0;
    s->reliable = 1;
}

void resqlite_rowid_set_free(resqlite_rowid_set* s) {
    for (int i = 0; i < s->allocated; i++) {
        rowid_dep_clear(&s->deps[i]);
    }
    s->count = 0;
    s->allocated = 0;
    s->reliable = 1;
}

void resqlite_column_dep_array_clear(resqlite_column_dep* deps, int* count) {
    for (int i = 0; i < *count; i++) {
        column_dep_clear(&deps[i]);
    }
    *count = 0;
}

int resqlite_column_dep_array_copy_from_set(resqlite_column_dep* dest,
                                            int capacity,
                                            int* dest_count,
                                            const resqlite_column_set* src) {
    *dest_count = 0;
    if (src->count > capacity) return -1;

    for (int i = 0; i < src->count; i++) {
        const resqlite_column_dep* dep = &src->deps[i];
        if (!dep->table || !dep->column ||
            column_dep_set(&dest[*dest_count], dep->table, dep->column) != 0) {
            resqlite_column_dep_array_clear(dest, dest_count);
            return -1;
        }
        (*dest_count)++;
    }
    return 0;
}

int resqlite_column_dep_belongs_to_table(const resqlite_column_dep* dep,
                                         const char* table_name,
                                         int table_name_len,
                                         const char** out_column) {
    if (!dep || !dep->table || !dep->column || !table_name) return 0;
    if ((int)strlen(dep->table) != table_name_len) return 0;
    if (memcmp(dep->table, table_name, table_name_len) != 0) return 0;

    *out_column = dep->column;
    return 1;
}
