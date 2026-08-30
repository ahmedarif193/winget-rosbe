/* A vectored exception handler runs before any frame-based filter. */
#include "stress_common.h"
char test[] = "stress0059";
static LONG CALLBACK veh(PEXCEPTION_POINTERS ep)
{
    (void)ep;
    mark('v');
    return EXCEPTION_CONTINUE_SEARCH;
}
int main(void)
{
    volatile int handled = 0;
    PVOID h = AddVectoredExceptionHandler(1, veh);
    if (h == NULL) { printf("%s SKIP: AddVectoredExceptionHandler\n", test); return 0; }
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(mark('f'), EXCEPTION_EXECUTE_HANDLER) { mark('H'); handled = 1; }
    endtry
    RemoveVectoredExceptionHandler(h);
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_trace(test, "vfH");
}
