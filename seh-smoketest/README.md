# psedevelop — SEH conformance harness for GCC/PSEH vs Clang

Builds and runs Windows structured-exception-handling tests against GCC/PSEH
backends across a sweep of optimization levels, and reports a
pass/fail/crash matrix. Clang/reference profiles remain available explicitly,
but are excluded from the default sweep while the GCC parity work is active.

The question it answers: **given identical source, how do GCC+PSEH and Clang's
native SEH actually behave — and does that change under `-O2`, `-O3` or LTO?**

## Why

GCC has no `__try`/`__except`. ReactOS supplies its own implementation, PSEH,
and the shape of it differs per architecture:

| Target | Backend | How it works |
|---|---|---|
| GCC / i386 | PSEH2 *framebased* | pushes a registration record onto the `FS:[0]` chain from inline asm |
| GCC / i386 | PSEH3 | alternative, lower-overhead try path |
| GCC / amd64 | `sdk/tools/gcc_plugin_seh` | a home-made GCC plugin that emits genuine `.seh_handler` unwind tables |
| GCC / amd64 | dummy | `__try`/`__except` compile but never catch — a control group |
| Clang / amd64, arm64 | native | clang implements SEH directly; ReactOS selects it with `-D_USE_NATIVE_SEH=1` |
| Clang / i386 | PSEH2 | `sdk/cmake/clang.cmake` sets `_USE_NATIVE_SEH` on amd64/arm64 **only** |

Those backends are not interchangeable, and SEH correctness is strongly
optimizer-sensitive: PSEH2 leans on inline asm, computed gotos and volatile
barriers to stop GCC moving code across handler boundaries. A backend that is
correct at `-O0` and wrong at `-O2` is the result worth having, so the
optimization level is a first-class axis rather than a fixed flag.

## Working implementation and test-corpus delta

`pseh/` and `gcc_plugin_seh/` are tracked working copies imported from ReactOS.
They are edited directly while parity fixes are developed; Git records their
delta from the commit named in `pseh/PROVENANCE.txt`.

The *test corpus* has only one portability delta, kept separate and reviewable
in `patches/`:

- `patches/ms_seh/0001-ms-seh-corpus-mingw-portability.patch` — lets the Microsoft
  corpus compile and link outside the ReactOS SDK against plain mingw-w64
  headers (`_exception_code`/`_exception_info` redirection, and the MSVC
  one-argument `_setjmp` spelling). Applied as an explicit step after
  vendoring; `--no-patch` vendors pristine so you can see upstream unmodified.

Failures are reported exactly as measured. Nothing is masked.

## Corpora

**`ms`** — the 58 Microsoft SEH conformance tests ReactOS carries in
`modules/rostests/apitests/compiler/ms/seh`. ReactOS only builds these for MSVC
and i386, so on GCC/amd64 and Clang they are largely unexercised upstream.

**`stress`** — 74 tests written for this harness (`stress/`), each built as
its own executable so that a crash, hang or hard process kill in one case
cannot disturb any other. They target semantics the MS corpus does not cover,
and most verify *ordering*, not just outcome: a backend can catch the right
exception while running filters and unwind handlers in the wrong order, so
each test appends a marker at every observable step and compares the resulting
trace against the sequence Windows produces.

| Range | Area |
|---|---|
| `0001`–`0003`, `0017`–`0024` | filter semantics: nesting, `CONTINUE_SEARCH` chains, evaluation-exactly-once, reading and writing the establishing frame's locals, `GetExceptionCode()` consistency, filters containing their own `try` |
| `0004` | `EXCEPTION_CONTINUE_EXECUTION` with a `VirtualProtect` repair |
| `0002`, `0005`, `0016`, `0025`–`0034` | two-pass semantics and unwind ordering: filters before any unwind, innermost-first termination handlers, `__leave`, `goto`/`break`/`continue` out of a try, `abnormal_termination()`, unwinding through frames with no handler |
| `0035`–`0042`, `0072` | exception sources: read/write/execute AV, `#DE`, `#UD`, `#BP`, misalignment, noncontinuable exceptions, 15-parameter records, custom severity codes |
| `0043`, `0044` | `setjmp`/`longjmp` out of a try body and out of a handler |
| `0007`, `0008`, `0060`, `0062`, `0070`, `0071` | nested and collided dispatch: faults inside filters, exceptions raised during unwind, raise-from-handler chains |
| `0009`, `0045`, `0047`, `0051`–`0052`, `0073` | scale: 64- and 200-frame unwinds, 16 levels of nesting, 32 KB frames, `_alloca`, stack overflow |
| `0013`, `0049`, `0050`, `0055`, `0066` | state preservation: callee-saved integer and XMM registers, x87 control word, handler writes to locals, stack alignment inside a handler |
| `0015`, `0063`, `0068`, `0069` | chain hygiene: 10k–50k iteration loops that expose a registration record that is pushed but never popped |
| `0053`, `0054`, `0064`, `0065`, `0074` | calling conventions: varargs, struct returns, `qsort` callbacks, Win32-style callbacks, jump tables |
| `0056`–`0058` | TLS access from a handler; SEH on a secondary thread; four threads handling concurrently |
| `0059`, `0060` | vectored exception handlers vs. frame-based filters |
| `0067` | a critical section released by a `finally` during unwind |

