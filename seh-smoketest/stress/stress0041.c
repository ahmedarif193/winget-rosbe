/* A noncontinuable exception: a filter asking to continue must be refused. */
#include "stress_common.h"
char test[] = "stress0041";
static volatile int filter_calls;
static int try_continue(void)
{
    filter_calls++;
    /* Asking to resume a noncontinuable exception raises
       STATUS_NONCONTINUABLE_EXCEPTION rather than resuming. */
    return (filter_calls == 1) ? EXCEPTION_CONTINUE_EXECUTION
                               : EXCEPTION_EXECUTE_HANDLER;
}
int main(void)
{
    volatile unsigned long code = 0;
    volatile int handled = 0;
    try {
        try {
            RaiseException(TEST_EXC, EXCEPTION_NONCONTINUABLE, 0, 0);
        }
        except(try_continue()) { mark('i'); handled = 1; }
        endtry
    }
    except(code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) {
        mark('o'); handled = 2;
    }
    endtry
    printf("%s: trace=\"%s\" code=0x%08lX handled=%d filter_calls=%d\n",
           test, g_trace, code, handled, filter_calls);
    /* Either the inner or the outer handler claims it, but execution must not
       resume at the RaiseException. */
    return check_int(test, "some handler ran", handled != 0, 1);
}
