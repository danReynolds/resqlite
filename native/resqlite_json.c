// JSON value encoders for selectBytes() output. See resqlite_json.h for the
// module boundary. This TU owns the base64 and string-escape encoders and the
// only SIMD kernel in resqlite; the number formatters are inline in the header.

#include "resqlite_json.h"

// SIMD kernel gating: AArch64 with NEON is the only ISA with a resqlite SIMD
// kernel. `vqtbl4q_u8` / `vld3q_u8` / `vst4q_u8` are AArch64-only and cover
// macOS/iOS/Android arm64. 32-bit ARM lacks `vqtbl4q_u8`; x86_64 SSSE3 needs a
// different table-lookup approach (deferred). Every other target uses the
// scalar 12-bit-LUT encoder.
#if defined(__aarch64__) && defined(__ARM_NEON)
#define RESQLITE_HAS_NEON_BASE64 1
#include <arm_neon.h>
#else
#define RESQLITE_HAS_NEON_BASE64 0
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

#if RESQLITE_HAS_NEON_BASE64
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
#endif // RESQLITE_HAS_NEON_BASE64

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

#if RESQLITE_HAS_NEON_BASE64
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

// Encode `val` as JSON decimal digits into `out` (caller-allocated, at least
// RESQLITE_JSON_INT_MAX bytes; no NUL written). Returns bytes written. Used
// only by the differential test to assert the shipped integer formatter
// matches Dart's oracle across boundary magnitudes and the full i64 range —
// added by exp 231, which found the scalar two-digit path had no such
// coverage. Not part of the query hot path.
int resqlite_test_i64_to_str(long long val, char* out) {
    return resqlite_json_i64_to_str(val, out);
}

// ---------------------------------------------------------------------------
// exp 240 — batched i64 -> decimal encoders (test/bench only)
//
// exp 231 rejected a per-value NEON i64 formatter: a scalar per-cell value has
// "nothing to amortise" over the SIMD setup. Its explicit reopen condition was
// "a future architecture that batches many integer cells into one encode call
// (a columnar/bulk transfer that hands the kernel an array of i64s)". These
// three implementations format a comma-separated array of i64 in ONE call so
// the batch can (a) drop exp 231's per-value out-of-line call overhead and
// (b) expose cross-value ILP that per-cell dispatch cannot. All three emit
// byte-identical output; `i64_batch_encode.dart` A/Bs them and a differential
// test asserts parity. None ship in the query path.
// ---------------------------------------------------------------------------

// Baseline: what write_json_to_buf's SQLITE_INTEGER arm does today, once per
// cell — the shipped scalar two-digit-LUT formatter, comma-separated.
int resqlite_test_i64_array_scalar(const long long* vals, int n, char* out) {
    char* p = out;
    for (int i = 0; i < n; i++) {
        if (i) *p++ = ',';
        p += resqlite_json_i64_to_str(vals[i], p);
    }
    return (int)(p - out);
}

// 2-way software-pipelined scalar: peel two decimal digits off two independent
// values per loop trip so their (magic-number) division chains overlap in the
// out-of-order window instead of serialising one value fully before the next.
// Same two-digit-LUT primitive as the baseline; the only change is the batch
// shape. Tail (odd last value) falls back to the scalar formatter.
static inline void split_magnitude(long long v, unsigned long long* uval,
                                    int* negative) {
    if (v < 0) {
        *negative = 1;
        *uval = (unsigned long long)(-(v + 1)) + 1; // avoid UB on LLONG_MIN
    } else {
        *negative = 0;
        *uval = (unsigned long long)v;
    }
}

int resqlite_test_i64_array_pipe2(const long long* vals, int n, char* out) {
    char* p = out;
    int i = 0;
    for (; i + 2 <= n; i += 2) {
        unsigned long long u0, u1;
        int neg0, neg1;
        split_magnitude(vals[i], &u0, &neg0);
        split_magnitude(vals[i + 1], &u1, &neg1);

        // Generate both values' digits LSB-first into separate scratch fields,
        // peeling a two-digit pair from each per trip. The two chains are data
        // independent, so the CPU can issue value 1's multiply while value 0's
        // is still retiring.
        char t0[20], t1[20];
        int p0 = 20, p1 = 20;
        while (u0 >= 100 && u1 >= 100) {
            unsigned d0 = (unsigned)(u0 % 100); u0 /= 100;
            unsigned d1 = (unsigned)(u1 % 100); u1 /= 100;
            p0 -= 2; memcpy(t0 + p0, resqlite_json_two_digits + d0 * 2, 2);
            p1 -= 2; memcpy(t1 + p1, resqlite_json_two_digits + d1 * 2, 2);
        }
        while (u0 >= 100) {
            unsigned d = (unsigned)(u0 % 100); u0 /= 100;
            p0 -= 2; memcpy(t0 + p0, resqlite_json_two_digits + d * 2, 2);
        }
        while (u1 >= 100) {
            unsigned d = (unsigned)(u1 % 100); u1 /= 100;
            p1 -= 2; memcpy(t1 + p1, resqlite_json_two_digits + d * 2, 2);
        }
        if (u0 >= 10) { p0 -= 2; memcpy(t0 + p0, resqlite_json_two_digits + u0 * 2, 2); }
        else { t0[--p0] = (char)('0' + (unsigned)u0); }
        if (u1 >= 10) { p1 -= 2; memcpy(t1 + p1, resqlite_json_two_digits + u1 * 2, 2); }
        else { t1[--p1] = (char)('0' + (unsigned)u1); }

        if (i) *p++ = ',';
        if (neg0) *p++ = '-';
        int dg0 = 20 - p0; memcpy(p, t0 + p0, dg0); p += dg0;
        *p++ = ',';
        if (neg1) *p++ = '-';
        int dg1 = 20 - p1; memcpy(p, t1 + p1, dg1); p += dg1;
    }
    for (; i < n; i++) {
        if (i) *p++ = ',';
        p += resqlite_json_i64_to_str(vals[i], p);
    }
    return (int)(p - out);
}

