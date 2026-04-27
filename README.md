# ReactOS RosBE

[![Validation](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/validate.yml)
[![Publish](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/release.yml)

Unofficial ReactOS build environment for Windows, Linux, and macOS.

- Windows: `winget` installs the small `rosbe` bootstrapper, then `rosbe install` downloads and verifies the toolchain bundle.
- Linux / macOS: a single bootstrap script auto-detects the host OS and architecture and installs the toolchain tree under `~/.local/opt/rosbe`.
- Release tags use daily snapshot versions like `v20260424`.

## Install

Windows:

```powershell
winget install ReactOS.RosBE
rosbe install
rosbe enable
```

Linux or macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-unix-bootstrap.sh | sh
```

The bootstrap detects:

- **Linux x86_64 / aarch64** — installs LLVM-MinGW plus the ct-ng MinGW-GCC toolchains for `i686` and `x86_64` Windows targets.
- **macOS Intel / Apple Silicon** — installs the LLVM-MinGW universal binary (Clang + lld + libc++). The ct-ng GCC bundle has no upstream macOS host build; if you need GCC, run `brew install mingw-w64` (separate version, MSVCRT default).

The script always replaces any previous tree at `~/.local/opt/rosbe` with a
fresh toolchain. On macOS, `com.apple.quarantine` is cleared after extraction
as a defensive measure for offline (Safari-downloaded) installs — the typical
`curl | sh` flow doesn't set the xattr in the first place.

On Windows, `rosbe install` verifies the downloaded bundle against
`SHA256SUMS.txt` and the release's GitHub artifact attestation before
activating it under `%LOCALAPPDATA%\RosBE`.

Useful Windows commands:

```powershell
rosbe status
rosbe update
rosbe disable
rosbe remove
```

On Linux and macOS, run `~/.local/bin/rosbe-shell` or source
`~/.local/opt/rosbe/rosbe-env.sh` before configuring ReactOS.
The bootstrap installs only the toolchains; use your distro/Homebrew packages
for CMake, Ninja, Flex, and Bison.

## What you get

| Component | Version |
|-----------|---------|
| LLVM-MinGW (Clang + lld + libc++) | 21.1.7 (20251202) |
| MinGW-GCC (crosstool-NG Canadian-cross, UCRT) | 15.2.0 |
| CMake | 3.31.6 |
| Ninja | 1.12.1 |
| Flex + Bison (winflexbison) | 2.6.4 / 3.8.2 |
| QEMU (Windows bundle) | 11.0.0 |

Targets: `i686` and `x86_64` (Windows UCRT).

## Repository layout

- `bootstrapper/`: Rust source for the Windows `rosbe.exe` bootstrapper.
- `scripts/package.sh`: produces the Windows toolchain ZIP, `rosbe.exe`, the
  winget bootstrapper ZIP, and `SHA256SUMS.txt`.
- `winget/`: local manifest templates used when publishing to `winget-pkgs`.

## Links

- Maintainer documentation: [wiki](https://github.com/ahmedarif193/winget-rosbe/wiki)
- Issues / feedback: [issue tracker](https://github.com/ahmedarif193/winget-rosbe/issues)
- ReactOS: <https://reactos.org>

## License

MIT. Bundled third-party toolchains keep their own licenses.
