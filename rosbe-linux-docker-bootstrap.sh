#!/bin/sh
# ReactOS RosBE - Linux Docker bootstrap installer.
# Use: wget -qO- https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-linux-docker-bootstrap.sh | sh

set -eu

IMAGE_DEFAULT="ghcr.io/ahmedarif193/rosbe-builder:latest"
IMAGE="${ROSBE_DOCKER_IMAGE:-$IMAGE_DEFAULT}"
INSTALL_DIR="${HOME}/.local/share/rosbe-docker"
MARKER_BEGIN="# >>> rosbe-docker (managed) >>>"
MARKER_END="# <<< rosbe-docker (managed) <<<"

DOCKERFILE_URL="https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/docker/Dockerfile"
ENTRYPOINT_URL="https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/docker/entrypoint.sh"
DOCKERIGNORE_URL="https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/docker/.dockerignore"
BOOTSTRAP_URL="https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-unix-bootstrap.sh"

RED="$(printf '\033[0;31m')"
GREEN="$(printf '\033[0;32m')"
YELLOW="$(printf '\033[0;33m')"
CYAN="$(printf '\033[0;36m')"
NC="$(printf '\033[0m')"

info() { printf '%s[INFO]%s %s\n' "${CYAN}" "${NC}" "$*"; }
ok()   { printf '%s[  OK]%s %s\n' "${GREEN}" "${NC}" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "${YELLOW}" "${NC}" "$*" >&2; }
fail() { printf '%s[FAIL]%s %s\n' "${RED}" "${NC}" "$*" >&2; exit 1; }

banner() {
    printf '%s\n' "${GREEN}ReactOS RosBE - Linux Docker Bootstrap${NC}"
    printf '%s\n\n' "${GREEN}=======================================${NC}"
    printf 'Image:        %s\n' "${IMAGE}"
    printf 'Install dir:  %s\n\n' "${INSTALL_DIR}"
}

pick_engine() {
    if [ -n "${ROSBE_DOCKER_ENGINE:-}" ]; then
        printf '%s\n' "${ROSBE_DOCKER_ENGINE}"; return
    fi
    if command -v podman >/dev/null 2>&1; then echo podman; return; fi
    if command -v docker >/dev/null 2>&1; then echo docker; return; fi
    fail "neither podman nor docker found in PATH"
}

ensure_image() {
    if "${ENGINE}" image inspect "${IMAGE}" >/dev/null 2>&1; then
        ok "Image already present locally: ${IMAGE}"
        return
    fi
    info "Installing image from ${IMAGE} via ${ENGINE}..."
    if "${ENGINE}" pull "${IMAGE}"; then
        ok "Image installed"
        return
    fi
    warn "Pull failed; you may need to log in to the registry or build locally."
    warn "Continuing install; you can build later with: ${ENGINE} build -t ${IMAGE} <path-to-Dockerfile>"
}

create_install_dir() {
    mkdir -p "${INSTALL_DIR}/shims" "${INSTALL_DIR}/docker"
    ok "Install dir ready: ${INSTALL_DIR}"
}

