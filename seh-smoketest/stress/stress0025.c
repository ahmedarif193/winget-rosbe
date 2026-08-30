/* A try/except inside a termination handler, running during an unwind. */
#include "stress_common.h"
char test[] = "stress0025";
int main(void)
{
    volatile int nested = 0, outer = 0;
    try {
        try { RaiseException(TEST_EXC, 0, 0, 0); }
        finally {
            mark('u');
            try { RaiseException(EXCEPTION_INT_OVERFLOW, 0, 0, 0); }
            except(EXCEPTION_EXECUTE_HANDLER) { mark('n'); nested = 1; }
            endtry
        }
        endtry
    }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('H'); outer = 1; }
    endtry
    if (check_int(test, "nested handler ran", nested, 1)) return -1;
    if (check_int(test, "outer handler ran", outer, 1)) return -1;
    return check_trace(test, "unH");
}
