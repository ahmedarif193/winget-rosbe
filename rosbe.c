/*
 * rosbe.exe - tiny launcher for rosbe.cmd
 * Built once and shipped in the winget bundle. Forwards all args to
 * rosbe.cmd in the same directory and inherits its exit code.
 *
 * Build: x86_64-w64-mingw32-gcc -O2 -s -o rosbe.exe rosbe.c
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    char self[MAX_PATH];
    if (!GetModuleFileNameA(NULL, self, sizeof(self))) {
        fprintf(stderr, "rosbe: GetModuleFileNameA failed\n");
        return 1;
    }
    char *slash = strrchr(self, '\\');
    if (!slash) return 1;
    *(slash + 1) = '\0';

    /* Build "<dir>rosbe.cmd" plus quoted forwarded args. */
    char cmd[32 * 1024];
    int n = snprintf(cmd, sizeof(cmd), "\"%srosbe.cmd\"", self);
    for (int i = 1; i < argc && n < (int)sizeof(cmd) - 4; i++) {
        n += snprintf(cmd + n, sizeof(cmd) - n, " \"%s\"", argv[i]);
    }

    STARTUPINFOA si = { .cb = sizeof(si) };
    PROCESS_INFORMATION pi = {0};
    if (!CreateProcessA(NULL, cmd, NULL, NULL, TRUE,
                        0, NULL, NULL, &si, &pi)) {
        fprintf(stderr, "rosbe: CreateProcess failed (err=%lu)\n",
                GetLastError());
        return 1;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return (int)code;
}
