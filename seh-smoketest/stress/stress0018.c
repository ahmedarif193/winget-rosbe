/* Declining filters are evaluated once each, innermost first. */
#include "stress_common.h"
char test[] = "stress0018";
static volatile int inner_calls, outer_calls;
int main(void)
{
    volatile int handled = 0;
    try {
        try { RaiseException(TEST_EXC, 0, 0, 0); }
        except(inner_calls++, EXCEPTION_CONTINUE_SEARCH) { mark('!'); }
        endtry
    }
    except(outer_calls++, EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "inner filter calls", inner_calls, 1)) return -1;
    return check_int(test, "outer filter calls", outer_calls, 1);
}
