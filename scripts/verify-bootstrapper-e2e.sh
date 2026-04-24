#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-$(date -u +%Y%m%d)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
DIST_DIR="${ROOT_DIR}/dist"
BOOTSTRAPPER="${DIST_DIR}/rosbe.exe"
GOOD_REPO="ci/rosbe"
BAD_REPO="ci-bad/rosbe"
ZERO_HASH="0000000000000000000000000000000000000000000000000000000000000000"

for file in \
    "${BOOTSTRAPPER}" \
    "${DIST_DIR}/rosbe-${VERSION}-win-x64.zip" \
    "${DIST_DIR}/SHA256SUMS.txt"
do
    [[ -f "${file}" ]] || {
        echo "missing required artifact: ${file}" >&2
        exit 1
    }
done

WINE_BIN="${WINE_BIN:-$(command -v wine || command -v wine64 || true)}"
WINEBOOT_BIN="${WINEBOOT_BIN:-$(command -v wineboot || true)}"

[[ -n "${WINE_BIN}" ]] || {
    echo "wine or wine64 is required for bootstrapper e2e verification" >&2
    exit 1
}
[[ -n "${WINEBOOT_BIN}" ]] || {
    echo "wineboot is required for bootstrapper e2e verification" >&2
    exit 1
}
command -v python3 >/dev/null || {
    echo "python3 is required for bootstrapper e2e verification" >&2
    exit 1
}
command -v curl >/dev/null || {
    echo "curl is required for bootstrapper e2e verification" >&2
    exit 1
}

PORT="$(
    python3 - <<'PY'
import socket
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
)"
BASE_URL="http://127.0.0.1:${PORT}"
WEB_ROOT="$(mktemp -d)"
GOOD_PREFIX="$(mktemp -d)"
BAD_PREFIX="$(mktemp -d)"
SERVER_LOG="$(mktemp)"

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill "${SERVER_PID}" >/dev/null 2>&1 || true
        wait "${SERVER_PID}" >/dev/null 2>&1 || true
    fi
    rm -rf "${WEB_ROOT}" "${GOOD_PREFIX}" "${BAD_PREFIX}"
    rm -f "${SERVER_LOG}"
}
trap cleanup EXIT

make_release_json() {
    local checksum_url="$1"
    local release_json="$2"

    mkdir -p "$(dirname "${release_json}")"
    cat > "${release_json}" <<EOF
{
  "tag_name": "v${VERSION}",
  "html_url": "${BASE_URL}/releases/v${VERSION}",
  "assets": [
    {
      "name": "rosbe-${VERSION}-win-x64.zip",
      "browser_download_url": "${BASE_URL}/downloads/rosbe-${VERSION}-win-x64.zip"
    },
    {
      "name": "SHA256SUMS.txt",
      "browser_download_url": "${checksum_url}"
    }
  ]
}
EOF
}

mkdir -p \
    "${WEB_ROOT}/downloads" \
    "${WEB_ROOT}/downloads-bad" \
    "${WEB_ROOT}/api/repos/${GOOD_REPO}/releases/tags" \
    "${WEB_ROOT}/api/repos/${BAD_REPO}/releases/tags"

cp "${DIST_DIR}/rosbe-${VERSION}-win-x64.zip" "${WEB_ROOT}/downloads/"
cp "${DIST_DIR}/SHA256SUMS.txt" "${WEB_ROOT}/downloads/"
awk -v asset="rosbe-${VERSION}-win-x64.zip" -v bad="${ZERO_HASH}" '
    {
        if ($2 == asset) {
            $1 = bad
        }
        printf "%s  %s\n", $1, $2
    }
' "${DIST_DIR}/SHA256SUMS.txt" > "${WEB_ROOT}/downloads-bad/SHA256SUMS.txt"

make_release_json \
    "${BASE_URL}/downloads/SHA256SUMS.txt" \
    "${WEB_ROOT}/api/repos/${GOOD_REPO}/releases/latest"
make_release_json \
    "${BASE_URL}/downloads/SHA256SUMS.txt" \
    "${WEB_ROOT}/api/repos/${GOOD_REPO}/releases/tags/v${VERSION}"
make_release_json \
    "${BASE_URL}/downloads-bad/SHA256SUMS.txt" \
    "${WEB_ROOT}/api/repos/${BAD_REPO}/releases/latest"
