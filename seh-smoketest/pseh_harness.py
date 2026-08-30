#!/usr/bin/env python3
"""
PSEH / SEH conformance harness.

Configures one persistent CMake/Ninja output tree per (SEH backend,
optimization level).  The build phase incrementally builds test targets in
those trees; the separate run phase executes existing Windows binaries under
Wine (or natively on Windows) without invoking the build system.

The point is to compare SEH backends against each other on identical source:

  * GCC has no __try/__except at all, so ReactOS supplies PSEH:
      - i686   : PSEH2 "framebased" (asm FS:[0] exception registration), or PSEH3
      - amd64  : a home-made GCC plugin (sdk/tools/gcc_plugin_seh) that emits
                 real .seh_handler tables, or a "dummy" no-op backend
  * Clang implements SEH natively on all Windows targets, which ReactOS
    selects with -D_USE_NATIVE_SEH=1.

Each test is compiled into its own executable so that a crash in one test
cannot take the rest of the run with it, and is linked against runner_main.c,
which reports its verdict as a machine-readable stdout line.

Usage:
    ./pseh_harness.py --vendor                  # import sources from ReactOS
    ./pseh_harness.py --list-profiles           # show detected toolchains
    ./pseh_harness.py --build                   # incrementally build 14 GCC trees
    ./pseh_harness.py --run                     # run them; never build
    ./pseh_harness.py --build -t stress0027     # build one target per tree
    ./pseh_harness.py --run -t stress0027       # run the existing target
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional

DEBUG_INFO = False  # overridden by --debug-info
PSEH_OPT: Optional[str] = None  # overridden by --pseh-opt

HERE = Path(__file__).resolve().parent
VENDOR = HERE / "vendor"
RESULTS = HERE / "results"
RUNNER = HERE / "runner"

DEFAULT_REACTOS = Path(
    os.environ.get("REACTOS_SOURCE_DIR", HERE.parent.parent / "reactos-dev4")
).expanduser()

ROSBE_ROOT = Path(
    os.environ.get("ROSBE_ROOT", Path.home() / ".local/opt/rosbe")
).expanduser()

# ---------------------------------------------------------------------------
# Verdict vocabulary
# ---------------------------------------------------------------------------

PASS = "PASS"
FAIL = "FAIL"            # test's own main() returned non-zero
CRASH = "CRASH"          # exception escaped every SEH scope
TIMEOUT = "TIMEOUT"
BUILD_FAIL = "BUILD_FAIL"
LINK_FAIL = "LINK_FAIL"
NORUN = "NORUN"          # built, but this arch can't execute here
NO_RESULT = "NO_RESULT"  # ran, but produced no verdict line
GUARDED = "GUARDED"      # failed, but it is a known//reproduced toolchain limit
UNGUARD = "UNGUARD"      # guarded as broken, yet it passed -- drop the guard

VERDICT_ORDER = [PASS, FAIL, CRASH, TIMEOUT, BUILD_FAIL, LINK_FAIL,
                 GUARDED, UNGUARD, NORUN, NO_RESULT]

#: verdicts that mean "this ran and behaved correctly"
GOOD = (PASS, UNGUARD)
#: verdicts that count as a real, unexpected problem
REGRESSION = (FAIL, CRASH, TIMEOUT, BUILD_FAIL, LINK_FAIL, NO_RESULT)


# ---------------------------------------------------------------------------
# Build configurations swept per profile
#
# SEH correctness is strongly optimizer-sensitive: PSEH2 leans on inline asm,
# computed gotos and volatile barriers to keep GCC from moving code across
# handler boundaries, and LTO adds cross-TU inlining on top. A backend that
# passes at -O0 and fails at -O2 is the interesting result, so the level is a
# first-class axis rather than a fixed flag.
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class OptConfig:
    name: str
    cflags: tuple[str, ...]
    ldflags: tuple[str, ...] = ()
    note: str = ""


OPT_CONFIGS = [
    OptConfig("O0",      ("-O0",),                     note="no optimization"),
    OptConfig("O1",      ("-O1",),                     note="light"),
    OptConfig("O2",      ("-O2",),                     note="release default"),
    OptConfig("O3",      ("-O3",),                     note="aggressive inlining"),
    OptConfig("Os",      ("-Os",),                     note="size-optimized"),
    OptConfig("O2-lto",  ("-O2", "-flto"), ("-flto",), note="release + LTO"),
    OptConfig("O3-lto",  ("-O3", "-flto"), ("-flto",), note="aggressive + LTO"),
]

# Each backend owns one persistent output tree per configuration.  The default
# sweep covers every level because incremental Ninja builds make repeated
# checks cheap when no source or flags changed.
DEFAULT_SWEEP = [opt.name for opt in OPT_CONFIGS]

# The active parity work is intentionally limited to the two GCC backends.
# The remaining GCC controls and Clang reference profiles stay available via
# explicit -p selections, but are not part of an accidental default sweep.
DEFAULT_PROFILE_NAMES = ("gcc-i686-pseh2", "gcc-x86_64-plugin")


# ---------------------------------------------------------------------------
# Guards: known, reproduced failures that are NOT harness bugs
#
# A guarded test still gets built and run -- the point is to keep measuring it
# and to keep its log -- but its failure is reported as GUARDED rather than
# counted as a regression. If a guarded test starts passing it is reported as
# UNGUARD (the guard can be dropped), which is how a toolchain fix shows up.
#
# Entries are (profile-name prefix, test-name or "*", reason).
# ---------------------------------------------------------------------------

GUARDS: list[tuple[str, str, str]] = [
    # Empty on purpose: failures are reported exactly as measured, never
    # masked. The mechanism is kept so a genuinely external limitation can be
    # annotated later without changing how results are collected.
]


# ---------------------------------------------------------------------------
# Host caveats
#
# Facts about the *execution environment* that shape how results should be
# read. These are not verdicts and nothing is filtered on them -- they are
# printed alongside the matrix so a host artefact is not mistaken for a
# backend defect. Each one records how it was established.
# ---------------------------------------------------------------------------

HOST_CAVEATS: list[tuple[str, str]] = [
    (
        "Hardware faults raised inline in the guarded function",
        "On Wine/macOS-arm64 an access violation, #DE, #UD or #BP executed "
        "directly inside a __try body reaches the process-wide "
        "SetUnhandledExceptionFilter but is not claimed by the enclosing "
        "__except, while the same fault raised inside a called function is "
        "caught normally. Verified with a standalone clang/x86_64 binary "
        "outside this harness. Affects stress0035, stress0037, stress0038, "
        "stress0039 and the filter fault in stress0007 on every profile "
        "equally, so cross-backend comparison stays valid -- but an isolated "
        "CRASH there says more about the host than about the SEH backend. "
        "Re-run on real Windows to settle those cases.",
    ),
    (
        "Stack overflow (stress0073)",
        "Once the guard page is consumed there may not be enough stack left "
        "to run a filter, so the process dying rather than handling is a "
        "documented Windows behaviour as well as a Wine one.",
    ),
]


def guard_reason(profile: str, test: str) -> Optional[str]:
    for pat, t, reason in GUARDS:
        if profile.startswith(pat) and (t == "*" or t == test):
            return reason
    return None


# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------

@dataclass
class Profile:
    """One (compiler, arch, SEH backend) combination under test."""
    name: str
    kind: str                       # "gcc" | "clang"
    arch: str                       # i686 | x86_64 | aarch64 | armv7
    backend: str                    # human-readable SEH backend name
    defines: list[str] = field(default_factory=list)
    cflags: list[str] = field(default_factory=list)
    ldflags: list[str] = field(default_factory=list)
    pseh_sources: list[str] = field(default_factory=list)  # rel. to vendor/pseh
    needs_plugin: bool = False
    note: str = ""

    # filled in by detection
    cc: Optional[str] = None
    available: bool = False
    unavailable_reason: str = ""

    @property
    def runnable(self) -> bool:
        # Wine on macOS/Linux runs i386 and x86_64 PE images only.
        return self.arch in ("i686", "x86_64")


ARCH_DEFINE = {
    "i686": ["-D_M_IX86", "-D__i386__"],
    "x86_64": ["-D_M_AMD64", "-D_M_X64"],
    "aarch64": ["-D_M_ARM64"],
    "armv7": ["-D_M_ARM"],
}

# PSEH2 framebased backend (GCC/i686): the classic FS:[0]-chain implementation.
PSEH2_FRAMEBASED_SRC = [
    "framebased.c",
    "i386/framebased.S",
    "i386/framebased-gcchack.c",
    "i386/framebased-gcchack-asm.S",
]

# PSEH3 backend (GCC/i686): setjmp-style, lower overhead in the try path.
PSEH3_SRC = [
    "i386/pseh3.c",
    "i386/pseh3_i386.S",
]


def all_profiles() -> list[Profile]:
    common = ["-fms-extensions", "-fno-strict-aliasing", "-fno-common"]
    # The MS corpus is old C: it relies on implicit decls and ignores results.
    # The MS corpus is 1990s C: implicit declarations, int/pointer mixing,
    # unused labels from the SEH macros. Silence only that noise.
    quiet = [
        "-Wno-format", "-Wno-implicit-function-declaration",
        "-Wno-unused-label", "-Wno-unused-variable", "-Wno-int-conversion",
        "-Wno-implicit-int", "-Wno-return-type", "-Wno-incompatible-pointer-types",
        "-Wno-attributes",
    ]
    gcc_quiet = quiet + ["-Wno-builtin-declaration-mismatch", "-Wno-discarded-qualifiers"]
    clang_quiet = quiet + ["-Wno-incompatible-pointer-types-discards-qualifiers",
                           "-Wno-unknown-warning-option"]

    profiles = [
        Profile(
            name="gcc-i686-pseh2",
            kind="gcc", arch="i686", backend="PSEH2 framebased (FS:[0] chain)",
            cflags=common + gcc_quiet,
            pseh_sources=PSEH2_FRAMEBASED_SRC,
            note="ReactOS default for GCC/i386.",
        ),
        Profile(
            name="gcc-i686-pseh3",
            kind="gcc", arch="i686", backend="PSEH3",
            defines=["-D_USE_PSEH3=1"],
            cflags=common + gcc_quiet,
            pseh_sources=PSEH3_SRC,
            note="Alternative i386 backend, selected by USE_PSEH3.",
        ),
        Profile(
            name="gcc-x86_64-plugin",
            kind="gcc", arch="x86_64", backend="GCC plugin (real .seh_handler)",
            cflags=common + gcc_quiet,
            needs_plugin=True,
            note="sdk/tools/gcc_plugin_seh emits genuine SEH unwind tables.",
        ),
        Profile(
            name="gcc-x86_64-dummy",
            kind="gcc", arch="x86_64", backend="dummy PSEH (no-op)",
            defines=["-D_USE_DUMMY_PSEH=1"],
            cflags=common + gcc_quiet,
            pseh_sources=["dummy.c"],
            note="Control group: __try/__except compile but never catch. "
                 "Everything that needs a handler is expected to CRASH.",
        ),
        Profile(
            name="clang-i686-pseh2",
            kind="clang", arch="i686", backend="PSEH2 framebased (FS:[0] chain)",
            cflags=common + clang_quiet,
            pseh_sources=PSEH2_FRAMEBASED_SRC,
            note="What ReactOS actually ships for clang/i386: sdk/cmake/clang.cmake "
                 "sets _USE_NATIVE_SEH only on amd64/arm64, so i386 uses PSEH2.",
        ),
        Profile(
            name="clang-i686-native",
            kind="clang", arch="i686", backend="Clang native SEH",
            defines=["-D_USE_NATIVE_SEH=1"],
            cflags=common + clang_quiet,
            note="Not a configuration ReactOS ships -- included to show why. "
                 "Any function with an __except FILTER fails to assemble on "
                 "i686-w64-mingw32 (undefined L__ehtable$ label).",
        ),
        Profile(
            name="clang-x86_64-native",
            kind="clang", arch="x86_64", backend="Clang native SEH",
            defines=["-D_USE_NATIVE_SEH=1"],
            cflags=common + clang_quiet,
        ),
        Profile(
            name="clang-aarch64-native",
            kind="clang", arch="aarch64", backend="Clang native SEH (ARM64)",
            defines=["-D_USE_NATIVE_SEH=1"],
            cflags=common + clang_quiet,
            note="Build-only here: Wine on this host cannot execute ARM64 PE.",
        ),
    ]
    for p in profiles:
        p.defines = ARCH_DEFINE.get(p.arch, []) + p.defines
    return profiles


def detect(profiles: list[Profile]) -> list[Profile]:
    """Locate a compiler for each profile."""
    llvm_bin = ROSBE_ROOT / "llvm-mingw" / "bin"
    for p in profiles:
        if p.kind == "gcc":
            cand = [f"{p.arch}-w64-mingw32-gcc"]
            found = next((shutil.which(c) for c in cand if shutil.which(c)), None)
        else:
            names = [f"{p.arch}-w64-mingw32-clang"]
            found = None
            for n in names:
                local = llvm_bin / n
                if local.is_file():
                    found = str(local)
                    break
                if shutil.which(n):
                    found = shutil.which(n)
                    break
        if found:
            p.cc = found
            p.available = True
        else:
            p.unavailable_reason = f"no {p.arch}-w64-mingw32-{p.kind} on PATH"
    return profiles


# ---------------------------------------------------------------------------
# Vendoring: pull PSEH + the MS SEH corpus out of the ReactOS tree
# ---------------------------------------------------------------------------

def vendor(reactos: Path, force: bool = False) -> None:
    if not reactos.is_dir():
        sys.exit(f"error: ReactOS tree not found at {reactos}\n"
                 f"       pass --reactos PATH or set REACTOS_SOURCE_DIR")

    pseh_src = reactos / "sdk/lib/pseh"
    tests_src = reactos / "modules/rostests/apitests/compiler/ms/seh"
    plugin_src = reactos / "sdk/tools/gcc_plugin_seh"

    for p in (pseh_src, tests_src):
        if not p.is_dir():
            sys.exit(f"error: expected {p} in the ReactOS tree")

    if force and VENDOR.exists():
        shutil.rmtree(VENDOR)

    # --- MS SEH conformance corpus ----------------------------------------
    dst_tests = VENDOR / "ms_seh"
    if dst_tests.exists():
        shutil.rmtree(dst_tests)
    dst_tests.mkdir(parents=True)
    n = 0
    for f in sorted(tests_src.iterdir()):
        if f.suffix in (".c", ".h", ".cpp") or f.name.endswith(".out"):
            shutil.copy2(f, dst_tests / f.name)
            if re.fullmatch(r"seh\d{4}\.c", f.name):
                n += 1

    (VENDOR / "PROVENANCE.txt").write_text(
        f"Imported by pseh_harness.py --vendor\n"
        f"source tree : {reactos}\n"
        f"tests       : modules/rostests/apitests/compiler/ms/seh ({n} tests)\n"
        f"imported at : {time.strftime('%Y-%m-%d %H:%M:%S')}\n"
    )
    print(f"vendored {n} MS SEH tests + PSEH sources from {reactos} (pristine)")


def apply_patches(quiet: bool = False) -> list[str]:
    """Apply patches/*.patch on top of the pristine vendored corpus.

    Kept deliberately separate from vendoring so the delta against upstream
    ReactOS stays reviewable in one place, and so `--no-patch` can show what
    upstream does on its own. Note that no patch touches the PSEH
    implementation itself -- only the test corpus -- so results describe
    upstream PSEH as it ships.
    """
    patch_dir = HERE / "patches"
    if not patch_dir.is_dir():
        return []
    applied = []
    marker = VENDOR / ".patches-applied"
    # patches/<subtree>/*.patch applies inside vendor/<subtree>, so corpus
    # fixes and PSEH fixes stay clearly separated.
    todo = []
    for sub in sorted(d.name for d in patch_dir.iterdir() if d.is_dir()):
        for pf in sorted((patch_dir / sub).glob("*.patch")):
            todo.append((sub, pf))
    for sub, pf in todo:
        target = VENDOR / sub
        if not target.is_dir():
            sys.exit(f"error: {pf.name} targets vendor/{sub}, which is missing")
        # -N makes re-application a no-op instead of an error.
        rc, out, err = run(["patch", "-p1", "-N", "-r", "-", "--no-backup-if-mismatch",
                            "-d", str(target), "-i", str(pf)])
        already = "previously applied" in (out + err) or "Reversed" in (out + err)
        if rc == 0:
            applied.append(f"{sub}/{pf.name}")
            if not quiet:
                print(f"applied {sub}/{pf.name}")
        elif already:
            applied.append(f"{sub}/{pf.name} (already applied)")
        else:
            sys.exit(f"error: failed to apply {pf.name}:\n{out}\n{err}")
    marker.write_text("\n".join(applied) + "\n")
    return applied


def patches_pending() -> bool:
    """True when patches/ exists but the vendored corpus has not got them.

    Checked on every run, not only on --vendor: an accidental pristine
    re-vendor otherwise produces a sweep of link failures that looks like a
    toolchain result.
    """
    patch_dir = HERE / "patches"
    if not patch_dir.is_dir() or not any(patch_dir.glob("*/*.patch")):
        return False
    if not (VENDOR / "ms_seh").is_dir():
        return False
    return not (VENDOR / ".patches-applied").is_file()


