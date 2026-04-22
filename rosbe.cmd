@echo off
setlocal EnableDelayedExpansion

set "ROSBE_ROOT=%~dp0"
if "!ROSBE_ROOT:~-1!"=="\" set "ROSBE_ROOT=!ROSBE_ROOT:~0,-1!"

set "ROSBE_TOOLS=!ROSBE_ROOT!\tools\bin"
set "ROSBE_CMAKE=!ROSBE_ROOT!\tools\cmake\bin"
set "ROSBE_LLVM=!ROSBE_ROOT!\toolchains\llvm-mingw"
set "ROSBE_GCC_X64=!ROSBE_ROOT!\toolchains\mingw-gcc\x86_64-w64-mingw32"
set "ROSBE_GCC_X86=!ROSBE_ROOT!\toolchains\mingw-gcc\i686-w64-mingw32"

echo.
echo   RosBE Modern - ReactOS Build Environment
echo   ==========================================
echo.
echo   Root: !ROSBE_ROOT!
echo.

if exist "!ROSBE_CMAKE!\cmake.exe"  (echo   [x] CMake   - !ROSBE_CMAKE!\cmake.exe)       else (echo   [ ] CMake)
if exist "!ROSBE_TOOLS!\ninja.exe"  (echo   [x] Ninja   - !ROSBE_TOOLS!\ninja.exe)        else (echo   [ ] Ninja)
if exist "!ROSBE_LLVM!\bin\clang.exe" (echo   [x] Clang   - !ROSBE_LLVM!\bin\clang.exe) else (echo   [ ] Clang)
if exist "!ROSBE_GCC_X64!\bin\gcc.exe" (echo   [x] GCC x64 - !ROSBE_GCC_X64!\bin\gcc.exe) else (echo   [ ] GCC x64)
if exist "!ROSBE_GCC_X86!\bin\gcc.exe" (echo   [x] GCC x86 - !ROSBE_GCC_X86!\bin\gcc.exe) else (echo   [ ] GCC x86)
if exist "!ROSBE_TOOLS!\bison.exe"  (echo   [x] Bison   - !ROSBE_TOOLS!\bison.exe)        else (echo   [ ] Bison)
if exist "!ROSBE_TOOLS!\flex.exe"   (echo   [x] Flex    - !ROSBE_TOOLS!\flex.exe)         else (echo   [ ] Flex)

echo.
echo   ReactOS's configure.cmd / configure.sh picks up tools from this path.
echo.
