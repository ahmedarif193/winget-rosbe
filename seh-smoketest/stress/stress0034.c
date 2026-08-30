/* __leave from the outer try when an inner try/finally is in scope. */
#include "stress_common.h"
char test[] = "stress0034";
int main(void)
{
    try {
        mark('a');
        try { mark('b'); }
        finally { mark('i'); }
        endtry
        mark('c');
        leave;
        mark('!');
    }
    finally { mark('o'); }
    endtry
    mark('d');
    return check_trace(test, "abicod");
}
