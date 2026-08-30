/* Nested try/except, three deep: the innermost filter must claim it. */
#include "stress_common.h"
char test[] = "stress0001";

int main(void)
{
    volatile int depth = 0;

    try {
        mark('a');
        try {
            mark('b');
            try {
                mark('c');
                RaiseException(TEST_EXC, 0, 0, 0);
                mark('!');           /* unreachable */
            }
            except(mark('3'), EXCEPTION_EXECUTE_HANDLER) {
                mark('C');
                depth = 3;
            }
            endtry
            mark('d');
        }
        except(mark('2'), EXCEPTION_EXECUTE_HANDLER) {
            mark('B');
            depth = 2;
        }
        endtry
        mark('e');
    }
    except(mark('1'), EXCEPTION_EXECUTE_HANDLER) {
        mark('A');
        depth = 1;
    }
    endtry

    /* Only the innermost filter runs; the outer ones are never consulted. */
    if (check_trace(test, "abc3Cde")) return -1;
    return check_int(test, "handling depth", depth, 3);
}
