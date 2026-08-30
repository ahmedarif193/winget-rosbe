/*
 * EXCEPTION_CONTINUE_EXECUTION: the filter repairs the fault and execution
 * resumes at the faulting instruction.
 *
 * The repair is done with VirtualProtect on a PAGE_NOACCESS page rather than
 * by fixing a pointer variable: resuming re-executes the instruction with the
 * address already in a register, so patching a C pointer is not guaranteed to
 * be observed and can spin forever. Making the *page* accessible is the
 * well-defined form of this idiom, and the retry counter bounds the test so a
 * backend that never makes progress fails instead of hanging.
 */
#include "stress_common.h"
char test[] = "stress0004";

static volatile LONG faults;
static void *page;

static int repair(struct _EXCEPTION_POINTERS *ep)
{
    DWORD old;

    mark('r');
    faults++;
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    if (faults > 4)                       /* not converging -- give up */
        return EXCEPTION_EXECUTE_HANDLER;
    if (!VirtualProtect(page, 4096, PAGE_READWRITE, &old))
        return EXCEPTION_EXECUTE_HANDLER;
    return EXCEPTION_CONTINUE_EXECUTION;
}

int main(void)
{
    volatile int handled = 0;

    page = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_NOACCESS);
    if (page == NULL) {
        printf("%s SKIP: VirtualAlloc failed\n", test);
        return 0;
    }

    try {
        mark('t');
        *(volatile int *)page = 0x5A;     /* faults once, then succeeds */
        mark('o');
    }
    except(repair(GetExceptionInformation())) {
        mark('X');
        handled = 1;
    }
    endtry

    if (check_int(test, "handler ran", handled, 0)) return -1;
    if (check_int(test, "faults", faults, 1)) return -1;
    if (check_trace(test, "tro")) return -1;
    return check_int(test, "value written", *(volatile int *)page, 0x5A);
}
