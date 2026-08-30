/* Access violation on WRITE, and the AV parameters describe a write. */
#include "stress_common.h"
char test[] = "stress0036";
static volatile ULONG_PTR kind = (ULONG_PTR)-1;
static int capture(struct _EXCEPTION_POINTERS *ep)
{
    if (ep && ep->ExceptionRecord && ep->ExceptionRecord->NumberParameters >= 1)
        kind = ep->ExceptionRecord->ExceptionInformation[0];
    return EXCEPTION_EXECUTE_HANDLER;
}
int main(void)
{
    volatile int handled = 0;
    try { raise_av(); }
    except(capture(GetExceptionInformation())) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    /* ExceptionInformation[0]: 0 = read, 1 = write, 8 = DEP */
    return check_int(test, "access kind (1 = write)", (long)kind, 1);
}
