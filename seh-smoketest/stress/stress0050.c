/*
 * Floating-point locals live across the handler. On amd64 xmm6-xmm15 are
 * callee-saved, so a backend that does not restore them corrupts these.
 */
#include "stress_common.h"
char test[] = "stress0050";
static double sink(double v) { return v; }
int main(void)
{
    double d0 = sink(1.5), d1 = sink(2.5), d2 = sink(3.5), d3 = sink(4.5);
    double d4 = sink(5.5), d5 = sink(6.5), d6 = sink(7.5), d7 = sink(8.5);
    volatile int handled = 0;
    try {
        d0 += 1.0; d1 += 1.0; d2 += 1.0; d3 += 1.0;
        d4 += 1.0; d5 += 1.0; d6 += 1.0; d7 += 1.0;
        RaiseException(TEST_EXC, 0, 0, 0);
        d0 = d1 = d2 = d3 = d4 = d5 = d6 = d7 = -1.0;
    }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "d0", (long)(d0 * 2), 5)) return -1;
    if (check_int(test, "d3", (long)(d3 * 2), 11)) return -1;
    if (check_int(test, "d5", (long)(d5 * 2), 15)) return -1;
    return check_int(test, "d7", (long)(d7 * 2), 19);
}
