/*
 * Unwind must pass through intermediate frames that establish no handler at
 * all, without losing the exception or the frames that do have one.
 */
#include "stress_common.h"
char test[] = "stress0033";
static void plain2(void) { RaiseException(TEST_EXC, 0, 0, 0); }
static void plain1(void) { plain2(); }
static void plain0(void) { plain1(); }
static void guarded(void)
{
    try { plain0(); }
    finally { mark('u'); }
    endtry
}
int main(void)
{
    volatile int handled = 0;
    try { guarded(); }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('H'); handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_trace(test, "uH");
}
