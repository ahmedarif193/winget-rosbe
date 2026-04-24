# winget-rosbe

A modernized ReactOS Build Environment (RosBE) bootstrapper and toolchain bundle.

> **Not an official RosBE release.** On Windows, `winget` installs a small Rust
> bootstrapper (`rosbe.exe`). That bootstrapper later downloads and verifies the
> full toolchain bundle on demand. The goal is for this to eventually become the
> default RosBE used when building upstream ReactOS; for now treat it as an
> experimental / preview build.
>
> Release tags use daily snapshot versions like `v20260424`.

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

On Windows, `winget` installs only the `rosbe` bootstrapper. The toolchain ZIP
is downloaded later by `rosbe install`, verified against the published
`SHA256SUMS.txt` and the release's GitHub artifact attestation, then activated
locally under `%LOCALAPPDATA%\RosBE`. The bootstrapper prints the install root
plus free space before download, then provides `rosbe status` to verify the
bundle layout and the active toolchain paths.

Release artifacts also carry GitHub build provenance attestations, so you can
manually validate them with `gh attestation verify`.

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
