// Copyright 2018 Ulf Adams
//
// The contents of this file may be used under the terms of the Apache License,
// Version 2.0.
//
//    (See accompanying file LICENSE or copy at
//     http://www.apache.org/licenses/LICENSE-2.0)
//
// Alternatively, the contents of this file may be used under the terms of
// the Boost Software License, Version 1.0.
//    (See https://www.boost.org/LICENSE_1_0.txt)
//
// Unless required by applicable law or agreed to in writing, this software
// is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.
//
// ---------------------------------------------------------------------------
// Note: Only a subset of the upstream Ryu API is vendored. We compile
// `d2s.c` (double-to-shortest-string) and expose only those functions below.
// Upstream also ships `f2s.c`, `d2fixed.c`, and `d2s_to_chars.c` for float,
// fixed-precision, and exponential variants; those sources are NOT vendored
// and their declarations are deliberately omitted from this header to
// prevent accidental link-time failures.
// ---------------------------------------------------------------------------
#ifndef RYU_H
#define RYU_H

#ifdef __cplusplus
extern "C" {
#endif

#include <inttypes.h>

// d2s: shortest round-trippable decimal representation of a double.
// Output is always in scientific notation ("1E2", "3.14E0", "0E0").
// resqlite wraps these via d2s_g_format() in resqlite.c to match %.17g-style
// formatting (plain decimal for exp in [-4, 16], scientific otherwise).
int d2s_buffered_n(double f, char* result);
void d2s_buffered(double f, char* result);
char* d2s(double f);

#ifdef __cplusplus
}
#endif

#endif // RYU_H
