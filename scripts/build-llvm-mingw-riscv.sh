#!/bin/bash
# Builds the LLVM-MinGW RISC-V host toolchain (Clang 24 with the Windows
# PE/COFF RISC-V target) pinned in scripts/versions.env, and packs it for the
# llvm-mingw-riscv24-<version> toolchain release. rosbe-unix-bootstrap.sh
# installs that archive as <root>/llvm-mingw-riscv24.
#
# Run it on the baseline host of the platform the archive is named after:
#   Linux : inside ubuntu:22.04 (glibc 2.35), for example
#             podman run --rm -v "$PWD:/src" -w /src ubuntu:22.04 \
#                 scripts/build-llvm-mingw-riscv.sh --install-deps
#   macOS : on the host; produces a universal (arm64 + x86_64) build.
#
# Outputs in dist/toolchain/:
#   llvm-mingw-riscv24-<version>-<platform>.tar.xz
#   llvm-mingw-riscv24-<version>-<platform>.tar.xz.sha256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
DIST_DIR="${ROOT_DIR}/dist"
CACHE_DIR="${DIST_DIR}/cache"
OUT_DIR="${DIST_DIR}/toolchain"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $*"; }
error(){ echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

SOURCE_DIR=""
WORK_DIR="${CACHE_DIR}/llvm-riscv-${LLVM_RISCV_VERSION}"
JOBS=""
INSTALL_DEPS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source=*)     SOURCE_DIR="${1#*=}" ;;
        --work=*)       WORK_DIR="${1#*=}" ;;
        --jobs=*)       JOBS="${1#*=}" ;;
        --install-deps) INSTALL_DEPS=1 ;;
        --help|-h)
            echo "usage: $0 [--source=LLVM-DIR] [--work=DIR] [--jobs=N] [--install-deps]"
            exit 0
            ;;
        *) error "Unrecognized option: $1" ;;
    esac
    shift
done

# Same component set as the toolchain the ReactOS RISC-V port is built with.
COMPONENTS=(
    clang clang-resource-headers lld
    llvm-ar llvm-ranlib llvm-dlltool llvm-lib
    llvm-rc llvm-windres
    llvm-nm llvm-objcopy llvm-strip llvm-objdump llvm-readobj llvm-symbolizer
)

# Newest glibc symbol version a Linux archive may reference (ubuntu 22.04).
GLIBC_BASELINE=2.35

detect_host() {
    case "$(uname -s)" in
        Linux)
            HOST_OS="linux"
            case "$(uname -m)" in
                x86_64)  HOST_PLATFORM="ubuntu-22.04-x86_64" ;;
                aarch64) HOST_PLATFORM="ubuntu-22.04-aarch64" ;;
                *)       error "Unsupported Linux architecture: $(uname -m)" ;;
            esac
            ;;
        Darwin)
            HOST_OS="macos"
            HOST_PLATFORM="macos-universal"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac
}

install_deps() {
    [[ "${HOST_OS}" == "linux" ]] || error "--install-deps only knows apt-based Linux hosts."
    command -v apt-get &>/dev/null || error "--install-deps needs apt-get."
    local run=(env DEBIAN_FRONTEND=noninteractive)
    [[ "$(id -u)" -eq 0 ]] || run=(sudo "${run[@]}")
    info "Installing build dependencies..."
    "${run[@]}" apt-get update -qq
    "${run[@]}" apt-get install -y -qq --no-install-recommends \
        build-essential cmake ninja-build python3 lld binutils curl ca-certificates xz-utils
}

ensure_tools() {
    local missing=()
    for cmd in curl tar xz cmake ninja python3 cc c++; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing: ${missing[*]}. On ubuntu:22.04 rerun with --install-deps."
    fi
}

fetch_source() {
    if [[ -n "${SOURCE_DIR}" ]]; then
        [[ -f "${SOURCE_DIR}/llvm/CMakeLists.txt" ]] || error "Not an llvm-project tree: ${SOURCE_DIR}"
        SOURCE_DIR="$(cd "${SOURCE_DIR}" && pwd)"
        info "Using LLVM source at ${SOURCE_DIR} (expected ${LLVM_RISCV_COMMIT})"
        return 0
    fi

    local archive="${CACHE_DIR}/llvm-project-${LLVM_RISCV_COMMIT}.tar.gz"
    local url="https://github.com/${LLVM_RISCV_REPO}/archive/${LLVM_RISCV_COMMIT}.tar.gz"
    SOURCE_DIR="${WORK_DIR}/llvm-project-${LLVM_RISCV_COMMIT}"

    if [[ ! -f "${archive}" ]]; then
        info "Downloading $(basename "${archive}")..."
        curl -fSL \
            --connect-timeout 30 \
            --speed-limit 10240 --speed-time 60 \
            --retry 3 --retry-delay 5 \
            -o "${archive}.part" "${url}"
        mv "${archive}.part" "${archive}"
    else
        info "Cached: $(basename "${archive}")"
    fi

    if [[ ! -f "${SOURCE_DIR}/llvm/CMakeLists.txt" ]]; then
        info "Extracting LLVM source..."
        rm -rf "${SOURCE_DIR}"
        tar -xzf "${archive}" -C "${WORK_DIR}"
    fi
    ok "LLVM source -> ${SOURCE_DIR}"
}

