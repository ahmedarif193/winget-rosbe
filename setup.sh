#!/bin/bash
# RosBE Modern - Linux Setup Script
#
# Downloads and extracts all toolchains + build tools into a flat per-component
# layout that mirrors the Windows winget package.
#
# Layout produced (under $ROSBE_PREFIX, default $(dirname "$0")):
#   cmake-<ver>/bin/cmake ...
#   ninja-<ver>/ninja
#   llvm-mingw/bin/clang ...
#   mingw-gcc/{i686,x86_64,aarch64}-w64-mingw32/bin/<triple>-gcc ...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROSBE_PREFIX="${ROSBE_PREFIX:-${SCRIPT_DIR}}"
CACHE_DIR="${ROSBE_PREFIX}/.cache"

# shellcheck source=scripts/versions.env
source "${SCRIPT_DIR}/scripts/versions.env"

LLVM_BASE_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_VERSION}"
GCC_BASE_URL="https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/${GCC_TAG}"
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[  OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

detect_host() {
    local os arch
    os="$(uname -s)"; arch="$(uname -m)"
    case "${os}" in
        Linux)
            case "${arch}" in
                x86_64)  HOST_PLATFORM="ubuntu-22.04-x86_64"; HOST_ARCH="x86_64" ;;
                aarch64) HOST_PLATFORM="ubuntu-22.04-aarch64"; HOST_ARCH="aarch64" ;;
                *)       error "Unsupported Linux architecture: ${arch}" ;;
            esac ;;
        Darwin) HOST_PLATFORM="macos-universal"; HOST_ARCH="universal" ;;
        *)      error "Unsupported OS: ${os}" ;;
    esac
    info "Host: ${os} ${arch} (${HOST_PLATFORM})"
}

download() {
    local url="$1" dest="$2"
    if [[ -f "${dest}" ]]; then
        info "Cached: $(basename "${dest}")"; return 0
    fi
    info "Downloading $(basename "${dest}")..."
    curl -fSL --progress-bar -o "${dest}" "${url}" || error "Download failed: ${url}"
    ok "Downloaded $(basename "${dest}")"
}

setup_cmake() {
    local target="${ROSBE_PREFIX}/cmake-${CMAKE_VERSION}"
    if [[ -x "${target}/bin/cmake" ]]; then
        ok "CMake already installed ($(${target}/bin/cmake --version | head -1))"
        return 0
    fi
    info "Setting up CMake ${CMAKE_VERSION}..."
    local archive="${CACHE_DIR}/cmake-${CMAKE_VERSION}-linux.tar.gz"
    download "${CMAKE_URL}" "${archive}"
    mkdir -p "${target}"
    tar -xf "${archive}" -C "${target}" --strip-components=1
    ok "CMake ${CMAKE_VERSION} -> ${target}"
}

setup_ninja() {
    local target="${ROSBE_PREFIX}/ninja-${NINJA_VERSION}"
    if [[ -x "${target}/ninja" ]]; then
        ok "Ninja already installed"
        return 0
    fi
    info "Setting up Ninja ${NINJA_VERSION}..."
    local archive="${CACHE_DIR}/ninja-linux.zip"
    download "${NINJA_URL}" "${archive}"
    mkdir -p "${target}"
    unzip -qo "${archive}" -d "${target}"
    chmod +x "${target}/ninja"
    ok "Ninja ${NINJA_VERSION} -> ${target}"
}

setup_llvm_mingw() {
    local crt="${1:-ucrt}"
    local target="${ROSBE_PREFIX}/llvm-mingw"
    if [[ -d "${target}" && -x "${target}/bin/clang" ]]; then
        ok "LLVM-MinGW already installed"
        return 0
    fi
    local filename="llvm-mingw-${LLVM_VERSION}-${crt}-${HOST_PLATFORM}.tar.xz"
    local archive="${CACHE_DIR}/${filename}"
    info "Setting up LLVM-MinGW (${crt})..."
    download "${LLVM_BASE_URL}/${filename}" "${archive}"
    mkdir -p "${target}"
    tar -xf "${archive}" -C "${target}" --strip-components=1
    ok "LLVM-MinGW -> ${target}"
}