STRESS = HERE / "stress"

# PSEH and the GCC SEH plugin are working sources tracked in this repo and
# edited directly -- git history is the record of what changed versus upstream.
# Only the Microsoft corpus is still imported into vendor/ and patched, because
# it is test data we do not intend to modify.
PSEH_DIR = HERE / "pseh"
PLUGIN_DIR = HERE / "gcc_plugin_seh"


def test_files(corpus: str = "all") -> list[Path]:
    """Collect the test sources for the requested corpus.

    "ms"     -- the Microsoft SEH conformance corpus vendored from ReactOS.
    "stress" -- this harness's own tests, which target ordering and two-pass
                semantics that the MS corpus does not cover: filter-before-
                unwind, CONTINUE_SEARCH chains, CONTINUE_EXECUTION, collided
                unwinds, deep unwind, register preservation, chain hygiene.
    """
    out: list[Path] = []
    if corpus in ("ms", "all"):
        d = VENDOR / "ms_seh"
        if not d.is_dir():
            sys.exit("error: nothing vendored yet -- run with --vendor first")
        out += sorted(p for p in d.iterdir() if re.fullmatch(r"seh\d{4}\.c", p.name))
    if corpus in ("stress", "all"):
        if STRESS.is_dir():
            out += sorted(p for p in STRESS.iterdir()
                          if re.fullmatch(r"stress\d{4}\.c", p.name))
    return out


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

