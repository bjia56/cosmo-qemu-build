/* SPDX-License-Identifier: MIT */
/*
 * sscanf() with %[...] scansets for Cosmopolitan Libc, whose own sscanf()
 * lacks them (every scanset makes it return -1).
 *
 * The format is walked one directive at a time. Scansets are handled here;
 * every other conversion is passed to libc's sscanf() as a one-directive
 * format followed by %n, which also reports how much input it consumed.
 * Whitespace, literals and %% behave as in C. Supported scanset syntax:
 * optional * and width, ^ negation, a leading ] as a member, and ranges.
 */
#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#undef sscanf

#define MAX_DIRECTIVE 64

int cosmo_sscanf(const char *str, const char *fmt, ...)
{
    va_list ap;
    const char *in = str;
    int assigned = 0;

    va_start(ap, fmt);
    while (*fmt) {
        if (isspace((unsigned char)*fmt)) {
            while (isspace((unsigned char)*in)) {
                in++;
            }
            fmt++;
            continue;
        }
        if (*fmt != '%') {
            if (*in != *fmt) {
                goto done;
            }
            in++;
            fmt++;
            continue;
        }

        const char *start = fmt++;
        if (*fmt == '%') {
            while (isspace((unsigned char)*in)) {
                in++;
            }
            if (*in != '%') {
                goto done;
            }
            in++;
            fmt++;
            continue;
        }

        bool suppress = false;
        size_t width = 0;
        if (*fmt == '*') {
            suppress = true;
            fmt++;
        }
        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + (*fmt++ - '0');
        }

        if (*fmt != '[') {
            /* length modifiers, then the conversion character */
            while (*fmt && strchr("hlLqjzt", *fmt)) {
                fmt++;
            }
            if (!*fmt) {
                goto done;
            }
            fmt++;
            size_t len = fmt - start;
            if (len + 3 > MAX_DIRECTIVE) {
                goto done;
            }
            if (fmt[-1] == 'n') {
                if (!suppress) {
                    int *p = va_arg(ap, int *);
                    *p = in - str;
                }
                continue;
            }
            char sub[MAX_DIRECTIVE];
            memcpy(sub, start, len);
            memcpy(sub + len, "%n", 3);
            int used = -1;
            if (suppress) {
                sscanf(in, sub, &used);
            } else {
                void *arg = va_arg(ap, void *);
                if (sscanf(in, sub, arg, &used) != 1) {
                    goto done;
                }
                assigned++;
            }
            if (used < 0) {
                goto done;
            }
            in += used;
            continue;
        }

        /* scanset: [ ^? ]? members ] */
        fmt++;
        bool negate = false;
        if (*fmt == '^') {
            negate = true;
            fmt++;
        }
        const char *set = fmt;
        if (*fmt == ']') {
            fmt++;
        }
        while (*fmt && *fmt != ']') {
            fmt++;
        }
        if (!*fmt) {
            goto done;
        }
        const char *set_end = fmt++;

        bool member[256] = { false };
        for (const char *s = set; s < set_end; s++) {
            if (s + 2 < set_end && s[1] == '-') {
                unsigned char lo = s[0], hi = s[2];
                for (unsigned c = lo; c <= hi; c++) {
                    member[c] = true;
                }
                s += 2;
            } else {
                member[(unsigned char)*s] = true;
            }
        }

        char *out = suppress ? NULL : va_arg(ap, char *);
        size_t n = 0;
        while (in[n] && (width == 0 || n < width) &&
               member[(unsigned char)in[n]] != negate) {
            if (out) {
                out[n] = in[n];
            }
            n++;
        }
        if (n == 0) {
            goto done;
        }
        if (out) {
            out[n] = '\0';
            assigned++;
        }
        in += n;
    }

done:
    va_end(ap);
    if (assigned == 0 && !*in && in == str) {
        return EOF;
    }
    return assigned;
}
