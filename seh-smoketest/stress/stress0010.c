/*
 * GetExceptionInformation(): code, flags and user parameters must survive
 * into the handler.
 *
 * The EXCEPTION_POINTERS are captured in the FILTER expression -- that is the
 * only place GetExceptionInformation() is legal, and clang enforces it -- and
 * the interesting fields are copied out for checking after the handler runs.
 */
#include "stress_common.h"
char test[] = "stress0010";

static volatile unsigned long g_code, g_nparams;
static volatile ULONG_PTR g_p0, g_p1, g_p2;
static volatile int g_have_context, g_have_record;

static int capture(struct _EXCEPTION_POINTERS *ep)
{
    if (ep != 0) {
        g_have_record  = (ep->ExceptionRecord != 0);
        g_have_context = (ep->ContextRecord != 0);
        if (ep->ExceptionRecord != 0) {
            g_code    = ep->ExceptionRecord->ExceptionCode;
            g_nparams = ep->ExceptionRecord->NumberParameters;
            g_p0 = ep->ExceptionRecord->ExceptionInformation[0];
            g_p1 = ep->ExceptionRecord->ExceptionInformation[1];
            g_p2 = ep->ExceptionRecord->ExceptionInformation[2];
        }
    }
    return EXCEPTION_EXECUTE_HANDLER;
}

int main(void)
{
    ULONG_PTR args[3];
    volatile unsigned long code_in_handler = 0;

    args[0] = (ULONG_PTR)0x1111;
    args[1] = (ULONG_PTR)0x2222;
    args[2] = (ULONG_PTR)0x3333;

    try {
        RaiseException(TEST_EXC, 0, 3, args);
    }
    except(capture(GetExceptionInformation())) {
        code_in_handler = GetExceptionCode();
    }
    endtry

    if (check_int(test, "ExceptionRecord present", g_have_record, 1)) return -1;
    if (check_int(test, "ContextRecord present", g_have_context, 1)) return -1;
    if (check_int(test, "filter code", (long)g_code, (long)TEST_EXC)) return -1;
    if (check_int(test, "handler code", (long)code_in_handler, (long)TEST_EXC)) return -1;
    if (check_int(test, "NumberParameters", (long)g_nparams, 3)) return -1;
    if (check_int(test, "param0", (long)g_p0, 0x1111)) return -1;
    if (check_int(test, "param1", (long)g_p1, 0x2222)) return -1;
    return check_int(test, "param2", (long)g_p2, 0x3333);
}
