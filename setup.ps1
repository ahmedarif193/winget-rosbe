#Requires -Version 5.1
<#
.SYNOPSIS
    ReactOS RosBE - Windows Setup Script
.DESCRIPTION
    Downloads and extracts all toolchains + build tools for ReactOS development
    into a flat per-component layout that mirrors the winget package.

    Layout produced (under -InstallRoot, default $PSScriptRoot):
      cmake-<ver>\bin\cmake.exe ...
      ninja-<ver>\ninja.exe
      win_flex_bison-<ver>\win_flex.exe, win_bison.exe, flex.exe, bison.exe
      llvm-mingw\bin\clang.exe ...
      mingw-gcc\x86_64-w64-mingw32\bin\x86_64-w64-mingw32-gcc.exe ...
      mingw-gcc\i686-w64-mingw32\bin\i686-w64-mingw32-gcc.exe ...
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -LlvmOnly
    .\setup.ps1 -GccOnly
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = $PSScriptRoot,
    [switch]$LlvmOnly,
    [switch]$GccOnly,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ── Configuration ─────────────────────────────────────────────────────────────
$CacheDir = Join-Path $InstallRoot ".cache"

# Load versions from scripts/versions.env (KEY=VALUE only, no quotes).
$VersionsEnv = Join-Path $PSScriptRoot "scripts/versions.env"
$V = @{}
foreach ($line in Get-Content $VersionsEnv) {
    if ($line -match '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.+?)\s*$') {
        $V[$matches[1]] = $matches[2]
    }
}

$LlvmVersion         = $V['LLVM_VERSION']
$LlvmTriplet         = $V['LLVM_TRIPLET']
$LlvmBaseUrl         = "https://github.com/mstorsjo/llvm-mingw/releases/download/$LlvmVersion"

$GccTag              = $V['GCC_TAG']
$GccBaseUrl          = "https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/$GccTag"
$GccWinX64Asset      = "x86_64-w64-mingw32-winhost.zip"
$GccWinX86Asset      = "i686-w64-mingw32-winhost.zip"

$CmakeVersion        = $V['CMAKE_VERSION']
$CmakeUrl            = "https://github.com/Kitware/CMake/releases/download/v$CmakeVersion/cmake-$CmakeVersion-windows-x86_64.zip"

$NinjaVersion        = $V['NINJA_VERSION']
$NinjaUrl            = "https://github.com/ninja-build/ninja/releases/download/v$NinjaVersion/ninja-win.zip"

$WinFlexBisonVersion = $V['WINFLEXBISON_VERSION']
$WinFlexBisonUrl     = "https://github.com/lexxmark/winflexbison/releases/download/v$WinFlexBisonVersion/win_flex_bison-$WinFlexBisonVersion.zip"

