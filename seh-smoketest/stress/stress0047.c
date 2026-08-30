/* Sixteen levels of nested try/except; only the innermost may claim it. */
#include "stress_common.h"
char test[] = "stress0047";
#define L_OPEN   try {
#define L_CLOSE  } except(depth++, EXCEPTION_CONTINUE_SEARCH) { claimed++; } endtry
static volatile int depth, claimed;
int main(void)
{
    volatile int outer = 0;
    try {
    L_OPEN L_OPEN L_OPEN L_OPEN L_OPEN L_OPEN L_OPEN L_OPEN
    L_OPEN L_OPEN L_OPEN L_OPEN L_OPEN L_OPEN L_OPEN
        RaiseException(TEST_EXC, 0, 0, 0);
    L_CLOSE L_CLOSE L_CLOSE L_CLOSE L_CLOSE L_CLOSE L_CLOSE L_CLOSE
    L_CLOSE L_CLOSE L_CLOSE L_CLOSE L_CLOSE L_CLOSE L_CLOSE
    }
    except(EXCEPTION_EXECUTE_HANDLER) { outer = 1; }
    endtry
    if (check_int(test, "outer handler ran", outer, 1)) return -1;
    if (check_int(test, "filters consulted", depth, 15)) return -1;
    return check_int(test, "declining handlers that ran", claimed, 0);
}
