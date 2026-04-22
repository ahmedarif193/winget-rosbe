#!/bin/bash
# Produces release archives by downloading upstreams and bundling into a
# self-contained prefix. Runs on Linux (CI or WSL).
#
# Outputs in dist/:
#   rosbe-modern-<version>-linux-x64.tar.xz
#   rosbe-modern-<version>-win-x64.zip
#   SHA256SUMS.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
VERSION="${1:-1.0.0}"
DIST_DIR="${ROOT_DIR}/dist"
CACHE_DIR="${DIST_DIR}/cache"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $*"; }
error(){ echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ── Upstream URLs ─────────────────────────────────────────────────────────────
LLVM_VERSION="20251202"
LLVM_BASE="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_VERSION}"
LLVM_LINUX_URL="${LLVM_BASE}/llvm-mingw-${LLVM_VERSION}-ucrt-ubuntu-22.04-x86_64.tar.xz"
LLVM_WIN_X64_URL="${LLVM_BASE}/llvm-mingw-${LLVM_VERSION}-ucrt-x86_64.zip"

# Linux host cross-compilers (crosstool-NG)
GCC_LINUX_BASE="https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/v15.2"
GCC_LINUX_I686_URL="${GCC_LINUX_BASE}/i686-w64-mingw32.tar.gz"
GCC_LINUX_X64_URL="${GCC_LINUX_BASE}/x86_64-w64-mingw32.tar.gz"
GCC_LINUX_AARCH64_URL="${GCC_LINUX_BASE}/aarch64-w64-mingw32.tar.xz"

# Windows-native GCC (winlibs)
WINLIBS_TAG="15.2.0posix-14.0.0-ucrt-r7"
WINLIBS_BASE="https://github.com/brechtsanders/winlibs_mingw/releases/download/${WINLIBS_TAG}"
WINLIBS_X64_URL="${WINLIBS_BASE}/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-14.0.0-r7.7z"
WINLIBS_I686_URL="${WINLIBS_BASE}/winlibs-i686-posix-dwarf-gcc-15.2.0-mingw-w64ucrt-14.0.0-r7.7z"

# Cross-platform tools
CMAKE_VERSION="3.31.6"
CMAKE_LINUX_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
CMAKE_WIN_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-windows-x86_64.zip"

NINJA_VERSION="1.12.1"
NINJA_LINUX_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"
NINJA_WIN_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-win.zip"

WINFLEXBISON_URL="https://github.com/lexxmark/winflexbison/releases/download/v2.5.25/win_flex_bison-2.5.25.zip"

# ── Helpers ───────────────────────────────────────────────────────────────────
download() {
    local url="$1" dest="$2"
    if [[ -f "${dest}" ]]; then info "Cached: $(basename "${dest}")"; return 0; fi
    info "Downloading $(basename "${dest}")..."
    curl -L --progress-bar -o "${dest}" "${url}"
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
}

# ── Linux package ─────────────────────────────────────────────────────────────
package_linux() {
    local pkg="rosbe-modern-${VERSION}-linux-x64"
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
    local pkg="rosbe-modern-${VERSION}-win-x64"
    local staging="${DIST_DIR}/staging/${pkg}"
    info "Building ${pkg}..."

    rm -rf "${staging}"
    mkdir -p "${staging}/tools/bin" "${staging}/toolchains/mingw-gcc"

    copy_common_files "${staging}"

    # CMake (Windows)
    download "${CMAKE_WIN_URL}" "${CACHE_DIR}/cmake-win.zip"
    unzip -qo "${CACHE_DIR}/cmake-win.zip" -d "${CACHE_DIR}/cmake-tmp"
    mv "${CACHE_DIR}/cmake-tmp"/cmake-* "${staging}/tools/cmake"
    rm -rf "${CACHE_DIR}/cmake-tmp"

    # Ninja (Windows)
    download "${NINJA_WIN_URL}" "${CACHE_DIR}/ninja-win.zip"
    unzip -qo "${CACHE_DIR}/ninja-win.zip" -d "${staging}/tools/bin"

    # win_flex_bison
    download "${WINFLEXBISON_URL}" "${CACHE_DIR}/winflexbison.zip"
    unzip -qo "${CACHE_DIR}/winflexbison.zip" -d "${staging}/tools/bin"
    cp "${staging}/tools/bin/win_flex.exe" "${staging}/tools/bin/flex.exe"
    cp "${staging}/tools/bin/win_bison.exe" "${staging}/tools/bin/bison.exe"

    # LLVM-MinGW (Windows)
    download "${LLVM_WIN_X64_URL}" "${CACHE_DIR}/llvm-win-x64.zip"
    unzip -qo "${CACHE_DIR}/llvm-win-x64.zip" -d "${CACHE_DIR}/llvm-tmp"
    mv "${CACHE_DIR}/llvm-tmp"/llvm-mingw-* "${staging}/toolchains/llvm-mingw"
    rm -rf "${CACHE_DIR}/llvm-tmp"

    # winlibs GCC (Windows)
    download "${WINLIBS_X64_URL}" "${CACHE_DIR}/winlibs-x64.7z"
    mkdir -p "${CACHE_DIR}/winlibs-x64-tmp"
    7z x -o"${CACHE_DIR}/winlibs-x64-tmp" "${CACHE_DIR}/winlibs-x64.7z" >/dev/null
    mv "${CACHE_DIR}/winlibs-x64-tmp/mingw64" "${staging}/toolchains/mingw-gcc/x86_64-w64-mingw32"
    rm -rf "${CACHE_DIR}/winlibs-x64-tmp"

    download "${WINLIBS_I686_URL}" "${CACHE_DIR}/winlibs-i686.7z"
    mkdir -p "${CACHE_DIR}/winlibs-i686-tmp"
    7z x -o"${CACHE_DIR}/winlibs-i686-tmp" "${CACHE_DIR}/winlibs-i686.7z" >/dev/null
    mv "${CACHE_DIR}/winlibs-i686-tmp/mingw32" "${staging}/toolchains/mingw-gcc/i686-w64-mingw32"
    rm -rf "${CACHE_DIR}/winlibs-i686-tmp"

    # Add prefix copies for binutils (toolchain-gcc.cmake expects x86_64-w64-mingw32-<tool>)
    add_prefix_copies "${staging}/toolchains/mingw-gcc/x86_64-w64-mingw32/bin" "x86_64-w64-mingw32"
    add_prefix_copies "${staging}/toolchains/mingw-gcc/i686-w64-mingw32/bin"   "i686-w64-mingw32"

    (cd "${DIST_DIR}/staging" && zip -qr "${DIST_DIR}/${pkg}.zip" "${pkg}")
    ok "Created ${pkg}.zip"
}

add_prefix_copies() {
    local bin="$1" prefix="$2"
    for tool in windres windmc ar nm objcopy objdump ranlib readelf strip strings size dlltool as addr2line ld ld.bfd; do
        [[ -f "${bin}/${tool}.exe" && ! -f "${bin}/${prefix}-${tool}.exe" ]] && \
            cp "${bin}/${tool}.exe" "${bin}/${prefix}-${tool}.exe"
    done
}

# ── Checksums ─────────────────────────────────────────────────────────────────
generate_checksums() {
    info "Generating SHA256 checksums..."
    (cd "${DIST_DIR}" && sha256sum *.tar.xz *.zip 2>/dev/null > SHA256SUMS.txt)
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

    package_linux
    package_windows_x64
    generate_checksums

    echo ""
    echo -e "${GREEN}Done! Artifacts in: ${DIST_DIR}/${NC}"
}

main "$@"
