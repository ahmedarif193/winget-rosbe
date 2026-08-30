/* abnormal_termination(): false on fall-through, true during unwind. */
#include "stress_common.h"
char test[] = "stress0012";

static volatile int normal_flag = -1;
static volatile int abnormal_flag = -1;

int main(void)
{
    /* 1: normal fall-through out of the try body */
    try {
        mark('n');
    }
    finally {
        normal_flag = abnormal_termination() ? 1 : 0;
    }
    endtry

    /* 2: unwound by an exception */
    try {
        try {
            mark('a');
            RaiseException(TEST_EXC, 0, 0, 0);
        }
        finally {
            abnormal_flag = abnormal_termination() ? 1 : 0;
        }
        endtry
    }
    except(EXCEPTION_EXECUTE_HANDLER) {
        mark('H');
    }
    endtry

    if (check_trace(test, "naH")) return -1;
    if (check_int(test, "normal abnormal_termination", normal_flag, 0)) return -1;
    return check_int(test, "unwind abnormal_termination", abnormal_flag, 1);
}
