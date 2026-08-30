/*
 * Shared scaffolding for the PSEH stress corpus.
 *
 * Same contract as the Microsoft corpus the harness vendors: every test is a
 * standalone main() returning 0 on success and non-zero on failure, so the
 * harness treats both corpora identically.
 *
 * Most tests verify *ordering*, not just outcome -- an SEH implementation can
 * catch the right exception while running filters and unwind handlers in the
 * wrong order, which is precisely the class of bug that separates a real
 * two-pass implementation from an approximation. Each test appends a marker
 * character at every observable step and compares the resulting trace against
 * the sequence Windows produces.
 */

#ifndef PSEH_STRESS_COMMON_H
#define PSEH_STRESS_COMMON_H

#include <windows.h>
#include <stdio.h>
#include <string.h>

/* Resolves via -I to the harness-generated wrapper next to the MS corpus. */
#include "seh.h"

static char g_trace[256];
static int g_trace_len;

static void mark(char c)
{
    if (g_trace_len < (int)sizeof(g_trace) - 1)
        g_trace[g_trace_len++] = c;
    g_trace[g_trace_len] = '\0';
}

static int check_trace(const char *test, const char *expected)
{
    if (strcmp(g_trace, expected) == 0)
        return 0;
    printf("%s FAILED: trace \"%s\", expected \"%s\"\n", test, g_trace, expected);
    return -1;
}

static int check_int(const char *test, const char *what, long got, long want)
{
    if (got == want)
        return 0;
    printf("%s FAILED: %s = %ld, expected %ld\n", test, what, got, want);
    return -1;
}

/* Take the address of a volatile null pointer through a sink the optimizer
   cannot fold away, so the access-violation actually happens at runtime. */
static volatile int * volatile g_null_ptr = 0;

static void raise_av(void)
{
    *g_null_ptr = 1;
}

#define TEST_EXC 0xE0001234u   /* private, non-continuable-looking code */

#endif /* PSEH_STRESS_COMMON_H */
