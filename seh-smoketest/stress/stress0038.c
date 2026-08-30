/* Illegal instruction delivered as EXCEPTION_ILLEGAL_INSTRUCTION. */
#include "stress_common.h"
char test[] = "stress0038";
int main(void)
{
    volatile unsigned long code = 0;
    volatile int handled = 0;
    try {
#if defined(__i386__) || defined(__x86_64__)
        __asm__ __volatile__("ud2");
#else
        RaiseException(EXCEPTION_ILLEGAL_INSTRUCTION, 0, 0, 0);
#endif
    }
    except(code = GetExceptionCode(), EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    printf("%s: code=0x%08lX\n", test, code);
    return check_int(test, "code", (long)code,
                     (long)EXCEPTION_ILLEGAL_INSTRUCTION);
}
