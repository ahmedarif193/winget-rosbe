/*
 * Interleaved try/finally and try/except at four levels, verifying the exact
 * Windows order: all filters (outward, first pass), then all termination
 * handlers up to the frame that claimed it (second pass), then the handler.
 */
#include "stress_common.h"
char test[] = "stress0016";

int main(void)
{
    try {                                  /* L1 except -- claims it */
        try {                              /* L2 finally */
            try {                          /* L3 except -- declines */
                try {                      /* L4 finally */
                    RaiseException(TEST_EXC, 0, 0, 0);
                }
                finally { mark('d'); }     /* unwind, second pass */
                endtry
            }
            except(mark('c'), EXCEPTION_CONTINUE_SEARCH) {
                mark('!');
            }
            endtry
        }
        finally { mark('b'); }             /* unwind, second pass */
        endtry
    }
    except(mark('a'), EXCEPTION_EXECUTE_HANDLER) {
        mark('H');
    }
    endtry

    /* Pass 1: L3 filter 'c', then L1 filter 'a'.
       Pass 2: unwind L4 'd', then L2 'b'. Then the handler 'H'. */
    return check_trace(test, "cadbH");
}
