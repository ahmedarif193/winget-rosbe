/* switch statement inside a try, with the exception raised from a case. */
#include "stress_common.h"
char test[] = "stress0046";
static volatile int selector = 2;
int main(void)
{
    volatile int handled = 0, hits = 0;
    try {
        switch (selector) {
        case 1: mark('1'); hits++; break;
        case 2: mark('2'); hits++; RaiseException(TEST_EXC, 0, 0, 0); mark('!'); break;
        default: mark('d'); hits++; break;
        }
        mark('!');
    }
    except(EXCEPTION_EXECUTE_HANDLER) { mark('H'); handled = 1; }
    endtry
    if (check_trace(test, "2H")) return -1;
    if (check_int(test, "cases entered", hits, 1)) return -1;
    return check_int(test, "handled", handled, 1);
}
