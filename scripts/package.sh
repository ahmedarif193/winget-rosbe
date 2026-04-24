#!/bin/bash
# Produces release archives by downloading upstreams and bundling into a
# self-contained prefix. Runs on Linux (CI or WSL).
#
# Outputs in dist/:
#   rosbe-<version>-linux-x64.tar.xz
#   rosbe-<version>-win-x64.zip
#   rosbe-bootstrapper-<version>-win-x64.zip
#   rosbe.exe
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
VERSION="${1:-$(date -u +%Y%m%d)}"
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

GCC_BASE="https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/${GCC_TAG}"
GCC_LINUX_I686_URL="${GCC_BASE}/i686-w64-mingw32.tar.gz"
GCC_LINUX_X64_URL="${GCC_BASE}/x86_64-w64-mingw32.tar.gz"
GCC_LINUX_AARCH64_URL="${GCC_BASE}/aarch64-w64-mingw32.tar.xz"
GCC_WIN_X64_URL="${GCC_BASE}/x86_64-w64-mingw32-winhost.zip"
GCC_WIN_I686_URL="${GCC_BASE}/i686-w64-mingw32-winhost.zip"

CMAKE_LINUX_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
CMAKE_WIN_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-windows-x86_64.zip"

NINJA_LINUX_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"
NINJA_WIN_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-win.zip"

WINFLEXBISON_URL="https://github.com/lexxmark/winflexbison/releases/download/v${WINFLEXBISON_VERSION}/win_flex_bison-${WINFLEXBISON_VERSION}.zip"
QEMU_WIN_NAME="qemu-w64-setup-${QEMU_WIN_BUILD}.exe"
QEMU_WIN_URL="https://qemu.weilnetz.de/w64/${QEMU_WIN_NAME}"
QEMU_WIN_SHA512_NAME="${QEMU_WIN_NAME%.exe}.sha512"
QEMU_WIN_SHA512_URL="https://qemu.weilnetz.de/w64/${QEMU_WIN_SHA512_NAME}"

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
    for cmd in curl tar unzip zip 7z sha256sum sha512sum cargo x86_64-w64-mingw32-gcc; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing: ${missing[*]}. Install the system archive tools, the MinGW x64 cross-compiler, and a Rust toolchain with the x86_64-pc-windows-gnu target."
    fi
}

reset_tmp_dir() {
    local tmp="$1"
    rm -rf "${tmp}"
    mkdir -p "${tmp}"
}

