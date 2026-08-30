/* goto out of a try block is a local unwind: the finally must run. */
#include "stress_common.h"
char test[] = "stress0027";
int main(void)
{
    volatile int fin = 0;
    try { mark('b'); goto out; }
    finally { mark('f'); fin++; }
    endtry
    mark('!');
out:
    mark('o');
    if (check_trace(test, "bfo")) return -1;
    return check_int(test, "finally ran once", fin, 1);
}
