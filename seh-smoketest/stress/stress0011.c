/* Re-raise a different exception from inside an except block. */
#include "stress_common.h"
char test[] = "stress0011";

int main(void)
{
    volatile unsigned long inner = 0, outer = 0;

    try {
        try {
            RaiseException(TEST_EXC, 0, 0, 0);
        }
        except(EXCEPTION_EXECUTE_HANDLER) {
            inner = GetExceptionCode();
            mark('i');
            RaiseException(EXCEPTION_INT_DIVIDE_BY_ZERO, 0, 0, 0);
            mark('!');
        }
        endtry
        mark('!');
    }
    except(EXCEPTION_EXECUTE_HANDLER) {
        outer = GetExceptionCode();
        mark('o');
    }
    endtry

    if (check_trace(test, "io")) return -1;
    if (check_int(test, "inner code", (long)inner, (long)TEST_EXC)) return -1;
    return check_int(test, "outer code", (long)outer,
                     (long)EXCEPTION_INT_DIVIDE_BY_ZERO);
}
