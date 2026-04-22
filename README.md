# winget-rosbe (kitchen)

Internal CI repo. Builds `ReactOS.RosBE` and publishes it to
`microsoft/winget-pkgs`. End users never see this repo — they run
`winget install ReactOS.RosBE` (or `winget install rosbe`).

## Release a new version

```bash
# Update scripts/versions.env if any upstream bumped, then:
git commit --allow-empty -m "publish: 1.2.0"
git push
```

That's it. CI does the rest. Any commit **not** starting with `publish:` runs nothing.

Version in the commit message must match `^[0-9]+\.[0-9]+\.[0-9]+$`. Anything else fails the gate job.

## What CI does on `publish: X.Y.Z`

`.github/workflows/release.yml` runs three jobs in sequence:

1. **gate** — extracts `X.Y.Z` from the commit subject, validates semver.
2. **package** — runs `scripts/package.sh X.Y.Z`:
   - Downloads all upstreams into `dist/cache/`
   - Builds `rosbe-modern-X.Y.Z-linux-x64.tar.xz` and `rosbe-modern-X.Y.Z-win-x64.zip`
   - Generates `dist/SHA256SUMS.txt`
   - Materializes `winget/manifests/r/ReactOS/RosBE/X.Y.Z/` from the `1.0.0` template (bumps `PackageVersion`, `InstallerUrl`, `InstallerSha256`)
   - Creates GitHub Release `vX.Y.Z` with all 3 artifacts + a body that lists every bundled upstream version.
3. **publish-winget** — runs `scripts/publish-winget.sh X.Y.Z`:
   - Forks `microsoft/winget-pkgs` (once), syncs master
   - Creates `ReactOS.RosBE-X.Y.Z-<UUID>` branch
   - Commits the new manifest, pushes, opens PR titled `New version: ReactOS.RosBE version X.Y.Z`
   - PR body includes release URL, SHA256, bundled upstream versions.

After Microsoft moderators merge the PR: `winget install rosbe` resolves to the new version.

## Required repo secrets

| Secret | Value |
|--------|-------|
| `WINGET_PUBLISHER_RELEASER` | Fine-grained PAT. Contents: R/W. Pull requests: R/W. Metadata: R. Repository access: All repositories. |

Settings → Secrets and variables → Actions → New repository secret.

## Upstream versions (single source of truth)

All version constants live in `scripts/versions.env` — plain KEY=VALUE:

```sh
LLVM_VERSION=20251202
LLVM_TRIPLET=ucrt
CMAKE_VERSION=3.31.6
NINJA_VERSION=1.12.1
WINFLEXBISON_VERSION=2.5.25
WINLIBS_TAG=15.2.0posix-14.0.0-ucrt-r7
GCC_VERSION=15.2.0
MINGW_W64_VERSION=14.0.0
GCC_LINUX_TAG=v15.2
```

Sourced by `scripts/package.sh` (bash) and parsed by `setup.ps1` (PowerShell). The release body and winget PR body both interpolate from these — one file to bump when upstreams release a new version.

## Repo layout

```
winget-rosbe/
├── setup.ps1                   # local Windows build (same logic as package.sh)
├── setup.sh                    # local Linux/WSL build
├── rosbe.cmd                   # status probe; shipped in the bundle, not used by CI
├── scripts/
│   ├── versions.env            # upstream version constants
│   ├── package.sh              # CI: build release archives
│   └── publish-winget.sh       # CI: open PR on microsoft/winget-pkgs
├── winget/
│   ├── manifests/r/ReactOS/RosBE/1.0.0/   # template; CI clones + bumps per version
│   └── personalize.yaml
└── .github/workflows/release.yml          # publish: trigger
```

## Local testing

```bash
# Build archives + generate a version directory locally
./scripts/package.sh 0.0.0-test

# Inspect what CI will publish
ls dist/
cat dist/SHA256SUMS.txt

# Dry-run the winget PR script (needs GH_TOKEN; will actually open a PR)
# GH_TOKEN=<pat> ./scripts/publish-winget.sh 1.2.0
```

## Reference implementations

- `microsoft/winget-create` — `SubmitPRAsync` (authoritative)
- `russellbanks/Komac` — branch name / commit title conventions
- `vedantmgoyal9/winget-releaser` — orchestration reference
- [Microsoft's submission docs](https://learn.microsoft.com/en-us/windows/package-manager/package/repository)

## License

MIT.
