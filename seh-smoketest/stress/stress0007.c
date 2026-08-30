/*
 * An exception raised while an exception FILTER is executing.
 *
 * Windows dispatches the nested fault from the filter's own context; what a
 * given backend does here varies, and some abort the process outright. The
 * test therefore asserts only the invariants that are well-defined -- the
 * inner handler whose filter faulted must not run, and the process must not
 * silently continue as if nothing happened -- and prints the observed
 * behaviour so the report can record how each backend differs.
 */
#include "stress_common.h"
char test[] = "stress0007";

static volatile unsigned long outer_code;

static int faulting_filter(void)
{
    mark('f');
    raise_av();                  /* fault while evaluating the filter */
    mark('!');                   /* only if the AV was swallowed */
    return EXCEPTION_EXECUTE_HANDLER;
}

int main(void)
{
    volatile int inner_ran = 0, outer_ran = 0;

    try {
        try {
            RaiseException(TEST_EXC, 0, 0, 0);
        }
        except(faulting_filter()) {
            mark('i');
            inner_ran = 1;
        }
        endtry
    }
    except(outer_code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) {
        mark('o');
        outer_ran = 1;
    }
    endtry

    printf("%s: trace=\"%s\" outer_code=0x%08lX inner=%d outer=%d\n",
           test, g_trace, outer_code, inner_ran, outer_ran);

    /* The filter must have been entered at all. */
    if (g_trace[0] != 'f')
        return check_trace(test, "f...");
    /* The handler guarded by the faulting filter must not run. */
    if (check_int(test, "inner handler ran", inner_ran, 0)) return -1;
    /* Something must have caught the nested fault. */
    return check_int(test, "outer handler ran", outer_ran, 1);
}
