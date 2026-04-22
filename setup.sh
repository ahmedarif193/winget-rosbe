#!/bin/bash
# RosBE Modern - Factory Setup Script
# Downloads and extracts all toolchains + build tools into a self-contained environment
#
# Components:
#   - LLVM-MinGW 20251202 (Clang 21.1.7) - i686/x86_64/aarch64
#   - MinGW-GCC 15.2                      - i686/x86_64/aarch64
#   - CMake (latest stable)
#   - Ninja (latest stable)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROSBE_PREFIX="${SCRIPT_DIR}"
TOOLCHAIN_DIR="${ROSBE_PREFIX}/toolchains"
TOOLS_DIR="${ROSBE_PREFIX}/tools"
CACHE_DIR="${ROSBE_PREFIX}/.cache"

# ── Release URLs ──────────────────────────────────────────────────────────────
LLVM_VERSION="20251202"
LLVM_BASE_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_VERSION}"

GCC_VERSION="v15.2"
GCC_BASE_URL="https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/${GCC_VERSION}"

CMAKE_VERSION="3.31.6"
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"

NINJA_VERSION="1.12.1"
NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[  OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ── Helpers ───────────────────────────────────────────────────────────────────
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
    curl -L --progress-bar -o "${dest}" "${url}" || error "Download failed: ${url}"
    ok "Downloaded $(basename "${dest}")"
}

# ── CMake ─────────────────────────────────────────────────────────────────────
setup_cmake() {
    local cmake_dir="${TOOLS_DIR}/cmake"
    if [[ -x "${cmake_dir}/bin/cmake" ]]; then
        ok "CMake already installed ($(${cmake_dir}/bin/cmake --version | head -1))"
        return 0
    fi
    info "Setting up CMake ${CMAKE_VERSION}..."
    local archive="${TOOLS_DIR}/cmake-${CMAKE_VERSION}.tar.gz"
    download "${CMAKE_URL}" "${archive}"
    mkdir -p "${cmake_dir}"
    tar -xf "${archive}" -C "${cmake_dir}" --strip-components=1
    ok "CMake ${CMAKE_VERSION} -> ${cmake_dir}"
}

# ── Ninja ─────────────────────────────────────────────────────────────────────
setup_ninja() {
    if [[ -x "${TOOLS_DIR}/bin/ninja" ]]; then
        ok "Ninja already installed"
        return 0
    fi
    info "Setting up Ninja ${NINJA_VERSION}..."
    local archive="${TOOLS_DIR}/ninja-linux.zip"
    download "${NINJA_URL}" "${archive}"
    mkdir -p "${TOOLS_DIR}/bin"
    unzip -qo "${archive}" -d "${TOOLS_DIR}/bin"
    chmod +x "${TOOLS_DIR}/bin/ninja"
    ok "Ninja ${NINJA_VERSION} -> ${TOOLS_DIR}/bin/ninja"
}

# ── LLVM-MinGW ────────────────────────────────────────────────────────────────
setup_llvm_mingw() {
    local crt="${1:-ucrt}"
    local extract_dir="${TOOLCHAIN_DIR}/llvm-mingw"
    if [[ -d "${extract_dir}" && -x "${extract_dir}/bin/clang" ]]; then
        ok "LLVM-MinGW already installed"
        return 0
    fi
    local filename="llvm-mingw-${LLVM_VERSION}-${crt}-${HOST_PLATFORM}.tar.xz"
    local archive="${TOOLCHAIN_DIR}/${filename}"
    info "Setting up LLVM-MinGW (${crt})..."
    download "${LLVM_BASE_URL}/${filename}" "${archive}"
    mkdir -p "${extract_dir}"
    tar -xf "${archive}" -C "${TOOLCHAIN_DIR}" --strip-components=1 --one-top-level=llvm-mingw
    ok "LLVM-MinGW -> ${extract_dir}"
}

# ── MinGW-GCC ─────────────────────────────────────────────────────────────────
setup_mingw_gcc() {
    local extract_dir="${TOOLCHAIN_DIR}/mingw-gcc"
    if [[ -d "${extract_dir}/i686-w64-mingw32" ]]; then
        ok "MinGW-GCC already installed"
        return 0
    fi
    info "Setting up MinGW-GCC 15.2..."
    mkdir -p "${extract_dir}"
    local arches=("i686-w64-mingw32:tar.gz" "x86_64-w64-mingw32:tar.gz" "aarch64-w64-mingw32:tar.xz")
    for entry in "${arches[@]}"; do
        local arch="${entry%%:*}" ext="${entry##*:}"
        local filename="${arch}.${ext}"
        download "${GCC_BASE_URL}/${filename}" "${TOOLCHAIN_DIR}/${filename}"
        info "Extracting ${arch}..."
        tar -xf "${TOOLCHAIN_DIR}/${filename}" -C "${extract_dir}"
    done
    ok "MinGW-GCC -> ${extract_dir}"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  RosBE Modern - Setup Complete${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo "  Install prefix: ${ROSBE_PREFIX}"
    echo ""

    [[ -x "${TOOLS_DIR}/cmake/bin/cmake" ]] && \
        echo -e "  ${CYAN}CMake:${NC}     $("${TOOLS_DIR}/cmake/bin/cmake" --version | head -1)"
    [[ -x "${TOOLS_DIR}/bin/ninja" ]] && \
        echo -e "  ${CYAN}Ninja:${NC}     $("${TOOLS_DIR}/bin/ninja" --version 2>&1)"
    [[ -x "${TOOLCHAIN_DIR}/llvm-mingw/bin/clang" ]] && \
        echo -e "  ${CYAN}LLVM:${NC}      $("${TOOLCHAIN_DIR}/llvm-mingw/bin/clang" --version | head -1)"

    local gcc
    for gcc in "${TOOLCHAIN_DIR}/mingw-gcc"/*/bin/*-gcc; do
        if [[ -x "${gcc}" ]]; then
            echo -e "  ${CYAN}GCC:${NC}       $("${gcc}" --version | head -1)"
            break
        fi
    done

    echo ""
    echo "  Add to PATH:"
    echo "    export PATH=\"${TOOLS_DIR}/cmake/bin:${TOOLS_DIR}/bin:${TOOLCHAIN_DIR}/llvm-mingw/bin:\$PATH\""
    echo "    export LLVM_MINGW_ROOT=\"${TOOLCHAIN_DIR}/llvm-mingw\""
    echo "    export REACTOS_CLANG_LLVM_MINGW_ROOT=\"\$LLVM_MINGW_ROOT\""
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${GREEN}RosBE Modern - Factory Setup${NC}"
    echo ""

    detect_host

    # Ensure basic host tools (curl, tar, unzip)
    for cmd in curl tar unzip; do
        command -v "${cmd}" &>/dev/null || error "Missing host tool: ${cmd}. Install it first."
    done

    mkdir -p "${TOOLCHAIN_DIR}" "${TOOLS_DIR}"

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

    # Build tools (bundled, not system)
    setup_cmake
    setup_ninja

    # Cross-compilers
    ${install_llvm} && setup_llvm_mingw "${crt}"
    ${install_gcc}  && setup_mingw_gcc

    print_summary
}

main "$@"
