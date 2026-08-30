/* Exception raised at the bottom of a 200-frame recursion. */
#include "stress_common.h"
char test[] = "stress0045";
#define DEPTH 200
static int deep(int n)
{
    if (n == 0) { RaiseException(TEST_EXC, 0, 0, 0); return -1; }
    return deep(n - 1) + 1;
}
int main(void)
{
    volatile int handled = 0;
    volatile unsigned long code = 0;
    try { deep(DEPTH); }
    except(code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_int(test, "code", (long)code, (long)TEST_EXC);
}
