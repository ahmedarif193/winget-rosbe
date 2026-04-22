#!/usr/bin/env bash
# Prepare a winget-pkgs PR for ReactOS.RosBE <version> WITHOUT actually
# creating the PR. Clones the fork, syncs with upstream, drops the manifests
# in, commits, pushes the branch, and prints the GitHub URL where you can
# click "Compare & pull request" to open the PR yourself in the browser.
#
# Uses your SSH key for the fork push (no PAT involved).
#
# Usage: ./scripts/manual-submit.sh [version]
#   defaults to 1.0.0 if no version given.

set -euo pipefail

VERSION="${1:-1.0.0}"

PKG_ID="ReactOS.RosBE"
LETTER="r"
FORK_USER="ahmedarif193"
UPSTREAM="microsoft/winget-pkgs"
FORK_SSH="git@github.com:${FORK_USER}/winget-pkgs.git"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/winget/manifests/${LETTER}/ReactOS/RosBE/${VERSION}"
BRANCH="${PKG_ID}-${VERSION}"

# Sanity
[[ -d "$SRC_DIR" ]] || { echo "ERROR: no manifests at $SRC_DIR"; exit 1; }
for f in "${PKG_ID}.yaml" "${PKG_ID}.installer.yaml" "${PKG_ID}.locale.en-US.yaml"; do
    [[ -f "$SRC_DIR/$f" ]] || { echo "ERROR: missing $f in $SRC_DIR"; exit 1; }
done

TMP="$(mktemp -d)"
cleanup() { echo; echo "(temp checkout left at: $TMP)"; }
trap cleanup EXIT

echo "Cloning ${FORK_USER}/winget-pkgs (shallow)..."
git clone --quiet --depth=50 "$FORK_SSH" "$TMP/winget-pkgs"
cd "$TMP/winget-pkgs"

echo "Fetching upstream master from ${UPSTREAM}..."
git remote add upstream "https://github.com/${UPSTREAM}.git"
git fetch --quiet --depth=1 upstream master

echo "Creating branch ${BRANCH} from upstream/master..."
git checkout -B "$BRANCH" upstream/master

DEST="manifests/${LETTER}/ReactOS/RosBE/${VERSION}"
echo "Copying manifests into ${DEST}/..."
mkdir -p "$DEST"
cp "$SRC_DIR"/*.yaml "$DEST/"

echo
echo "=== Files to commit ==="
git status --short
echo

git add "$DEST"
git commit -q -m "New version: ${PKG_ID} version ${VERSION}"

echo "Pushing ${BRANCH} to ${FORK_USER}/winget-pkgs (uses your SSH key)..."
git push --quiet -u origin "$BRANCH"

# Pre-fill the PR title and body so the user just clicks Submit on GitHub.
INSTALLER_YAML="$SRC_DIR/${PKG_ID}.installer.yaml"
SHA256="$(awk '/InstallerSha256:/ {print $2}' "$INSTALLER_YAML")"

PR_TITLE="New version: ${PKG_ID} version ${VERSION}"
PR_BODY="### Update from [RosBE Modern](https://github.com/ahmedarif193/winget-rosbe) :rocket:

- **Package**: \`${PKG_ID}\`
- **Version**: \`${VERSION}\`
- **Release**: https://github.com/ahmedarif193/winget-rosbe/releases/tag/v${VERSION}
- **Installer SHA256 (x64)**: \`${SHA256}\`

- [x] Signed the Microsoft CLA
- [x] Only modifies one manifest
"

# URL-encode title and body for the prefill query string.
url_encode() {
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))'
}
ENC_TITLE="$(printf '%s' "$PR_TITLE" | url_encode)"
ENC_BODY="$(printf '%s'  "$PR_BODY"  | url_encode)"

PR_URL="https://github.com/${UPSTREAM}/compare/master...${FORK_USER}:winget-pkgs:${BRANCH}?expand=1&title=${ENC_TITLE}&body=${ENC_BODY}"

echo
echo "============================================================"
echo "Branch pushed. Open this URL to file the PR (web UI prefilled):"
echo
echo "  $PR_URL"
echo
echo "============================================================"