def run(cmd: list[str], cwd: Optional[Path] = None, timeout: int = 300,
        env: Optional[dict] = None) -> tuple[int, str, str]:
    try:
        cp = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                            timeout=timeout, env=env)
        return cp.returncode, cp.stdout, cp.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"
    except FileNotFoundError as e:
        return 127, "", str(e)


@dataclass
class TestResult:
    profile: str
    test: str
    verdict: str
    exit_code: Optional[int] = None
    detail: str = ""
    build_log: str = ""
    run_log: str = ""
    duration: float = 0.0
    # NB: appended after the original fields on purpose. Several call sites
    # construct TestResult positionally as (profile, test, verdict, exit_code,
    # detail); inserting anything ahead of exit_code silently shifts those.
    opt: str = ""
    guard: str = ""
    log_path: str = ""


@dataclass
class BuildOutcome:
    profile: str
    opt: str
    output_dir: Path
    ready: list[str] = field(default_factory=list)
    failed: dict[str, str] = field(default_factory=dict)
    log_path: str = ""


def output_tree(profile: Profile, opt: OptConfig) -> Path:
    """Return the independent CMake/Ninja tree for one matrix cell."""
    return HERE / f"output-{profile.name}-{opt.name}"


def cmake_list(items) -> str:
    return ";".join(str(item) for item in items)


