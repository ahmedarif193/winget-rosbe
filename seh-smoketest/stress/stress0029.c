/* continue out of a try inside a loop runs that iteration's finally. */
#include "stress_common.h"
char test[] = "stress0029";
int main(void)
{
    volatile int fin = 0, after = 0;
    int i;
    for (i = 0; i < 4; i++) {
        try { if ((i & 1) == 0) continue; after++; }
        finally { fin++; }
        endtry
    }
    if (check_int(test, "finally runs", fin, 4)) return -1;
    return check_int(test, "body completions", after, 2);
}
