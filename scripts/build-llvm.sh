#!/bin/bash
# Builds the RosBE LLVM toolchain (Clang 24 for every LiberNT target: x86,
# AArch64, ARM, RISC-V and PowerPC PE/COFF) pinned in scripts/versions.env,
# and packs it for the llvm-<version> toolchain release with the LLVM runtime
# sources the LiberNT build compiles its C++ runtimes from (src/llvm-project).
# rosbe-unix-bootstrap.sh installs that archive as <root>/llvm.
#
# Run it on the baseline host of the platform the archive is named after:
#   Linux : inside ubuntu:22.04 (glibc 2.35), for example
#             podman run --rm -v "$PWD:/src" -w /src ubuntu:22.04 \
#                 scripts/build-llvm.sh --install-deps
#   macOS : on the host; produces a universal (arm64 + x86_64) build.
#
# The Windows archive is cross-compiled on Linux with the LLVM-MinGW release
# pinned as LLVM_VERSION (downloaded unless --mingw points at one):
#             scripts/build-llvm.sh --install-deps --host=windows-x86_64
# Its binaries cannot run on the build host, so the smoke test only runs when
# Wine is installed; the workflow repeats it on a Windows runner.
#
# Outputs in dist/toolchain/ (.zip for Windows hosts, .tar.xz otherwise):
#   llvm-<version>-<platform>.tar.xz
#   llvm-<version>-<platform>.tar.xz.sha256

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
WORK_DIR="${CACHE_DIR}/llvm-${LLVM_NATIVE_VERSION}"
JOBS=""
INSTALL_DEPS=0
TARGET_HOST=""
MINGW_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source=*)     SOURCE_DIR="${1#*=}" ;;
        --work=*)       WORK_DIR="${1#*=}" ;;
        --jobs=*)       JOBS="${1#*=}" ;;
        --host=*)       TARGET_HOST="${1#*=}" ;;
        --mingw=*)      MINGW_DIR="${1#*=}" ;;
        --install-deps) INSTALL_DEPS=1 ;;
        --help|-h)
            echo "usage: $0 [--source=LLVM-DIR] [--work=DIR] [--jobs=N] [--install-deps]"
            echo "          [--host=windows-x86_64 [--mingw=LLVM-MINGW-DIR]]"
            exit 0
            ;;
        *) error "Unrecognized option: $1" ;;
    esac
    shift
done

# The tools the LiberNT Clang build drives.
COMPONENTS=(
    clang clang-resource-headers lld
    llvm-ar llvm-ranlib llvm-dlltool llvm-lib
    llvm-rc llvm-windres
    llvm-nm llvm-objcopy llvm-strip llvm-objdump llvm-readobj llvm-symbolizer
)

# Newest glibc symbol version a Linux archive may reference (ubuntu 22.04).
GLIBC_BASELINE=2.35

# The only DLLs a Windows archive may import: the UCRT and system libraries
# present on every supported Windows install (winhttp and crypt32 back the
# debuginfod client in llvm-objdump and llvm-symbolizer).
WINDOWS_SYSTEM_DLLS='^(api-ms-win-crt-[a-z0-9-]+|kernel32|ntdll|advapi32|shell32|ole32|user32|ws2_32|version|psapi|winhttp|crypt32)\.dll$'

# Without symlinks every tool alias is a full copy of its binary (lld is
# ~90 MB). Leave out the lld names a PE/COFF toolchain never runs: the Mach-O
# and WebAssembly drivers and the generic driver, which only tells the caller
# to use one of the others. ld.lld and lld-link stay.
WINDOWS_PRUNED_TOOLS=(lld ld64.lld wasm-ld)

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

    ARCHIVE_EXT="tar.xz"
    case "${TARGET_HOST}" in
        ""|"${HOST_PLATFORM}")
            [[ -z "${MINGW_DIR}" ]] || error "--mingw is only used with --host=windows-x86_64."
            ;;
        windows-x86_64)
            [[ "${HOST_OS}" == "linux" ]] || error "--host=${TARGET_HOST} is cross-compiled on Linux."
            # Release assets of the LLVM-MinGW build that runs on this machine.
            MINGW_PLATFORM="${HOST_PLATFORM}"
            MINGW_TRIPLE="x86_64-w64-mingw32"
            HOST_OS="windows"
            HOST_PLATFORM="windows-x86_64"
            ARCHIVE_EXT="zip"
            ;;
        *)
            error "Unsupported --host: ${TARGET_HOST} (this machine builds ${HOST_PLATFORM} or windows-x86_64)"
            ;;
    esac
}