move_extracted_dir() {
    local tmp="$1" name_glob="$2" dest="$3"
    local matches=()
    mapfile -t matches < <(find "${tmp}" -mindepth 1 -maxdepth 1 -type d -name "${name_glob}" -print)

    if [[ ${#matches[@]} -ne 1 ]]; then
        error "Unexpected archive layout in ${tmp}: expected one ${name_glob} directory, found ${#matches[@]}"
    fi

    chmod -R u+rwX "${tmp}" 2>/dev/null || true
    mkdir -p "$(dirname "${dest}")"
    rm -rf "${dest}"

    if ! mv "${matches[0]}" "${dest}"; then
        info "Direct move failed for ${name_glob}; copying into place..."
        rm -rf "${dest}"
        cp -a "${matches[0]}" "${dest}"
    fi

    chmod -R u+rwX "${dest}" 2>/dev/null || true
    rm -rf "${tmp}"
}

verify_sha512() {
    local root="$1" checksum_file="$2"
    info "Verifying $(basename "${checksum_file}")..."
    ( cd "${root}" && sha512sum -c --status "$(basename "${checksum_file}")" )
    ok "Verified $(basename "${checksum_file}")"
}

write_windows_component_manifest() {
    local staging="$1"
    cat > "${staging}/rosbe-components.json" <<EOF
[
  { "name": "CMake", "version": "${CMAKE_VERSION}", "path": "cmake-${CMAKE_VERSION}/bin" },
  { "name": "Ninja", "version": "${NINJA_VERSION}", "path": "ninja-${NINJA_VERSION}" },
  { "name": "WinFlexBison", "version": "${WINFLEXBISON_VERSION}", "path": "win_flex_bison-${WINFLEXBISON_VERSION}" },
  { "name": "LLVM-MinGW", "version": "${LLVM_VERSION}", "path": "llvm-mingw/bin" },
  { "name": "MinGW-GCC (x86_64)", "version": "${GCC_VERSION}", "path": "mingw-gcc/x86_64-w64-mingw32/bin" },
  { "name": "MinGW-GCC (i686)", "version": "${GCC_VERSION}", "path": "mingw-gcc/i686-w64-mingw32/bin" },
  { "name": "QEMU", "version": "${QEMU_VERSION}", "path": "qemu-${QEMU_VERSION}" }
]
EOF
}

build_bootstrapper_windows() {
    local target="x86_64-pc-windows-gnu"
    local release_dir="${ROOT_DIR}/bootstrapper/target/${target}/release"
    local asset="rosbe-bootstrapper-${VERSION}-win-x64.zip"

    info "Building rosbe.exe bootstrapper..."
    cargo build \
        --manifest-path "${ROOT_DIR}/bootstrapper/Cargo.toml" \
        --locked \
        --release \
        --target "${target}"

    mkdir -p "${DIST_DIR}"
    cp "${release_dir}/rosbe.exe" "${DIST_DIR}/rosbe.exe"
    (cd "${DIST_DIR}" && rm -f "${asset}" && zip -q "${asset}" rosbe.exe)
    ok "Created rosbe.exe and ${asset}"
}

# ── Linux package ─────────────────────────────────────────────────────────────
# Layout (each component at its own top-level folder):
#   <root>/
#     cmake-${CMAKE_VERSION}/bin/cmake ...
#     ninja-${NINJA_VERSION}/ninja
#     llvm-mingw/bin/clang ...
#     mingw-gcc/{i686,x86_64,aarch64}-w64-mingw32/...
package_linux() {
    local pkg="rosbe-${VERSION}-linux-x64"
    local staging="${DIST_DIR}/staging/${pkg}"
    info "Building ${pkg}..."

    rm -rf "${staging}"
    mkdir -p "${staging}/mingw-gcc"

    cp "${ROOT_DIR}/LICENSE" "${ROOT_DIR}/README.md" "${staging}/"

    # CMake (Linux) -> cmake-<version>/
    download "${CMAKE_LINUX_URL}" "${CACHE_DIR}/cmake-linux.tar.gz"
    mkdir -p "${staging}/cmake-${CMAKE_VERSION}"
    tar -xf "${CACHE_DIR}/cmake-linux.tar.gz" -C "${staging}/cmake-${CMAKE_VERSION}" --strip-components=1

    # Ninja (Linux) -> ninja-<version>/ninja
    download "${NINJA_LINUX_URL}" "${CACHE_DIR}/ninja-linux.zip"
    mkdir -p "${staging}/ninja-${NINJA_VERSION}"
    unzip -qo "${CACHE_DIR}/ninja-linux.zip" -d "${staging}/ninja-${NINJA_VERSION}"
    chmod +x "${staging}/ninja-${NINJA_VERSION}/ninja"

    # LLVM-MinGW (Linux) -> llvm-mingw/
    download "${LLVM_LINUX_URL}" "${CACHE_DIR}/llvm-linux.tar.xz"
    mkdir -p "${staging}/llvm-mingw"
    tar -xf "${CACHE_DIR}/llvm-linux.tar.xz" -C "${staging}/llvm-mingw" --strip-components=1

    # MinGW-GCC (Linux crosstool-NG) -> mingw-gcc/<triple>/
    for entry in "i686-w64-mingw32:tar.gz:${GCC_LINUX_I686_URL}" \
                 "x86_64-w64-mingw32:tar.gz:${GCC_LINUX_X64_URL}" \
                 "aarch64-w64-mingw32:tar.xz:${GCC_LINUX_AARCH64_URL}"; do
        local triple="${entry%%:*}"; local rest="${entry#*:}"
        local ext="${rest%%:*}"; local url="${rest#*:}"
        download "${url}" "${CACHE_DIR}/${triple}.${ext}"
        tar -xf "${CACHE_DIR}/${triple}.${ext}" -C "${staging}/mingw-gcc"
    done

    tar -cJf "${DIST_DIR}/${pkg}.tar.xz" -C "${DIST_DIR}/staging" "${pkg}"
    ok "Created ${pkg}.tar.xz"
}

# ── Windows package ──────────────────────────────────────────────────────────
# Layout (each component at its own top-level folder, no wrapper scripts):
#   <root>/
#     cmake-${CMAKE_VERSION}/bin/cmake.exe ...
#     ninja-${NINJA_VERSION}/ninja.exe
#     win_flex_bison-${WINFLEXBISON_VERSION}/win_flex.exe, win_bison.exe ...
#     llvm-mingw/bin/clang.exe ...
#     mingw-gcc/{x86_64,i686}-w64-mingw32/bin/<triple>-gcc.exe ...
#     qemu-${QEMU_VERSION}/qemu-system-x86_64.exe ...
package_windows_x64() {
    local pkg="rosbe-${VERSION}-win-x64"
    local staging="${DIST_DIR}/staging/${pkg}"
    info "Building ${pkg}..."

    rm -rf "${staging}"
    mkdir -p "${staging}/mingw-gcc"

    cp "${ROOT_DIR}/LICENSE" "${ROOT_DIR}/README.md" "${staging}/"

    # CMake (Windows) -> cmake-<version>/
    download "${CMAKE_WIN_URL}" "${CACHE_DIR}/cmake-win.zip"
    info "Extracting cmake-win.zip..."
    reset_tmp_dir "${CACHE_DIR}/cmake-tmp"
    unzip -qo "${CACHE_DIR}/cmake-win.zip" -d "${CACHE_DIR}/cmake-tmp"
    move_extracted_dir "${CACHE_DIR}/cmake-tmp" "cmake-*" "${staging}/cmake-${CMAKE_VERSION}"

    # Ninja (Windows) -> ninja-<version>/ninja.exe
    download "${NINJA_WIN_URL}" "${CACHE_DIR}/ninja-win.zip"
    info "Extracting ninja-win.zip..."
    mkdir -p "${staging}/ninja-${NINJA_VERSION}"
    unzip -qo "${CACHE_DIR}/ninja-win.zip" -d "${staging}/ninja-${NINJA_VERSION}"

    # win_flex_bison -> win_flex_bison-<version>/
    download "${WINFLEXBISON_URL}" "${CACHE_DIR}/winflexbison.zip"
    info "Extracting winflexbison.zip..."
    local wfb="${staging}/win_flex_bison-${WINFLEXBISON_VERSION}"
    mkdir -p "${wfb}"
    unzip -qo "${CACHE_DIR}/winflexbison.zip" -d "${wfb}"
    cp "${wfb}/win_flex.exe"  "${wfb}/flex.exe"
    cp "${wfb}/win_bison.exe" "${wfb}/bison.exe"

    # LLVM-MinGW (Windows) -> llvm-mingw/
    download "${LLVM_WIN_X64_URL}" "${CACHE_DIR}/llvm-win-x64.zip"
    info "Extracting llvm-win-x64.zip (~500MB extracted)..."
    reset_tmp_dir "${CACHE_DIR}/llvm-tmp"
    unzip -qo "${CACHE_DIR}/llvm-win-x64.zip" -d "${CACHE_DIR}/llvm-tmp"
    move_extracted_dir "${CACHE_DIR}/llvm-tmp" "llvm-mingw-*" "${staging}/llvm-mingw"

    # MinGW-GCC (Canadian-cross, ahmedarif193/mingw-gcc15.2) -> mingw-gcc/<triple>/
    download "${GCC_WIN_X64_URL}" "${CACHE_DIR}/gcc-win-x64.zip"
    info "Extracting gcc-win-x64.zip..."
    reset_tmp_dir "${CACHE_DIR}/gcc-win-x64-tmp"
    unzip -qo "${CACHE_DIR}/gcc-win-x64.zip" -d "${CACHE_DIR}/gcc-win-x64-tmp"
    move_extracted_dir "${CACHE_DIR}/gcc-win-x64-tmp" "x86_64-w64-mingw32-winhost" "${staging}/mingw-gcc/x86_64-w64-mingw32"

    download "${GCC_WIN_I686_URL}" "${CACHE_DIR}/gcc-win-i686.zip"
    info "Extracting gcc-win-i686.zip..."
    reset_tmp_dir "${CACHE_DIR}/gcc-win-i686-tmp"
    unzip -qo "${CACHE_DIR}/gcc-win-i686.zip" -d "${CACHE_DIR}/gcc-win-i686-tmp"
    move_extracted_dir "${CACHE_DIR}/gcc-win-i686-tmp" "i686-w64-mingw32-winhost" "${staging}/mingw-gcc/i686-w64-mingw32"

    info "Trimming bundle..."
    trim_bundle "${staging}/mingw-gcc/x86_64-w64-mingw32"
    trim_bundle "${staging}/mingw-gcc/i686-w64-mingw32"

    # QEMU (Windows) -> qemu-<version>/
    download "${QEMU_WIN_URL}" "${CACHE_DIR}/${QEMU_WIN_NAME}"
    download "${QEMU_WIN_SHA512_URL}" "${CACHE_DIR}/${QEMU_WIN_SHA512_NAME}"
    verify_sha512 "${CACHE_DIR}" "${CACHE_DIR}/${QEMU_WIN_SHA512_NAME}"
    info "Extracting ${QEMU_WIN_NAME}..."
    local qemu_dir="${staging}/qemu-${QEMU_VERSION}"
    mkdir -p "${qemu_dir}"
    7z x -y "${CACHE_DIR}/${QEMU_WIN_NAME}" "-o${qemu_dir}" >/dev/null
    rm -rf "${qemu_dir}/\$PLUGINSDIR"
    rm -f "${qemu_dir}/uninst.exe" "${qemu_dir}/uninstall.exe"

    write_windows_component_manifest "${staging}"

    info "Zipping ${pkg}..."
    # Zip from INSIDE the staging dir so files are at the zip root (winget
    # extracts directly under the package's sandboxed dir).
    (cd "${DIST_DIR}/staging/${pkg}" && zip -qr "${DIST_DIR}/${pkg}.zip" .)
    local zsize; zsize=$(du -h "${DIST_DIR}/${pkg}.zip" | cut -f1)
    ok "Created ${pkg}.zip (${zsize})"
}

# Strip files ReactOS doesn't use AND known false-positive triggers. LTO and
# the Fortran/D/Go/ObjC front-ends balloon the bundle and regularly trip
# Defender's ML heuristic (Trojan:Win32/Pomal!rfn).
trim_bundle() {
    local root="$1"
    local rm_paths=(
        build.log.bz2                # ct-ng build log, ~5MB of noise
        bin/*gfortran*.exe           # Fortran front-end, unused by ReactOS
        bin/*gdc*.exe                # D front-end, unused
        bin/*gccgo*.exe              # Go front-end, unused
        bin/*nasm*.exe               # NASM assembler/disassembler, ML flag
        bin/cmake-gui.exe            # we ship our own cmake.exe
        bin/doxygen.exe              # docs generator, unused
        bin/ctags.exe bin/etags.exe
        share/doc share/info share/man share/locale share/gettext
        libexec/gcc/*/*/cc1obj.exe libexec/gcc/*/*/cc1objplus.exe
        libexec/gcc/*/*/f951.exe
        libexec/gcc/*/*/cc1gccgo.exe libexec/gcc/*/*/cc1d.exe
        libexec/gcc/*/*/lto1.exe     # LTO not used by ReactOS, often flagged
        */sysroot/lib/libgfortran* */sysroot/lib32/libgfortran*
        */sysroot/lib/libgo* */sysroot/lib32/libgo*
        */sysroot/lib/libgphobos* */sysroot/lib32/libgphobos*
    )
    for p in "${rm_paths[@]}"; do
        rm -rf "${root}"/${p} 2>/dev/null || true
    done
}

# ── Checksums ─────────────────────────────────────────────────────────────────
generate_checksums() {
    info "Generating SHA256 checksums..."
    ( cd "${DIST_DIR}" && shopt -s nullglob && \
      files=( *.tar.xz *.zip *.exe ) && \
      [[ ${#files[@]} -gt 0 ]] && sha256sum "${files[@]}" > SHA256SUMS.txt )
    echo ""
    cat "${DIST_DIR}/SHA256SUMS.txt"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${GREEN}ReactOS RosBE - Packager v${VERSION}${NC}"
    echo ""

    ensure_tools

    rm -rf "${DIST_DIR}/staging"
    mkdir -p "${DIST_DIR}" "${CACHE_DIR}"

    if [[ "$WINDOWS_ONLY" -eq 0 ]]; then
        package_linux
    else
        info "Skipping linux package (--windows-only)"
    fi
    build_bootstrapper_windows
    package_windows_x64
    generate_checksums

    echo ""
    echo -e "${GREEN}Done! Artifacts in: ${DIST_DIR}/${NC}"
}

main "$@"