download_to() {
    url="$1"; dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest" || fail "Failed to download ${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url" || fail "Failed to download ${url}"
    else
        fail "Neither curl nor wget is available"
    fi
}

install_docker_files() {
    docker_dir="${INSTALL_DIR}/docker"
    self_dir=""
    if [ -n "${0:-}" ] && [ -f "$0" ]; then
        self_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || self_dir=""
    fi

    if [ -n "${self_dir}" ] && [ -f "${self_dir}/docker/Dockerfile" ] && [ -f "${self_dir}/rosbe-unix-bootstrap.sh" ]; then
        info "Copying docker/ + bootstrap from local checkout: ${self_dir}"
        cp "${self_dir}/docker/Dockerfile"          "${docker_dir}/Dockerfile"
        cp "${self_dir}/docker/entrypoint.sh"       "${docker_dir}/entrypoint.sh"
        cp "${self_dir}/rosbe-unix-bootstrap.sh"    "${INSTALL_DIR}/rosbe-unix-bootstrap.sh"
        [ -f "${self_dir}/docker/.dockerignore" ] && \
            cp "${self_dir}/docker/.dockerignore"   "${docker_dir}/.dockerignore"
    else
        info "Fetching docker/ + bootstrap from GitHub..."
        download_to "${DOCKERFILE_URL}"    "${docker_dir}/Dockerfile"
        download_to "${ENTRYPOINT_URL}"    "${docker_dir}/entrypoint.sh"
        download_to "${BOOTSTRAP_URL}"     "${INSTALL_DIR}/rosbe-unix-bootstrap.sh"
        download_to "${DOCKERIGNORE_URL}"  "${docker_dir}/.dockerignore" || true
    fi
    chmod +x "${docker_dir}/entrypoint.sh"
    chmod +x "${INSTALL_DIR}/rosbe-unix-bootstrap.sh"
    ok "Docker assets cached at ${INSTALL_DIR} (used as local-build fallback)"
}

write_rosbe_init() {
    cat > "${INSTALL_DIR}/rosbe-init.sh" <<EOF
# shellcheck shell=bash
# rosbe-docker shell init. Sourced from ~/.bashrc / ~/.zshrc.
# Defines the \`rosbe\` command. Edits to this file persist across shells.

ROSBE_DOCKER_HOME="${INSTALL_DIR}"
ROSBE_DOCKER_IMAGE="\${ROSBE_DOCKER_IMAGE:-${IMAGE}}"
export ROSBE_DOCKER_HOME ROSBE_DOCKER_IMAGE

rosbe() {
    case "\${1:-}" in
        enable)
            . "\$ROSBE_DOCKER_HOME/rosbe-enable.sh"
            ;;
        disable)
            if command -v rosbe_disable >/dev/null 2>&1; then
                rosbe_disable
            else
                echo "rosbe: not active" >&2
                return 1
            fi
            ;;
        update)
            "\$ROSBE_DOCKER_HOME/rosbe-docker.sh" update
            ;;
        status)
            if [ -n "\${ROSBE_DOCKER_ACTIVE:-}" ]; then
                echo "rosbe: enabled (image=\$ROSBE_DOCKER_IMAGE)"
            else
                echo "rosbe: disabled"
            fi
            ;;
        ""|-h|--help|help)
            cat <<USAGE
Usage: rosbe {enable|disable|update|status}

  enable    Activate containerized RosBE in this shell.
            Prepends shims so ninja/cmake/ctest run inside the rosbe-builder
            container. Bind-mounts \\\$HOME so your repos are visible.

  disable   Restore PATH and unset rosbe environment.

  update    Pull the latest \$ROSBE_DOCKER_IMAGE image.

  status    Show whether rosbe is currently enabled.
USAGE
            ;;
        *)
            echo "rosbe: unknown subcommand: \$1" >&2
            echo "Try: rosbe help" >&2
            return 2
            ;;
    esac
}
EOF
    ok "Wrote rosbe-init.sh (defines the \`rosbe\` command)"
}

write_rosbe_enable() {
    cat > "${INSTALL_DIR}/rosbe-enable.sh" <<'ENABLE_EOF'
# shellcheck shell=bash
# Activation script: sourced via `rosbe enable`. Prepends PATH shims so
# ninja/cmake transparently route into the rosbe-builder container.

if [ -n "${ROSBE_DOCKER_ACTIVE:-}" ]; then
    echo "rosbe: already enabled (image=${ROSBE_DOCKER_IMAGE:-default})" >&2
    return 0 2>/dev/null || exit 0
fi

if [ -z "${ROSBE_DOCKER_HOME:-}" ]; then
    echo "rosbe: ROSBE_DOCKER_HOME not set; was rosbe-init.sh sourced?" >&2
    return 1 2>/dev/null || exit 1
fi

if ! "$ROSBE_DOCKER_HOME/rosbe-docker.sh" ensure-image; then
    echo "rosbe-enable: failed to ensure image; aborting" >&2
    return 1 2>/dev/null || exit 1
fi

# Stash original PATH so rosbe_disable can restore it.
export _ROSBE_OLD_PATH="$PATH"

export PATH="$ROSBE_DOCKER_HOME/shims:$PATH"
export ROSBE_DOCKER_ACTIVE=1

# Container-side RosBE paths. configure.sh checks ROSBE_DOCKER_ACTIVE and
# uses /opt/rosbe/* + skips host -x validation when set.
export ROSBE_ROOT=/opt/rosbe
export REACTOS_CLANG_LLVM_MINGW_ROOT=/opt/rosbe/llvm-mingw
export LLVM_MINGW_ROOT=/opt/rosbe/llvm-mingw

rosbe_disable() {
    if [ -n "${_ROSBE_OLD_PATH:-}" ]; then
        export PATH="$_ROSBE_OLD_PATH"
    fi
    unset _ROSBE_OLD_PATH
    unset ROSBE_DOCKER_ACTIVE ROSBE_ROOT
    unset REACTOS_CLANG_LLVM_MINGW_ROOT LLVM_MINGW_ROOT
    unset -f rosbe_disable 2>/dev/null || true
    echo "rosbe: disabled"
}

"$ROSBE_DOCKER_HOME/rosbe-docker.sh" info | sed 's/^/rosbe: /'
echo "rosbe: enabled. Run 'rosbe disable' to deactivate."
ENABLE_EOF
    ok "Wrote rosbe-enable.sh (activation logic)"
}

