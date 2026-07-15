// JSON value encoders for selectBytes() output. See resqlite_json.h for the
// module boundary. This TU owns the base64 and string-escape encoders and the
// only SIMD kernel in resqlite; the number formatters are inline in the header.

#include "resqlite_json.h"

// SIMD kernel gating: AArch64 with NEON is the only ISA with resqlite SIMD
// kernels. `vqtbl4q_u8` / `vld3q_u8` / `vst4q_u8` are AArch64-only and cover
// macOS/iOS/Android arm64. 32-bit ARM lacks `vqtbl4q_u8`; x86_64 SSSE3 needs a
// different table-lookup approach (deferred). Every other target uses the
// scalar encoders.
#if RESQLITE_JSON_HAS_NEON
#include <arm_neon.h>
#endif

// ---------------------------------------------------------------------------
// Base64
// ---------------------------------------------------------------------------

static const char b64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// 12-bit lookup table: index carries two 6-bit base64 slots; entry `[0]` is
// the high slot's char, `[1]` the low slot's. One 24-bit triplet becomes two
// 12-bit lookups + two 16-bit stores instead of four 6-bit lookups + four
// 8-bit stores. 4096 x 2 bytes = 8 KB in .bss.
static unsigned char b64_pair_table[4096][2];
static int b64_pair_table_initialized = 0;

static void init_b64_pair_table(void) {
    for (int i = 0; i < 4096; i++) {
        b64_pair_table[i][0] = (unsigned char)b64_table[(i >> 6) & 0x3F];
        b64_pair_table[i][1] = (unsigned char)b64_table[i & 0x3F];
    }
    b64_pair_table_initialized = 1;
}

// One 24-bit input triplet at data[idx..idx+2] -> four base64 chars at `out`,
// advancing `out` by 4. Two 12-bit pair lookups + two 16-bit stores. Shared by
// the dispatcher's scalar tail and the always-scalar reference so both emit
// identical machine code for the triplet body.
#define RESQLITE_WRITE_B64_TRIPLET(idx) do { \
        unsigned int v = ((unsigned int)data[(idx)] << 16) | \
                         ((unsigned int)data[(idx) + 1] << 8) | \
                          (unsigned int)data[(idx) + 2]; \
        memcpy(out,     b64_pair_table[(v >> 12) & 0xFFF], 2); \
        memcpy(out + 2, b64_pair_table[ v        & 0xFFF], 2); \
        out += 4; \
    } while (0)

#if RESQLITE_JSON_HAS_NEON
// NEON base64 kernel — kept out-of-line (`noinline`) so the small-blob path in
// the dispatcher never carries the kernel's register footprint. Standard
// `vld3q_u8` + `vqtbl4q_u8` shape:
//   1. vld3q_u8 loads 48 bytes deinterleaved as 3 x uint8x16_t (lane j of vec
//      0/1/2 is triplet j's A/B/C byte).
//   2. Derive the four 6-bit indices per triplet:
//        idx0 = A >> 2
//        idx1 = ((A & 0x03) << 4) | (B >> 4)
//        idx2 = ((B & 0x0F) << 2) | (C >> 6)
//        idx3 = C & 0x3F
//   3. Map each index vector through the 64-byte alphabet via 4 x vqtbl4q_u8.
//   4. vst4q_u8 stores 64 bytes interleaved, matching the scalar byte order.
//
// Byte-for-byte identical output to the scalar path. Consumes as many full
// 48-byte blocks as fit and returns the input bytes consumed; the caller runs
// the < 48-byte tail through the scalar loop.
__attribute__((noinline))
RESQLITE_HOT static int b64_neon_bulk(
    const unsigned char* __restrict data,
    int len,
    unsigned char* __restrict out
) {
    uint8x16x4_t table;
    table.val[0] = vld1q_u8((const uint8_t*)b64_table);
    table.val[1] = vld1q_u8((const uint8_t*)b64_table + 16);
    table.val[2] = vld1q_u8((const uint8_t*)b64_table + 32);
    table.val[3] = vld1q_u8((const uint8_t*)b64_table + 48);

    const uint8x16_t mask_03 = vdupq_n_u8(0x03);
    const uint8x16_t mask_0F = vdupq_n_u8(0x0F);
    const uint8x16_t mask_3F = vdupq_n_u8(0x3F);

    int i = 0;
    unsigned char* p = out;
    while (i <= len - 48) {
        uint8x16x3_t in3 = vld3q_u8(data + i);
        uint8x16_t a = in3.val[0];
        uint8x16_t b_vec = in3.val[1];
        uint8x16_t c = in3.val[2];

        uint8x16_t idx0 = vshrq_n_u8(a, 2);
        uint8x16_t idx1 = vorrq_u8(
            vshlq_n_u8(vandq_u8(a, mask_03), 4),
            vshrq_n_u8(b_vec, 4)
        );
        uint8x16_t idx2 = vorrq_u8(
            vshlq_n_u8(vandq_u8(b_vec, mask_0F), 2),
            vshrq_n_u8(c, 6)
        );
        uint8x16_t idx3 = vandq_u8(c, mask_3F);

        uint8x16x4_t out4;
        out4.val[0] = vqtbl4q_u8(table, idx0);
        out4.val[1] = vqtbl4q_u8(table, idx1);
        out4.val[2] = vqtbl4q_u8(table, idx2);
        out4.val[3] = vqtbl4q_u8(table, idx3);

        vst4q_u8(p, out4);
        p += 64;
        i += 48;
    }
    return i;
}
#endif // RESQLITE_JSON_HAS_NEON

