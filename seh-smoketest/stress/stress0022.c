/*
 * Only the sign matters: <0 continues execution, 0 continues the search,
 * >0 executes the handler. Verify a large positive value still handles.
 */
#include "stress_common.h"
char test[] = "stress0022";
int main(void)
{
    volatile int handled = 0, searched = 0;
    try {
        try { RaiseException(TEST_EXC, 0, 0, 0); }
        except(0) { searched = 1; }          /* 0 == CONTINUE_SEARCH */
        endtry
    }
    except(12345) { handled = 1; }           /* >0 == EXECUTE_HANDLER */
    endtry
    if (check_int(test, "inner handler ran", searched, 0)) return -1;
    return check_int(test, "outer handler ran", handled, 1);
}
