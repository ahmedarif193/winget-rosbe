/* Propagation across function boundaries: raise deep, catch shallow. */
#include "stress_common.h"
char test[] = "stress0014";

static void level3(void) { mark('3'); RaiseException(TEST_EXC, 0, 0, 0); mark('!'); }

static void level2(void)
{
    try { mark('2'); level3(); mark('!'); }
    finally { mark('u'); }
    endtry
}

static void level1(void) { mark('1'); level2(); mark('!'); }

int main(void)
{
    volatile unsigned long code = 0;

    try {
        level1();
        mark('!');
    }
    except(EXCEPTION_EXECUTE_HANDLER) {
        code = GetExceptionCode();
        mark('H');
    }
    endtry

    if (check_trace(test, "123uH")) return -1;
    return check_int(test, "code", (long)code, (long)TEST_EXC);
}
