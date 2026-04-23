# winget-rosbe


A modernized ReactOS Build Environment (RosBE) delivered through winget.

> **Not an official RosBE release.** This package ships the latest upstream
> toolchains (Clang 21 / LLVM-MinGW, GCC 15.2 built via crosstool-NG, CMake
> 3.31, Ninja 1.12, flex/bison) bundled the way ReactOS expects them. The
> goal is for this to eventually become the default RosBE used when building
> upstream ReactOS; for now treat it as an experimental / preview build.

## Install

Windows:

```powershell
winget install rosbe
```

Linux:

```bash
wget -qO- https://raw.githubusercontent.com/ahmedarif193/winget-rosbe/main/rosbe-linux-bootstrap.sh | sh
```

The Linux bootstrap installs a fresh toolchain tree under
`~/.local/opt/rosbe` and replaces any previous tree at that path.

On Windows, ReactOS's own `configure.cmd` / `cmake` pick up the toolchain
from the standard winget install path. The package also exposes a lightweight
`rosbe` command that verifies the bundle layout and prints the key paths.

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

Targets: `i686` and `x86_64` (Windows UCRT).

## Links

- Maintainer documentation: [wiki](https://github.com/ahmedarif193/winget-rosbe/wiki)
- Issues / feedback: [issue tracker](https://github.com/ahmedarif193/winget-rosbe/issues)
- ReactOS: <https://reactos.org>

## License

MIT. Bundled third-party toolchains keep their own licenses.
