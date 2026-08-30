/* An exception raised inside a handler that a VEH observes as a new dispatch. */
#include "stress_common.h"
char test[] = "stress0060";
static volatile LONG veh_calls;
static LONG CALLBACK veh(PEXCEPTION_POINTERS ep)
{
    (void)ep;
    InterlockedIncrement(&veh_calls);
    return EXCEPTION_CONTINUE_SEARCH;
}
int main(void)
{
    volatile int inner = 0, outer = 0;
    PVOID h = AddVectoredExceptionHandler(1, veh);
    if (h == NULL) { printf("%s SKIP: AddVectoredExceptionHandler\n", test); return 0; }
    try {
        try { RaiseException(TEST_EXC, 0, 0, 0); }
        except(EXCEPTION_EXECUTE_HANDLER) {
            inner = 1;
            RaiseException(EXCEPTION_INT_OVERFLOW, 0, 0, 0);
        }
        endtry
    }
    except(EXCEPTION_EXECUTE_HANDLER) { outer = 1; }
    endtry
    RemoveVectoredExceptionHandler(h);
    if (check_int(test, "inner handler", inner, 1)) return -1;
    if (check_int(test, "outer handler", outer, 1)) return -1;
    return check_int(test, "VEH dispatches seen", veh_calls, 2);
}
