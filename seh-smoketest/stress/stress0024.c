/* A complete try/except living inside another handler's body. */
#include "stress_common.h"
char test[] = "stress0024";
int main(void)
{
    volatile int outer = 0, inner = 0;
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) {
        outer = 1;
        mark('o');
        try { RaiseException(EXCEPTION_INT_OVERFLOW, 0, 0, 0); }
        except(EXCEPTION_EXECUTE_HANDLER) { mark('i'); inner = 1; }
        endtry
    }
    endtry
    if (check_trace(test, "oi")) return -1;
    if (check_int(test, "outer", outer, 1)) return -1;
    return check_int(test, "inner", inner, 1);
}