write_rosbe_docker_helper() {
    cat > "${INSTALL_DIR}/rosbe-docker.sh" <<'HELPER_EOF'
#!/bin/sh
# rosbe-docker: host-side helper used by the activation script and the
# PATH shims. Runs commands inside the rosbe-builder container with the
# user's $HOME bind-mounted at the same absolute path inside the container.
#
# Subcommands:
#   ensure-image   pull or report missing image
#   run <cmd...>   exec cmd inside the container, $HOME bind-mounted
#   update         pull the latest tag of $ROSBE_DOCKER_IMAGE
#   info           print engine, image, mount, UID
set -eu

IMAGE="${ROSBE_DOCKER_IMAGE:-ghcr.io/ahmedarif193/rosbe-builder:latest}"
MOUNT_ROOT="${ROSBE_DOCKER_MOUNT:-$HOME}"

pick_engine() {
    if [ -n "${ROSBE_DOCKER_ENGINE:-}" ]; then
        printf '%s\n' "$ROSBE_DOCKER_ENGINE"; return
    fi
    if command -v podman >/dev/null 2>&1; then echo podman; return; fi
    if command -v docker >/dev/null 2>&1; then echo docker; return; fi
    echo "rosbe-docker: neither podman nor docker found" >&2
    exit 1
}

ENGINE="$(pick_engine)"

user_flags() {
    if [ "$ENGINE" = "podman" ]; then
        # Rootless podman: map host UID to same UID inside the container.
        echo "--userns=keep-id"
    else
        # Docker (rootful or rootless): pass UID:GID explicitly.
        echo "--user $(id -u):$(id -g)"
    fi
}

ensure_image() {
    if "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then return 0; fi
    if "$ENGINE" pull "$IMAGE" 2>/dev/null; then return 0; fi
    # Fallback: build from the Dockerfile + bootstrap cached at install time.
    if [ -n "${ROSBE_DOCKER_HOME:-}" ] && \
       [ -f "$ROSBE_DOCKER_HOME/docker/Dockerfile" ] && \
       [ -f "$ROSBE_DOCKER_HOME/rosbe-unix-bootstrap.sh" ]; then
        echo "rosbe-docker: pull failed; building locally from $ROSBE_DOCKER_HOME" >&2
        "$ENGINE" build -t "$IMAGE" \
            -f "$ROSBE_DOCKER_HOME/docker/Dockerfile" \
            "$ROSBE_DOCKER_HOME"
        return $?
    fi
    echo "rosbe-docker: image $IMAGE not available, pull failed, no cached Dockerfile" >&2
    echo "rosbe-docker: re-run the bootstrap or fix registry access" >&2
    return 1
}

update_image() {
    echo "rosbe-docker: pulling latest $IMAGE via $ENGINE"
    "$ENGINE" pull "$IMAGE"
}

run_in_container() {
    ensure_image
    # shellcheck disable=SC2046
    exec "$ENGINE" run --rm \
        $(user_flags) \
        -v "$MOUNT_ROOT:$MOUNT_ROOT" \
        -w "$PWD" \
        -e HOME=/tmp \
        -e CCACHE_DIR -e CCACHE_BASEDIR -e CCACHE_MAXSIZE -e CCACHE_SLOPPINESS \
        ${ROSBE_DOCKER_TTY:+-it} \
        "$IMAGE" \
        "$@"
}

case "${1:-}" in
    ensure-image) ensure_image ;;
    run)          shift; run_in_container "$@" ;;
    update)       update_image ;;
    info)
        echo "engine:     $ENGINE"
        echo "image:      $IMAGE"
        echo "mount_root: $MOUNT_ROOT"
        echo "pwd:        $PWD"
        echo "user:       $(id -u):$(id -g)"
        echo "user_flags: $(user_flags)"
        ;;
    ""|-h|--help)
        cat <<EOF
