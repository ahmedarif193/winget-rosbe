/* Filter that itself contains a complete try/except. */
#include "stress_common.h"
char test[] = "stress0070";
static int guarded_filter(void)
{
    volatile int inner = 0;
    mark('f');
    try { RaiseException(EXCEPTION_INT_OVERFLOW, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('g'); inner = 1; }
    endtry
    return inner ? EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH;
}
int main(void)
{
    volatile int handled = 0;
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(guarded_filter()) { mark('H'); handled = 1; }
    endtry
    if (check_trace(test, "fgH")) return -1;
    return check_int(test, "handled", handled, 1);
}
