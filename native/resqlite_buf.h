#ifndef RESQLITE_BUF_H
#define RESQLITE_BUF_H

// Shared growable-byte-buffer primitives and hot/branch-hint macros.
//
// Split out of resqlite.c so the JSON value encoders (resqlite_json.c) and
// the connection/orchestration code (resqlite.c) share one definition. The
// helpers are `static inline` so each translation unit inlines them exactly
// as they were inlined when they lived inside resqlite.c — no cross-TU call
// is introduced for the hot buffer path.

#include <stdlib.h>
#include <string.h>

#if defined(_MSC_VER) || defined(RESQLITE_PGO)
// PGO's measured function counts own hotness. Keeping manual hot attributes
// would override a representative profile and produce backend warnings when a
// rare guard path is correctly cold. Normal O3 builds retain the annotations.
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

typedef struct {
    unsigned char* data;
    int len;
    int cap;
} resqlite_buf;

static inline int buf_init(resqlite_buf* b, int initial_cap) {
    b->data = (unsigned char*)malloc(initial_cap);
    if (!b->data) { b->len = 0; b->cap = 0; return -1; }
    b->len = 0;
    b->cap = initial_cap;
    return 0;
}

RESQLITE_HOT static inline int buf_ensure(resqlite_buf* b, int extra) {
    if (RESQLITE_LIKELY(b->len + extra <= b->cap)) return 0;
    int new_cap = b->cap;
    while (new_cap < b->len + extra) new_cap *= 2;
    unsigned char* p = (unsigned char*)realloc(b->data, new_cap);
    if (!p) return -1;
    b->data = p;
    b->cap = new_cap;
    return 0;
}

RESQLITE_HOT static inline int buf_write(
    resqlite_buf* __restrict b, const void* __restrict src, int n) {
    if (buf_ensure(b, n) != 0) return -1;
    memcpy(b->data + b->len, src, n);
    b->len += n;
    return 0;
}

static inline int buf_write_byte(resqlite_buf* b, unsigned char v) {
    if (buf_ensure(b, 1) != 0) return -1;
    b->data[b->len++] = v;
    return 0;
}

static inline int buf_write_char(resqlite_buf* b, char c) {
    return buf_write_byte(b, (unsigned char)c);
}

#endif // RESQLITE_BUF_H
