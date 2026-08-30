/* A filter's writes to enclosing-frame locals must be visible to the handler. */
#include "stress_common.h"
char test[] = "stress0020";
int main(void)
{
    volatile int token = 0;
    volatile int in_handler = -1;
    try { token = 1; RaiseException(TEST_EXC, 0, 0, 0); }
    except(token = 0x4D, EXCEPTION_EXECUTE_HANDLER) { in_handler = token; }
    endtry
    return check_int(test, "handler saw filter's write", in_handler, 0x4D);
}
