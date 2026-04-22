#Requires -Version 5.1
<#
.SYNOPSIS
    RosBE Modern - Windows Setup Script
.DESCRIPTION
    Downloads and extracts all toolchains + build tools for ReactOS development.
    Components:
      - LLVM-MinGW 20251202 (Clang 21.1.7)
      - MinGW-GCC 15.2
      - CMake 3.31.6
      - Ninja 1.12.1
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -LlvmOnly
    .\setup.ps1 -GccOnly
#>
[CmdletBinding()]
param(
    [switch]$LlvmOnly,
    [switch]$GccOnly,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ── Configuration ─────────────────────────────────────────────────────────────
$RosbeRoot    = $PSScriptRoot
$ToolsDir     = Join-Path $RosbeRoot "tools"
$ToolchainDir = Join-Path $RosbeRoot "toolchains"
$CacheDir     = Join-Path $RosbeRoot ".cache"

$LlvmVersion  = "20251202"
$LlvmBaseUrl  = "https://github.com/mstorsjo/llvm-mingw/releases/download/$LlvmVersion"

# GCC: winlibs (native Windows builds). crosstool-NG will replace this later.
# Release tag: GCC 15.2.0 + MinGW-w64 14.0.0 UCRT (posix threads)
$WinlibsReleaseTag = "15.2.0posix-14.0.0-ucrt-r7"
$WinlibsBaseUrl    = "https://github.com/brechtsanders/winlibs_mingw/releases/download/$WinlibsReleaseTag"
$WinlibsX64Asset   = "winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-14.0.0-r7.7z"
$WinlibsX86Asset   = "winlibs-i686-posix-dwarf-gcc-15.2.0-mingw-w64ucrt-14.0.0-r7.7z"

$CmakeVersion = "3.31.6"
$CmakeUrl     = "https://github.com/Kitware/CMake/releases/download/v$CmakeVersion/cmake-$CmakeVersion-windows-x86_64.zip"

$NinjaVersion = "1.12.1"
$NinjaUrl     = "https://github.com/ninja-build/ninja/releases/download/v$NinjaVersion/ninja-win.zip"

$WinFlexBisonVersion = "2.5.25"
$WinFlexBisonUrl     = "https://github.com/lexxmark/winflexbison/releases/download/v$WinFlexBisonVersion/win_flex_bison-$WinFlexBisonVersion.zip"

# Detect host architecture
$HostArch = if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
} else { "i686" }

$LlvmArchMap = @{
    "x86_64"  = "x86_64"
    "aarch64" = "aarch64"
    "i686"    = "i686"
}

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-Status($Icon, $Color, $Message) {
    Write-Host "  [$Icon] " -ForegroundColor $Color -NoNewline
    Write-Host $Message
}

function Download-File($Url, $Dest) {
    if (Test-Path $Dest) {
        Write-Status "=" "DarkGray" "Cached: $(Split-Path $Dest -Leaf)"
        return
    }
    Write-Status ">" "Cyan" "Downloading: $(Split-Path $Dest -Leaf)"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    $ProgressPreference = 'Continue'
    Write-Status "+" "Green" "Downloaded: $(Split-Path $Dest -Leaf)"
}

function Extract-Archive($Archive, $Dest) {
    Write-Status ">" "Cyan" "Extracting: $(Split-Path $Archive -Leaf)"
    if ($Archive -match '\.zip$') {
        Expand-Archive -Path $Archive -DestinationPath $Dest -Force
    }
    elseif ($Archive -match '\.(tar\.gz|tar\.xz)$') {
        # Use tar.exe (built into Windows 10+)
        if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
        tar -xf $Archive -C $Dest
    }
    else {
        throw "Unknown archive format: $Archive"
    }
}

# ── CMake ─────────────────────────────────────────────────────────────────────
function Setup-CMake {
    $cmakeDir = Join-Path $ToolsDir "cmake"
    $cmakeExe = Join-Path $cmakeDir "bin\cmake.exe"

    if (Test-Path $cmakeExe) {
        $ver = & $cmakeExe --version | Select-Object -First 1
        Write-Status "x" "Green" "CMake already installed ($ver)"
        return
    }

    $archive = Join-Path $CacheDir "cmake-$CmakeVersion-win-x64.zip"
    Download-File $CmakeUrl $archive

    $tmpDir = Join-Path $CacheDir "cmake-tmp"
    Extract-Archive $archive $tmpDir

    # The zip contains a single top-level folder
    $inner = Get-ChildItem $tmpDir | Select-Object -First 1
    if (Test-Path $cmakeDir) { Remove-Item $cmakeDir -Recurse -Force }
    Move-Item $inner.FullName $cmakeDir
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Status "x" "Green" "CMake $CmakeVersion installed"
}