Usage: $(basename "$0") {ensure-image|run <cmd...>|update|info}

Env:
  ROSBE_DOCKER_IMAGE    image ref (default: $IMAGE)
  ROSBE_DOCKER_ENGINE   force engine: podman or docker
  ROSBE_DOCKER_MOUNT    bind-mount root (default: \$HOME)
  ROSBE_DOCKER_TTY      allocate a TTY when set
EOF
        ;;
    *)
        echo "rosbe-docker: unknown subcommand: $1" >&2
        exit 2
        ;;
esac
HELPER_EOF
    chmod +x "${INSTALL_DIR}/rosbe-docker.sh"
    ok "Wrote rosbe-docker.sh (engine + container helper)"
}

write_shims() {
    # Do NOT shim `bash` here: snap apps and many `#!/usr/bin/env bash`
    # scripts on the host would resolve to the shim and run inside the
    # container, where /snap/... and other host paths don't exist.
    for tool in ninja cmake ctest; do
        cat > "${INSTALL_DIR}/shims/${tool}" <<'SHIM_EOF'
#!/bin/sh
self="$(cd "$(dirname "$0")/.." && pwd)"
exec "$self/rosbe-docker.sh" run "$(basename "$0")" "$@"
SHIM_EOF
        chmod +x "${INSTALL_DIR}/shims/${tool}"
    done
    ok "Wrote PATH shims: ninja cmake ctest"
}

# Idempotently inject a managed source-line into a shell rc file.
wire_rc_file() {
    rc="$1"
    [ -f "${rc}" ] || { info "Skipping ${rc} (not present)"; return 0; }

    if grep -Fq "${MARKER_BEGIN}" "${rc}" 2>/dev/null; then
        info "${rc} already wired (managed block found); leaving as-is"
        return 0
    fi

    {
        printf '\n%s\n' "${MARKER_BEGIN}"
        printf '[ -f "%s/rosbe-init.sh" ] && . "%s/rosbe-init.sh"\n' "${INSTALL_DIR}" "${INSTALL_DIR}"
        printf '%s\n' "${MARKER_END}"
    } >> "${rc}"
    ok "Wired ${rc}"
}

wire_shells() {
    info "Wiring shell rc files..."
    wired_any=0
    if [ -f "${HOME}/.bashrc" ]; then
        wire_rc_file "${HOME}/.bashrc"
        wired_any=1
    fi
    if [ -f "${HOME}/.zshrc" ]; then
        wire_rc_file "${HOME}/.zshrc"
        wired_any=1
    fi
    if [ "${wired_any}" -eq 0 ]; then
        warn "Neither ~/.bashrc nor ~/.zshrc found; you'll need to manually source"
        warn "  . ${INSTALL_DIR}/rosbe-init.sh"
        warn "in your shell startup file."
    fi
}

print_summary() {
    printf '\n%s rosbe-docker installed.\n\n' "${GREEN}OK${NC}"
    printf 'Available commands:\n'
    printf '  rosbe enable\n'
    printf '  rosbe disable\n'
    printf '  rosbe status\n'
    printf '  rosbe update\n\n'
}

main() {
    if [ "$#" -ne 0 ]; then
        fail "This installer does not accept options. Override via env vars: ROSBE_DOCKER_IMAGE, ROSBE_DOCKER_ENGINE."
    fi

    banner
    ENGINE="$(pick_engine)"
    info "Using engine: ${ENGINE}"
    create_install_dir
    install_docker_files
    ensure_image
    write_rosbe_init
    write_rosbe_enable
    write_rosbe_docker_helper
    write_shims
    wire_shells
    print_summary
}

main "$@"