# Detect host architecture
$HostArch = if ([System.Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x86_64" }
} else { "i686" }

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

function Extract-Zip($Archive, $Dest) {
    Write-Status ">" "Cyan" "Extracting: $(Split-Path $Archive -Leaf)"
    if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
    Expand-Archive -Path $Archive -DestinationPath $Dest -Force
}

# ── CMake ─────────────────────────────────────────────────────────────────────
function Setup-CMake {
    $target = Join-Path $InstallRoot "cmake-$CmakeVersion"
    $cmakeExe = Join-Path $target "bin\cmake.exe"

    if (Test-Path $cmakeExe) {
        $ver = & $cmakeExe --version | Select-Object -First 1
        Write-Status "x" "Green" "CMake already installed ($ver)"
        return
    }

    $archive = Join-Path $CacheDir "cmake-$CmakeVersion-win-x64.zip"
    Download-File $CmakeUrl $archive

    $tmpDir = Join-Path $CacheDir "cmake-tmp"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Extract-Zip $archive $tmpDir
    $inner = Get-ChildItem $tmpDir | Select-Object -First 1
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Move-Item $inner.FullName $target
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Status "x" "Green" "CMake $CmakeVersion -> $target"
}

# ── Ninja ─────────────────────────────────────────────────────────────────────
function Setup-Ninja {
    $target = Join-Path $InstallRoot "ninja-$NinjaVersion"
    $ninjaExe = Join-Path $target "ninja.exe"

    if (Test-Path $ninjaExe) {
        Write-Status "x" "Green" "Ninja already installed"
        return
    }

    $archive = Join-Path $CacheDir "ninja-win.zip"
    Download-File $NinjaUrl $archive
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Extract-Zip $archive $target

    Write-Status "x" "Green" "Ninja $NinjaVersion -> $target"
}

# ── Flex & Bison ─────────────────────────────────────────────────────────────
function Setup-FlexBison {
    $target = Join-Path $InstallRoot "win_flex_bison-$WinFlexBisonVersion"
    $flexExe = Join-Path $target "win_flex.exe"

    if (Test-Path $flexExe) {
        Write-Status "x" "Green" "Flex & Bison already installed"
        return
    }

    $archive = Join-Path $CacheDir "win_flex_bison-$WinFlexBisonVersion.zip"
    Download-File $WinFlexBisonUrl $archive
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Extract-Zip $archive $target

    # Aliases so CMake finds them as "flex" / "bison"
    Copy-Item (Join-Path $target "win_flex.exe")  (Join-Path $target "flex.exe")  -Force
    Copy-Item (Join-Path $target "win_bison.exe") (Join-Path $target "bison.exe") -Force

    Write-Status "x" "Green" "Flex & Bison $WinFlexBisonVersion -> $target"
}

# ── LLVM-MinGW ────────────────────────────────────────────────────────────────
function Setup-LlvmMingw {
    $target = Join-Path $InstallRoot "llvm-mingw"
    $clangExe = Join-Path $target "bin\clang.exe"

    if (Test-Path $clangExe) {
        $ver = & $clangExe --version | Select-Object -First 1
        Write-Status "x" "Green" "LLVM-MinGW already installed ($ver)"
        return
    }

    $filename = "llvm-mingw-$LlvmVersion-$LlvmTriplet-$HostArch.zip"
    $archive = Join-Path $CacheDir $filename
    Download-File "$LlvmBaseUrl/$filename" $archive

    $tmpDir = Join-Path $CacheDir "llvm-tmp"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Extract-Zip $archive $tmpDir
    $inner = Get-ChildItem $tmpDir | Select-Object -First 1
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    Move-Item $inner.FullName $target
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    $ver = & (Join-Path $target "bin\clang.exe") --version | Select-Object -First 1
    Write-Status "x" "Green" "LLVM-MinGW $LlvmVersion -> $target ($ver)"
}

# ── MinGW-GCC (ct-ng Canadian-cross, native Windows) ─────────────────────────
# Ships triple-prefixed binaries only (x86_64-w64-mingw32-gcc.exe etc.) and the
# ct-ng-emitted toolchain.cmake for CMake consumers.
function Setup-MingwGcc {
    $gccRoot = Join-Path $InstallRoot "mingw-gcc"
    $x64Dir  = Join-Path $gccRoot "x86_64-w64-mingw32"
    $x86Dir  = Join-Path $gccRoot "i686-w64-mingw32"
    $x64Gcc  = Join-Path $x64Dir "bin\x86_64-w64-mingw32-gcc.exe"
    $x86Gcc  = Join-Path $x86Dir "bin\i686-w64-mingw32-gcc.exe"

    New-Item -ItemType Directory -Path $gccRoot -Force | Out-Null

    foreach ($arch in @(
        @{ Name="x86_64"; Asset=$GccWinX64Asset; Target=$x64Dir; Probe=$x64Gcc; InnerDir="x86_64-w64-mingw32-winhost" },
        @{ Name="i686";   Asset=$GccWinX86Asset; Target=$x86Dir; Probe=$x86Gcc; InnerDir="i686-w64-mingw32-winhost"   }
    )) {
        if (Test-Path $arch.Probe) {
            Write-Status "x" "Green" "MinGW-GCC $($arch.Name) already installed"
            continue
        }

        $archive = Join-Path $CacheDir $arch.Asset
        Download-File "$GccBaseUrl/$($arch.Asset)" $archive

        $tmpDir = Join-Path $CacheDir "gcc-$($arch.Name)-tmp"
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        Write-Status ">" "Cyan" "Extracting MinGW-GCC $($arch.Name)..."
        Expand-Archive -Path $archive -DestinationPath $tmpDir -Force

        $inner = Join-Path $tmpDir $arch.InnerDir
        if (-not (Test-Path $inner)) {
            throw "Unexpected archive layout: $inner not found inside $($arch.Asset)"
        }
        if (Test-Path $arch.Target) { Remove-Item $arch.Target -Recurse -Force }
        Move-Item $inner $arch.Target
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        $ver = & $arch.Probe --version | Select-Object -First 1
        Write-Status "x" "Green" "MinGW-GCC $($arch.Name) $GccTag -> $($arch.Target) ($ver)"
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────
function Main {
    Write-Host ""
    Write-Host "  ReactOS RosBE - Windows Setup" -ForegroundColor Green
    Write-Host "  =============================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Host: Windows $HostArch"
    Write-Host "  Root: $InstallRoot"
    Write-Host ""

    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

    Setup-CMake
    Setup-Ninja
    Setup-FlexBison

    $installLlvm = -not $GccOnly
    $installGcc  = -not $LlvmOnly

    if ($installLlvm) { Setup-LlvmMingw }
    if ($installGcc)  { Setup-MingwGcc }

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "  Setup Complete!" -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Each component lives in its own top-level folder under:"
    Write-Host "    $InstallRoot"
    Write-Host ""
    Write-Host "  Point CMake at ReactOS with either toolchain file:"
    Write-Host "    -DCMAKE_TOOLCHAIN_FILE=$InstallRoot\mingw-gcc\x86_64-w64-mingw32\toolchain.cmake"
    Write-Host "    -DCMAKE_TOOLCHAIN_FILE=<reactos>\toolchain-clang.cmake   (LLVM)"
    Write-Host ""
}

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    return
}

Main
