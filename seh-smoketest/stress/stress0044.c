/* longjmp out of an except handler, back past the guarded scope. */
#include "stress_common.h"
#include <setjmp.h>
char test[] = "stress0044";
static jmp_buf jb;
int main(void)
{
    volatile int landed = 0, handled = 0;
    if (setjmp(jb) == 0) {
        try { mark('b'); RaiseException(TEST_EXC, 0, 0, 0); }
        except(EXCEPTION_EXECUTE_HANDLER) {
            mark('H'); handled = 1; longjmp(jb, 1);
        }
        endtry
        mark('!');
    } else {
        mark('l'); landed = 1;
    }
    if (check_int(test, "handler ran", handled, 1)) return -1;
    if (check_int(test, "longjmp landed", landed, 1)) return -1;
    return check_trace(test, "bHl");
}