// Write the trailing 1 or 2 input bytes (data[i..len)) as a padded base64
// group at `out`, advancing it by 4. No-op when `i == len`.
static inline void b64_write_tail(
    const unsigned char* data, int i, int len, unsigned char** outp) {
    if (i < len) {
        unsigned char* out = *outp;
        unsigned int v = (unsigned int)data[i] << 16;
        if (i + 1 < len) v |= (unsigned int)data[i + 1] << 8;
        out[0] = b64_table[(v >> 18) & 0x3F];
        out[1] = b64_table[(v >> 12) & 0x3F];
        out[2] = (i + 1 < len) ? b64_table[(v >> 6) & 0x3F] : '=';
        out[3] = '=';
        *outp = out + 4;
    }
}

int resqlite_json_write_base64(resqlite_buf* __restrict b,
                               const unsigned char* data, int len) {
    // Output size: 4 chars per 3 bytes, rounded up, plus quotes.
    int encoded_len = ((len + 2) / 3) * 4;
    if (buf_write_char(b, '"') != 0) return -1;
    if (buf_ensure(b, encoded_len) != 0) return -1;

    if (RESQLITE_UNLIKELY(!b64_pair_table_initialized)) {
        init_b64_pair_table();
    }

    unsigned char* out = b->data + b->len;
    int i = 0;

#if RESQLITE_JSON_HAS_NEON
    // SIMD bulk: 48 input bytes -> 64 output bytes per iteration on AArch64.
    // The kernel is out-of-line so the small-blob path — which never enters it
    // — keeps the scalar layout.
    if (len >= 48) {
        int consumed = b64_neon_bulk(data, len, out);
        i = consumed;
        out += consumed / 3 * 4;
    }
#endif

    // Scalar 12-bit-LUT loop, 4x-unrolled (exp 216 unroll, exp 225 pair LUT).
    for (; i <= len - 12; i += 12) {
        RESQLITE_WRITE_B64_TRIPLET(i);
        RESQLITE_WRITE_B64_TRIPLET(i + 3);
        RESQLITE_WRITE_B64_TRIPLET(i + 6);
        RESQLITE_WRITE_B64_TRIPLET(i + 9);
    }
    for (; i <= len - 3; i += 3) {
        RESQLITE_WRITE_B64_TRIPLET(i);
    }

    b64_write_tail(data, i, len, &out);

    b->len += encoded_len;
    return buf_write_char(b, '"');
}

