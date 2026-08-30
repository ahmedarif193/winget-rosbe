/*
 * Callee-saved registers must be restored when an exception unwinds into a
 * handler. Optimizers keep hot locals in ebx/esi/edi (rbx/r12-r15), so a
 * backend that fails to restore them corrupts values the handler still reads.
 */
#include "stress_common.h"
char test[] = "stress0013";

static int sink(int v) { return v; }

int main(void)
{
    /* Enough live values to force register allocation across the try. */
    int a = sink(0x1001), b = sink(0x2002), c = sink(0x3003);
    int d = sink(0x4004), e = sink(0x5005), f = sink(0x6006);
    volatile int caught = 0;

    try {
        a += sink(1); b += sink(1); c += sink(1);
        d += sink(1); e += sink(1); f += sink(1);
        RaiseException(TEST_EXC, 0, 0, 0);
        a = b = c = d = e = f = -1;      /* unreachable */
    }
    except(EXCEPTION_EXECUTE_HANDLER) {
        caught = 1;
    }
    endtry

    if (check_int(test, "caught", caught, 1)) return -1;
    if (check_int(test, "a", a, 0x1002)) return -1;
    if (check_int(test, "b", b, 0x2003)) return -1;
    if (check_int(test, "c", c, 0x3004)) return -1;
    if (check_int(test, "d", d, 0x4005)) return -1;
    if (check_int(test, "e", e, 0x5006)) return -1;
    return check_int(test, "f", f, 0x6007);
}
