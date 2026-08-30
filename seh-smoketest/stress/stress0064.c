/* Exception thrown from inside a qsort comparison callback. */
#include "stress_common.h"
#include <stdlib.h>
char test[] = "stress0064";
static volatile int compares;
static int cmp(const void *a, const void *b)
{
    compares++;
    if (compares > 3) RaiseException(TEST_EXC, 0, 0, 0);
    return (*(const int *)a) - (*(const int *)b);
}
int main(void)
{
    int arr[16];
    volatile int handled = 0;
    int i;
    for (i = 0; i < 16; i++) arr[i] = 16 - i;
    try { qsort(arr, 16, sizeof(int), cmp); }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    return check_int(test, "callback entered", compares > 0, 1);
}
