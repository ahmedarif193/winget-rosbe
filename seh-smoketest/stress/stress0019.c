/*
 * A filter executes as a funclet but must see the establishing frame's
 * locals. This is where a backend that gets the frame pointer wrong fails.
 */
#include "stress_common.h"
char test[] = "stress0019";
static volatile int seen_a, seen_b, seen_c;
int main(void)
{
    volatile int a = 0x1234, b = 0x5678, c = 0x9ABC;
    volatile int handled = 0;
    try {
        a = 0x1111; b = 0x2222; c = 0x3333;
        RaiseException(TEST_EXC, 0, 0, 0);
    }
    except(seen_a = a, seen_b = b, seen_c = c, EXCEPTION_EXECUTE_HANDLER) {
        handled = 1;
    }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "filter saw a", seen_a, 0x1111)) return -1;
    if (check_int(test, "filter saw b", seen_b, 0x2222)) return -1;
    return check_int(test, "filter saw c", seen_c, 0x3333);
}
