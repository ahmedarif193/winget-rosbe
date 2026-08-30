/* Handler writes to locals; the values must persist after the endtry. */
#include "stress_common.h"
char test[] = "stress0055";
int main(void)
{
    volatile int a = 1, b = 2, c = 3;
    try { a = 10; RaiseException(TEST_EXC, 0, 0, 0); b = 20; }
    except(EXCEPTION_EXECUTE_HANDLER) { b = 200; c = 300; }
    endtry
    if (check_int(test, "a set in try", a, 10)) return -1;
    if (check_int(test, "b set in handler", b, 200)) return -1;
    return check_int(test, "c set in handler", c, 300);
}
