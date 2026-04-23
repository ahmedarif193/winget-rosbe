#!/bin/bash
# Produces release archives by downloading upstreams and bundling into a
# self-contained prefix. Runs on Linux (CI or WSL).
#
# Outputs in dist/:
#   rosbe-<version>-linux-x64.tar.xz
#   rosbe-<version>-win-x64.zip
#   SHA256SUMS.txt

set -euo pipefail

WINDOWS_ONLY=0
args=()
for a in "$@"; do
    case "$a" in
        --windows-only) WINDOWS_ONLY=1 ;;
        *) args+=("$a") ;;
    esac
done
set -- "${args[@]-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
VERSION="${1:-1.0.0}"
DIST_DIR="${ROOT_DIR}/dist"
CACHE_DIR="${DIST_DIR}/cache"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $*"; }
error(){ echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

LLVM_BASE="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_VERSION}"
LLVM_LINUX_URL="${LLVM_BASE}/llvm-mingw-${LLVM_VERSION}-${LLVM_TRIPLET}-ubuntu-22.04-x86_64.tar.xz"
LLVM_WIN_X64_URL="${LLVM_BASE}/llvm-mingw-${LLVM_VERSION}-${LLVM_TRIPLET}-x86_64.zip"

GCC_LINUX_BASE="https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/${GCC_LINUX_TAG}"
GCC_LINUX_I686_URL="${GCC_LINUX_BASE}/i686-w64-mingw32.tar.gz"
GCC_LINUX_X64_URL="${GCC_LINUX_BASE}/x86_64-w64-mingw32.tar.gz"
GCC_LINUX_AARCH64_URL="${GCC_LINUX_BASE}/aarch64-w64-mingw32.tar.xz"

WINLIBS_BASE="https://github.com/brechtsanders/winlibs_mingw/releases/download/${WINLIBS_TAG}"
WINLIBS_X64_URL="${WINLIBS_BASE}/winlibs-x86_64-posix-seh-gcc-${GCC_VERSION}-mingw-w64ucrt-${MINGW_W64_VERSION}-r7.7z"
WINLIBS_I686_URL="${WINLIBS_BASE}/winlibs-i686-posix-dwarf-gcc-${GCC_VERSION}-mingw-w64ucrt-${MINGW_W64_VERSION}-r7.7z"

CMAKE_LINUX_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
CMAKE_WIN_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-windows-x86_64.zip"

NINJA_LINUX_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"
NINJA_WIN_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-win.zip"

WINFLEXBISON_URL="https://github.com/lexxmark/winflexbison/releases/download/v${WINFLEXBISON_VERSION}/win_flex_bison-${WINFLEXBISON_VERSION}.zip"

# ── Helpers ───────────────────────────────────────────────────────────────────
download() {
    local url="$1" dest="$2"
    if [[ -f "${dest}" ]]; then info "Cached: $(basename "${dest}")"; return 0; fi
    local name; name="$(basename "${dest}")"
    info "Downloading ${name}..."
    # -fSL (no -s): show errors and HTTP failures, follow redirects, fail on 4xx/5xx
    # --connect-timeout: abort if TCP connect takes >30s
    # --max-time: hard 5-min ceiling per download
    # --speed-limit/time: abort if transfer is <10KB/s for 60s (stuck download)
    # --retry: retry transient network errors up to 3 times with exponential backoff
    curl -fSL \
        --connect-timeout 30 \
        --max-time 300 \
        --speed-limit 10240 --speed-time 60 \
        --retry 3 --retry-delay 5 \
        -o "${dest}" "${url}"
    local size; size=$(du -h "${dest}" 2>/dev/null | cut -f1)
    ok "Downloaded ${name} (${size})"
}

ensure_tools() {
    local missing=()
    for cmd in curl tar unzip zip 7z sha256sum; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing: ${missing[*]}. On Debian/Ubuntu: sudo apt install ${missing[*]}"
    fi
}

copy_common_files() {
    local staging="$1"
    cp "${ROOT_DIR}/rosbe.cmd" "${staging}/" 2>/dev/null || true
    cp "${ROOT_DIR}/LICENSE" "${staging}/"
    cp "${ROOT_DIR}/README.md" "${staging}/"
    # rosbe.exe wraps rosbe.cmd. Required because winget portable installers
    # only accept .exe in NestedInstallerFiles. Compile via Ubuntu's
    # gcc-mingw-w64-x86-64 if available, else fall back to a prebuilt copy.
    if [[ -f "${ROOT_DIR}/rosbe.c" ]] && command -v x86_64-w64-mingw32-gcc &>/dev/null; then
        info "Compiling rosbe.exe (Linux-hosted mingw cross-compiler)..."
        x86_64-w64-mingw32-gcc -O2 -s -o "${staging}/rosbe.exe" "${ROOT_DIR}/rosbe.c"
    elif [[ -f "${ROOT_DIR}/rosbe.exe" ]]; then
        info "Using committed pre-built rosbe.exe..."
        cp "${ROOT_DIR}/rosbe.exe" "${staging}/"
    else
        error "rosbe.exe not found, and x86_64-w64-mingw32-gcc not in PATH (apt install gcc-mingw-w64-x86-64)"
    fi
}

# ── Linux package ─────────────────────────────────────────────────────────────
package_linux() {
    local pkg="rosbe-${VERSION}-linux-x64"
    local staging="${DIST_DIR}/staging/${pkg}"
    info "Building ${pkg}..."

    rm -rf "${staging}"
    mkdir -p "${staging}/tools/bin" "${staging}/toolchains/mingw-gcc"

    cp "${ROOT_DIR}/LICENSE" "${ROOT_DIR}/README.md" "${staging}/"
    cp "${ROOT_DIR}/setup.sh" "${staging}/"

    # CMake (Linux)
    download "${CMAKE_LINUX_URL}" "${CACHE_DIR}/cmake-linux.tar.gz"
    mkdir -p "${staging}/tools/cmake"
    tar -xf "${CACHE_DIR}/cmake-linux.tar.gz" -C "${staging}/tools/cmake" --strip-components=1

    # Ninja (Linux)
    download "${NINJA_LINUX_URL}" "${CACHE_DIR}/ninja-linux.zip"
    unzip -qo "${CACHE_DIR}/ninja-linux.zip" -d "${staging}/tools/bin"
    chmod +x "${staging}/tools/bin/ninja"

    # LLVM-MinGW (Linux)
    download "${LLVM_LINUX_URL}" "${CACHE_DIR}/llvm-linux.tar.xz"
    mkdir -p "${staging}/toolchains/llvm-mingw"
    tar -xf "${CACHE_DIR}/llvm-linux.tar.xz" -C "${staging}/toolchains/llvm-mingw" --strip-components=1

    # MinGW-GCC (Linux crosstool-NG)
    for entry in "i686-w64-mingw32:tar.gz:${GCC_LINUX_I686_URL}" \
                 "x86_64-w64-mingw32:tar.gz:${GCC_LINUX_X64_URL}" \
                 "aarch64-w64-mingw32:tar.xz:${GCC_LINUX_AARCH64_URL}"; do
        local triple="${entry%%:*}"; local rest="${entry#*:}"
        local ext="${rest%%:*}"; local url="${rest#*:}"
        download "${url}" "${CACHE_DIR}/${triple}.${ext}"
        tar -xf "${CACHE_DIR}/${triple}.${ext}" -C "${staging}/toolchains/mingw-gcc"
    done

    tar -cJf "${DIST_DIR}/${pkg}.tar.xz" -C "${DIST_DIR}/staging" "${pkg}"
    ok "Created ${pkg}.tar.xz"
}

# ── Windows package ──────────────────────────────────────────────────────────
package_windows_x64() {
    local pkg="rosbe-${VERSION}-win-x64"
    local staging="${DIST_DIR}/staging/${pkg}"
    info "Building ${pkg}..."

    rm -rf "${staging}"
    mkdir -p "${staging}/tools/bin" "${staging}/toolchains/mingw-gcc"

    copy_common_files "${staging}"

    # CMake (Windows)
    download "${CMAKE_WIN_URL}" "${CACHE_DIR}/cmake-win.zip"
    info "Extracting cmake-win.zip..."
    unzip -qo "${CACHE_DIR}/cmake-win.zip" -d "${CACHE_DIR}/cmake-tmp"
    mv "${CACHE_DIR}/cmake-tmp"/cmake-* "${staging}/tools/cmake"
    rm -rf "${CACHE_DIR}/cmake-tmp"

    # Ninja (Windows)
    download "${NINJA_WIN_URL}" "${CACHE_DIR}/ninja-win.zip"
    info "Extracting ninja-win.zip..."
    unzip -qo "${CACHE_DIR}/ninja-win.zip" -d "${staging}/tools/bin"

    # win_flex_bison
    download "${WINFLEXBISON_URL}" "${CACHE_DIR}/winflexbison.zip"
    info "Extracting winflexbison.zip..."
    unzip -qo "${CACHE_DIR}/winflexbison.zip" -d "${staging}/tools/bin"
    cp "${staging}/tools/bin/win_flex.exe" "${staging}/tools/bin/flex.exe"
    cp "${staging}/tools/bin/win_bison.exe" "${staging}/tools/bin/bison.exe"

    # LLVM-MinGW (Windows)
    download "${LLVM_WIN_X64_URL}" "${CACHE_DIR}/llvm-win-x64.zip"
    info "Extracting llvm-win-x64.zip (~500MB extracted)..."
    unzip -qo "${CACHE_DIR}/llvm-win-x64.zip" -d "${CACHE_DIR}/llvm-tmp"
    mv "${CACHE_DIR}/llvm-tmp"/llvm-mingw-* "${staging}/toolchains/llvm-mingw"
    rm -rf "${CACHE_DIR}/llvm-tmp"

    # winlibs GCC (Windows)
    download "${WINLIBS_X64_URL}" "${CACHE_DIR}/winlibs-x64.7z"
    info "Extracting winlibs-x64.7z (~250MB extracted)..."
    mkdir -p "${CACHE_DIR}/winlibs-x64-tmp"
    7z x -o"${CACHE_DIR}/winlibs-x64-tmp" "${CACHE_DIR}/winlibs-x64.7z" >/dev/null
    mv "${CACHE_DIR}/winlibs-x64-tmp/mingw64" "${staging}/toolchains/mingw-gcc/x86_64-w64-mingw32"
    rm -rf "${CACHE_DIR}/winlibs-x64-tmp"

    download "${WINLIBS_I686_URL}" "${CACHE_DIR}/winlibs-i686.7z"
    info "Extracting winlibs-i686.7z (~250MB extracted)..."
    mkdir -p "${CACHE_DIR}/winlibs-i686-tmp"
    7z x -o"${CACHE_DIR}/winlibs-i686-tmp" "${CACHE_DIR}/winlibs-i686.7z" >/dev/null
    mv "${CACHE_DIR}/winlibs-i686-tmp/mingw32" "${staging}/toolchains/mingw-gcc/i686-w64-mingw32"
    rm -rf "${CACHE_DIR}/winlibs-i686-tmp"

    info "Adding prefix-copies for binutils..."
    add_prefix_copies "${staging}/toolchains/mingw-gcc/x86_64-w64-mingw32/bin" "x86_64-w64-mingw32"
    add_prefix_copies "${staging}/toolchains/mingw-gcc/i686-w64-mingw32/bin"   "i686-w64-mingw32"

    info "Trimming bundle..."
    trim_bundle "${staging}/toolchains/mingw-gcc/x86_64-w64-mingw32"
    trim_bundle "${staging}/toolchains/mingw-gcc/i686-w64-mingw32"

    info "Zipping ${pkg} (flat, ~700MB to ~300MB compressed)..."
    # Zip from INSIDE the staging dir so files are at the zip root, not under
    # a ${pkg}/ subdir. Winget extracts this directly under the package's
    # sandboxed dir, so tools end up at a stable versionless path.
    (cd "${DIST_DIR}/staging/${pkg}" && zip -qr "${DIST_DIR}/${pkg}.zip" .)
    local zsize; zsize=$(du -h "${DIST_DIR}/${pkg}.zip" | cut -f1)
    ok "Created ${pkg}.zip (${zsize})"
}

add_prefix_copies() {
    local bin="$1" prefix="$2"
    for tool in windres windmc ar nm objcopy objdump ranlib readelf strip strings size dlltool as addr2line ld ld.bfd; do
        [[ -f "${bin}/${tool}.exe" && ! -f "${bin}/${prefix}-${tool}.exe" ]] && \
            cp "${bin}/${tool}.exe" "${bin}/${prefix}-${tool}.exe"
    done
}

# Strip files ReactOS doesn't use AND known false-positive triggers (ndisasm
# specifically gets flagged as Trojan:Win32/Pomal!rfn by Defender's ML
# heuristic; nasm assembly isn't used by ReactOS at all).
trim_bundle() {
    local root="$1"
    local rm_paths=(
        bin/nasm.exe                 # NASM assembler, unused by ReactOS
        bin/ndisasm.exe              # NASM disassembler, ML false-positive
        bin/gfortran.exe bin/gfortran-15.exe
        bin/gdc.exe bin/gdc-15.exe   # D compiler
        bin/cmake-gui.exe            # we ship our own cmake.exe
        bin/doxygen.exe              # docs generator, unused
        bin/ctags.exe bin/etags.exe
        share/doc share/info share/man share/locale share/gettext
        libexec/gcc/*/*/cc1obj.exe libexec/gcc/*/*/cc1objplus.exe
        libexec/gcc/*/*/f951.exe
        libexec/gcc/*/*/cc1gccgo.exe libexec/gcc/*/*/cc1d.exe
        libexec/gcc/*/*/lto1.exe     # LTO not used by ReactOS, often flagged
    )
    for p in "${rm_paths[@]}"; do
        rm -rf "${root}"/${p} 2>/dev/null || true
    done
}

# ── Checksums ─────────────────────────────────────────────────────────────────
generate_checksums() {
    info "Generating SHA256 checksums..."
    ( cd "${DIST_DIR}" && shopt -s nullglob && \
      files=( *.tar.xz *.zip ) && \
      [[ ${#files[@]} -gt 0 ]] && sha256sum "${files[@]}" > SHA256SUMS.txt )
    echo ""
    cat "${DIST_DIR}/SHA256SUMS.txt"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${GREEN}RosBE Modern - Packager v${VERSION}${NC}"
    echo ""

    ensure_tools

    rm -rf "${DIST_DIR}/staging"
    mkdir -p "${DIST_DIR}" "${CACHE_DIR}"

    if [[ "$WINDOWS_ONLY" -eq 0 ]]; then
        package_linux
    else
        info "Skipping linux package (--windows-only)"
    fi
    package_windows_x64
    generate_checksums

    echo ""
    echo -e "${GREEN}Done! Artifacts in: ${DIST_DIR}/${NC}"
}

main "$@"
