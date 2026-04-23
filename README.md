# winget-rosbe

A modernized ReactOS Build Environment (RosBE) delivered through winget.

> **Not an official RosBE release.** This package ships the latest upstream
> toolchains (Clang 21 / LLVM-MinGW, GCC 15.2 built via crosstool-NG, CMake
> 3.31, Ninja 1.12, flex/bison) bundled the way ReactOS expects them. The
> goal is for this to eventually become the default RosBE used when building
> upstream ReactOS; for now treat it as an experimental / preview build.

## Install

```powershell
winget install rosbe
```

That's all you need. After install, ReactOS's own `configure.cmd` /
`configure.sh` / `cmake` pick up the toolchain from the standard winget
install path — no PATH edits required.

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
