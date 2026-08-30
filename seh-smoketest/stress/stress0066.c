/* Handler must run with a correctly aligned stack (16-byte on amd64). */
#include "stress_common.h"
char test[] = "stress0066";
static volatile ULONG_PTR sp_in_handler;
static double alignment_probe(void)
{
    /* Requires an aligned stack for spills on amd64 ABI. */
    volatile double v[4] = { 1.0, 2.0, 3.0, 4.0 };
    return v[0] + v[1] + v[2] + v[3];
}
int main(void)
{
    volatile int handled = 0;
    volatile double r = 0.0;
    int local;
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) {
        int probe;
        sp_in_handler = (ULONG_PTR)&probe;
        r = alignment_probe();
        handled = 1;
    }
    endtry
    (void)local;
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "aligned fp work in handler", (long)r, 10)) return -1;
    return check_int(test, "handler had a stack frame", sp_in_handler != 0, 1);
}