def compiler_archive_tools(profile: Profile) -> tuple[str, str]:
    """Return LTO-aware archiver tools for the selected cross compiler."""
    compiler = Path(profile.cc or "")
    if profile.kind == "gcc" and compiler.name.endswith("-gcc"):
        ar_name = compiler.name[:-4] + "-gcc-ar"
        ranlib_name = compiler.name[:-4] + "-gcc-ranlib"
    else:
        ar_name = compiler.name.replace("-clang", "-ar")
        ranlib_name = compiler.name.replace("-clang", "-ranlib")
    ar = shutil.which(ar_name) or str(compiler.with_name(ar_name))
    ranlib = shutil.which(ranlib_name) or str(compiler.with_name(ranlib_name))
    return ar, ranlib


def configuration_payload(profile: Profile, opt: OptConfig,
                          all_tests: list[Path]) -> dict:
    """Everything that selects the shape and flags of one CMake tree."""
    compile_options = profile.defines + profile.cflags
    if DEBUG_INFO:
        compile_options += ["-g"]
    ar, ranlib = compiler_archive_tools(profile)
    return {
        "profile": profile.name,
        "compiler": profile.cc,
        "arch": profile.arch,
        "backend": profile.backend,
        "compile_options": compile_options,
        "opt_options": list(opt.cflags),
        "link_options": list(opt.cflags) + list(opt.ldflags) + profile.ldflags,
        "pseh_lib_options": [PSEH_OPT] if PSEH_OPT else list(opt.cflags),
        "pseh_sources": [str(PSEH_DIR / rel) for rel in profile.pseh_sources],
        "needs_plugin": profile.needs_plugin,
        "host_cxx": os.environ.get("HOST_CXX", shutil.which("c++") or "c++"),
        "ar": ar,
        "ranlib": ranlib,
        "tests": [str(test) for test in all_tests],
    }


def configuration_file(outdir: Path) -> Path:
    return outdir / ".pseh-configuration.json"


def generated_toolchain_matches(outdir: Path, payload: dict) -> bool:
    """CMake cannot safely replace compiler/archive tools in an existing tree."""
    if not (outdir / "build.ninja").is_file():
        return True
    files = list((outdir / "CMakeFiles").glob("*/CMakeCCompiler.cmake"))
    if len(files) != 1:
        return False
    try:
        text = files[0].read_text()
    except OSError:
        return False
    expected = {
        "CMAKE_C_COMPILER": payload["compiler"],
        "CMAKE_AR": payload["ar"],
        "CMAKE_RANLIB": payload["ranlib"],
    }
    return all(f'set({name} "{value}")' in text for name, value in expected.items())


def configure_tree(profile: Profile, opt: OptConfig, all_tests: list[Path],
                   verbose: bool) -> tuple[bool, str]:
    """Configure one persistent output tree; CMake owns dependency tracking."""
    outdir = output_tree(profile, opt)
    payload = configuration_payload(profile, opt, all_tests)
    if outdir.is_dir() and not generated_toolchain_matches(outdir, payload):
        print(f"  resetting {outdir.name}: CMake toolchain changed", flush=True)
        shutil.rmtree(outdir)
    args = [
        "cmake", "-S", str(HERE), "-B", str(outdir), "-G", "Ninja",
        "-DCMAKE_SYSTEM_NAME=Windows",
        "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY",
        f"-DCMAKE_C_COMPILER:FILEPATH={profile.cc}",
        f"-DCMAKE_ASM_COMPILER:FILEPATH={profile.cc}",
        f"-DCMAKE_AR:FILEPATH={payload['ar']}",
        f"-DCMAKE_RANLIB:FILEPATH={payload['ranlib']}",
        f"-DPSEH_PROFILE_NAME:STRING={profile.name}",
        f"-DPSEH_HARNESS_ROOT:PATH={HERE}",
        f"-DPSEH_PROFILE_OPTIONS:STRING={cmake_list(payload['compile_options'])}",
        f"-DPSEH_OPT_OPTIONS:STRING={cmake_list(payload['opt_options'])}",
        f"-DPSEH_LINK_OPTIONS:STRING={cmake_list(payload['link_options'])}",
        f"-DPSEH_LIB_OPTIONS:STRING={cmake_list(payload['pseh_lib_options'])}",
        f"-DPSEH_SUPPORT_SOURCES:STRING={cmake_list(payload['pseh_sources'])}",
        f"-DPSEH_NEEDS_PLUGIN:BOOL={'ON' if profile.needs_plugin else 'OFF'}",
    ]
    if profile.needs_plugin:
        args += [f"-DPSEH_HOST_CXX:FILEPATH={payload['host_cxx']}"]
    if verbose:
        print("  configure:", " ".join(args), flush=True)
    rc, out, err = run(args, timeout=600)
    log = (out + ("\n" + err if err.strip() else "")).strip()
    if rc != 0:
        return False, log
    configuration_file(outdir).write_text(json.dumps(payload, indent=2) + "\n")
    return True, log


def tree_configuration_current(profile: Profile, opt: OptConfig,
                               all_tests: list[Path]) -> bool:
    path = configuration_file(output_tree(profile, opt))
    if not path.is_file():
        return False
    try:
        return json.loads(path.read_text()) == configuration_payload(profile, opt, all_tests)
    except (OSError, json.JSONDecodeError):
        return False


def executable_path(profile: Profile, opt: OptConfig, test: Path) -> Path:
    return output_tree(profile, opt) / "bin" / f"{test.stem}.exe"


def target_inputs(profile: Profile, opt: OptConfig, test: Path) -> list[Path]:
    """Inputs used to reject a stale executable during a run-only phase."""
    paths = [HERE / "CMakeLists.txt", RUNNER / "runner_main.c", test]
    paths += sorted(p for p in (PSEH_DIR / "include").rglob("*") if p.is_file())
    paths += [PSEH_DIR / rel for rel in profile.pseh_sources]
    paths += sorted(p for p in STRESS.glob("*.h") if p.is_file())
    paths += sorted(p for p in (VENDOR / "ms_seh").glob("*.h") if p.is_file())
    if profile.needs_plugin:
        paths += sorted(p for p in PLUGIN_DIR.rglob("*") if p.is_file())
    return paths


