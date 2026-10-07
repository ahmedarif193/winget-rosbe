#!/bin/bash
# Smoke-tests an LLVM-MinGW RISC-V toolchain tree: compiles and links a
# RISC-V PE image and builds an import library, the way the ReactOS RISC-V
# toolchain file drives the tools.
#
#   scripts/smoke-llvm-mingw-riscv.sh <toolchain-dir>
#   scripts/smoke-llvm-mingw-riscv.sh --launcher=wine <toolchain-dir>
#
# build-llvm-mingw-riscv.sh runs it on the staged tree before packing. A
# Windows-hosted tree is tested either on Windows (Git Bash) or, with
# --launcher=wine, on the Linux host that cross-built it.

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
grep -F "${LLVM_RISCV_COMMIT}" version.txt >/dev/null \
    || error "clang does not report revision ${LLVM_RISCV_COMMIT}"

printf 'int Value = 7;\nint EfiEntry(void) { return Value; }\n' > smoke.c
tool clang --target=riscv64-w64-windows-gnu \
    -march=rv64gc -mabi=lp64 -mcmodel=medany -mno-relax \
    -nostdlib -fuse-ld=lld -Wl,-entry,EfiEntry -Wl,--subsystem,efi_application \
    smoke.c -o smoke.efi
tool llvm-readobj --file-headers smoke.efi > headers.txt
grep -F 'IMAGE_FILE_MACHINE_RISCV64' headers.txt >/dev/null \
    || error "Linked image is not a RISC-V 64-bit PE"

printf 'EXPORTS\nSmoke\n' > smoke.def
tool llvm-dlltool -m riscv64 -d smoke.def -D smoke.dll -l libsmoke.a
tool llvm-nm libsmoke.a >/dev/null

ok "RISC-V 64-bit PE compile, link and import-library checks passed"