build_toolchain() {
    local build_dir="${WORK_DIR}/build-${HOST_PLATFORM}"
    local components; components="$(IFS=';'; echo "${COMPONENTS[*]}")"
    local flags=()

    if [[ "${HOST_OS}" == "macos" ]]; then
        flags+=(-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0)
    else
        # Only glibc may stay a runtime dependency of the Linux archive.
        flags+=(-DLLVM_STATIC_LINK_CXX_STDLIB=ON -DCMAKE_EXE_LINKER_FLAGS=-static-libgcc)
        if command -v ld.lld &>/dev/null; then
            flags+=(-DLLVM_USE_LINKER=lld)
        fi
    fi

    info "Configuring ${PKG}..."
    rm -rf "${STAGE_DIR}"
    cmake -G Ninja -S "${SOURCE_DIR}/llvm" -B "${build_dir}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${STAGE_DIR}" \
        -DLLVM_ENABLE_ASSERTIONS=ON \
        -DLLVM_ENABLE_PROJECTS="clang;lld" \
        -DLLVM_TARGETS_TO_BUILD="RISCV;X86" \
        -DLLVM_DISTRIBUTION_COMPONENTS="${components}" \
        -DLLVM_FORCE_VC_REPOSITORY="https://github.com/${LLVM_RISCV_REPO}.git" \
        -DLLVM_FORCE_VC_REVISION="${LLVM_RISCV_COMMIT}" \
        -DLLVM_ENABLE_BINDINGS=OFF \
        -DLLVM_ENABLE_ZLIB=OFF \
        -DLLVM_ENABLE_ZSTD=OFF \
        -DLLVM_ENABLE_LIBXML2=OFF \
        -DLLVM_ENABLE_LIBEDIT=OFF \
        -DLLVM_ENABLE_LIBPFM=OFF \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_INCLUDE_DOCS=OFF \
        -DLLVM_PARALLEL_LINK_JOBS=2 \
        "${flags[@]}"

    info "Building ${PKG}..."
    cmake --build "${build_dir}" --target install-distribution-stripped ${JOBS:+--parallel "${JOBS}"}

    cp "${SOURCE_DIR}/llvm/LICENSE.TXT" "${STAGE_DIR}/LICENSE.TXT"
    write_toolchain_manifest
    ok "Built ${PKG}"
}

write_toolchain_manifest() {
    local list="" c
    for c in "${COMPONENTS[@]}"; do
        list+="${list:+,
}    \"${c}\""
    done
    cat > "${STAGE_DIR}/native-toolchain.json" <<EOF
{
  "version": "${LLVM_RISCV_VERSION}",
  "host": "${HOST_PLATFORM}",
  "source": "https://github.com/${LLVM_RISCV_REPO}",
  "revision": "${LLVM_RISCV_COMMIT}",
  "components": [
${list}
  ]
}
EOF
}

# A Linux archive must run on the ubuntu 22.04 baseline with nothing but
# glibc: no newer symbol versions, no host libstdc++/zlib/zstd/libxml2.
verify_linux_portability() {
    [[ "${HOST_OS}" == "linux" ]] || return 0
    info "Checking glibc baseline (<= ${GLIBC_BASELINE}) and runtime dependencies..."
    local f needed newest
    while IFS= read -r f; do
        needed="$(objdump -p "${f}" | awk '$1 == "NEEDED" { print $2 }' \
            | grep -Ev '^(libc|libm|libdl|libpthread|librt)\.so\.[0-9]+$|^ld-linux-.*\.so\.[0-9]+$' || true)"
        [[ -z "${needed}" ]] || error "$(basename "${f}") depends on host libraries: ${needed//$'\n'/ }"
        newest="$(objdump -T "${f}" | grep -oE 'GLIBC_[0-9.]+' | sed 's/GLIBC_//' | sort -Vu | tail -1)"
        if [[ -n "${newest}" && "$(printf '%s\n' "${GLIBC_BASELINE}" "${newest}" | sort -V | tail -1)" != "${GLIBC_BASELINE}" ]]; then
            error "$(basename "${f}") needs glibc ${newest}; build inside ubuntu:22.04."
        fi
    done < <(find "${STAGE_DIR}/bin" -type f -perm -u+x)
    ok "Linux archive depends on glibc <= ${GLIBC_BASELINE} only"
}

