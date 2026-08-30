/* Same as 0068 but with the handler inside the loop, so all rounds execute. */
#include "stress_common.h"
#include <stdlib.h>
char test[] = "stress0069";
#define ITERS 10000
int main(void)
{
    volatile int handled = 0, freed = 0;
    int i;
    for (i = 0; i < ITERS; i++) {
        try {
            void *p = NULL;
            try {
                p = malloc(256);
                if (p == NULL) break;
                memset(p, i & 0xFF, 256);
                RaiseException(TEST_EXC, 0, 0, 0);
            }
            finally { if (p) { free(p); freed++; } }
            endtry
        }
        except(EXCEPTION_EXECUTE_HANDLER) { handled++; }
        endtry
    }
    if (check_int(test, "handled", handled, ITERS)) return -1;
    return check_int(test, "allocations freed", freed, ITERS);
}
