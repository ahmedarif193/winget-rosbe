#!/bin/sh
# ReactOS RosBE - Unix bootstrap installer (Linux and macOS)
#
# Intended use:
#   wget -qO- https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-unix-bootstrap.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-unix-bootstrap.sh | sh
#
# Auto-detects the host OS (Linux or macOS) and architecture, then installs a
# fresh toolchain tree under:
#   ~/.local/opt/rosbe
#
# Linux  : LLVM-MinGW (host build for the detected arch) + ct-ng MinGW-GCC
#          for i686 and x86_64 Windows targets.
# macOS  : LLVM-MinGW universal binary (covers both Intel and Apple Silicon).
#          The ct-ng MinGW-GCC bundle has no macOS host build upstream; if you
#          need GCC on macOS, `brew install mingw-w64` is the easiest option
#          (separate version, MSVCRT default).
#
# The installer always removes the old tree first and downloads fresh archives.

set -eu

LLVM_VERSION=20251202
LLVM_TRIPLET=ucrt
GCC_VERSION=15.2.0
GCC_TAG=v15.2

INSTALL_ROOT="${INSTALL_ROOT:-${HOME}/.local/opt/rosbe}"
BIN_DIR="${BIN_DIR:-${HOME}/.local/bin}"
TMP_DIR=""

LLVM_BASE_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_VERSION}"
GCC_BASE_URL="https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/${GCC_TAG}"

RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
CYAN="$(printf '\033[0;36m')"
NC="$(printf '\033[0m')"

info() { printf '%s[INFO]%s %s\n' "${CYAN}" "${NC}" "$*"; }
ok()   { printf '%s[  OK]%s %s\n' "${GREEN}" "${NC}" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "${RED}" "${NC}" "$*" >&2; }
fail() { printf '%s[FAIL]%s %s\n' "${RED}" "${NC}" "$*" >&2; exit 1; }

cleanup() {
    if [ -n "${TMP_DIR}" ]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

banner() {
    printf '%s\n' "${GREEN}ReactOS RosBE - Unix Bootstrap${NC}"
    printf '%s\n\n' "${GREEN}===============================${NC}"
    printf 'Install root: %s\n' "${INSTALL_ROOT}"
    printf 'Toolchains:   LLVM-MinGW %s, MinGW-GCC %s\n\n' "${LLVM_VERSION}" "${GCC_VERSION}"
}

detect_host() {
    os="$(uname -s)"
    arch="$(uname -m)"

    case "${os}" in
        Linux)
            HOST_OS="linux"
            case "${arch}" in
                x86_64)  LLVM_HOST_PLATFORM="ubuntu-22.04-x86_64" ;;
                aarch64) LLVM_HOST_PLATFORM="ubuntu-22.04-aarch64" ;;
                *)       fail "Unsupported Linux architecture: ${arch}" ;;
            esac
            ;;
        Darwin)
            HOST_OS="macos"
            # LLVM-MinGW ships a single universal Mach-O for macOS that runs
            # natively on both Intel (x86_64) and Apple Silicon (arm64). No
            # per-arch detection or Rosetta dance needed.
            case "${arch}" in
                x86_64|arm64|aarch64) LLVM_HOST_PLATFORM="macos-universal" ;;
                *) fail "Unsupported macOS architecture: ${arch}" ;;
            esac
            ;;
        *)
            fail "Unsupported operating system: ${os}. This installer supports Linux and macOS."
            ;;
    esac

    info "Host: ${os} ${arch} (LLVM platform: ${LLVM_HOST_PLATFORM})"
}

require_tools() {
    missing=""

    command -v tar >/dev/null 2>&1 || missing="${missing} tar"
    command -v mktemp >/dev/null 2>&1 || missing="${missing} mktemp"

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing="${missing} curl-or-wget"
    fi

    if [ -n "${missing}" ]; then
        fail "Missing host tools:${missing}"
    fi
}

create_tmp_dir() {
    TMP_DIR="$(mktemp -d)"
}

safe_remove_install_root() {
    case "${INSTALL_ROOT}" in
        ""|"/"|"/home"|"/home/"*"/.."*|"${HOME}") fail "Refusing to remove unsafe install root: ${INSTALL_ROOT}" ;;
    esac

    info "Removing old RosBE tree..."
    if [ -d "${INSTALL_ROOT}" ]; then
        chmod -R u+rwX "${INSTALL_ROOT}" 2>/dev/null || true
        rm -rf "${INSTALL_ROOT}" 2>/dev/null || fail "Could not remove old RosBE tree: ${INSTALL_ROOT}"
    fi
    mkdir -p "${INSTALL_ROOT}" "${BIN_DIR}"
}

download() {
    url="$1"
    dest="$2"
    name="${dest##*/}"

    info "Downloading ${name}..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL \
            --connect-timeout 30 \
            --max-time 600 \
            --speed-limit 10240 --speed-time 60 \
            --retry 3 --retry-delay 5 \
            -o "${dest}" "${url}" || fail "Download failed: ${url}"
    else
        wget -O "${dest}" "${url}" || fail "Download failed: ${url}"
    fi

    ok "Downloaded ${name}"
}

