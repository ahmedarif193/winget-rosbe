/* Exception raised through an indirect (function-pointer) call. */
#include "stress_common.h"
char test[] = "stress0048";
static void thrower(void) { mark('t'); RaiseException(TEST_EXC, 0, 0, 0); mark('!'); }
static void (*volatile fp)(void) = thrower;
int main(void)
{
    volatile int handled = 0;
    try { fp(); mark('!'); }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('H'); handled = 1; }
    endtry
    if (check_trace(test, "tH")) return -1;
    return check_int(test, "handled", handled, 1);
}