int resqlite_json_write_base64_scalar(resqlite_buf* __restrict b,
                                      const unsigned char* data, int len) {
    int encoded_len = ((len + 2) / 3) * 4;
    if (buf_write_char(b, '"') != 0) return -1;
    if (buf_ensure(b, encoded_len) != 0) return -1;

    if (RESQLITE_UNLIKELY(!b64_pair_table_initialized)) {
        init_b64_pair_table();
    }

    unsigned char* out = b->data + b->len;
    int i = 0;
    for (; i <= len - 12; i += 12) {
        RESQLITE_WRITE_B64_TRIPLET(i);
        RESQLITE_WRITE_B64_TRIPLET(i + 3);
        RESQLITE_WRITE_B64_TRIPLET(i + 6);
        RESQLITE_WRITE_B64_TRIPLET(i + 9);
    }
    for (; i <= len - 3; i += 3) {
        RESQLITE_WRITE_B64_TRIPLET(i);
    }

    b64_write_tail(data, i, len, &out);

    b->len += encoded_len;
    return buf_write_char(b, '"');
}

#undef RESQLITE_WRITE_B64_TRIPLET

// ---------------------------------------------------------------------------
// String escaping
// ---------------------------------------------------------------------------

// Maps each byte to its JSON escape string length (0 = safe).
// 2 = two-char escape (\", \\, \b, \f, \n, \r, \t), 6 = \uXXXX.
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

// Maps an escapable byte to its 2-char escape suffix.
static const char json_esc_char[256] = {
    ['"']  = '"',
    ['\\'] = '\\',
    ['\b'] = 'b',
    ['\f'] = 'f',
    ['\n'] = 'n',
    ['\r'] = 'r',
    ['\t'] = 't',
};

static const char json_hex_digits[] = "0123456789abcdef";

#if RESQLITE_JSON_HAS_NEON
// Fused safe-prefix scan + copy for long JSON strings. Each loaded vector is
// classified for the only bytes that require JSON escaping (< 0x20, quote,
// and backslash). A fully safe vector is stored directly to the destination,
// removing the scalar path's separate scan and later memcpy traversal. The
// first vector containing an escapable byte is left untouched for the scalar
// tail below. This is inlined only into the out-of-line long-string encoder,
// keeping NEON state out of the scalar path while avoiding a second call.
RESQLITE_HOT static inline int json_copy_safe_prefix_neon(
    const unsigned char* __restrict src,
    int len,
    unsigned char* __restrict dst
) {
    const uint8x16_t space = vdupq_n_u8(0x20);
    const uint8x16_t quote = vdupq_n_u8('"');
    const uint8x16_t backslash = vdupq_n_u8('\\');

    int i = 0;
    while (i <= len - 16) {
        uint8x16_t bytes = vld1q_u8(src + i);
        uint8x16_t needs_escape = vorrq_u8(
            vcltq_u8(bytes, space),
            vorrq_u8(vceqq_u8(bytes, quote), vceqq_u8(bytes, backslash))
        );
        if (RESQLITE_UNLIKELY(vmaxvq_u8(needs_escape) != 0)) break;
        vst1q_u8(dst + i, bytes);
        i += 16;
    }
    return i;
}
#endif // RESQLITE_JSON_HAS_NEON

RESQLITE_HOT static int json_write_u00_escape(resqlite_buf* b, unsigned char c) {
    if (buf_ensure(b, 6) != 0) return -1;
    unsigned char* out = b->data + b->len;
    out[0] = '\\';
    out[1] = 'u';
    out[2] = '0';
    out[3] = '0';
    out[4] = (unsigned char)json_hex_digits[c >> 4];
    out[5] = (unsigned char)json_hex_digits[c & 0x0f];
    b->len += 6;
    return 0;
}

