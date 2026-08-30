/* Misaligned access: raises only if alignment checking is enabled, so the
   test asserts the observed outcome is one of the two defined behaviours. */
#include "stress_common.h"
char test[] = "stress0072";
static char buf[64];
int main(void)
{
    volatile int handled = 0, completed = 0;
    volatile unsigned long code = 0;
    double *p = (double *)(void *)(buf + 1);   /* deliberately misaligned */
    try { *p = 1.5; completed = 1; }
    except(code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    printf("%s: completed=%d handled=%d code=0x%08lX\n",
           test, completed, handled, code);
    /* x86 tolerates it; a raising platform must report DATATYPE_MISALIGNMENT. */
    if (completed) return 0;
    return check_int(test, "code", (long)code,
                     (long)EXCEPTION_DATATYPE_MISALIGNMENT);
}
