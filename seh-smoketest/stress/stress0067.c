/* Exception while holding a critical section; finally must release it. */
#include "stress_common.h"
char test[] = "stress0067";
static CRITICAL_SECTION cs;
int main(void)
{
    volatile int handled = 0, released = 0;
    InitializeCriticalSection(&cs);
    try {
        EnterCriticalSection(&cs);
        try { RaiseException(TEST_EXC, 0, 0, 0); }
        finally { LeaveCriticalSection(&cs); released = 1; }
        endtry
    }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "released", released, 1)) return -1;
    /* If the release really happened we can take it again without blocking. */
    if (!TryEnterCriticalSection(&cs)) {
        printf("%s FAILED: lock still held after unwind\n", test);
        return -1;
    }
    LeaveCriticalSection(&cs);
    DeleteCriticalSection(&cs);
    return 0;
}
