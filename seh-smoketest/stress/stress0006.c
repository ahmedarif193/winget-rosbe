/* __leave jumps to the end of its own try block, running that block's finally. */
#include "stress_common.h"
char test[] = "stress0006";

int main(void)
{
    try {
        mark('a');
        try {
            mark('b');
            leave;               /* leaves the INNER try only */
            mark('!');
        }
        finally { mark('i'); }
        endtry
        mark('c');
    }
    finally { mark('o'); }
    endtry
    mark('d');

    /* leave runs the inner finally, then execution continues after it. */
    return check_trace(test, "abicod");
}
