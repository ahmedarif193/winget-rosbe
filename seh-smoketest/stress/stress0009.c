/* Deep unwind: 64 nested frames, each with a termination handler. */
#include "stress_common.h"
char test[] = "stress0009";

#define DEPTH 64
static volatile int unwound;

static void recurse(int n)
{
    try {
        if (n > 0)
            recurse(n - 1);
        else
            RaiseException(TEST_EXC, 0, 0, 0);
    }
    finally {
        unwound++;
    }
    endtry
}

int main(void)
{
    volatile int caught = 0;

    unwound = 0;
    try {
        recurse(DEPTH);
    }
    except(EXCEPTION_EXECUTE_HANDLER) {
        caught = 1;
    }
    endtry

    if (check_int(test, "caught", caught, 1)) return -1;
    return check_int(test, "frames unwound", unwound, DEPTH + 1);
}
