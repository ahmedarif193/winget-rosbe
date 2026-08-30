/* try/except guarding a call that itself installs and uses try/finally. */
#include "stress_common.h"
char test[] = "stress0061";
static int callee(int mode)
{
    volatile int r = 0;
    try {
        mark('c');
        if (mode) RaiseException(TEST_EXC, 0, 0, 0);
        r = 1;
    }
    finally { mark('f'); }
    endtry
    return r;
}
static volatile int mode = 1;
int main(void)
{
    volatile int handled = 0, r = -1;
    try { r = callee(mode); }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('H'); handled = 1; }
    endtry
    if (check_trace(test, "cfH")) return -1;
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_int(test, "return value untouched", r, -1);
}
