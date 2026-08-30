/* An exception raised while another is already handled, from the handler. */
#include "stress_common.h"
char test[] = "stress0062";
int main(void)
{
    volatile unsigned long codes[3];
    volatile int n = 0;
    codes[0] = codes[1] = codes[2] = 0;
    try {
        try {
            try { RaiseException(0xE0000001u, 0, 0, 0); }
            except(EXCEPTION_EXECUTE_HANDLER) {
                codes[n++] = GetExceptionCode();
                RaiseException(0xE0000002u, 0, 0, 0);
            }
            endtry
        }
        except(EXCEPTION_EXECUTE_HANDLER) {
            codes[n++] = GetExceptionCode();
            RaiseException(0xE0000003u, 0, 0, 0);
        }
        endtry
    }
    except(EXCEPTION_EXECUTE_HANDLER) { codes[n++] = GetExceptionCode(); }
    endtry
    if (check_int(test, "dispatches", n, 3)) return -1;
    if (check_int(test, "code0", (long)codes[0], 0xE0000001)) return -1;
    if (check_int(test, "code1", (long)codes[1], 0xE0000002)) return -1;
    return check_int(test, "code2", (long)codes[2], 0xE0000003);
}
