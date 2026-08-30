/*
 * Handler outside the loop: the exception must terminate the loop, running
 * only the current iteration's termination handler, and leave the induction
 * variable at the iteration that raised.
 */
#include "stress_common.h"
char test[] = "stress0068";
int main(void)
{
    volatile int fin = 0, body = 0, handled = 0;
    volatile int last = -1;
    int i;
    try {
        for (i = 0; i < 100; i++) {
            try {
                body++;
                last = i;
                if (i == 7) RaiseException(TEST_EXC, 0, 0, 0);
            }
            finally { fin++; }
            endtry
        }
    }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    if (check_int(test, "iterations entered", body, 8)) return -1;
    if (check_int(test, "finally runs", fin, 8)) return -1;
    return check_int(test, "last iteration", last, 7);
}
