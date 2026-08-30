/* Several sequential try/finally blocks, each running exactly once, in order. */
#include "stress_common.h"
char test[] = "stress0030";
int main(void)
{
    try { mark('1'); } finally { mark('a'); } endtry
    try { mark('2'); } finally { mark('b'); } endtry
    try { mark('3'); } finally { mark('c'); } endtry
    return check_trace(test, "1a2b3c");
}
