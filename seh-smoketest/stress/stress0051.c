/* A large stack frame in the guarded scope must not confuse the unwinder. */
#include "stress_common.h"
char test[] = "stress0051";
#define BIG 32768
static volatile int guard;   /* holds an unsigned byte value */
int main(void)
{
    volatile int handled = 0;
    try {
        unsigned char big[BIG];
        memset(big, 0xA5, sizeof(big));
        guard = big[BIG - 1];
        RaiseException(TEST_EXC, 0, 0, 0);
    }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "frame touched", guard, 0xA5)) return -1;
    return check_int(test, "handled", handled, 1);
}
