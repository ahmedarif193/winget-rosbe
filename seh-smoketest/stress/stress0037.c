/* Integer divide by zero raised by the CPU, not by RaiseException. */
#include "stress_common.h"
char test[] = "stress0037";
static volatile int zero = 0;
static volatile int one = 1;
int main(void)
{
    volatile unsigned long code = 0;
    volatile int q = 0;
    try { q = one / zero; }
    except(code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) { mark('H'); }
    endtry
    (void)q;
    if (check_trace(test, "H")) return -1;
    return check_int(test, "code", (long)code,
                     (long)EXCEPTION_INT_DIVIDE_BY_ZERO);
}