# ── Ninja ─────────────────────────────────────────────────────────────────────
function Setup-Ninja {
    $ninjaExe = Join-Path $ToolsDir "bin\ninja.exe"

    if (Test-Path $ninjaExe) {
        Write-Status "x" "Green" "Ninja already installed"
        return
    }

    $archive = Join-Path $CacheDir "ninja-win.zip"
    Download-File $NinjaUrl $archive

    $binDir = Join-Path $ToolsDir "bin"
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Extract-Archive $archive $binDir

    Write-Status "x" "Green" "Ninja $NinjaVersion installed"
}

# ── Flex & Bison ─────────────────────────────────────────────────────────────
function Setup-FlexBison {
    $flexExe = Join-Path $ToolsDir "bin\win_flex.exe"
    $bisonExe = Join-Path $ToolsDir "bin\win_bison.exe"

    if ((Test-Path $flexExe) -and (Test-Path $bisonExe)) {
        Write-Status "x" "Green" "Flex & Bison already installed"
        return
    }

    $archive = Join-Path $CacheDir "win_flex_bison-$WinFlexBisonVersion.zip"
    Download-File $WinFlexBisonUrl $archive

    $binDir = Join-Path $ToolsDir "bin"
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Extract-Archive $archive $binDir

    # Create aliases so CMake finds them as "flex" and "bison"
    Copy-Item (Join-Path $binDir "win_flex.exe") (Join-Path $binDir "flex.exe") -Force
    Copy-Item (Join-Path $binDir "win_bison.exe") (Join-Path $binDir "bison.exe") -Force

    Write-Status "x" "Green" "Flex & Bison $WinFlexBisonVersion installed"
}

# windmc: not a separate download. Comes from winlibs GCC (bin/windmc.exe) or
# is built as a host tool by ReactOS (sdk/tools/windmc -> native-windmc).

# ── LLVM-MinGW ────────────────────────────────────────────────────────────────
function Setup-LlvmMingw {
    $llvmDir = Join-Path $ToolchainDir "llvm-mingw"
    $clangExe = Join-Path $llvmDir "bin\clang.exe"

    if (Test-Path $clangExe) {
        $ver = & $clangExe --version | Select-Object -First 1
        Write-Status "x" "Green" "LLVM-MinGW already installed ($ver)"
        return
    }

    $llvmArch = $LlvmArchMap[$HostArch]
    $filename = "llvm-mingw-$LlvmVersion-ucrt-$llvmArch.zip"
    $archive = Join-Path $CacheDir $filename
    Download-File "$LlvmBaseUrl/$filename" $archive

    $tmpDir = Join-Path $CacheDir "llvm-tmp"
    Extract-Archive $archive $tmpDir

    $inner = Get-ChildItem $tmpDir | Select-Object -First 1
    if (Test-Path $llvmDir) { Remove-Item $llvmDir -Recurse -Force }
    Move-Item $inner.FullName $llvmDir
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    $ver = & (Join-Path $llvmDir "bin\clang.exe") --version | Select-Object -First 1
    Write-Status "x" "Green" "LLVM-MinGW installed ($ver)"
}

