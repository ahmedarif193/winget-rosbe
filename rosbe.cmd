@echo off
setlocal EnableDelayedExpansion

set "ROSBE_ROOT=%~dp0"
if "!ROSBE_ROOT:~-1!"=="\" set "ROSBE_ROOT=!ROSBE_ROOT:~0,-1!"

set "ROSBE_CMAKE="
for /d %%D in ("!ROSBE_ROOT!\cmake-*") do (
    if not defined ROSBE_CMAKE if exist "%%~fD\bin\cmake.exe" set "ROSBE_CMAKE=%%~fD\bin"
)

set "ROSBE_NINJA="
for /d %%D in ("!ROSBE_ROOT!\ninja-*") do (
    if not defined ROSBE_NINJA if exist "%%~fD\ninja.exe" set "ROSBE_NINJA=%%~fD"
)

set "ROSBE_FLEX_BISON="
for /d %%D in ("!ROSBE_ROOT!\win_flex_bison-*") do (
    if not defined ROSBE_FLEX_BISON if exist "%%~fD\win_flex.exe" set "ROSBE_FLEX_BISON=%%~fD"
)

set "ROSBE_LLVM=!ROSBE_ROOT!\llvm-mingw"
set "ROSBE_GCC_X64=!ROSBE_ROOT!\mingw-gcc\x86_64-w64-mingw32"
set "ROSBE_GCC_X86=!ROSBE_ROOT!\mingw-gcc\i686-w64-mingw32"

echo.
echo   ReactOS RosBE - ReactOS Build Environment
echo   ==========================================
echo.
echo   Root: !ROSBE_ROOT!
echo.

if defined ROSBE_CMAKE (
    if exist "!ROSBE_CMAKE!\cmake.exe" (echo   [x] CMake   - !ROSBE_CMAKE!\cmake.exe) else (echo   [ ] CMake)
) else (
    echo   [ ] CMake
)
if defined ROSBE_NINJA (
    if exist "!ROSBE_NINJA!\ninja.exe" (echo   [x] Ninja   - !ROSBE_NINJA!\ninja.exe) else (echo   [ ] Ninja)
) else (
    echo   [ ] Ninja
)
if exist "!ROSBE_LLVM!\bin\clang.exe" (echo   [x] Clang   - !ROSBE_LLVM!\bin\clang.exe) else (echo   [ ] Clang)
if exist "!ROSBE_GCC_X64!\bin\x86_64-w64-mingw32-gcc.exe" (echo   [x] GCC x64 - !ROSBE_GCC_X64!\bin\x86_64-w64-mingw32-gcc.exe) else (echo   [ ] GCC x64)
if exist "!ROSBE_GCC_X86!\bin\i686-w64-mingw32-gcc.exe" (echo   [x] GCC x86 - !ROSBE_GCC_X86!\bin\i686-w64-mingw32-gcc.exe) else (echo   [ ] GCC x86)
if defined ROSBE_FLEX_BISON (
    if exist "!ROSBE_FLEX_BISON!\bison.exe" (echo   [x] Bison   - !ROSBE_FLEX_BISON!\bison.exe) else (echo   [ ] Bison)
) else (
    echo   [ ] Bison
)
if defined ROSBE_FLEX_BISON (
    if exist "!ROSBE_FLEX_BISON!\flex.exe" (echo   [x] Flex    - !ROSBE_FLEX_BISON!\flex.exe) else (echo   [ ] Flex)
) else (
    echo   [ ] Flex
)

echo.
echo   ReactOS's configure.cmd / cmake can consume this tree directly.
echo   Suggested GCC toolchain file:
echo     !ROSBE_GCC_X64!\toolchain.cmake
echo.
