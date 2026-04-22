# winget-rosbe

Winget-installable toolchain bundle for building [ReactOS](https://reactos.org).

This repo is the **kitchen** — it downloads upstream toolchains and build
tools, assembles them into a self-contained prefix, and publishes it as
`ReactOS.RosBE` on the Windows Package Manager. End users never clone this
repo; they run `winget install ReactOS.RosBE`.

> **Status:** Windows (`winget install`) is the primary target and is
> working. The Linux / WSL2 installer (`setup.sh` + `rosbe-modern-*-linux-x64.tar.xz`
> artifact) is kept in the kitchen but not yet polished — expect rough edges
> there until a dedicated Linux release.

## For end users

```powershell
winget install ReactOS.RosBE
```

Winget installs the bundle to `%LOCALAPPDATA%\Microsoft\WinGet\Packages\ReactOS.RosBE_*\`.
ReactOS's own `configure.cmd` / `configure.sh` / cmake toolchain files find
the tools there — no PATH editing required on the RosBE side.

Verify the install:
```powershell
rosbe
```

## Layout of the installed bundle

```
%LOCALAPPDATA%\Microsoft\WinGet\Packages\ReactOS.RosBE_*\rosbe-modern-<version>-win-x64\
├── rosbe.cmd
├── LICENSE  README.md
├── tools/
│   ├── cmake/bin/cmake.exe
│   └── bin/{ninja,flex,bison,win_flex,win_bison}.exe
└── toolchains/
    ├── llvm-mingw/              # Clang 21 (LLVM-MinGW)
    └── mingw-gcc/
        ├── x86_64-w64-mingw32/  # GCC 15.2 + binutils (UCRT, SEH)
        └── i686-w64-mingw32/    # GCC 15.2 + binutils (UCRT, DWARF)
```

## Ingredients (kitchen pulls these at CI time)

| Component | Source | Notes |
|-----------|--------|-------|
| LLVM-MinGW (Clang 21, lld, libc++) | [mstorsjo/llvm-mingw](https://github.com/mstorsjo/llvm-mingw) | i686, x86_64, aarch64 |
| MinGW-GCC 15.2.0 (Windows, UCRT) | [brechtsanders/winlibs_mingw](https://github.com/brechtsanders/winlibs_mingw) | ships windres + windmc |
| MinGW-GCC 15.2.0 (Linux host, crosstool-NG) | [ahmedarif193/mingw-gcc15.2](https://github.com/ahmedarif193/mingw-gcc15.2) | for WSL/Linux bundle |
| CMake | [Kitware/CMake](https://github.com/Kitware/CMake) | latest stable |
| Ninja | [ninja-build/ninja](https://github.com/ninja-build/ninja) | |
| Flex + Bison (Windows) | [lexxmark/winflexbison](https://github.com/lexxmark/winflexbison) | |

> crosstool-NG-based Windows-hosted builds will replace winlibs in a future
> release once they're published to `ahmedarif193/mingw-gcc15.2`.

## Kitchen layout

```
winget-rosbe/
├── setup.ps1                                  # Windows kitchen (local dev)
├── setup.sh                                   # Linux kitchen (local dev)
├── rosbe.cmd                                  # Entry point shipped in the bundle
├── scripts/
│   ├── package.sh                             # CI: build release archives
│   └── submit-winget.sh                       # CI: PR to microsoft/winget-pkgs
├── winget/
│   ├── manifests/r/ReactOS/RosBE/<version>/   # Winget manifest
│   └── personalize.yaml                       # winget configure for dev deps
├── .github/workflows/release.yml              # tag push → release → manifest PR
└── LICENSE
```

## Release flow

```bash
git tag v1.0.0 && git push origin v1.0.0
#   → .github/workflows/release.yml triggers
#   → scripts/package.sh on Ubuntu runner
#      - downloads upstream LLVM / winlibs / CMake / Ninja / win_flex_bison
#      - assembles rosbe-modern-1.0.0-linux-x64.tar.xz
#      - assembles rosbe-modern-1.0.0-win-x64.zip
#      - uploads both + SHA256SUMS.txt to the GitHub Release

./scripts/submit-winget.sh 1.0.0
#   → updates winget manifest with the release SHA256
#   → prints PR instructions for microsoft/winget-pkgs
```

## Scope

RosBE is the **toolchain only**. It does not ship:

- ReactOS source
- ReactOS `configure.cmd` / `configure.sh`
- CMake toolchain files (`toolchain-gcc.cmake`, `toolchain-clang.cmake`)
- Anything under `sdk/cmake/*`

Those live in ReactOS. ReactOS's build scripts discover RosBE tools by their
well-known winget install path.

## License

MIT — see [LICENSE](LICENSE). Bundled third-party toolchains keep their own
licenses.
