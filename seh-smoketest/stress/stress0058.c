/* Four threads each running their own SEH loop concurrently. */
#include "stress_common.h"
char test[] = "stress0058";
#define NTHREADS 4
#define NITER 2000
static volatile LONG total_handled;
static DWORD WINAPI worker(LPVOID arg)
{
    int i, handled = 0;
    (void)arg;
    for (i = 0; i < NITER; i++) {
        try { RaiseException(TEST_EXC, 0, 0, 0); }
        except(EXCEPTION_EXECUTE_HANDLER) { handled++; }
        endtry
    }
    InterlockedExchangeAdd(&total_handled, handled);
    return 0;
}
int main(void)
{
    HANDLE h[NTHREADS];
    int i;
    for (i = 0; i < NTHREADS; i++) {
        h[i] = CreateThread(NULL, 0, worker, NULL, 0, NULL);
        if (h[i] == NULL) { printf("%s SKIP: CreateThread\n", test); return 0; }
    }
    if (WaitForMultipleObjects(NTHREADS, h, TRUE, 60000) == WAIT_TIMEOUT) {
        printf("%s FAILED: threads did not finish\n", test);
        return -1;
    }
    for (i = 0; i < NTHREADS; i++) CloseHandle(h[i]);
    return check_int(test, "total handled", total_handled, NTHREADS * NITER);
}