setup_mingw_gcc() {
    local target_root="${ROSBE_PREFIX}/mingw-gcc"
    if [[ -d "${target_root}/i686-w64-mingw32" ]]; then
        ok "MinGW-GCC already installed"
        return 0
    fi
    info "Setting up MinGW-GCC ${GCC_VERSION}..."
    mkdir -p "${target_root}"
    local arches=("i686-w64-mingw32:tar.gz" "x86_64-w64-mingw32:tar.gz" "aarch64-w64-mingw32:tar.xz")
    for entry in "${arches[@]}"; do
        local arch="${entry%%:*}" ext="${entry##*:}"
        local filename="${arch}.${ext}"
        download "${GCC_BASE_URL}/${filename}" "${CACHE_DIR}/${filename}"
        info "Extracting ${arch}..."
        tar -xf "${CACHE_DIR}/${filename}" -C "${target_root}"
    done
    ok "MinGW-GCC -> ${target_root}"
}

print_summary() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  RosBE Modern - Setup Complete${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo "  Install prefix: ${ROSBE_PREFIX}"
    echo ""

    local cmake_bin="${ROSBE_PREFIX}/cmake-${CMAKE_VERSION}/bin/cmake"
    local ninja_bin="${ROSBE_PREFIX}/ninja-${NINJA_VERSION}/ninja"
    local clang_bin="${ROSBE_PREFIX}/llvm-mingw/bin/clang"

    [[ -x "${cmake_bin}" ]] && echo -e "  ${CYAN}CMake:${NC}     $("${cmake_bin}" --version | head -1)"
    [[ -x "${ninja_bin}" ]] && echo -e "  ${CYAN}Ninja:${NC}     $("${ninja_bin}" --version 2>&1)"
    [[ -x "${clang_bin}" ]] && echo -e "  ${CYAN}LLVM:${NC}      $("${clang_bin}" --version | head -1)"

    local gcc
    for gcc in "${ROSBE_PREFIX}/mingw-gcc"/*/bin/*-gcc; do
        if [[ -x "${gcc}" ]]; then
            echo -e "  ${CYAN}GCC:${NC}       $("${gcc}" --version | head -1)"
            break
        fi
    done

    echo ""
    echo "  Add to PATH:"
    echo "    export PATH=\"${ROSBE_PREFIX}/cmake-${CMAKE_VERSION}/bin:${ROSBE_PREFIX}/ninja-${NINJA_VERSION}:${ROSBE_PREFIX}/llvm-mingw/bin:\$PATH\""
    echo ""
}

main() {
    echo -e "${GREEN}RosBE Modern - Linux Setup${NC}"
    echo ""

    detect_host

    for cmd in curl tar unzip; do
        command -v "${cmd}" &>/dev/null || error "Missing host tool: ${cmd}. Install it first."
    done

    mkdir -p "${ROSBE_PREFIX}" "${CACHE_DIR}"

    local install_llvm=true install_gcc=true crt="ucrt"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --llvm-only)  install_gcc=false; shift ;;
            --gcc-only)   install_llvm=false; shift ;;
            --msvcrt)     crt="msvcrt"; shift ;;
            --ucrt)       crt="ucrt"; shift ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "  --llvm-only   Only install LLVM-MinGW"
                echo "  --gcc-only    Only install MinGW-GCC"
                echo "  --ucrt        UCRT variant (default)"
                echo "  --msvcrt      MSVCRT variant"
                exit 0 ;;
            *) error "Unknown option: $1" ;;
        esac
    done

    setup_cmake
    setup_ninja

    ${install_llvm} && setup_llvm_mingw "${crt}"
    ${install_gcc}  && setup_mingw_gcc

    print_summary
}

main "$@"
