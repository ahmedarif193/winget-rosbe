#!/usr/bin/env bash
# Open a PR to microsoft/winget-pkgs for ReactOS.RosBE <version>.
#
# Usage: GH_TOKEN=<PAT> ./scripts/publish-winget.sh <version>
#
# Prerequisites:
#   - GitHub release v<version> already exists on ahmedarif193/winget-rosbe
#     with the installer ZIP and SHA256SUMS.txt attached.
#   - Local manifests at winget/manifests/r/ReactOS/RosBE/<version>/*.yaml
#     with InstallerUrl and InstallerSha256 already correct.
#   - GH_TOKEN is a PAT (classic public_repo, or fine-grained with:
#     Contents R/W on the fork, Pull requests R/W on microsoft/winget-pkgs,
#     Metadata R).

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
: "${GH_TOKEN:?GH_TOKEN must be set}"

PKG_ID="ReactOS.RosBE"
LETTER="r"
UPSTREAM="microsoft/winget-pkgs"
RELEASE_REPO="ahmedarif193/winget-rosbe"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/winget/manifests/${LETTER}/ReactOS/RosBE/${VERSION}"
COMMIT_EMAIL="actions@github.com"
COMMIT_NAME="RosBE Modern Bot"

[[ -d "$SRC_DIR" ]] || { echo "ERROR: no manifests at $SRC_DIR"; exit 1; }
for f in "${PKG_ID}.yaml" "${PKG_ID}.installer.yaml" "${PKG_ID}.locale.en-US.yaml"; do
    [[ -f "$SRC_DIR/$f" ]] || { echo "ERROR: missing $f"; exit 1; }
done
command -v gh      >/dev/null || { echo "ERROR: gh CLI not installed"; exit 1; }
command -v uuidgen >/dev/null || { echo "ERROR: uuidgen not installed"; exit 1; }

FORK_USER="$(gh api user -q .login)"
FORK="${FORK_USER}/winget-pkgs"
UUID="$(uuidgen | tr -d - | tr 'a-f' 'A-F')"
BRANCH="${PKG_ID}-${VERSION}-${UUID}"
PR_TITLE="New version: ${PKG_ID} version ${VERSION}"
MANIFEST_PATH="manifests/${LETTER}/ReactOS/RosBE/${VERSION}"

EXISTING_PR="$(gh pr list --repo "$UPSTREAM" \
    --search "head:${FORK_USER} ${PKG_ID} ${VERSION} in:title" \
    --state open --json url --jq '.[0].url // empty')"
if [[ -n "$EXISTING_PR" ]]; then
    echo "Open PR already exists: $EXISTING_PR"
    exit 0
fi

echo "Checking fork $FORK exists..."
if ! gh api "repos/${FORK}" --silent 2>/dev/null; then
    echo ""
    echo "ERROR: Fork $FORK does not exist."
    echo ""
    echo "The token cannot create it automatically (fine-grained PATs usually"
    echo "lack read access to public repos outside the owner's account)."
    echo ""
    echo "Fix: fork manually once via the GitHub UI:"
    echo "  https://github.com/${UPSTREAM}/fork"
    echo ""
    echo "Pick ${FORK_USER} as the destination, confirm. The script is"
    echo "idempotent after that: every future publish reuses the fork."
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Init, fetch upstream master's tip only, branch from it (never touch fork's
# own master -- only push the new feature branch, which is all fine-grained
# PATs reliably allow).
echo "Preparing workspace (fetching upstream master HEAD)..."
git -C "$TMP" init --quiet
git -C "$TMP" config core.sparseCheckout true
git -C "$TMP" sparse-checkout init --cone
git -C "$TMP" sparse-checkout set "manifests/${LETTER}/ReactOS/RosBE"
git -C "$TMP" config user.email "$COMMIT_EMAIL"
git -C "$TMP" config user.name  "$COMMIT_NAME"
git -C "$TMP" remote add origin   "https://${FORK_USER}:${GH_TOKEN}@github.com/${FORK}.git"
git -C "$TMP" remote add upstream "https://github.com/${UPSTREAM}.git"
git -C "$TMP" fetch --quiet --depth=1 --filter=blob:none upstream master

echo "Creating branch ${BRANCH} from upstream master..."
git -C "$TMP" checkout -B "$BRANCH" FETCH_HEAD
mkdir -p "$TMP/$MANIFEST_PATH"
cp "$SRC_DIR"/*.yaml "$TMP/$MANIFEST_PATH/"
git -C "$TMP" add "$MANIFEST_PATH"
git -C "$TMP" commit -m "$PR_TITLE"
git -C "$TMP" push --quiet -u origin "$BRANCH"

HASHES="$(gh release view "v${VERSION}" --repo "$RELEASE_REPO" \
    --json assets --jq '.assets[] | select(.name=="SHA256SUMS.txt") | .url' \
    | xargs -I{} curl -sL {} 2>/dev/null || true)"
X64_HASH="$(echo "$HASHES" | awk '/win-x64\.zip/ {print toupper($1)}' | head -1)"

# shellcheck source=versions.env
source "${ROOT_DIR}/scripts/versions.env"
BODY_FILE="$TMP/pr-body.md"
cat > "$BODY_FILE" <<EOF
### Update from [RosBE Modern](https://github.com/${RELEASE_REPO}) :rocket:

- **Package**: \`${PKG_ID}\`
- **Version**: \`${VERSION}\`
- **Release**: https://github.com/${RELEASE_REPO}/releases/tag/v${VERSION}
- **Installer SHA256 (x64)**: \`${X64_HASH:-see manifest}\`

Bundled upstream versions:
- LLVM-MinGW: \`${LLVM_VERSION}\`
- MinGW-GCC (ct-ng Canadian-cross): \`${GCC_VERSION}\` (${GCC_TAG} from ahmedarif193/mingw-gcc15.2)
- CMake: \`${CMAKE_VERSION}\`
- Ninja: \`${NINJA_VERSION}\`
- WinFlexBison: \`${WINFLEXBISON_VERSION}\`

- [x] Signed the Microsoft CLA
- [x] Only modifies one manifest
EOF

PR_URL="$(gh pr create --repo "$UPSTREAM" \
    --base master --head "${FORK_USER}:${BRANCH}" \
    --title "$PR_TITLE" --body-file "$BODY_FILE")"

echo "Opened PR: $PR_URL"
