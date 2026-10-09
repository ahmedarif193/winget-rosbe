#!/bin/bash
# Smoke-tests a RosBE LLVM toolchain tree: compiles and links a PE image and
# builds an import library for every LiberNT target, the way the LiberNT
# toolchain file drives the tools, and checks the packed runtime sources.
#
#   scripts/smoke-llvm.sh <toolchain-dir>
#   scripts/smoke-llvm.sh --launcher=wine <toolchain-dir>
#
# build-llvm.sh runs it on the staged tree before packing. A Windows-hosted
# tree is tested either on Windows (Git Bash) or, with --launcher=wine, on the
# Linux host that cross-built it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[  OK]${NC} $*"; }
error(){ echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# shellcheck source=versions.env
source "${SCRIPT_DIR}/versions.env"

LAUNCHER=()
TOOLCHAIN_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --launcher=*) read -r -a LAUNCHER <<<"${1#*=}" ;;
        --help|-h)
            echo "usage: $0 [--launcher=CMD] TOOLCHAIN-DIR"
            exit 0
            ;;
        -*) error "Unrecognized option: $1" ;;
        *)
            [[ -z "${TOOLCHAIN_DIR}" ]] || error "Only one toolchain directory is accepted."
            TOOLCHAIN_DIR="$1"
            ;;
    esac
    shift
done

[[ -n "${TOOLCHAIN_DIR}" ]] || error "usage: $0 [--launcher=CMD] TOOLCHAIN-DIR"
[[ -d "${TOOLCHAIN_DIR}/bin" ]] || error "Not a toolchain tree: ${TOOLCHAIN_DIR}"
BIN="$(cd "${TOOLCHAIN_DIR}/bin" && pwd)"

EXE=""
[[ ! -f "${BIN}/clang.exe" ]] || EXE=".exe"
[[ -f "${BIN}/clang${EXE}" ]] || error "No clang in ${BIN}"

tool() {
    local name="$1"; shift
    # The ${a[@]+...} form keeps an empty launcher working on bash 3.2 (macOS).
    ${LAUNCHER[@]+"${LAUNCHER[@]}"} "${BIN}/${name}${EXE}" "$@"
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

info "Smoke-testing ${TOOLCHAIN_DIR}..."

# Every file argument is relative to the scratch directory, so the same
# command lines work for native tools, Wine and Git Bash.
cd "${TMP}"

tool clang --version > version.txt
grep -F "${LLVM_NATIVE_COMMIT}" version.txt >/dev/null \
    || error "clang does not report revision ${LLVM_NATIVE_COMMIT}"

printf 'int Value = 7;\nint EfiEntry(void) { return Value; }\n' > smoke.c
printf 'EXPORTS\nSmoke\n' > smoke.def

# Target triple, extra compiler flags, PE machine name, llvm-dlltool machine.
TARGETS=(
    "i686-w64-windows-gnu||IMAGE_FILE_MACHINE_I386|i386"
    "x86_64-w64-windows-gnu||IMAGE_FILE_MACHINE_AMD64|i386:x86-64"
    "armv7-w64-windows-gnu||IMAGE_FILE_MACHINE_ARMNT|arm"
    "aarch64-w64-windows-gnu||IMAGE_FILE_MACHINE_ARM64|arm64"
    "riscv64-w64-windows-gnu|-march=rv64gc -mabi=lp64 -mcmodel=medany -mno-relax|IMAGE_FILE_MACHINE_RISCV64|riscv64"
)

for entry in "${TARGETS[@]}"; do
    IFS='|' read -r triple flags machine dllmachine <<<"${entry}"
    read -r -a extra <<<"${flags}"
    tool clang --target="${triple}" ${extra[@]+"${extra[@]}"} \
        -nostdlib -fuse-ld=lld -Wl,-entry,EfiEntry -Wl,--subsystem,efi_application \
        smoke.c -o "smoke-${triple}.efi"
    tool llvm-readobj --file-headers "smoke-${triple}.efi" > headers.txt
    grep -F "${machine}" headers.txt >/dev/null \
        || error "${triple}: linked image is not ${machine}"
    tool llvm-dlltool -m "${dllmachine}" -d smoke.def -D smoke.dll -l "libsmoke-${triple}.a"
    tool llvm-nm "libsmoke-${triple}.a" >/dev/null
    ok "${triple}: PE compile, link and import library"
done

tool clang --target=powerpcle-w64-windows-gnu -c smoke.c -o smoke-ppc.obj
tool llvm-readobj --file-headers smoke-ppc.obj > headers.txt
grep -F 'IMAGE_FILE_MACHINE_POWERPC' headers.txt >/dev/null \
    || error "powerpcle: object is not a PowerPC COFF object"
ok "powerpcle-w64-windows-gnu: COFF compile"

SRC="$(dirname "${BIN}")/src/llvm-project"
for f in runtimes/CMakeLists.txt libcxxabi/include/cxxabi.h libunwind/src/Unwind-seh.cpp \
         compiler-rt/lib/builtins/CMakeLists.txt; do
    [[ -f "${SRC}/${f}" ]] || error "Missing runtime source ${f}"
done
ok "Runtime sources present in src/llvm-project"
