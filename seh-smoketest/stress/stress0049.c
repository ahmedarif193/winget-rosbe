/* x87 FPU control word must survive an exception dispatch. */
#include "stress_common.h"
char test[] = "stress0049";
int main(void)
{
    volatile double a = 3.5, b = 2.25, r_before, r_after;
    volatile int handled = 0;
    r_before = a * b + 1.0;
    try { RaiseException(TEST_EXC, 0, 0, 0); }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    r_after = a * b + 1.0;
    if (check_int(test, "handled", handled, 1)) return -1;
    if (r_before != r_after) {
        printf("%s FAILED: fp result changed %f -> %f\n", test,
               (double)r_before, (double)r_after);
        return -1;
    }
    return check_int(test, "fp result", (long)(r_after * 100.0), 887);
}
