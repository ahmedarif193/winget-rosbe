/* abnormal_termination() in stacked finallys during a single unwind. */
#include "stress_common.h"
char test[] = "stress0032";
static volatile int at_inner = -1, at_outer = -1;
int main(void)
{
    volatile int handled = 0;
    try {
        try {
            try { RaiseException(TEST_EXC, 0, 0, 0); }
            finally { at_inner = abnormal_termination() ? 1 : 0; }
            endtry
        }
        finally { at_outer = abnormal_termination() ? 1 : 0; }
        endtry
    }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "inner abnormal", at_inner, 1)) return -1;
    return check_int(test, "outer abnormal", at_outer, 1);
}
