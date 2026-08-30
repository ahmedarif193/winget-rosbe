/* Struct-returning function that raises; the caller's handler must recover. */
#include "stress_common.h"
char test[] = "stress0054";
typedef struct { int a, b, c, d; } Quad;
static Quad make(int raise_it)
{
    Quad q; q.a = 1; q.b = 2; q.c = 3; q.d = 4;
    if (raise_it) RaiseException(TEST_EXC, 0, 0, 0);
    return q;
}
static volatile int do_raise = 1;
int main(void)
{
    Quad q; volatile int handled = 0;
    q.a = q.b = q.c = q.d = -1;
    try { q = make(do_raise); }
    except(EXCEPTION_EXECUTE_HANDLER) { handled = 1; }
    endtry
    if (check_int(test, "handled", handled, 1)) return -1;
    /* q must be untouched -- the assignment never completed. */
    return check_int(test, "q.a unchanged", q.a, -1);
}