#if RESQLITE_HAS_NEON_BASE64
// Convert one 8-digit group `v` (0..99999999) into exactly 8 zero-padded ASCII
// bytes at `out`, MSD first. Reused verbatim from exp 231's archived kernel
// (differential-verified). Two vector reciprocal splits, no serial digit
// dependency: /100 for d<10000 is (d*5243)>>19; /10 for p<100 is (p*205)>>11.
static inline void neon_write_8_digits(uint32_t v, unsigned char* out) {
    uint32_t hi = v / 10000;
    uint32_t lo = v - hi * 10000;
    uint32x2_t d4 = vset_lane_u32(lo, vdup_n_u32(hi), 1); // {hi, lo}
    uint32x2_t q = vshr_n_u32(vmul_n_u32(d4, 5243), 19);  // {hi/100, lo/100}
    uint32x2_t r = vsub_u32(d4, vmul_n_u32(q, 100));      // {hi%100, lo%100}
    uint16x4_t qn = vmovn_u32(vcombine_u32(q, vdup_n_u32(0)));
    uint16x4_t rn = vmovn_u32(vcombine_u32(r, vdup_n_u32(0)));
    uint16x4_t p = vzip_u16(qn, rn).val[0];               // {q0,r0,q1,r1}
    uint16x4_t tens = vshr_n_u16(vmul_n_u16(p, 205), 11); // p/10
    uint16x4_t ones = vsub_u16(p, vmul_n_u16(tens, 10));  // p%10
    uint16x4x2_t io = vzip_u16(tens, ones);
    uint16x8_t digits16 = vcombine_u16(io.val[0], io.val[1]);
    uint8x8_t digits8 = vadd_u8(vmovn_u16(digits16), vdup_n_u8('0'));
    vst1_u8(out, digits8);
}

static inline int neon_write_group_trimmed(uint32_t v, unsigned char* out) {
    unsigned char tmp[8];
    neon_write_8_digits(v, tmp);
    int start = 0;
    while (start < 7 && tmp[start] == '0') start++;
    int n = 8 - start;
    memcpy(out, tmp + start, n);
    return n;
}

// Full-range magnitude formatter (handles < 1e8 too, unlike exp 231's shipped
// >= 1e8 variant). Inlined into the array loop so adjacent values' independent
// 8-digit-group formatting overlaps — the amortisation exp 231's out-of-line
// per-value kernel could not provide.
static inline int neon_write_u64(unsigned long long uval, char* buf) {
    unsigned char* p = (unsigned char*)buf;
    if (uval < 100000000ULL) {
        return neon_write_group_trimmed((uint32_t)uval, p);
    }
    unsigned long long low8 = uval % 100000000ULL;
    unsigned long long t = uval / 100000000ULL;
    unsigned long long mid8 = t % 100000000ULL;
    unsigned long long high = t / 100000000ULL;   // 0..1844
    if (high != 0) {
        p += neon_write_group_trimmed((uint32_t)high, p);
        neon_write_8_digits((uint32_t)mid8, p); p += 8;
    } else {
        p += neon_write_group_trimmed((uint32_t)mid8, p);
    }
    neon_write_8_digits((uint32_t)low8, p); p += 8;
    return (int)(p - (unsigned char*)buf);
}
#endif // RESQLITE_HAS_NEON_BASE64

// NEON batch: the faithful form of exp 231's reopen — a SIMD kernel handed an
// array of i64s. Formats each value with the vector digit kernel, inlined so
// values pipeline. Non-AArch64 falls back to the scalar baseline.
int resqlite_test_i64_array_neon(const long long* vals, int n, char* out) {
#if RESQLITE_HAS_NEON_BASE64
    char* p = out;
    for (int i = 0; i < n; i++) {
        if (i) *p++ = ',';
        long long v = vals[i];
        if (v == 0) { *p++ = '0'; continue; }
        unsigned long long uval;
        int negative;
        split_magnitude(v, &uval, &negative);
        if (negative) *p++ = '-';
        p += neon_write_u64(uval, p);
    }
    return (int)(p - out);
#else
    return resqlite_test_i64_array_scalar(vals, n, out);
#endif
}
