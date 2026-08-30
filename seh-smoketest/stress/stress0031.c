/* try/finally nested inside another finally, on the normal path. */
#include "stress_common.h"
char test[] = "stress0031";
int main(void)
{
    try { mark('b'); }
    finally {
        mark('f');
        try { mark('i'); } finally { mark('j'); } endtry
        mark('g');
    }
    endtry
    return check_trace(test, "bfijg");
}
