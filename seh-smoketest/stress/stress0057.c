/* SEH in a secondary thread, independent of the main thread's chain. */
#include "stress_common.h"
char test[] = "stress0057";
static volatile LONG thread_handled;
static DWORD WINAPI worker(LPVOID arg)
{
    volatile int handled = 0;
    (void)arg;
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    InterlockedExchange(&thread_handled, handled);
    return handled ? 7 : 0;
}
int main(void)
{
    DWORD rc = 0;
    HANDLE h = CreateThread(NULL, 0, worker, NULL, 0, NULL);
    if (h == NULL) { printf("%s SKIP: CreateThread\n", test); return 0; }
    if (WaitForSingleObject(h, 30000) != WAIT_OBJECT_0) {
        printf("%s FAILED: worker did not finish\n", test);
        return -1;
    }
    GetExitCodeThread(h, &rc);
    CloseHandle(h);
    if (check_int(test, "worker handled", thread_handled, 1)) return -1;
    return check_int(test, "worker exit code", (long)rc, 7);
}
