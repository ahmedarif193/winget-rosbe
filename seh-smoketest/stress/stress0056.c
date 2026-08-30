/* Thread-local storage must be reachable from a handler. */
#include "stress_common.h"
char test[] = "stress0056";
static DWORD tls;
int main(void)
{
    volatile int handled = 0;
    void *got = (void *)(ULONG_PTR)-1;
    tls = TlsAlloc();
    if (tls == TLS_OUT_OF_INDEXES) { printf("%s SKIP: TlsAlloc\n", test); return 0; }
    TlsSetValue(tls, (void *)(ULONG_PTR)0xC0DE);
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) { got = TlsGetValue(tls); handled = 1; }
    endtry
    TlsFree(tls);
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_int(test, "TLS value in handler", (long)(ULONG_PTR)got, 0xC0DE);
}
