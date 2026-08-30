/*
 * Stack overflow must surface as EXCEPTION_STACK_OVERFLOW and be catchable.
 *
 * burn() consumes the frame *after* the recursive call and feeds the result
 * back, so the call is not in tail position and cannot be rewritten into a
 * loop at -O2/-O3 -- otherwise the test spins forever instead of overflowing.
 */
#include "stress_common.h"
char test[] = "stress0073";

static volatile int depth;

#if defined(__GNUC__)
__attribute__((noinline))
#endif
static int burn(int n)
{
    volatile char pad[4096];
    int r;
    pad[0] = (char)n;
    pad[4095] = (char)(n + 1);
    depth++;
    r = burn(n + 1);
    return r + pad[0] + pad[4095];   /* keeps the frame live past the call */
}

int main(void)
{
    volatile unsigned long code = 0;
    volatile int handled = 0;

    try { burn(0); }
    except(code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry

    printf("%s: depth=%d code=0x%08lX\n", test, depth, code);
    if (check_int(test, "recursion made progress", depth > 100, 1)) return -1;
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_int(test, "code", (long)code, (long)EXCEPTION_STACK_OVERFLOW);
}
