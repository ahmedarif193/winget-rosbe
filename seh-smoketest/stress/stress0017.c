/* A filter must be evaluated exactly once per exception dispatch. */
#include "stress_common.h"
char test[] = "stress0017";
static volatile int filter_calls;
static int counting_filter(void) { filter_calls++; return EXCEPTION_EXECUTE_HANDLER; }
int main(void)
{
    volatile int handled = 0;
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(counting_filter()) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_int(test, "filter evaluations", filter_calls, 1);
}
