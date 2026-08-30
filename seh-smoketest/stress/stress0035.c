/* Access violation on READ of an unmapped address. */
#include "stress_common.h"
char test[] = "stress0035";
static volatile int * volatile bad = 0;
int main(void)
{
    volatile unsigned long code = 0;
    volatile int sink = 0;
    try { sink = *bad; }
    except(code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) { mark('H'); }
    endtry
    (void)sink;
    if (check_trace(test, "H")) return -1;
    return check_int(test, "code", (long)code, (long)EXCEPTION_ACCESS_VIOLATION);
}
