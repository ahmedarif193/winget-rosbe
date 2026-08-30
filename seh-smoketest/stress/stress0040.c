/* RaiseException carrying the maximum 15 parameters, all preserved. */
#include "stress_common.h"
char test[] = "stress0040";
static ULONG_PTR got[EXCEPTION_MAXIMUM_PARAMETERS];
static volatile unsigned long n_got;
static int capture(struct _EXCEPTION_POINTERS *ep)
{
    unsigned i;
    if (ep && ep->ExceptionRecord) {
        n_got = ep->ExceptionRecord->NumberParameters;
        for (i = 0; i < n_got && i < EXCEPTION_MAXIMUM_PARAMETERS; i++)
            got[i] = ep->ExceptionRecord->ExceptionInformation[i];
    }
    return EXCEPTION_EXECUTE_HANDLER;
}
int main(void)
{
    ULONG_PTR args[EXCEPTION_MAXIMUM_PARAMETERS];
    unsigned i;
    volatile int handled = 0;
    for (i = 0; i < EXCEPTION_MAXIMUM_PARAMETERS; i++)
        args[i] = (ULONG_PTR)(0x100 + i);
    try { RaiseException(TEST_EXC, 0, EXCEPTION_MAXIMUM_PARAMETERS, args); }
    except(capture(GetExceptionInformation())) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "NumberParameters", (long)n_got,
                  EXCEPTION_MAXIMUM_PARAMETERS)) return -1;
    for (i = 0; i < EXCEPTION_MAXIMUM_PARAMETERS; i++) {
        char what[32];
        sprintf(what, "param%u", i);
        if (check_int(test, what, (long)got[i], (long)(0x100 + i))) return -1;
    }
    return 0;
}
