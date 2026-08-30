/* break out of a try inside a loop must run that iteration's finally. */
#include "stress_common.h"
char test[] = "stress0028";
int main(void)
{
    volatile int fin = 0, iters = 0;
    int i;
    for (i = 0; i < 5; i++) {
        try {
            iters++;
            if (i == 2) break;
        }
        finally { fin++; }
        endtry
    }
    if (check_int(test, "iterations entered", iters, 3)) return -1;
    return check_int(test, "finally runs", fin, 3);
}
