#include "../../native/resqlite_deps.h"

#include <stdio.h>
#include <string.h>

#define CHECK(expr) do { \
    if (!(expr)) { \
        fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__, #expr); \
        return 1; \
    } \
} while (0)

static int test_read_set_overflow_marks_unreliable(void) {
    resqlite_read_set s;
    resqlite_read_set_init(&s);

    char name[16];
    for (int i = 0; i < RESQLITE_MAX_READ_TABLES; i++) {
        snprintf(name, sizeof(name), "r%d", i);
        resqlite_read_set_add(&s, name);
    }
    CHECK(s.count == RESQLITE_MAX_READ_TABLES);
    CHECK(s.reliable == 1);

    resqlite_read_set_add(&s, "overflow");
    CHECK(s.count == RESQLITE_MAX_READ_TABLES);
    CHECK(s.reliable == 0);

    resqlite_read_set_reset(&s);
    CHECK(s.count == 0);
    CHECK(s.reliable == 1);
    resqlite_read_set_free(&s);
    return 0;
}

static int test_dirty_null_marks_unreliable(void) {
    resqlite_dirty_set s;
    resqlite_dirty_set_init(&s);
    resqlite_dirty_set_add(&s, NULL);
    CHECK(s.count == 0);
    CHECK(s.reliable == 0);
    resqlite_dirty_set_free(&s);
    return 0;
}

static int test_column_pairs_preserve_dots_and_wildcards(void) {
    resqlite_column_set s;
    resqlite_column_set_init(&s);

    resqlite_column_set_add(&s, "schema.table", "column.with.dot");
    CHECK(s.count == 1);
    CHECK(strcmp(s.deps[0].table, "schema.table") == 0);
    CHECK(strcmp(s.deps[0].column, "column.with.dot") == 0);

    resqlite_column_set_add(&s, "schema.table", "column.with.dot");
    CHECK(s.count == 1);

    resqlite_column_set_add(&s, "schema.table", NULL);
    CHECK(s.count == 2);
    CHECK(strcmp(s.deps[1].table, "schema.table") == 0);
    CHECK(strcmp(s.deps[1].column, "*") == 0);

    resqlite_column_set_free(&s);
    return 0;
}

static int test_column_overflow_marks_unreliable(void) {
    resqlite_column_set s;
    resqlite_column_set_init(&s);

    char col[16];
    for (int i = 0; i < RESQLITE_MAX_DEP_COLUMNS; i++) {
        snprintf(col, sizeof(col), "c%d", i);
        resqlite_column_set_add(&s, "t", col);
    }
    CHECK(s.count == RESQLITE_MAX_DEP_COLUMNS);
    CHECK(s.reliable == 1);

    resqlite_column_set_add(&s, "t", "overflow");
    CHECK(s.count == RESQLITE_MAX_DEP_COLUMNS);
    CHECK(s.reliable == 0);

    resqlite_column_set_free(&s);
    return 0;
}

static int test_add_oom_marks_unreliable_without_counting_nulls(void) {
    resqlite_read_set tables;
    resqlite_read_set_init(&tables);
    resqlite_deps_test_fail_alloc_after(0);
    resqlite_read_set_add(&tables, "t");
    CHECK(tables.count == 0);
    CHECK(tables.reliable == 0);
    resqlite_deps_test_reset_alloc();
    resqlite_read_set_free(&tables);

    resqlite_column_set columns;
    resqlite_column_set_init(&columns);
    resqlite_deps_test_fail_alloc_after(0);
    resqlite_column_set_add(&columns, "t", "c");
    CHECK(columns.count == 0);
    CHECK(columns.reliable == 0);
    resqlite_deps_test_reset_alloc();
    resqlite_column_set_free(&columns);
    return 0;
}

static int test_partial_copy_failure_clears_destination(void) {
    resqlite_column_set src;
    resqlite_column_set_init(&src);
    resqlite_column_set_add(&src, "t", "a");
    resqlite_column_set_add(&src, "t", "b");
    CHECK(src.count == 2);

    resqlite_column_dep dest[RESQLITE_MAX_DEP_COLUMNS] = {0};
    int dest_count = 0;
    resqlite_deps_test_fail_alloc_after(1);
    int rc = resqlite_column_dep_array_copy_from_set(
        dest, RESQLITE_MAX_DEP_COLUMNS, &dest_count, &src);
    CHECK(rc == -1);
    CHECK(dest_count == 0);
    CHECK(dest[0].storage == NULL);
    resqlite_deps_test_reset_alloc();
    resqlite_column_set_free(&src);
    return 0;
}

static int test_string_copy_failure_clears_destination(void) {
    char* src[2] = {"a", "b"};
    char* dest[2] = {0};
    int dest_count = 0;

    resqlite_deps_test_fail_alloc_after(1);
    int rc = resqlite_string_array_copy(dest, 2, &dest_count, src, 2);
    CHECK(rc == -1);
    CHECK(dest_count == 0);
    CHECK(dest[0] == NULL);
    resqlite_deps_test_reset_alloc();
    return 0;
}

int main(void) {
    if (test_read_set_overflow_marks_unreliable() != 0) return 1;
    if (test_dirty_null_marks_unreliable() != 0) return 1;
    if (test_column_pairs_preserve_dots_and_wildcards() != 0) return 1;
    if (test_column_overflow_marks_unreliable() != 0) return 1;
    if (test_add_oom_marks_unreliable_without_counting_nulls() != 0) return 1;
    if (test_partial_copy_failure_clears_destination() != 0) return 1;
    if (test_string_copy_failure_clears_destination() != 0) return 1;
    return 0;
}