install_llvm_mingw() {
    filename="llvm-mingw-${LLVM_VERSION}-${LLVM_TRIPLET}-${LLVM_HOST_PLATFORM}.tar.xz"
    archive="${TMP_DIR}/${filename}"
    target="${INSTALL_ROOT}/llvm-mingw"

    download "${LLVM_BASE_URL}/${filename}" "${archive}"
    info "Extracting LLVM-MinGW..."
    mkdir -p "${target}"
    tar -xf "${archive}" -C "${target}" --strip-components=1
    chmod -R u+rwX "${target}" 2>/dev/null || true

    if [ ! -x "${target}/bin/clang" ]; then
        fail "LLVM-MinGW extraction did not produce ${target}/bin/clang"
    fi

    ok "LLVM-MinGW -> ${target}"
}

install_mingw_gcc_arch() {
    archive_name="$1"
    ext="$2"
    toolchain_dir="$3"
    gcc_name="$4"
    archive="${TMP_DIR}/${archive_name}.${ext}"
    target="${INSTALL_ROOT}/mingw-gcc"

    download "${GCC_BASE_URL}/${archive_name}.${ext}" "${archive}"
    info "Extracting MinGW-GCC ${toolchain_dir}..."
    mkdir -p "${target}"
    tar -xf "${archive}" -C "${target}"
    chmod -R u+rwX "${target}/${toolchain_dir}" 2>/dev/null || true

    if [ ! -x "${target}/${toolchain_dir}/bin/${gcc_name}" ]; then
        fail "MinGW-GCC extraction did not produce ${target}/${toolchain_dir}/bin/${gcc_name}"
    fi

    ok "MinGW-GCC ${toolchain_dir} -> ${target}/${toolchain_dir}"
}

install_mingw_gcc() {
    if [ "${HOST_OS}" = "macos" ]; then
        info "Skipping MinGW-GCC: no macOS host build available upstream."
        info "Install via Homebrew if needed: brew install mingw-w64 (separate version, MSVCRT default)."
        return 0
    fi
    install_mingw_gcc_arch "i686-w64-mingw32" "tar.gz" "i686-w64-mingw32" "i686-w64-mingw32-gcc"
    install_mingw_gcc_arch "x86_64-w64-mingw32" "tar.gz" "x86_64-w64-mingw32" "x86_64-w64-mingw32-gcc"
}

# Defensive: clear com.apple.quarantine after extraction. curl/wget do not set
# this xattr (so the curl-pipe-to-sh flow never needs it), but tar propagates
# quarantine from inside-archive xattrs and from archives downloaded via
# Safari/Chrome — covers the offline-install case at zero cost. Idempotent.
strip_macos_quarantine() {
    [ "${HOST_OS}" = "macos" ] || return 0
    command -v xattr >/dev/null 2>&1 || return 0
    info "Clearing com.apple.quarantine (defensive)..."
    xattr -dr com.apple.quarantine "${INSTALL_ROOT}" 2>/dev/null || true
}

write_env_file() {
    env_file="${INSTALL_ROOT}/rosbe-env.sh"

    cat > "${env_file}" <<EOF
# ReactOS RosBE environment. Source this file from a shell:
#   . "${env_file}"

export ROSBE_ROOT="${INSTALL_ROOT}"

rosbe_prepend_path() {
    [ -d "\$1" ] || return 0
    case ":\${PATH}:" in
        *":\$1:"*) ;;
        *) PATH="\$1\${PATH:+:\$PATH}" ;;
    esac
}

rosbe_prepend_path "\${ROSBE_ROOT}/llvm-mingw/bin"
rosbe_prepend_path "\${ROSBE_ROOT}/mingw-gcc/i686-w64-mingw32/bin"
rosbe_prepend_path "\${ROSBE_ROOT}/mingw-gcc/x86_64-w64-mingw32/bin"

export PATH
unset -f rosbe_prepend_path 2>/dev/null || unset rosbe_prepend_path
EOF

    chmod +x "${env_file}"
    ok "Environment file -> ${env_file}"
}

write_shell_entrypoint() {
    shell_bin="${BIN_DIR}/rosbe-shell"

    cat > "${shell_bin}" <<EOF
#!/bin/sh
set -eu
. "${INSTALL_ROOT}/rosbe-env.sh"
exec "\${SHELL:-/bin/sh}" "\$@"
EOF

    chmod +x "${shell_bin}"
    ok "Shell entry point -> ${shell_bin}"
}

print_summary() {
    printf '\n%s\n' "${GREEN}ReactOS RosBE installed.${NC}"
    printf '\nUse it with:\n'
    printf '  %s/rosbe-shell\n\n' "${BIN_DIR}"
    printf 'Or source it in the current shell:\n'
    printf '  . "%s/rosbe-env.sh"\n\n' "${INSTALL_ROOT}"
    printf 'If %s is not in PATH, add this to your shell profile:\n' "${BIN_DIR}"
    # $PATH is intentionally literal — the user copy-pastes this into their shell profile.
    # shellcheck disable=SC2016
    printf '  export PATH="%s:$PATH"\n' "${BIN_DIR}"
    if [ "${HOST_OS}" = "macos" ]; then
        printf '\nNote (macOS): only LLVM-MinGW (Clang/lld) is bundled.\n'
        printf 'For GCC: brew install mingw-w64 (MSVCRT default; not version-matched).\n'
    fi
    printf '\n'
}

main() {
    if [ "$#" -ne 0 ]; then
        fail "This installer does not accept options."
    fi

    banner
    detect_host
    require_tools
    create_tmp_dir
    safe_remove_install_root
    install_llvm_mingw
    install_mingw_gcc
    strip_macos_quarantine
    write_env_file
    write_shell_entrypoint
    print_summary
}

main "$@"
