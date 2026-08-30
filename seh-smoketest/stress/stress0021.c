/* GetExceptionCode() must agree between the filter and its handler. */
#include "stress_common.h"
char test[] = "stress0021";
static volatile unsigned long in_filter;
int main(void)
{
    volatile unsigned long in_handler = 0;
    try { RaiseException(EXCEPTION_INT_OVERFLOW, 0, 0, 0); }
    except(in_filter = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) {
        in_handler = GetExceptionCode();
    }
    endtry
    if (check_int(test, "filter code", (long)in_filter, (long)EXCEPTION_INT_OVERFLOW)) return -1;
    return check_int(test, "handler code", (long)in_handler, (long)EXCEPTION_INT_OVERFLOW);
}
