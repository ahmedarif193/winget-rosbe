/* Termination handlers unwind innermost-first as the exception escapes. */
#include "stress_common.h"
char test[] = "stress0005";

int main(void)
{
    try {
        try {
            try {
                try {
                    RaiseException(TEST_EXC, 0, 0, 0);
                }
                finally { mark('4'); }
                endtry
            }
            finally { mark('3'); }
            endtry
        }
        finally { mark('2'); }
        endtry
    }
    except(EXCEPTION_EXECUTE_HANDLER) {
        mark('H');
    }
    endtry

    return check_trace(test, "432H");
}
