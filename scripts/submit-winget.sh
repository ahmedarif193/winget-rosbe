#!/bin/bash
# RosBE Modern - Submit winget manifest to microsoft/winget-pkgs
#
# Prerequisites:
#   - gh CLI authenticated
#   - GitHub release already created (with zip artifacts)
#   - SHA256SUMS.txt downloaded or available
#
# Usage: ./scripts/submit-winget.sh <version>
#   e.g.: ./scripts/submit-winget.sh 1.0.0

set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_SRC="${ROOT_DIR}/winget/manifests/r/ReactOS/RosBE/${VERSION}"

if [[ ! -d "${MANIFEST_SRC}" ]]; then
    echo "ERROR: Manifest directory not found: ${MANIFEST_SRC}"
    echo "Create the manifest for version ${VERSION} first."
    exit 1
fi

echo "RosBE Modern - Winget Submission"
echo "================================"
echo ""

# Step 1: Get checksums from the release
echo "Fetching SHA256SUMS from GitHub release v${VERSION}..."
SUMS=$(gh release download "v${VERSION}" --repo ahmedarif193/winget-rosbe --pattern "SHA256SUMS.txt" --output - 2>/dev/null || true)

if [[ -z "${SUMS}" ]]; then
    echo "WARNING: Could not fetch SHA256SUMS.txt from release."
    echo "Make sure the release v${VERSION} exists with artifacts."
    echo ""
    echo "You can manually update the hashes in:"
    echo "  ${MANIFEST_SRC}/ReactOS.RosBE.installer.yaml"
    exit 1
fi

WIN_X64_HASH=$(echo "${SUMS}" | grep "win-x64.zip" | awk '{print toupper($1)}')
WIN_ARM64_HASH=$(echo "${SUMS}" | grep "win-arm64.zip" | awk '{print toupper($1)}')

echo "  x64 hash:   ${WIN_X64_HASH}"
echo "  arm64 hash: ${WIN_ARM64_HASH}"
echo ""

# Step 2: Update manifest with real hashes
INSTALLER_YAML="${MANIFEST_SRC}/ReactOS.RosBE.installer.yaml"
sed -i "0,/InstallerSha256:.*/{s|InstallerSha256:.*|InstallerSha256: ${WIN_X64_HASH}|}" "${INSTALLER_YAML}"
sed -i "0,/InstallerSha256: ${WIN_X64_HASH}/! {0,/InstallerSha256:.*/{s|InstallerSha256:.*|InstallerSha256: ${WIN_ARM64_HASH}|}}" "${INSTALLER_YAML}"

echo "Updated installer manifest:"
cat "${INSTALLER_YAML}"
echo ""

# Step 3: Fork & PR to winget-pkgs
echo "To submit to winget-pkgs:"
echo ""
echo "  # Fork microsoft/winget-pkgs if not already done"
echo "  gh repo fork microsoft/winget-pkgs --clone --remote-name origin"
echo ""
echo "  # Copy manifests"
echo "  cp -r ${MANIFEST_SRC} <winget-pkgs-clone>/manifests/r/ReactOS/RosBE/${VERSION}/"
echo ""
echo "  # Commit and PR"
echo "  cd <winget-pkgs-clone>"
echo "  git checkout -b rosbe-${VERSION}"
echo "  git add manifests/r/ReactOS/RosBE/"
echo "  git commit -m 'New package: ReactOS.RosBE version ${VERSION}'"
echo "  gh pr create --title 'New package: ReactOS.RosBE version ${VERSION}' --body 'Adds RosBE Modern - ReactOS Build Environment'"
echo ""