install_deps() {
    [[ "${HOST_OS}" != "macos" ]] || error "--install-deps only knows apt-based Linux hosts."
    command -v apt-get &>/dev/null || error "--install-deps needs apt-get."
    local extra=()
    [[ "${HOST_OS}" != "windows" ]] || extra+=(zip)
    local run=(env DEBIAN_FRONTEND=noninteractive)
    [[ "$(id -u)" -eq 0 ]] || run=(sudo "${run[@]}")
    info "Installing build dependencies..."
    "${run[@]}" apt-get update -qq
    "${run[@]}" apt-get install -y -qq --no-install-recommends \
        build-essential cmake ninja-build python3 lld binutils curl ca-certificates xz-utils \
        ${extra[@]+"${extra[@]}"}
}

ensure_tools() {
    local missing=() tools=(curl tar xz cmake ninja python3 cc c++)
    [[ "${HOST_OS}" != "windows" ]] || tools+=(zip)
    for cmd in "${tools[@]}"; do
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
        info "Using LLVM source at ${SOURCE_DIR} (expected ${LLVM_NATIVE_COMMIT})"
        return 0
    fi

    local archive="${CACHE_DIR}/llvm-project-${LLVM_NATIVE_COMMIT}.tar.gz"
    local url="https://github.com/${LLVM_NATIVE_REPO}/archive/${LLVM_NATIVE_COMMIT}.tar.gz"
    SOURCE_DIR="${WORK_DIR}/llvm-project-${LLVM_NATIVE_COMMIT}"

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

# The cross compiler and Windows sysroot for --host=windows-x86_64.
fetch_cross_toolchain() {
    [[ "${HOST_OS}" == "windows" ]] || return 0

    if [[ -n "${MINGW_DIR}" ]]; then
        MINGW_DIR="$(cd "${MINGW_DIR}" && pwd)" || error "No LLVM-MinGW at --mingw"
    else
        local name="llvm-mingw-${LLVM_VERSION}-${LLVM_TRIPLET}-${MINGW_PLATFORM}"
        local archive="${CACHE_DIR}/${name}.tar.xz"
        local url="https://github.com/ahmedarif193/winget-rosbe/releases/download/llvm-mingw-${LLVM_VERSION}/${name}.tar.xz"
        MINGW_DIR="${WORK_DIR}/${name}"

        if [[ ! -f "${archive}" ]]; then
            info "Downloading ${name}.tar.xz..."
            curl -fSL \
                --connect-timeout 30 \
                --speed-limit 10240 --speed-time 60 \
                --retry 3 --retry-delay 5 \
                -o "${archive}.part" "${url}"
            mv "${archive}.part" "${archive}"
        else
            info "Cached: ${name}.tar.xz"
        fi

        if [[ ! -x "${MINGW_DIR}/bin/${MINGW_TRIPLE}-clang" ]]; then
            info "Extracting LLVM-MinGW..."
            rm -rf "${MINGW_DIR}"
            tar -xJf "${archive}" -C "${WORK_DIR}"
        fi
    fi

    [[ -x "${MINGW_DIR}/bin/${MINGW_TRIPLE}-clang" && -d "${MINGW_DIR}/${MINGW_TRIPLE}/lib" ]] \
        || error "${MINGW_DIR} has no ${MINGW_TRIPLE} compiler and sysroot"
    ok "LLVM-MinGW cross toolchain -> ${MINGW_DIR}"
}

build_toolchain() {
    local build_dir="${WORK_DIR}/build-${HOST_PLATFORM}"
    local components; components="$(IFS=';'; echo "${COMPONENTS[*]}")"
    local flags=()

    if [[ "${HOST_OS}" == "macos" ]]; then
        flags+=(-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0)
    elif [[ "${HOST_OS}" == "windows" ]]; then
        # LLVM builds the matching native tablegen tools itself, with the
        # build machine's default compiler. -static keeps libc++ and libunwind
        # out of the runtime dependencies; a zip carries no symlinks.
        flags+=(
            -DCMAKE_SYSTEM_NAME=Windows
            -DCMAKE_SYSTEM_PROCESSOR=x86_64
            -DCMAKE_C_COMPILER="${MINGW_DIR}/bin/${MINGW_TRIPLE}-clang"
            -DCMAKE_CXX_COMPILER="${MINGW_DIR}/bin/${MINGW_TRIPLE}-clang++"
            -DCMAKE_RC_COMPILER="${MINGW_DIR}/bin/${MINGW_TRIPLE}-windres"
            -DCMAKE_AR="${MINGW_DIR}/bin/llvm-ar"
            -DCMAKE_RANLIB="${MINGW_DIR}/bin/llvm-ranlib"
            -DCMAKE_STRIP="${MINGW_DIR}/bin/llvm-strip"
            -DCMAKE_FIND_ROOT_PATH="${MINGW_DIR}/${MINGW_TRIPLE}"
            -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
            -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
            -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
            -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
            -DLLVM_HOST_TRIPLE="${MINGW_TRIPLE}"
            -DLLVM_USE_SYMLINKS=OFF
            -DCMAKE_EXE_LINKER_FLAGS=-static
        )
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
        -DLLVM_TARGETS_TO_BUILD="${LLVM_NATIVE_TARGETS//,/;}" \
        -DLLVM_DISTRIBUTION_COMPONENTS="${components}" \
        -DLLVM_FORCE_VC_REPOSITORY="https://github.com/${LLVM_NATIVE_REPO}.git" \
        -DLLVM_FORCE_VC_REVISION="${LLVM_NATIVE_COMMIT}" \
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

    if [[ "${HOST_OS}" == "windows" ]]; then
        local t
        for t in "${WINDOWS_PRUNED_TOOLS[@]}"; do
            rm -f "${STAGE_DIR}/bin/${t}.exe"
        done
    fi

    cp "${SOURCE_DIR}/llvm/LICENSE.TXT" "${STAGE_DIR}/LICENSE.TXT"
    stage_runtime_sources
    write_toolchain_manifest
    ok "Built ${PKG}"
}

# The LiberNT build compiles libc++, libc++abi, libunwind and the compiler-rt
# builtins for each target from the sources of this exact revision.
RUNTIME_SOURCE_DIRS=(
    cmake runtimes libcxx libcxxabi libunwind libc compiler-rt third-party
    llvm/cmake llvm/utils
)

stage_runtime_sources() {
    local dest="${STAGE_DIR}/src/llvm-project" d
    rm -rf "${dest}"
    for d in "${RUNTIME_SOURCE_DIRS[@]}"; do
        mkdir -p "${dest}/$(dirname "${d}")"
        cp -RL "${SOURCE_DIR}/${d}" "${dest}/${d}"
    done
    ok "Runtime sources -> src/llvm-project"
}

write_toolchain_manifest() {
    local list="" c
    for c in "${COMPONENTS[@]}"; do
        list+="${list:+,
}    \"${c}\""
    done
    cat > "${STAGE_DIR}/native-toolchain.json" <<EOF
{
  "version": "${LLVM_NATIVE_VERSION}",
  "host": "${HOST_PLATFORM}",
  "source": "https://github.com/${LLVM_NATIVE_REPO}",
  "revision": "${LLVM_NATIVE_COMMIT}",
  "targets": "${LLVM_NATIVE_TARGETS}",
  "runtime_source": "src/llvm-project",
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

# A Windows archive must run on a clean install: no libc++, libunwind or
# winpthread DLLs next to the tools, and no symlinks, which zip extraction on
# Windows cannot recreate.
verify_windows_portability() {
    [[ "${HOST_OS}" == "windows" ]] || return 0
    info "Checking DLL imports and archive layout..."
    local f imports foreign links count=0
    links="$(find "${STAGE_DIR}" -type l)"
    [[ -z "${links}" ]] || error "Staged tree contains symlinks: ${links//$'\n'/ }"
    while IFS= read -r f; do
        imports="$("${MINGW_DIR}/bin/llvm-objdump" -p "${f}" | awk '$1 == "DLL" && $2 == "Name:" { print $3 }')"
        [[ -n "${imports}" ]] || error "$(basename "${f}") has no import table; is it a PE image?"
        foreign="$(grep -Eiv "${WINDOWS_SYSTEM_DLLS}" <<<"${imports}" || true)"
        [[ -z "${foreign}" ]] || error "$(basename "${f}") depends on non-system DLLs: ${foreign//$'\n'/ }"
        count=$((count + 1))
    done < <(find "${STAGE_DIR}/bin" -type f \( -name '*.exe' -o -name '*.dll' \))
    [[ "${count}" -gt 0 ]] || error "No Windows binaries were staged"
    [[ -f "${STAGE_DIR}/bin/clang.exe" && -f "${STAGE_DIR}/bin/ld.lld.exe" ]] \
        || error "Staged tree is missing clang.exe or ld.lld.exe"
    ok "Windows archive imports system DLLs only (${count} binaries)"
}

# Compile and link a RISC-V PE image with the staged tools, the way the
# ReactOS RISC-V toolchain file drives them.
smoke_test() {
    if [[ "${HOST_OS}" != "windows" ]]; then
        "${SCRIPT_DIR}/smoke-llvm.sh" "${STAGE_DIR}"
    elif command -v wine &>/dev/null; then
        WINEPREFIX="${WORK_DIR}/wine-${HOST_PLATFORM}" WINEDEBUG=-all \
            "${SCRIPT_DIR}/smoke-llvm.sh" --launcher=wine "${STAGE_DIR}"
    else
        info "Wine is not installed: skipping the smoke test (run smoke-llvm.sh on Windows)."
    fi
}

package_toolchain() {
    local archive="${OUT_DIR}/${PKG}.${ARCHIVE_EXT}"
    local tar_cmd=(tar)

    info "Packing ${PKG}.${ARCHIVE_EXT}..."
    if [[ "${ARCHIVE_EXT}" == "zip" ]]; then
        ( cd "${WORK_DIR}/stage" && zip -q -r -X -9 "${archive}.part" "${PKG}" )
    else
        # GNU tar can drop the builder's uid/gid; macOS ships bsdtar unless
        # Homebrew's gnu-tar is installed.
        if command -v gtar &>/dev/null; then
            tar_cmd=(gtar)
        fi
        if "${tar_cmd[@]}" --version 2>/dev/null | grep -q 'GNU tar'; then
            tar_cmd+=(--numeric-owner --owner=0 --group=0)
        fi
        XZ_OPT=-9 "${tar_cmd[@]}" -cJf "${archive}.part" -C "${WORK_DIR}/stage" "${PKG}"
    fi
    mv "${archive}.part" "${archive}"

    # Checksum files name the archive relative to the directory they sit in.
    if command -v sha256sum &>/dev/null; then
        ( cd "${OUT_DIR}" && sha256sum "${PKG}.${ARCHIVE_EXT}" > "${PKG}.${ARCHIVE_EXT}.sha256" )
    else
        ( cd "${OUT_DIR}" && shasum -a 256 "${PKG}.${ARCHIVE_EXT}" > "${PKG}.${ARCHIVE_EXT}.sha256" )
    fi

    local size; size=$(du -h "${archive}" | cut -f1)
    ok "Created ${PKG}.${ARCHIVE_EXT} (${size})"
    cat "${archive}.sha256"
}

main() {
    echo -e "${GREEN}RosBE - LLVM toolchain builder v${LLVM_NATIVE_VERSION}${NC}"
    echo ""

    detect_host
    if [[ "${INSTALL_DEPS}" -eq 1 ]]; then
        install_deps
    fi
    ensure_tools

    mkdir -p "${OUT_DIR}" "${CACHE_DIR}" "${WORK_DIR}"
    WORK_DIR="$(cd "${WORK_DIR}" && pwd)"
    PKG="llvm-${LLVM_NATIVE_VERSION}-${HOST_PLATFORM}"
    STAGE_DIR="${WORK_DIR}/stage/${PKG}"

    # A failed run must not leave an earlier archive behind to be published.
    rm -f "${OUT_DIR}/${PKG}.${ARCHIVE_EXT}"{,.sha256,.part}

    fetch_source
    fetch_cross_toolchain
    build_toolchain
    verify_linux_portability
    verify_windows_portability
    smoke_test
    package_toolchain

    echo ""
    echo -e "${GREEN}Done! Artifacts in: ${OUT_DIR}/${NC}"
}

main "$@"
