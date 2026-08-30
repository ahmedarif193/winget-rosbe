/* Two independent try/except scopes in one function must not interfere. */
#include "stress_common.h"
char test[] = "stress0023";
int main(void)
{
    volatile int first = 0, second = 0;
    try { mark('1'); RaiseException(TEST_EXC, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('A'); first = 1; }
    endtry
    try { mark('2'); RaiseException(EXCEPTION_INT_OVERFLOW, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('B'); second = 1; }
    endtry
    if (check_trace(test, "1A2B")) return -1;
    if (check_int(test, "first", first, 1)) return -1;
    return check_int(test, "second", second, 1);
}
