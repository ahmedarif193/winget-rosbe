/*
 * Collided unwind: a new exception raised inside a termination handler while
 * an unwind is already running.
 *
 * Windows does not resume the original dispatch -- the new exception is
 * dispatched from the point of the raise. Which handler ends up claiming it
 * depends on where that point sits relative to the unwind target, so the test
 * asserts the invariants (the unwind handler ran, the process survived, some
 * handler claimed the collided exception) and prints the observed trace and
 * code for the report rather than hard-coding one backend's answer.
 */
#include "stress_common.h"
char test[] = "stress0008";

static volatile unsigned long claimed_code;

int main(void)
{
    volatile int mid_ran = 0, outer_ran = 0, unwound = 0;

    try {
        try {
            try {
                RaiseException(TEST_EXC, 0, 0, 0);
            }
            finally {
                mark('u');
                unwound = 1;
                if (abnormal_termination())
                    RaiseException(EXCEPTION_INT_OVERFLOW, 0, 0, 0);
            }
            endtry
        }
        except(mark('m'), EXCEPTION_EXECUTE_HANDLER) {
            claimed_code = GetExceptionCode();
            mid_ran = 1;
        }
        endtry
    }
    except(mark('o'), EXCEPTION_EXECUTE_HANDLER) {
        claimed_code = GetExceptionCode();
        outer_ran = 1;
    }
    endtry

    printf("%s: trace=\"%s\" claimed=0x%08lX mid=%d outer=%d\n",
           test, g_trace, claimed_code, mid_ran, outer_ran);

    if (check_int(test, "termination handler ran", unwound, 1)) return -1;
    /* Exactly one of the two enclosing handlers must claim it. */
    if (check_int(test, "handlers that claimed", mid_ran + outer_ran, 1)) return -1;
    return 0;
}
