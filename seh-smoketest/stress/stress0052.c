/* alloca inside a guarded scope: the unwind must restore the stack pointer. */
#include "stress_common.h"
#include <malloc.h>
char test[] = "stress0052";
static volatile int sink_v;
int main(void)
{
    volatile int handled = 0, iters = 0;
    int i;
    /* Repeat: a stack pointer that is not restored on unwind accumulates. */
    for (i = 0; i < 64; i++) {
        try {
            char *p = (char *)_alloca(4096);
            p[0] = (char)i; p[4095] = (char)i;
            sink_v = p[0] + p[4095];
            iters++;
            RaiseException(TEST_EXC, 0, 0, 0);
        }
        except(EXCEPTION_EXECUTE_HANDLER) { handled++; }
        endtry
    }
    if (check_int(test, "iterations", iters, 64)) return -1;
    return check_int(test, "handled", handled, 64);
}