make_release_json \
    "${BASE_URL}/downloads-bad/SHA256SUMS.txt" \
    "${WEB_ROOT}/api/repos/${BAD_REPO}/releases/tags/v${VERSION}"

python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${WEB_ROOT}" >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!
for _ in {1..20}; do
    if curl -fsS "${BASE_URL}/api/repos/${GOOD_REPO}/releases/latest" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done
curl -fsS "${BASE_URL}/api/repos/${GOOD_REPO}/releases/latest" >/dev/null

run_rosbe() {
    local prefix="$1"
    shift
    WINEPREFIX="${prefix}" \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    ROSBE_DISABLE_ATTESTATION=1 \
    ROSBE_RELEASE_REPO="${GOOD_REPO}" \
    ROSBE_RELEASE_API_BASE="${BASE_URL}/api/repos" \
    "${WINE_BIN}" "${BOOTSTRAPPER}" "$@"
}

run_bad_rosbe() {
    local prefix="$1"
    shift
    WINEPREFIX="${prefix}" \
    WINEARCH=win64 \
    WINEDEBUG=-all \
    ROSBE_DISABLE_ATTESTATION=1 \
    ROSBE_RELEASE_REPO="${BAD_REPO}" \
    ROSBE_RELEASE_API_BASE="${BASE_URL}/api/repos" \
    "${WINE_BIN}" "${BOOTSTRAPPER}" "$@"
}

WINEPREFIX="${GOOD_PREFIX}" WINEARCH=win64 WINEDEBUG=-all "${WINEBOOT_BIN}" -u >/dev/null 2>&1
WINEPREFIX="${BAD_PREFIX}" WINEARCH=win64 WINEDEBUG=-all "${WINEBOOT_BIN}" -u >/dev/null 2>&1

run_rosbe "${GOOD_PREFIX}" --no-banner install --version "${VERSION}"

status_output="$(run_rosbe "${GOOD_PREFIX}" --no-banner status)"
echo "${status_output}"
grep -F "Installed    : ${VERSION}" <<<"${status_output}" >/dev/null
grep -F "Layout       : ok" <<<"${status_output}" >/dev/null

enable_output="$(run_rosbe "${GOOD_PREFIX}" --no-banner enable)"
echo "${enable_output}"
grep -F "Exposed      :" <<<"${enable_output}" >/dev/null
grep -F "QEMU 11.0.0" <<<"${enable_output}" >/dev/null
env_output="$(
    WINEPREFIX="${GOOD_PREFIX}" WINEARCH=win64 WINEDEBUG=-all \
    "${WINE_BIN}" reg query 'HKCU\Environment'
)"
echo "${env_output}"
grep -F "ROSBE_ROOT" <<<"${env_output}" >/dev/null
grep -F "mingw-gcc\\x86_64-w64-mingw32\\bin" <<<"${env_output}" >/dev/null
grep -F "qemu-11.0.0" <<<"${env_output}" >/dev/null

run_rosbe "${GOOD_PREFIX}" --no-banner disable
disabled_status="$(run_rosbe "${GOOD_PREFIX}" --no-banner status)"
echo "${disabled_status}"
grep -F "PATH Enabled : no" <<<"${disabled_status}" >/dev/null

post_disable_env="$(
    WINEPREFIX="${GOOD_PREFIX}" WINEARCH=win64 WINEDEBUG=-all \
    "${WINE_BIN}" reg query 'HKCU\Environment'
)"
echo "${post_disable_env}"
if grep -Fq "ROSBE_ROOT" <<<"${post_disable_env}"; then
    echo "disable left ROSBE_ROOT behind" >&2
    exit 1
fi

run_rosbe "${GOOD_PREFIX}" --no-banner remove
removed_status="$(run_rosbe "${GOOD_PREFIX}" --no-banner status)"
echo "${removed_status}"
grep -F "Installed    : not installed" <<<"${removed_status}" >/dev/null

set +e
bad_output="$(
    run_bad_rosbe "${BAD_PREFIX}" --no-banner install --version "${VERSION}" 2>&1
)"
bad_rc=$?
set -e
echo "${bad_output}"
if [[ ${bad_rc} -eq 0 ]]; then
    echo "expected checksum verification failure" >&2
    exit 1
fi
grep -F "SHA256 mismatch" <<<"${bad_output}" >/dev/null

echo "bootstrapper end-to-end verification passed"
