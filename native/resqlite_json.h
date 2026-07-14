#ifndef RESQLITE_JSON_H
#define RESQLITE_JSON_H

// JSON value encoders for the selectBytes() output path.
//
// This is the byte-level encoding layer: it turns individual SQLite cell
// values (integers, doubles, TEXT, BLOB) into their JSON spelling inside a
// resqlite_buf. It knows nothing about statements, the reader pool, or the
// stmt cache — the row-assembly orchestration (write_json_to_buf,
// ensure_json_name_tokens) stays in resqlite.c and calls into here.
//
// The small number formatters are `static inline` so the per-cell hot loop
// in write_json_to_buf inlines them exactly as it did before this module was
// split out (zero cross-TU call on the number path). The larger escape /
// base64 encoders are out-of-line in resqlite_json.c — they were already
// out-of-line calls from write_json_to_buf, so moving them across a
// translation-unit boundary changes no inlining decision.

#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "resqlite_buf.h"

// Maximum bytes a JSON-encoded INTEGER cell can occupy: 20 digits + optional
// '-' sign. resqlite_json_i64_to_str never writes a NUL terminator.
#define RESQLITE_JSON_INT_MAX 24
// Maximum bytes a JSON-encoded FLOAT cell can occupy through
// resqlite_json_double_to_num. %.17g produces at most ~25 chars for finite
// doubles; round up and reserve one extra for snprintf's NUL terminator,
// which lands inside the buffer but is not counted toward the return length.
#define RESQLITE_JSON_FLOAT_MAX 32

// Two-decimal-digit table: entry `d*2` holds the two ASCII digits of d in
// [00..99]. Lets the itoa loop emit two digits per iteration instead of one.
static const char resqlite_json_two_digits[200] =
    "0001020304050607080910111213141516171819"
    "2021222324252627282930313233343536373839"
    "4041424344454647484950515253545556575859"
    "6061626364656667686970717273747576777879"
    "8081828384858687888990919293949596979899";

// Write a signed 64-bit integer as JSON decimal digits into `buf` (no NUL).
// Returns the number of bytes written (<= RESQLITE_JSON_INT_MAX).
RESQLITE_HOT static inline int resqlite_json_i64_to_str(long long val, char* buf) {
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
        memcpy(tmp + pos, resqlite_json_two_digits + d * 2, 2);
    }
    if (uval >= 10) {
        unsigned d = (unsigned)uval;
        pos -= 2;
        memcpy(tmp + pos, resqlite_json_two_digits + d * 2, 2);
    } else {
        tmp[--pos] = (char)('0' + (unsigned)uval);
    }

    int digits = 20 - pos;
    int len = 0;
    if (negative) buf[len++] = '-';
    memcpy(buf + len, tmp + pos, digits);
    return len + digits;
}

// Write a double as a JSON number into `buf` (capacity `buf_size`, includes
// room for snprintf's NUL). Exact integer-valued doubles reuse the integer
// encoder; everything else — fractionals, huge magnitudes, non-finite, and
// negative zero — falls back to snprintf("%.17g"). Returns bytes written.
RESQLITE_HOT static inline int resqlite_json_double_to_num(
    double val, char* buf, size_t buf_size) {
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
            return resqlite_json_i64_to_str(as_int, buf);
        }
    }

    return snprintf(buf, buf_size, "%.17g", val);
}

// Write `s` (len bytes) as a quoted, JSON-escaped string. Manages its own
// buf_ensure; returns 0 on success, -1 on allocation failure.
int resqlite_json_write_string(resqlite_buf* b, const char* s, int len);

// Write `data` (len bytes) as a quoted base64 JSON string. On AArch64 this
// dispatches to the NEON kernel for the bulk and the scalar 12-bit-LUT loop
// for the tail; on every other target it is the pure scalar encoder. Manages
// its own buf_ensure; returns 0 on success, -1 on allocation failure.
int resqlite_json_write_base64(resqlite_buf* b, const unsigned char* data, int len);

// Always-scalar base64 encoder (never NEON), byte-identical output to
// resqlite_json_write_base64. Exists so the differential fuzz test can assert
// the SIMD path matches the scalar reference on the arch that ships SIMD.
int resqlite_json_write_base64_scalar(
    resqlite_buf* b, const unsigned char* data, int len);

#endif // RESQLITE_JSON_H