# Compile and link a RISC-V PE image with the staged tools, the way the
# ReactOS RISC-V toolchain file drives them.
smoke_test() {
    local tmp="${WORK_DIR}/smoke-${HOST_PLATFORM}"
    local bin="${STAGE_DIR}/bin"
    info "Smoke-testing the staged toolchain..."
    rm -rf "${tmp}"
    mkdir -p "${tmp}"

    "${bin}/clang" --version | grep -F "${LLVM_RISCV_COMMIT}" >/dev/null \
        || error "clang does not report revision ${LLVM_RISCV_COMMIT}"

    printf 'int Value = 7;\nint EfiEntry(void) { return Value; }\n' > "${tmp}/smoke.c"
    "${bin}/clang" --target=riscv64-w64-windows-gnu \
        -march=rv64gc -mabi=lp64 -mcmodel=medany -mno-relax \
        -nostdlib -fuse-ld=lld -Wl,-entry,EfiEntry -Wl,--subsystem,efi_application \
        "${tmp}/smoke.c" -o "${tmp}/smoke.efi"
    "${bin}/llvm-readobj" --file-headers "${tmp}/smoke.efi" | grep -F 'IMAGE_FILE_MACHINE_RISCV64' >/dev/null \
        || error "Linked image is not a RISC-V 64-bit PE"

    printf 'EXPORTS\nSmoke\n' > "${tmp}/smoke.def"
    "${bin}/llvm-dlltool" -m riscv64 -d "${tmp}/smoke.def" -D smoke.dll -l "${tmp}/libsmoke.a"
    "${bin}/llvm-nm" "${tmp}/libsmoke.a" >/dev/null

    rm -rf "${tmp}"
    ok "RISC-V 64-bit PE compile, link and import-library checks passed"
}

package_toolchain() {
    local archive="${OUT_DIR}/${PKG}.tar.xz"
    local tar_cmd=(tar)

    # GNU tar can drop the builder's uid/gid; macOS ships bsdtar unless
    # Homebrew's gnu-tar is installed.
    if command -v gtar &>/dev/null; then
        tar_cmd=(gtar)
    fi
    if "${tar_cmd[@]}" --version 2>/dev/null | grep -q 'GNU tar'; then
        tar_cmd+=(--numeric-owner --owner=0 --group=0)
    fi

    info "Packing ${PKG}.tar.xz..."
    rm -f "${archive}" "${archive}.sha256"
    XZ_OPT=-9 "${tar_cmd[@]}" -cJf "${archive}" -C "${WORK_DIR}/stage" "${PKG}"

    if command -v sha256sum &>/dev/null; then
        ( cd "${OUT_DIR}" && sha256sum "${PKG}.tar.xz" > "${PKG}.tar.xz.sha256" )
    else
        ( cd "${OUT_DIR}" && shasum -a 256 "${PKG}.tar.xz" > "${PKG}.tar.xz.sha256" )
    fi

    local size; size=$(du -h "${archive}" | cut -f1)
    ok "Created ${PKG}.tar.xz (${size})"
    cat "${archive}.sha256"
}

main() {
    echo -e "${GREEN}RosBE - LLVM-MinGW RISC-V toolchain builder v${LLVM_RISCV_VERSION}${NC}"
    echo ""

    detect_host
    if [[ "${INSTALL_DEPS}" -eq 1 ]]; then
        install_deps
    fi
    ensure_tools

    mkdir -p "${OUT_DIR}" "${CACHE_DIR}" "${WORK_DIR}"
    WORK_DIR="$(cd "${WORK_DIR}" && pwd)"
    PKG="llvm-mingw-riscv24-${LLVM_RISCV_VERSION}-${HOST_PLATFORM}"
    STAGE_DIR="${WORK_DIR}/stage/${PKG}"

    fetch_source
    build_toolchain
    verify_linux_portability
    smoke_test
    package_toolchain

    echo ""
    echo -e "${GREEN}Done! Artifacts in: ${OUT_DIR}/${NC}"
}

main "$@"