def target_signature(profile: Profile, opt: OptConfig, test: Path,
                     all_tests: list[Path]) -> str:
    digest = hashlib.sha256()
    payload = configuration_payload(profile, opt, all_tests).copy()
    payload.pop("tests", None)
    digest.update(json.dumps(payload, sort_keys=True).encode())
    for path in target_inputs(profile, opt, test):
        digest.update(str(path.relative_to(HERE)).encode())
        digest.update(path.read_bytes())
    if profile.cc:
        try:
            stat = Path(profile.cc).stat()
            digest.update(f"{stat.st_size}:{stat.st_mtime_ns}".encode())
        except OSError:
            pass
    if profile.needs_plugin:
        host_cxx = Path(configuration_payload(profile, opt, all_tests)["host_cxx"])
        try:
            stat = host_cxx.stat()
            digest.update(f"{stat.st_size}:{stat.st_mtime_ns}".encode())
        except OSError:
            pass
    return digest.hexdigest()


def manifest_file(outdir: Path) -> Path:
    return outdir / ".pseh-built-targets.json"


def load_manifest(outdir: Path) -> dict[str, str]:
    try:
        data = json.loads(manifest_file(outdir).read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_manifest(outdir: Path, manifest: dict[str, str]) -> None:
    manifest_file(outdir).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def ninja_target_is_current(outdir: Path, target: str) -> bool:
    """Ask Ninja about freshness without executing a build command."""
    rc, out, err = run(["ninja", "-C", str(outdir), "-n", target], timeout=60)
    log = out + "\n" + err
    return rc == 0 and "no work to do" in log.lower()


def write_build_log(profile: Profile, opt: OptConfig, log: str) -> str:
    path = RESULTS / "build-logs" / profile.name / f"{opt.name}.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(log.rstrip() + "\n")
    return str(path.relative_to(RESULTS))


def build_tree(profile: Profile, opt: OptConfig, selected_tests: list[Path],
               all_tests: list[Path], jobs: int, verbose: bool) -> BuildOutcome:
    """Configure and incrementally build selected targets in one Ninja tree."""
    outdir = output_tree(profile, opt)
    outcome = BuildOutcome(profile.name, opt.name, outdir)
    print(f"\n=== BUILD {profile.name} @ {opt.name} -> {outdir.name} ===", flush=True)

    if not profile.available:
        outcome.failed = {test.stem: profile.unavailable_reason for test in selected_tests}
        print(f"  SKIP: {profile.unavailable_reason}", flush=True)
        return outcome

    ok, configure_log = configure_tree(profile, opt, all_tests, verbose)
    if not ok:
        reason = first_error(configure_log)
        outcome.failed = {test.stem: reason for test in selected_tests}
        outcome.log_path = write_build_log(profile, opt, configure_log)
        print(f"  CONFIGURE_FAIL: {reason}", flush=True)
        return outcome

    targets = [test.stem for test in selected_tests]
    ninja_target = ["pseh_tests"] if len(selected_tests) == len(all_tests) else targets
    cmd = ["ninja", "-C", str(outdir), "-j", str(jobs), "-k", "0"] + ninja_target
    if verbose:
        print("  build:", " ".join(cmd), flush=True)
    rc, out, err = run(cmd, timeout=3600)
    build_log = (configure_log + "\n" + out + ("\n" + err if err.strip() else "")).strip()
    outcome.log_path = write_build_log(profile, opt, build_log)

    manifest = load_manifest(outdir)
    if rc == 0:
        current = set(targets)
    else:
        # Ninja -k 0 builds every independent target it can.  Query each target
        # in dry-run mode afterward to distinguish completed executables from
        # the targets that still have pending work because they failed.
        current = {name for name in targets if ninja_target_is_current(outdir, name)}

    reason = first_error(build_log) if rc != 0 else ""
    for test in selected_tests:
        name = test.stem
        exe = executable_path(profile, opt, test)
        if name in current and exe.is_file():
            outcome.ready.append(name)
            manifest[name] = target_signature(profile, opt, test, all_tests)
        else:
            manifest.pop(name, None)
            outcome.failed[name] = reason or "target did not produce an executable"
    save_manifest(outdir, manifest)

    print(f"  READY={len(outcome.ready)}  BUILD_FAIL={len(outcome.failed)}", flush=True)
    if outcome.failed:
        print(f"  log: {RESULTS / outcome.log_path}", flush=True)
    return outcome


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

RESULT_RE = re.compile(r"^PSEH_RESULT\s+(\w+)(.*)$", re.M)


def wine_cmd() -> Optional[list[str]]:
    if sys.platform.startswith("win"):
        return []
    for cand in ("wine", "wine64", "wine-stable"):
        p = shutil.which(cand)
        if p:
            return [p]
    return None


def run_one(exe: Path, runner: Optional[list[str]], timeout: int) -> TestResult:
    env = dict(os.environ)
    env.setdefault("WINEDEBUG", "-all")
    env.setdefault("WINEDLLOVERRIDES", "mscoree,mshtml=")
    cmd = (runner or []) + [str(exe)]

    t0 = time.time()
    rc, out, err = run(cmd, timeout=timeout, env=env)
    dt = time.time() - t0

    log = (out + ("\n" + err if err.strip() else "")).strip()
    tail = log[-3000:]

    if rc == 124:
        return TestResult("", exe.stem, TIMEOUT, rc, "hung", run_log=tail, duration=dt)

    verdicts = RESULT_RE.findall(out)
    kinds = [v[0] for v in verdicts]

    if "CRASH" in kinds:
        detail = next(v[1].strip() for v in verdicts if v[0] == "CRASH")
        return TestResult("", exe.stem, CRASH, rc, detail, run_log=tail, duration=dt)

    for kind, rest in verdicts:
        if kind == "RC":
            try:
                val = int(rest.strip())
            except ValueError:
                val = -999
            if val == 0:
                return TestResult("", exe.stem, PASS, rc, "", run_log=tail, duration=dt)
            return TestResult("", exe.stem, FAIL, rc, f"test returned {val}",
                              run_log=tail, duration=dt)

    # No verdict line at all: the process died before reporting.
    return TestResult("", exe.stem, NO_RESULT, rc,
                      f"no verdict line (exit {rc})", run_log=tail, duration=dt)


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def dump_log(profile: str, opt: str, test: str, r: TestResult) -> str:
    """Persist the full build+run output for one test, and return its path.

    Guarded failures are only useful if the evidence survives the run, so every
    non-passing test gets its log written out rather than truncated into the
    summary.
    """
    d = RESULTS / "logs" / profile / opt
    d.mkdir(parents=True, exist_ok=True)
    f = d / f"{test}.log"
    parts = [
        f"profile : {profile}",
        f"opt     : {opt}",
        f"test    : {test}",
        f"verdict : {r.verdict}",
        f"detail  : {r.detail}",
        f"guard   : {r.guard or '(none)'}",
        f"exit    : {r.exit_code}",
        "",
        "----- build -----",
        r.build_log or "(clean)",
        "",
        "----- run -----",
        r.run_log or "(no run)",
        "",
    ]
    f.write_text("\n".join(parts))
    return str(f.relative_to(RESULTS))


def run_tree(profile: Profile, opt: OptConfig, tests: list[Path],
             all_tests: list[Path], args) -> list[TestResult]:
    """Run existing executables.  This function never configures or builds."""
    tag = f"{profile.name} @ {opt.name}"
    outdir = output_tree(profile, opt)
    print(f"\n=== RUN {tag} <- {outdir.name} :: {profile.backend} ===", flush=True)

    runner = wine_cmd()
    can_run = profile.runnable and (runner is not None or sys.platform.startswith("win"))
    config_current = profile.available and tree_configuration_current(profile, opt, all_tests)
    manifest = load_manifest(outdir) if config_current else {}
    manifest_changed = False

    ready: dict[str, Path] = {}
    unavailable: dict[str, str] = {}
    for test in tests:
        name = test.stem
        exe = executable_path(profile, opt, test)
        if not profile.available:
            unavailable[name] = profile.unavailable_reason
            continue
        if not config_current:
            unavailable[name] = f"{outdir.name} is not configured for the current profile; run --build"
            continue

        signature = target_signature(profile, opt, test, all_tests)
        if exe.is_file() and manifest.get(name) == signature:
            ready[name] = exe
            continue

        # A user may have run Ninja directly in the output tree.  Accept that
        # build if Ninja says the target is current, but never execute a build
        # from the run phase.
        if exe.is_file() and ninja_target_is_current(outdir, name):
            ready[name] = exe
            manifest[name] = signature
            manifest_changed = True
        else:
            unavailable[name] = f"{name} is missing or stale in {outdir.name}; run --build"

    if manifest_changed:
        save_manifest(outdir, manifest)

    def work(test: Path) -> TestResult:
        try:
            return work_inner(test)
        except Exception as exc:            # never let one test kill the pool
            r = TestResult(profile.name, test.stem, NO_RESULT, None,
                           f"harness error: {exc!r}", opt=opt.name)
            r.log_path = dump_log(profile.name, opt.name, test.stem, r)
            return r

    def work_inner(test: Path) -> TestResult:
        guard = guard_reason(profile.name, test.stem) or ""
        exe = ready.get(test.stem)
        if exe is None:
            r = TestResult(profile.name, test.stem, BUILD_FAIL, None,
                           unavailable[test.stem])
        elif not can_run:
            r = TestResult(profile.name, test.stem, NORUN, None, "built ok",
                           build_log="")
        else:
            r = run_one(exe, runner, args.timeout)
            r.profile = profile.name
        r.opt = opt.name
        r.guard = guard

        # Apply the guard: a known-broken combination that still fails is
        # expected, not a regression; one that now passes means the guard is
        # stale and should be removed.
        if guard:
            if r.verdict in REGRESSION:
                r.detail = f"{r.detail} [guarded: {guard}]".strip()
                r.verdict = GUARDED
            elif r.verdict == PASS:
                r.verdict = UNGUARD
                r.detail = f"passes despite guard: {guard}"

        if r.verdict != PASS:
            r.log_path = dump_log(profile.name, opt.name, test.stem, r)
        return r

    results: list[TestResult] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        for r in ex.map(work, tests):
            results.append(r)

    results.sort(key=lambda r: r.test)
    print("  " + "  ".join(f"{k}={v}" for k, v in tally(results).items() if v),
          flush=True)

    # Checkpoint immediately: a sweep is thousands of builds, and losing all of
    # it because a later profile wedges the machine is not acceptable.
    ckpt = RESULTS / "partial"
    ckpt.mkdir(parents=True, exist_ok=True)
    (ckpt / f"{profile.name}@{opt.name}.json").write_text(
        json.dumps([asdict(r) for r in results], indent=2))
    return results


def first_error(log: str) -> str:
    for line in log.splitlines():
        if re.search(r"\berror\b", line, re.I):
            return line.strip()[:240]
    return log.strip().splitlines()[0][:240] if log.strip() else "build failed"


def tally(results: list[TestResult]) -> dict[str, int]:
    out = {v: 0 for v in VERDICT_ORDER}
    for r in results:
        out[r.verdict] = out.get(r.verdict, 0) + 1
    return out


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

SYMBOL = {
    PASS: "ok", FAIL: "FAIL", CRASH: "CRSH", TIMEOUT: "HANG",
    BUILD_FAIL: "bld!", LINK_FAIL: "lnk!", NORUN: "-", NO_RESULT: "?",
    GUARDED: "grd", UNGUARD: "UNGD",
}


def key(profile: str, opt: str) -> str:
    return f"{profile}@{opt}"


def print_sweep_summary(profiles: list[Profile], opts: list[OptConfig],
                        res: dict[str, list[TestResult]]) -> None:
    """Pass counts per profile across every optimization config."""
    print("\n" + "=" * 78)
    print("OPTIMIZATION SWEEP -- passing tests per build config")
    print("=" * 78)
    w = max(len(p.name) for p in profiles) + 1
    print(" " * w + "".join(o.name.rjust(9) for o in opts))
    for prof in profiles:
        row = prof.name.ljust(w)
        for o in opts:
            rs = res.get(key(prof.name, o.name), [])
            if not rs:
                row += "-".rjust(9); continue
            good = sum(1 for r in rs if r.verdict in GOOD)
            row += f"{good}/{len(rs)}".rjust(9)
        print(row)

    # Optimizer sensitivity: same profile, same test, different verdict across
    # configs. This is the headline result for an SEH backend.
    print("\n" + "=" * 78)
    print("OPTIMIZER SENSITIVITY -- tests whose verdict changes with -O level")
    print("=" * 78)
    any_drift = False
    for prof in profiles:
        rows = {o.name: {r.test: r.verdict for r in res.get(key(prof.name, o.name), [])}
                for o in opts}
        tests = sorted({t for m in rows.values() for t in m})
        drifted = []
        for t in tests:
            verdicts = {o.name: rows[o.name].get(t, "-") for o in opts}
            if len({v for v in verdicts.values() if v != "-"}) > 1:
                drifted.append((t, verdicts))
        if not drifted:
            continue
        any_drift = True
        print(f"\n{prof.name}:")
        for t, verdicts in drifted:
            cells = "  ".join(f"{o.name}={SYMBOL.get(verdicts[o.name], '?')}" for o in opts)
            print(f"  {t:<12} {cells}")
    if not any_drift:
        print("  none -- every profile is stable across optimization levels")

    if HOST_CAVEATS:
        print("\n" + "=" * 78)
        print("HOST CAVEATS -- environment effects, not backend defects")
        print("=" * 78)
        for title, _ in HOST_CAVEATS:
            print(f"  - {title}")
        print("  (full text in results/matrix.md)")

    # Guard accounting
    stale = [(k, r.test) for k, rs in res.items() for r in rs if r.verdict == UNGUARD]
    if stale:
        print("\n" + "=" * 78)
        print("STALE GUARDS -- guarded as broken, but passed (drop the guard)")
        print("=" * 78)
        for k, t in stale:
            print(f"  {k}  {t}")


def write_reports(profiles: list[Profile], opts: list[OptConfig],
                  res: dict[str, list[TestResult]], tests: list[Path]) -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)

    payload = {
        "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "host": {"platform": sys.platform, "wine": (wine_cmd() or ["<none>"])[0]},
        "opt_configs": [asdict(o) for o in opts],
        "pseh_lib_opt": PSEH_OPT or "(follows the swept level)",
        "guards": [{"profile": a, "test": b, "reason": c} for a, b, c in GUARDS],
        "profiles": [{k: v for k, v in asdict(p).items() if k != "cflags"}
                     for p in profiles],
        "results": {k: [asdict(r) for r in rs] for k, rs in res.items()},
        "summary": {k: tally(rs) for k, rs in res.items()},
    }
    (RESULTS / "results.json").write_text(json.dumps(payload, indent=2))

    L = []
    L.append("# PSEH / SEH benchmark across GCC and Clang\n")
    L.append(f"Generated {payload['generated']} on `{sys.platform}` "
             f"(runner: `{payload['host']['wine']}`)\n")
    L.append("Corpus: the Microsoft SEH conformance tests ReactOS carries in "
             "`modules/rostests/apitests/compiler/ms/seh`, one executable per test.\n")
    L.append("\nThe tracked `pseh/` implementation and `gcc_plugin_seh/` plugin "
             "are working copies imported from the ReactOS commit recorded in "
             "`pseh/PROVENANCE.txt`. Their Git delta is the implementation under "
             "test; the Microsoft corpus portability delta remains isolated in "
             "`patches/ms_seh/`.\n")

    L.append("\n## Profiles\n")
    L.append("| Profile | Compiler | Arch | SEH backend | Notes |")
    L.append("|---|---|---|---|---|")
    for p in profiles:
        cc = Path(p.cc).name if p.cc else "_not found_"
        L.append(f"| `{p.name}` | {cc} | {p.arch} | {p.backend} | {p.note} |")

    L.append(f"\nPSEH support library compiled at: "
             f"**{PSEH_OPT or 'the same level as the tests'}**.\n")

    L.append("\n## Build configurations\n")
    L.append("| Config | Flags | Note |")
    L.append("|---|---|---|")
    for o in opts:
        L.append(f"| `{o.name}` | `{' '.join(o.cflags)}` | {o.note} |")

    L.append("\n## Pass rate by optimization level\n")
    L.append("| Profile | " + " | ".join(f"`{o.name}`" for o in opts) + " |")
    L.append("|---" * (len(opts) + 1) + "|")
    for prof in profiles:
        row = [f"`{prof.name}`"]
        for o in opts:
            rs = res.get(key(prof.name, o.name), [])
            row.append(f"{sum(1 for r in rs if r.verdict in GOOD)}/{len(rs)}" if rs else "-")
        L.append("| " + " | ".join(row) + " |")

    L.append("\n## Full verdict breakdown\n")
    L.append("| Profile @ config | " + " | ".join(VERDICT_ORDER) + " |")
    L.append("|---" * (len(VERDICT_ORDER) + 1) + "|")
    for prof in profiles:
        for o in opts:
            k = key(prof.name, o.name)
            if k not in res:
                continue
            t = tally(res[k])
            L.append(f"| `{k}` | " + " | ".join(str(t[v]) for v in VERDICT_ORDER) + " |")

    L.append("\n## Optimizer sensitivity\n")
    L.append("Tests whose verdict changes with the optimization level -- the "
             "clearest signal that a SEH backend depends on codegen details.\n")
    drift_any = False
    for prof in profiles:
        rows = {o.name: {r.test: r.verdict for r in res.get(key(prof.name, o.name), [])}
                for o in opts}
        all_t = sorted({t for m in rows.values() for t in m})
        drifted = [(t, {o.name: rows[o.name].get(t, "-") for o in opts})
                   for t in all_t
                   if len({rows[o.name].get(t, "-") for o in opts} - {"-"}) > 1]
        if not drifted:
            continue
        drift_any = True
        L.append(f"\n### `{prof.name}`\n")
        L.append("| Test | " + " | ".join(f"`{o.name}`" for o in opts) + " |")
        L.append("|---" * (len(opts) + 1) + "|")
        for t, v in drifted:
            L.append(f"| `{t}` | " + " | ".join(v[o.name] for o in opts) + " |")
    if not drift_any:
        L.append("_No profile changed behaviour across optimization levels._")

    L.append("\n## Host caveats\n")
    L.append("Properties of the execution environment, not of any backend. "
             "Nothing is filtered on these; they are recorded so a host "
             "artefact is not read as an SEH defect.\n")
    for title, body in HOST_CAVEATS:
        L.append(f"- **{title}** — {body}")

    L.append("\n## Guards\n")
    L.append("Known, reproduced toolchain limitations. A guarded test is still "
             "built and run and its log kept under `results/logs/`; its failure "
             "is reported as `GUARDED` rather than counted as a regression.\n")
    L.append("| Profile | Test | Reason |")
    L.append("|---|---|---|")
    for a, b, c in GUARDS:
        L.append(f"| `{a}` | `{b}` | {c} |")

    L.append("\n## Failures in detail\n")
    for prof in profiles:
        for o in opts:
            k = key(prof.name, o.name)
            bad = [r for r in res.get(k, []) if r.verdict not in (PASS, NORUN)]
            if not bad:
                continue
            L.append(f"\n### `{k}`\n")
            for r in bad:
                line = f"- **{r.test}** — {r.verdict}"
                if r.detail:
                    line += f": {r.detail}"
                if r.log_path:
                    line += f" ([log](logs/{Path(r.log_path).as_posix().split('logs/')[-1]}))" \
                        if "logs/" in r.log_path else f" (`{r.log_path}`)"
                L.append(line)

    (RESULTS / "matrix.md").write_text("\n".join(L) + "\n")
    print(f"\nwrote {RESULTS/'results.json'}")
    print(f"wrote {RESULTS/'matrix.md'}")
    print(f"logs  {RESULTS/'logs'}/<profile>/<config>/<test>.log")


# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reactos", type=Path, default=DEFAULT_REACTOS,
                    help=f"ReactOS source tree (default: {DEFAULT_REACTOS})")
    ap.add_argument("--vendor", action="store_true",
                    help="(re-)import PSEH + tests from the ReactOS tree")
    ap.add_argument("--list-profiles", action="store_true")
    ap.add_argument("-p", "--profile", action="append", default=[],
                    help="select this profile (repeatable)")
    ap.add_argument("-t", "--test", action="append", default=[],
                    help="select this test target, e.g. seh0023 (repeatable)")
    phase = ap.add_mutually_exclusive_group()
    phase.add_argument("--build", "--build-only", dest="build", action="store_true",
                       help="configure and incrementally build; never run tests")
    phase.add_argument("--run", action="store_true",
                       help="run existing executables; never configure or build")
    ap.add_argument("-j", "--jobs", type=int, default=min(4, os.cpu_count() or 4))
    ap.add_argument("--timeout", type=int, default=60, help="per-test run timeout (s)")
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--clean", action="store_true",
                    help="remove selected output trees before --build")
    ap.add_argument("--corpus", choices=["ms", "stress", "all"], default="all",
                    help="which corpus to run (default: all)")
    ap.add_argument("--no-patch", action="store_true",
                    help="vendor the corpus pristine, without patches/*.patch "
                         "(shows what upstream does unmodified)")
    ap.add_argument("--opt", action="append", default=[],
                    help=f"build config to sweep, repeatable. "
                         f"Choices: {[o.name for o in OPT_CONFIGS]}. "
                         f"Default: all of them.")
    ap.add_argument("--list-opts", action="store_true",
                    help="show the available build configurations")
    ap.add_argument("--pseh-opt", default=None, metavar="FLAG",
                    help="compile the PSEH support library at this fixed "
                         "optimization level (e.g. -O2) instead of following "
                         "the swept level, isolating whether a failure comes "
                         "from PSEH itself or from the code it guards")
    ap.add_argument("--debug-info", action="store_true",
                    help="also compile with -g (note: breaks clang's 32-bit SEH)")
    args = ap.parse_args()

    global DEBUG_INFO, PSEH_OPT
    DEBUG_INFO = args.debug_info
    PSEH_OPT = args.pseh_opt

    profiles = detect(all_profiles())

    if args.vendor:
        vendor(args.reactos, force=True)
        if not args.no_patch:
            apply_patches()

    if args.list_opts:
        print(f"{'config':<10} {'flags':<24} note")
        for o in OPT_CONFIGS:
            print(f"{o.name:<10} {' '.join(o.cflags):<24} {o.note}")
        return 0

    if args.list_profiles:
        print(f"{'profile':<26} {'arch':<9} {'status':<10} {'sweep':<8} backend")
        for p in profiles:
            status = "ok" if p.available else "missing"
            sweep = "default" if p.name in DEFAULT_PROFILE_NAMES else "opt-in"
            print(f"{p.name:<26} {p.arch:<9} {status:<10} {sweep:<8} {p.backend}")
            if not p.available:
                print(f"{'':<26} {'':<9} {'':<10} {'':<8} ^ {p.unavailable_reason}")
        w = wine_cmd()
        print(f"\nrunner: {w[0] if w else '<none: build phase only>'}")
        return 0

    if not args.build and not args.run:
        if args.vendor:
            return 0
        ap.error("choose one phase: --build or --run")

    if args.clean and not args.build:
        ap.error("--clean is only valid with --build")

    if not (VENDOR / "ms_seh").is_dir():
        vendor(args.reactos, force=False)
        if not args.no_patch:
            apply_patches()
    elif patches_pending():
        if args.no_patch:
            print("note: corpus is pristine (--no-patch)")
        else:
            print("corpus is unpatched -- applying patches/ before building")
            apply_patches()

    all_tests = test_files("all")
    tests = test_files(args.corpus)
    if args.test:
        want = {t.replace(".c", "") for t in args.test}
        tests = [t for t in tests if t.stem in want]
        if not tests:
            sys.exit(f"error: no tests matched {sorted(want)}")

    selected = [p for p in profiles if p.name in DEFAULT_PROFILE_NAMES]
    if args.profile:
        want = set(args.profile)
        selected = [p for p in profiles if p.name in want]
        unknown = want - {p.name for p in profiles}
        if unknown:
            sys.exit(f"error: unknown profile(s): {sorted(unknown)}")

    want_opts = args.opt or DEFAULT_SWEEP
    opts = [o for o in OPT_CONFIGS if o.name in want_opts]
    unknown = set(want_opts) - {o.name for o in OPT_CONFIGS}
    if unknown:
        sys.exit(f"error: unknown opt config(s): {sorted(unknown)}\n"
                 f"       available: {[o.name for o in OPT_CONFIGS]}")

    if args.clean:
        for prof in selected:
            for opt in opts:
                outdir = output_tree(prof, opt)
                if outdir.is_dir():
                    shutil.rmtree(outdir)

    phase_name = "build" if args.build else "run"
    print(f"corpus: {len(tests)} tests | profiles: {len(selected)} | "
          f"opt configs: {len(opts)} ({','.join(o.name for o in opts)}) | "
          f"targets: {len(tests)*len(selected)*len(opts)} | "
          f"phase: {phase_name} | jobs: {args.jobs}")

    if args.build:
        outcomes = []
        for prof in selected:
            for opt in opts:
                outcomes.append(build_tree(prof, opt, tests, all_tests,
                                           args.jobs, args.verbose))
        failed = sum(len(outcome.failed) for outcome in outcomes)
        ready = sum(len(outcome.ready) for outcome in outcomes)
        print("\n" + "=" * 78)
        print(f"BUILD SWEEP COMPLETE -- READY={ready}  BUILD_FAIL={failed}")
        print("=" * 78)
        return 1 if failed else 0

    all_results: dict[str, list[TestResult]] = {}
    for prof in selected:
        for opt in opts:
            k = f"{prof.name}@{opt.name}"
            all_results[k] = run_tree(prof, opt, tests, all_tests, args)

    print_sweep_summary(selected, opts, all_results)
    write_reports(selected, opts, all_results, tests)

    # Exit non-zero only if a profile that should work produced no passes.
    return 0


if __name__ == "__main__":
    sys.exit(main())
