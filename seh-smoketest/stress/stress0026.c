/* Plain try/finally with no exception: body then handler, exactly once. */
#include "stress_common.h"
char test[] = "stress0026";
int main(void)
{
    volatile int body = 0, fin = 0;
    try { mark('b'); body++; }
    finally { mark('f'); fin++; }
    endtry
    mark('a');
    if (check_trace(test, "bfa")) return -1;
    if (check_int(test, "body runs", body, 1)) return -1;
    return check_int(test, "finally runs", fin, 1);
}
