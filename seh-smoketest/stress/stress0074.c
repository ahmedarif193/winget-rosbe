/* Exception raised from a function called through a jump table (dense switch). */
#include "stress_common.h"
char test[] = "stress0074";
static volatile int which = 5;
int main(void)
{
    volatile int handled = 0, visited = 0;
    try {
        switch (which) {
        case 0: visited = 1; break;
        case 1: visited = 2; break;
        case 2: visited = 3; break;
        case 3: visited = 4; break;
        case 4: visited = 5; break;
        case 5: visited = 6; RaiseException(TEST_EXC, 0, 0, 0); break;
        case 6: visited = 7; break;
        case 7: visited = 8; break;
        default: visited = -1; break;
        }
    }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "case visited", visited, 6)) return -1;
    return check_int(test, "handled", handled, 1);
}