## Build and run phases

The harness creates 14 independent default output trees: two GCC backends
times seven optimization configurations.

```text
output-gcc-i686-pseh2-O0/
...
output-gcc-i686-pseh2-O3-lto/
output-gcc-x86_64-plugin-O0/
...
output-gcc-x86_64-plugin-O3-lto/
```

Each is a normal CMake/Ninja project containing all 132 executable targets,
its backend support library or GCC plugin, and the runner object. The build
phase configures each tree and invokes Ninja once; Ninja recompiles only inputs
whose dependencies or command lines changed. The run phase never configures,
compiles, or links. It executes only binaries proven current by that output
tree.

You can also build directly inside any configured tree:

```bash
ninja -C output-gcc-i686-pseh2-O2              # all 132 targets
ninja -C output-gcc-i686-pseh2-O2 stress0027   # one target
```

One executable per test. Each test's own `main()` is renamed with
`-Dmain=pseh_test_entry` and linked against `runner/runner_main.c`, which:

- reports the verdict as a machine-readable stdout line, because Wine truncates
  Windows exit codes to 8 bits and `-1` would collide with `0xC0000005`;
- installs a `SetUnhandledExceptionFilter` — a plain Win32 API, never
  `__try`/`__except` — so the runner does not depend on the SEH implementation
  it is measuring;
- suppresses the crash dialog so a failing test returns instead of hanging.

Per-test isolation means a crash takes down one executable, not the run.
Runtime results are checkpointed per `(profile, config)` after execution.

Binaries run under Wine on macOS/Linux (i386 and x86_64), or natively on
Windows. ARM64 builds but is not executed here.

## Usage

```bash
./pseh_harness.py --vendor              # import PSEH + corpus, apply patches/
./pseh_harness.py --list-profiles       # detected toolchains
./pseh_harness.py --list-opts           # build configurations
./pseh_harness.py --build               # incremental build: 2 GCC x 7 levels
./pseh_harness.py --run                 # run existing binaries; never rebuild
./pseh_harness.py --build -t stress0027 # build one target in all 14 trees
./pseh_harness.py --run -t stress0027   # run that already-built target
./pseh_harness.py --build -p gcc-x86_64-plugin --opt O2 --opt O2-lto
./pseh_harness.py --run -p gcc-x86_64-plugin --opt O2 --opt O2-lto
./pseh_harness.py --no-patch --vendor   # pristine corpus, unpatched
```

The default profiles are `gcc-i686-pseh2` and `gcc-x86_64-plugin`. PSEH3,
dummy, and Clang profiles require explicit `-p`; no Clang tree is built by the
default commands.

Point it at a different tree with `--reactos PATH` or `REACTOS_SOURCE_DIR`.
Toolchains are found on `PATH` and under `$ROSBE_ROOT/llvm-mingw/bin`.

## Build configurations swept

`O0`, `O1`, `O2`, `O3`, `Os`, `O2-lto`, `O3-lto`. LTO flags are passed at link
time as well as compile time.

`-g` is off by default and opt-in via `--debug-info`: clang's 32-bit SEH does
not survive it, which would otherwise confound every i686 comparison.

## Output

- `results/matrix.md` — profiles, pass rate per optimization level, full
  verdict breakdown, **optimizer-sensitivity table** (tests whose verdict
  changes with `-O`), and every failure with a link to its log.
- `results/results.json` — the same data, machine-readable.
- `results/logs/<profile>/<config>/<test>.log` — full build and run output for
  every non-passing test.
- `results/build-logs/<profile>/<config>.log` — CMake/Ninja output.
- `results/partial/` — per-`(profile, config)` runtime checkpoints.

### Verdicts

| Verdict | Meaning |
|---|---|
| `PASS` | test's `main()` returned 0 |
| `FAIL` | returned non-zero — it detected wrong behaviour itself |
| `CRASH` | an exception escaped every SEH scope; NTSTATUS is recorded |
| `TIMEOUT` | hung |
| `BUILD_FAIL` | did not compile or link |
| `NO_RESULT` | ran but died before reporting — the process was killed |
| `NORUN` | built for an architecture this host cannot execute |

## Layout

```
pseh_harness.py    the harness
CMakeLists.txt     one test project, configured once per matrix cell
runner/            entry-point stub linked into every test executable
stress/            this harness's own SEH stress corpus
patches/           the test-corpus delta vs upstream ReactOS
vendor/            imported from the ReactOS tree (generated)
output-*/          independent incremental CMake/Ninja trees (generated)
results/           reports, logs and runtime checkpoints (generated)
```
