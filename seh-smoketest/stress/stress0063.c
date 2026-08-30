/* 50000 iterations of try/finally on the normal path: no chain growth. */
#include "stress_common.h"
char test[] = "stress0063";
#define ITERS 50000
int main(void)
{
    volatile int fin = 0;
    int i;
    for (i = 0; i < ITERS; i++) {
        try { }
        finally { fin++; }
        endtry
    }
    return check_int(test, "finally runs", fin, ITERS);
}
