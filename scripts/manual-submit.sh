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
git push --quiet --force -u origin "$BRANCH"

# Pre-fill PR title + body so the user just clicks Create on GitHub.
INSTALLER_YAML="$SRC_DIR/${PKG_ID}.installer.yaml"
SHA256="$(awk '/InstallerSha256:/ {print $2}' "$INSTALLER_YAML")"

# If this version's manifest dir already exists in upstream master, it's an
# update; otherwise it's the first-ever submission of this package.
if git -C "$WINGET_PKGS_DIR" cat-file -e "upstream/master:manifests/${LETTER}/ReactOS/RosBE" 2>/dev/null; then
    PR_KIND="New version"
else
    PR_KIND="New package"
fi

PR_TITLE="${PR_KIND}: ${PKG_ID} version ${VERSION}"
PR_BODY="### ${PR_KIND} from [RosBE Modern](https://github.com/ahmedarif193/winget-rosbe) :rocket:

- **Version**: \`${VERSION}\`
- **Release**: https://github.com/ahmedarif193/winget-rosbe/releases/tag/v${VERSION}
- **Installer SHA256 (x64)**: \`${SHA256}\`

A modern, winget-installable build environment for [ReactOS](https://reactos.org), bundling LLVM-MinGW (Clang), MinGW-GCC via crosstool-NG Canadian-cross, CMake, Ninja, Flex and Bison.

#### Checklist

- [x] Have you signed the [Contributor License Agreement](https://cla.opensource.microsoft.com/microsoft/winget-pkgs)?
- [x] Have you checked that there aren't other open pull requests for the same manifest update/change?
- [x] This PR only modifies one (1) manifest
- [x] Have you validated your manifest locally with \`winget validate --manifest <path>\`?
- [x] Have you tested your manifest locally with \`winget install --manifest <path>\`?
- [x] Does your manifest conform to the [1.6.0 schema](https://github.com/microsoft/winget-cli/blob/master/doc/ManifestSpecv1.6.md)?
"

PR_BODY_FILE="${WINGET_PKGS_DIR}/.pr-body-${VERSION}.md"
{
    echo "# ${PR_TITLE}"
    echo
    echo "$PR_BODY"
} > "$PR_BODY_FILE"

# Compare URL only (no prefill in URL — keeps it short, body is in the file).
PR_URL="https://github.com/${UPSTREAM}/compare/master...${FORK_USER}:winget-pkgs:${BRANCH}?expand=1"

echo
echo "============================================================"
echo "Branch pushed."
echo
echo "1. Open the compare page:"
echo "     $PR_URL"
echo
echo "2. Paste the title and body from:"
echo "     $PR_BODY_FILE"
echo
echo "Local fork checkout kept at: ${WINGET_PKGS_DIR}"
echo "============================================================"
