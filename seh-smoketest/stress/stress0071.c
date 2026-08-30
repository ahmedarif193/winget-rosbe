/* GetExceptionCode() must reflect the innermost active dispatch. */
#include "stress_common.h"
char test[] = "stress0071";
int main(void)
{
    volatile unsigned long outer_before = 0, inner = 0, outer_after = 0;
    try { RaiseException(0xE0AAAAAAu, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) {
        outer_before = GetExceptionCode();
        try { RaiseException(0xE0BBBBBBu, 0, 0, 0); }
        except(EXCEPTION_EXECUTE_HANDLER) { inner = GetExceptionCode(); }
        endtry
        outer_after = GetExceptionCode();
    }
    endtry
    if (check_int(test, "outer code before", (long)outer_before, 0xE0AAAAAA)) return -1;
    if (check_int(test, "inner code", (long)inner, 0xE0BBBBBB)) return -1;
    return check_int(test, "outer code after", (long)outer_after, 0xE0AAAAAA);
}
