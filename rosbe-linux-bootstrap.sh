#!/bin/sh
# ReactOS RosBE - Linux bootstrap installer
#
# Intended use:
#   wget -qO- https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-linux-bootstrap.sh | sh
#
# Installs a fresh toolchain tree under:
#   ~/.local/opt/rosbe
#
# The installer always removes the old tree first and downloads fresh archives.

set -eu

LLVM_VERSION=20251202
LLVM_TRIPLET=ucrt
GCC_VERSION=15.2.0
GCC_TAG=v15.2

INSTALL_ROOT="${HOME}/.local/opt/rosbe"
BIN_DIR="${HOME}/.local/bin"
TMP_DIR=""

LLVM_BASE_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_VERSION}"
GCC_BASE_URL="https://github.com/ahmedarif193/mingw-gcc15.2/releases/download/${GCC_TAG}"

RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
CYAN="$(printf '\033[0;36m')"
NC="$(printf '\033[0m')"

info() { printf '%s[INFO]%s %s\n' "${CYAN}" "${NC}" "$*"; }
ok()   { printf '%s[  OK]%s %s\n' "${GREEN}" "${NC}" "$*"; }
fail() { printf '%s[FAIL]%s %s\n' "${RED}" "${NC}" "$*" >&2; exit 1; }

cleanup() {
    if [ -n "${TMP_DIR}" ]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

banner() {
    printf '%s\n' "${GREEN}ReactOS RosBE - Linux Bootstrap${NC}"
    printf '%s\n\n' "${GREEN}================================${NC}"
    printf 'Install root: %s\n' "${INSTALL_ROOT}"
    printf 'Toolchains:   LLVM-MinGW %s, MinGW-GCC %s\n\n' "${LLVM_VERSION}" "${GCC_VERSION}"
}

detect_host() {
    os="$(uname -s)"
    arch="$(uname -m)"

    if [ "${os}" != "Linux" ]; then
        fail "This installer is for Linux. Detected: ${os}"
    fi

    case "${arch}" in
        x86_64)  HOST_PLATFORM="ubuntu-22.04-x86_64" ;;
        aarch64) HOST_PLATFORM="ubuntu-22.04-aarch64" ;;
        *)       fail "Unsupported Linux architecture: ${arch}" ;;
    esac

    info "Host: ${os} ${arch} (${HOST_PLATFORM})"
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
            --max-time 300 \
            --speed-limit 10240 --speed-time 60 \
            --retry 3 --retry-delay 5 \
            -o "${dest}" "${url}" || fail "Download failed: ${url}"
    else
        wget -O "${dest}" "${url}" || fail "Download failed: ${url}"
    fi

    ok "Downloaded ${name}"
}

install_llvm_mingw() {
    filename="llvm-mingw-${LLVM_VERSION}-${LLVM_TRIPLET}-${HOST_PLATFORM}.tar.xz"
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
    install_mingw_gcc_arch "i686-w64-mingw32" "tar.gz" "i686-w64-mingw32" "i686-w64-mingw32-gcc"
    install_mingw_gcc_arch "x86_64-w64-mingw32" "tar.gz" "x86_64-w64-mingw32" "x86_64-w64-mingw32-gcc"
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
    printf '  export PATH="%s:$PATH"\n\n' "${BIN_DIR}"
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
    write_env_file
    write_shell_entrypoint
    print_summary
}

main "$@"
