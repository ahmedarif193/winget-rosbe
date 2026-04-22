#!/usr/bin/env bash
# Prepare a winget-pkgs PR for ReactOS.RosBE <version> WITHOUT actually
# creating the PR. Maintains a persistent local checkout of the fork at
# $WINGET_PKGS_DIR (default $HOME/winget-pkgs) - first run clones it, every
# subsequent run reuses it. Drops the manifests on a fresh branch, commits,
# pushes via SSH (no PAT involved), and prints the GitHub URL where you can
# click "Compare & pull request" to file the PR yourself in the browser.
#
# Usage: ./scripts/manual-submit.sh [version]
#   defaults to 1.0.0 if no version given.
#
# Override checkout location:
#   WINGET_PKGS_DIR=/some/other/path ./scripts/manual-submit.sh 1.2.0

set -euo pipefail

VERSION="${1:-1.0.0}"

PKG_ID="ReactOS.RosBE"
LETTER="r"
FORK_USER="ahmedarif193"
UPSTREAM="microsoft/winget-pkgs"
FORK_SSH="git@github.com:${FORK_USER}/winget-pkgs.git"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/winget/manifests/${LETTER}/ReactOS/RosBE/${VERSION}"
WINGET_PKGS_DIR="${WINGET_PKGS_DIR:-$HOME/winget-pkgs}"
BRANCH="${PKG_ID}-${VERSION}"

# Sanity
[[ -d "$SRC_DIR" ]] || { echo "ERROR: no manifests at $SRC_DIR"; exit 1; }
for f in "${PKG_ID}.yaml" "${PKG_ID}.installer.yaml" "${PKG_ID}.locale.en-US.yaml"; do
    [[ -f "$SRC_DIR/$f" ]] || { echo "ERROR: missing $f in $SRC_DIR"; exit 1; }
done

# First run: clone the fork. Subsequent runs: reuse the existing checkout.
if [[ ! -d "$WINGET_PKGS_DIR/.git" ]]; then
    echo "First run: cloning ${FORK_USER}/winget-pkgs to ${WINGET_PKGS_DIR}..."
    git clone --quiet --depth=50 "$FORK_SSH" "$WINGET_PKGS_DIR"
fi

cd "$WINGET_PKGS_DIR"

# Make sure remotes are correct (idempotent).
git remote get-url origin   >/dev/null 2>&1 || git remote add origin   "$FORK_SSH"
git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "https://github.com/${UPSTREAM}.git"

# Discard any local edits left from a previous failed run.
git reset --hard HEAD --quiet 2>/dev/null || true
git clean -fd --quiet 2>/dev/null || true

echo "Fetching upstream master from ${UPSTREAM}..."
git fetch --quiet --depth=1 upstream master

echo "Creating branch ${BRANCH} from upstream/master..."
git checkout -B "$BRANCH" upstream/master --quiet

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

echo "Pushing ${BRANCH} to ${FORK_USER}/winget-pkgs (SSH)..."
git push --quiet --force-with-lease -u origin "$BRANCH"

# Pre-fill PR title + body so the user just clicks Create on GitHub.
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
echo "Local fork checkout kept at: ${WINGET_PKGS_DIR}"
echo "============================================================"