# ── MinGW-GCC (winlibs, native Windows) ──────────────────────────────────────
# winlibs ships native Windows mingw-w64 + GCC 15.2 as .7z.
# We extract the inner mingw64/ -> toolchains/mingw-gcc/x86_64-w64-mingw32/
# and inner mingw32/ -> toolchains/mingw-gcc/i686-w64-mingw32/
# aarch64: winlibs does not publish ARM64 — will come from crosstool-NG later.
function Setup-MingwGcc {
    $gccDir  = Join-Path $ToolchainDir "mingw-gcc"
    $x64Dir  = Join-Path $gccDir "x86_64-w64-mingw32"
    $x86Dir  = Join-Path $gccDir "i686-w64-mingw32"
    $x64Gcc  = Join-Path $x64Dir "bin\gcc.exe"
    $x86Gcc  = Join-Path $x86Dir "bin\gcc.exe"

    $alreadyInstalled = (Test-Path $x64Gcc) -and (Test-Path $x86Gcc)

    New-Item -ItemType Directory -Path $gccDir -Force | Out-Null

    # x86_64 (posix threads, SEH exceptions)
    if (-not (Test-Path $x64Gcc)) {
        $archive = Join-Path $CacheDir $WinlibsX64Asset
        Download-File "$WinlibsBaseUrl/$WinlibsX64Asset" $archive

        $tmpDir = Join-Path $CacheDir "winlibs-x64-tmp"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        Write-Status ">" "Cyan" "Extracting winlibs x86_64 (~255MB extracted)..."
        tar -xf $archive -C $tmpDir
        if ($LASTEXITCODE -ne 0) { throw "winlibs x86_64 extraction failed" }

        if (Test-Path $x64Dir) { Remove-Item $x64Dir -Recurse -Force }
        Move-Item (Join-Path $tmpDir "mingw64") $x64Dir
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # i686 (posix threads, DWARF exceptions)
    if (-not (Test-Path $x86Gcc)) {
        $archive = Join-Path $CacheDir $WinlibsX86Asset
        Download-File "$WinlibsBaseUrl/$WinlibsX86Asset" $archive

        $tmpDir = Join-Path $CacheDir "winlibs-x86-tmp"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        Write-Status ">" "Cyan" "Extracting winlibs i686 (~254MB extracted)..."
        tar -xf $archive -C $tmpDir
        if ($LASTEXITCODE -ne 0) { throw "winlibs i686 extraction failed" }

        if (Test-Path $x86Dir) { Remove-Item $x86Dir -Recurse -Force }
        Move-Item (Join-Path $tmpDir "mingw32") $x86Dir
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # winlibs binutils are unprefixed (windres.exe etc). ReactOS toolchain-gcc.cmake
    # expects prefixed names for amd64 (x86_64-w64-mingw32-windres etc). Create copies.
    # Idempotent: safe to run on every setup call.
    Add-WinlibsBinutilsPrefix $x64Dir "x86_64-w64-mingw32"
    Add-WinlibsBinutilsPrefix $x86Dir "i686-w64-mingw32"

    $ver = & $x64Gcc --version | Select-Object -First 1
    if ($alreadyInstalled) {
        Write-Status "x" "Green" "winlibs GCC already installed ($ver)"
    } else {
        Write-Status "x" "Green" "winlibs GCC installed ($ver)"
    }
}

function Add-WinlibsBinutilsPrefix($toolchainDir, $prefix) {
    $bin = Join-Path $toolchainDir "bin"
    $unprefixed = @(
        "windres", "windmc", "ar", "nm", "objcopy", "objdump", "ranlib",
        "readelf", "strip", "strings", "size", "dlltool", "as", "addr2line",
        "ld", "ld.bfd"
    )
    foreach ($tool in $unprefixed) {
        $src = Join-Path $bin "$tool.exe"
        $dst = Join-Path $bin "$prefix-$tool.exe"
        if ((Test-Path $src) -and (-not (Test-Path $dst))) {
            Copy-Item $src $dst
        }
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────
function Main {
    Write-Host ""
    Write-Host "  RosBE Modern - Windows Setup" -ForegroundColor Green
    Write-Host "  =============================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Host: Windows $HostArch"
    Write-Host "  Root: $RosbeRoot"
    Write-Host ""

    # Create directories
    @($ToolsDir, $ToolchainDir, $CacheDir) | ForEach-Object {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }

    # Build tools
    Setup-CMake
    Setup-Ninja
    Setup-FlexBison

    # Toolchains (winlibs GCC also provides windmc.exe and windres.exe)
    $installLlvm = -not $GccOnly
    $installGcc  = -not $LlvmOnly

    if ($installLlvm) { Setup-LlvmMingw }
    if ($installGcc)  { Setup-MingwGcc }

    # Summary
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  Setup Complete!" -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Run: .\rosbe.cmd   to enter the environment"
    Write-Host ""
}

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    return
}

Main
