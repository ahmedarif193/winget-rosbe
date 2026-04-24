# ReactOS RosBE

[![Validation](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/validate.yml)
[![Publish](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/ahmedarif193/winget-rosbe/actions/workflows/release.yml)

Unofficial ReactOS build environment for Windows and Linux.

- Windows: `winget` installs the small `rosbe` bootstrapper, then `rosbe install` downloads and verifies the toolchain bundle.
- Linux: the bootstrap script installs the toolchain tree under `~/.local/opt/rosbe`.
- Release tags use daily snapshot versions like `v20260424`.

## Install

Windows:

```powershell
winget install ReactOS.RosBE
rosbe install
rosbe enable
```

Linux:

```bash
wget -qO- https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-linux-bootstrap.sh | sh
```

The Linux bootstrap installs a fresh toolchain tree under
`~/.local/opt/rosbe` and replaces any previous tree at that path.

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

On Linux, run `~/.local/bin/rosbe-shell` or source
`~/.local/opt/rosbe/rosbe-env.sh` before configuring ReactOS.
The Linux bootstrap installs only the toolchains; use your distro packages
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
