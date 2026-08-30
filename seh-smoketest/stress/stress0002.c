/*
 * Two-pass semantics: every filter on the way out runs BEFORE any termination
 * handler unwinds. A one-pass implementation runs the finally first and gets
 * "fF" instead of "Ff".
 */
#include "stress_common.h"
char test[] = "stress0002";

int main(void)
{
    try {
        try {
            RaiseException(TEST_EXC, 0, 0, 0);
        }
        finally {
            mark('f');           /* unwind: second pass */
        }
        endtry
    }
    except(mark('F'), EXCEPTION_EXECUTE_HANDLER) {   /* filter: first pass */
        mark('H');
    }
    endtry

    return check_trace(test, "FfH");
}
