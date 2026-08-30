/*
 * PSEH test-harness runner stub.
 *
 * Each MS SEH conformance test (seh0001.c .. seh0058.c) ships its own main()
 * that returns 0 on success and non-zero on failure. We compile the test with
 * -Dmain=pseh_test_entry and link it against this stub so that:
 *
 *   1. The pass/fail verdict is reported on stdout as a machine-readable line,
 *      instead of being squeezed through a process exit code (Wine truncates
 *      Windows exit codes to 8 bits, which makes -1 and 0xC0000005 collide).
 *   2. A test that escapes its own SEH scopes is caught by an unhandled
 *      exception filter and reported as CRASH with the real NTSTATUS, rather
 *      than tearing down the process with no diagnosis.
 *
 * The filter uses SetUnhandledExceptionFilter -- a plain Win32 API -- rather
 * than __try/__except, so the runner itself never depends on the SEH
 * implementation that is under test.
 */

#include <windows.h>
#include <stdio.h>

int pseh_test_entry(void);

static LONG CALLBACK
PsehHarnessFilter(EXCEPTION_POINTERS *ExceptionInfo)
{
    EXCEPTION_RECORD *rec = ExceptionInfo->ExceptionRecord;

    printf("PSEH_RESULT CRASH code=0x%08lX addr=%p flags=0x%lX\n",
           (unsigned long)rec->ExceptionCode,
           rec->ExceptionAddress,
           (unsigned long)rec->ExceptionFlags);
    fflush(stdout);

    /* Distinct, un-truncated exit status for "escaped exception". */
    ExitProcess(101);

    /* Not reached. */
    return EXCEPTION_EXECUTE_HANDLER;
}

int
main(void)
{
    int rc;

    /* Unbuffered-ish: make sure partial output survives a hard kill. */
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    SetUnhandledExceptionFilter(PsehHarnessFilter);

    /*
     * Suppress the Wine/Windows crash dialog and WER, so a failing test
     * returns promptly instead of blocking the harness on a modal popup.
     */
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX |
                 SEM_NOOPENFILEERRORBOX);

    printf("PSEH_RESULT START\n");
    fflush(stdout);

    rc = pseh_test_entry();

    printf("PSEH_RESULT RC %d\n", rc);
    fflush(stdout);

    /* 0 == pass, 1 == the test reported failure. Never leak the raw rc. */
    return (rc == 0) ? 0 : 1;
}
