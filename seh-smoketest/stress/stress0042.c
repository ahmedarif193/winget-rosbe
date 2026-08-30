/* Custom exception codes with the severity/customer bits set round-trip. */
#include "stress_common.h"
char test[] = "stress0042";
#define CUSTOM_ERR  0xE0BEEF01u   /* severity=3 (error), customer bit set */
#define CUSTOM_WARN 0xA0BEEF02u   /* severity=2 (warning) */
#define CUSTOM_INFO 0x60BEEF03u   /* severity=1 (informational) */
static unsigned long got[3];
static int idx;
int main(void)
{
    unsigned long codes[3];
    int i;
    codes[0] = CUSTOM_ERR; codes[1] = CUSTOM_WARN; codes[2] = CUSTOM_INFO;
    for (i = 0; i < 3; i++) {
        try { RaiseException(codes[i], 0, 0, 0); }
        except(got[idx] = GetExceptionCode(), idx++, EXCEPTION_EXECUTE_HANDLER) { }
        endtry
    }
    if (check_int(test, "dispatches", idx, 3)) return -1;
    for (i = 0; i < 3; i++) {
        char what[32];
        sprintf(what, "code%d", i);
        if (check_int(test, what, (long)got[i], (long)codes[i])) return -1;
    }
    return 0;
}
