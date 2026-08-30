/*
 * Registration-chain hygiene: 20000 iterations of enter/raise/handle. PSEH2
 * pushes an entry on the FS:[0] chain per scope, so a missing pop leaks the
 * chain and eventually faults or diverges. Also catches per-iteration state
 * that is not reset.
 */
#include "stress_common.h"
char test[] = "stress0015";

#define ITERS 20000

int main(void)
{
    volatile int caught = 0;
    volatile int normal = 0;
    int i;

    for (i = 0; i < ITERS; i++) {
        try {
            try {
                if ((i & 1) == 0)
                    RaiseException(TEST_EXC, 0, 0, 0);
                else
                    normal++;
            }
            finally {
                /* runs on both paths */
            }
            endtry
        }
        except(EXCEPTION_EXECUTE_HANDLER) {
            caught++;
        }
        endtry
    }

    if (check_int(test, "caught", caught, ITERS / 2)) return -1;
    return check_int(test, "normal", normal, ITERS / 2);
}
