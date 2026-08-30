/* EXCEPTION_CONTINUE_SEARCH must walk outward, consulting each filter once. */
#include "stress_common.h"
char test[] = "stress0003";

int main(void)
{
    volatile int caught = 0;

    try {
        try {
            try {
                RaiseException(TEST_EXC, 0, 0, 0);
            }
            except(mark('3'), EXCEPTION_CONTINUE_SEARCH) {
                mark('x');       /* must not run */
            }
            endtry
        }
        except(mark('2'), EXCEPTION_CONTINUE_SEARCH) {
            mark('y');           /* must not run */
        }
        endtry
    }
    except(mark('1'), EXCEPTION_EXECUTE_HANDLER) {
        mark('H');
        caught = 1;
    }
    endtry

    if (check_trace(test, "321H")) return -1;
    return check_int(test, "caught", caught, 1);
}
