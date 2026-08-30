/* SEH inside a varargs function. */
#include "stress_common.h"
#include <stdarg.h>
char test[] = "stress0053";
static int sum_then_raise(int n, ...)
{
    va_list ap; int i, total = 0;
    volatile int handled = 0;
    va_start(ap, n);
    for (i = 0; i < n; i++) total += va_arg(ap, int);
    va_end(ap);
    try { if (total > 0) RaiseException(TEST_EXC, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    return handled ? total : -1;
}
int main(void)
{
    int r = sum_then_raise(4, 1, 2, 3, 4);
    return check_int(test, "varargs total after handling", r, 10);
}