int resqlite_json_write_string(resqlite_buf* __restrict b,
                               const char* s, int len) {
    if (buf_write_char(b, '"') != 0) return -1;

    int start = 0;
    int i = 0;

    // SWAR: scan 8 bytes at a time for the common case (no escapes needed).
    // For each target byte (< 0x20, '"', '\\') use the "has zero byte" trick:
    // XOR the word with the repeated target, then (v - 0x01..) & ~v & 0x80..
    // flags any lane that hit. Pure portable C, no SIMD intrinsics.
    while (i + 8 <= len) {
        uint64_t word;
        memcpy(&word, s + i, 8);

        uint64_t below_space = (word - 0x2020202020202020ULL) & ~word & 0x8080808080808080ULL;
        uint64_t xor_quote = word ^ 0x2222222222222222ULL;
        uint64_t has_quote = (xor_quote - 0x0101010101010101ULL) & ~xor_quote & 0x8080808080808080ULL;
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
            if (json_write_u00_escape(b, c) != 0) return -1;
        }
        start = i + 1;
    }

    // Flush remaining unescaped span.
    if (start < len && buf_write(b, s + start, len - start) != 0) return -1;

    return buf_write_char(b, '"');
}

#if RESQLITE_JSON_HAS_NEON
// Continue from the first vector that may contain an escape. The already copied
// prefix is committed once, then the canonical byte loop owns the remainder.
// Kept out-of-line so the all-safe NEON path does not carry its register frame.
__attribute__((noinline))
static int json_write_string_neon_escaped_tail(
    resqlite_buf* __restrict b, const char* s, int len, int copied
) {
    b->len += copied;
    int start = copied;
    for (int i = copied; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        unsigned char elen = json_esc_len[c];

        if (RESQLITE_LIKELY(elen == 0)) continue;

        if (i > start && buf_write(b, s + start, i - start) != 0) return -1;

        if (elen == 2) {
            char pair[2] = { '\\', json_esc_char[c] };
            if (buf_write(b, pair, 2) != 0) return -1;
        } else {
            if (json_write_u00_escape(b, c) != 0) return -1;
        }
        start = i + 1;
    }

    if (start < len && buf_write(b, s + start, len - start) != 0) return -1;

    return buf_write_char(b, '"');
}

// Long-string encoder. NEON classifies and copies only the safe prefix. If it
// encounters an escapable vector, the canonical byte loop resumes at that
// vector and remains scalar for the rest of the string; SIMD is never restarted
// after an escape.
__attribute__((noinline))
RESQLITE_HOT int resqlite_json_write_string_neon(
    resqlite_buf* __restrict b, const char* s, int len
) {
    if (buf_write_char(b, '"') != 0) return -1;
    if (buf_ensure(b, len) != 0) return -1;

    unsigned char* out = b->data + b->len;
    int copied = json_copy_safe_prefix_neon(
        (const unsigned char*)s, len, out
    );

    if (copied > len - 16) {
        for (int i = copied; i < len; i++) {
            if (json_esc_len[(unsigned char)s[i]] != 0) {
                return json_write_string_neon_escaped_tail(b, s, len, copied);
            }
        }
        if (copied < len) memcpy(out + copied, s + copied, len - copied);
        b->len += len;
        return buf_write_char(b, '"');
    }

    return json_write_string_neon_escaped_tail(b, s, len, copied);
}
#endif // RESQLITE_JSON_HAS_NEON

// ---------------------------------------------------------------------------
// Test support
// ---------------------------------------------------------------------------

// Encode `len` input bytes as base64 into `out` (caller-allocated, at least
// ((len+2)/3)*4 + 2 bytes for the surrounding quotes). `force_scalar` selects
// the always-scalar reference path; otherwise the shipped dispatcher (NEON
// where available). Returns bytes written, or -1 on allocation failure. Used
// only by the differential encoder fuzz test — not part of the query hot path.
int resqlite_test_base64_encode(const unsigned char* data, int len,
                                unsigned char* out, int force_scalar) {
    resqlite_buf b;
    if (buf_init(&b, len * 2 + 16) != 0) return -1;
    int rc = force_scalar
        ? resqlite_json_write_base64_scalar(&b, data, len)
        : resqlite_json_write_base64(&b, data, len);
    if (rc != 0) { free(b.data); return -1; }
    int n = b.len;
    memcpy(out, b.data, n);
    free(b.data);
    return n;
}
