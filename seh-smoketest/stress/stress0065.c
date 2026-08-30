/* Unwinding out of a Win32 callback (EnumWindows-style, via a local invoke). */
#include "stress_common.h"
char test[] = "stress0065";
typedef int (CALLBACK *CB)(void *);
static int CALLBACK raiser(void *ctx) { (void)ctx; mark('c'); RaiseException(TEST_EXC, 0, 0, 0); return 0; }
static void invoke(CB cb) { mark('i'); cb(NULL); mark('!'); }
static CB volatile the_cb = raiser;
int main(void)
{
    volatile int handled = 0;
    try { invoke(the_cb); mark('!'); }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('H'); handled = 1; }
    endtry
    if (check_trace(test, "icH")) return -1;
    return check_int(test, "handled", handled, 1);
}
