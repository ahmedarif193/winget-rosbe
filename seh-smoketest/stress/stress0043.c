/* setjmp before the try, longjmp out of the try body. */
#include "stress_common.h"
#include <setjmp.h>
char test[] = "stress0043";
static jmp_buf jb;
int main(void)
{
    volatile int landed = 0, fin = 0;
    if (setjmp(jb) == 0) {
        try { mark('b'); longjmp(jb, 1); mark('!'); }
        finally { mark('f'); fin++; }
        endtry
        mark('!');
    } else {
        mark('l');
        landed = 1;
    }
    printf("%s: trace=\"%s\" finally_ran=%d\n", test, g_trace, fin);
    return check_int(test, "longjmp landed", landed, 1);
}
