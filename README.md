# spacewasm-crossbuild

A reproducible Linux environment and a set of minimal, self-contained cases for
building and cross-compiling the C API of
[nasa/spacewasm](https://github.com/nasa/spacewasm) with CMake.

Not affiliated with NASA or JPL.

## Why

spacewasm's CI (`.github/workflows/ci.yml`) covers macOS ARM64, Linux x86_64,
Linux ARM64, and a 32-bit `i686-unknown-linux-gnu` test job — but it has no
CMake job. The CMake integration added in
[PR #130](https://github.com/nasa/spacewasm/pull/130) is therefore not exercised
by CI.

This repo provides a container that mirrors the CI toolchain and adds CMake, so
build-system behaviour can be checked reproducibly and reported with an exact
upstream commit attached.

## Environment

```sh
docker build -t spacewasm-dev dev/
```

Provides Rust stable, WABT 1.0.41 (the spectests shell out to `wat2wasm`),
`gcc-multilib`, the `aarch64-linux-gnu` cross tools, CMake, clang, and the
`i686-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `wasm32-unknown-unknown`
and `wasm32-wasip1` targets.

Verified baseline on `nasa/spacewasm@8abced5` (2026-07-27), inside this image:

| Check | Result |
| --- | --- |
| `cargo test -p spacewasm` (core spectests) | 75/75 pass |
| `cargo test -p spacewasm --target i686-unknown-linux-gnu` | pass |

Note: `custom_page_sizes_integration::memory_max` instantiates two ~4 GiB linear
memories and is killed by the OOM killer on a host with 8 GB available. That is
an environment limit, not an upstream defect — give the container ~12 GB or skip
that test.

## Cases

Each case is a single `run.sh` that fetches one exact upstream commit — by SHA,
not by `refs/pull/N/head`, so a later push to the branch cannot quietly change
what is being measured — runs a controlled experiment, and prints an explicit
verdict. Run them inside the image:

```sh
docker run --rm -v "$PWD:/repo" spacewasm-dev bash /repo/cases/<name>/run.sh
```

### `cases/gnuinstalldirs/`

Checks whether the `add_subdirectory()` integration documented in
`crates/spacewasm_c_api/README.md` configures successfully.

Observed on PR #130 head `a1ef2ca`: it does not, unless the consuming project
has already called `include(GNUInstallDirs)`. `CMAKE_INSTALL_INCLUDEDIR` and
`CMAKE_INSTALL_LIBDIR` are defined only by that module, so both `install()`
calls receive an empty `DESTINATION` and configuration aborts. The case runs the
same parent project with and without the `include()` to isolate the cause.

**Status: resolved upstream.** Reported on
[PR #130](https://github.com/nasa/spacewasm/pull/130#issuecomment-5101181671)
and fixed the same day in
[`ca42f9c`](https://github.com/nasa/spacewasm/commit/ca42f9c255d083a7fdaabfcb33118846996b40b1),
which drops both `install()` calls rather than adding the module — F´ consumes
the crate through `add_subdirectory()` and does not need them. The case stays
pinned to `a1ef2ca` as the record of what was reported.

### `cases/cross-triple/`

Pinned to `ca42f9c`. Records what target triple reaches cargo when CMake is
configured with a cross-compilation toolchain file, and reports the architecture
of the resulting `libspacewasm_c_api.a`.

This is an observation, not a defect report: `crates/spacewasm_c_api/README.md`
documents that cross compiling requires setting `SPACEWASM_TARGET` explicitly.
The case exists to give
[issue #112](https://github.com/nasa/spacewasm/issues/112) — which asks how
CMake builds should pass their linker and sysroots to cargo — a concrete
starting point, since the current default is the *host* triple from `rustc -vV`
and a mismatch surfaces only at link time.

### `cases/cross-guard/`

Pinned to `ca42f9c`, and to `nasa/fprime@307acd7` for the toolchain files.

Uses F´'s own `cmake/toolchain/aarch64-linux.cmake` rather than a hand-written
toolchain file. That file sets `CMAKE_SYSTEM_PROCESSOR` and includes
`helpers/arm-linux-base.cmake`, which sets `CMAKE_SYSTEM_NAME` — so CMake enters
cross-compiling mode. `arm-hf-linux.cmake`, `arm-sf-linux.cmake` and
`raspberrypi.cmake` all include the same helper.

| Variant | configure | archive |
| --- | --- | --- |
| upstream as-is, `SPACEWASM_TARGET` unset | 0 | ELF64 / **x86-64** (the host) |
| with `proposed/SpacewasmCrossGuard.cmake` | **error** | — |
| with the guard, triple given explicitly | 0 | ELF64 / AArch64 |

The first row is the point: a clean build, no diagnostic, and an archive for the
wrong machine.

### `cases/cross-triple-fix/`

Pinned to `ca42f9c`. Demonstrates the *withdrawn* approach — see `proposed/`
below. Builds that commit with the same toolchain file twice, once unpatched and
once with `proposed/SpacewasmRustTarget.cmake` included by the consuming
project, and compares the architecture of the resulting archive.

| Variant | cargo target dir | archive |
| --- | --- | --- |
| unpatched | `x86_64-unknown-linux-gnu` | ELF64 / x86-64 |
| with the module | `i686-unknown-linux-gnu` | ELF32 / Intel 80386 |

Kept because the measurement is still valid and reproducible; the design it
demonstrates is not the one being proposed any more.

## `proposed/`

**`SpacewasmCrossGuard.cmake`** — the current proposal, three lines. It derives
nothing. Specifying `SPACEWASM_TARGET` by hand stays the contract, exactly as in
Wasmtime's `c-api`; the guard only declines to fall back to the `rustc` host
triple, silently and with a zero exit code, once a toolchain file has put CMake
into cross-compiling mode.

Two limits, stated up front:

- A toolchain file that sets `CMAKE_SYSTEM_PROCESSOR` without
  `CMAKE_SYSTEM_NAME` leaves `CMAKE_CROSSCOMPILING` false, and CMake resets the
  processor to the host value — no signal survives for the guard to read.
- A toolchain file that deliberately targets the host now has to say so.

**`SpacewasmRustTarget.cmake`** — **withdrawn.** It derived the triple from
`CMAKE_SYSTEM_NAME` and `CMAKE_SYSTEM_PROCESSOR`. The maintainer's objection on
[#112](https://github.com/nasa/spacewasm/issues/112#issuecomment-5112166321) is
sound: `CMAKE_SYSTEM_PROCESSOR` holds whatever the toolchain file wrote there,
cross-compilers do not share one naming scheme, and the closest prior art
requires the triple explicitly. The file is kept as the record of what was
proposed, with the reasoning at the top.

Forwarding a C toolchain to cargo — `CC_<triple>`, `AR_<triple>`, `--sysroot`
and friends — was also proposed on #112 and **withdrawn**: `spacewasm` and
`spacewasm_c_api` are both `#![no_std]`, the dependency tree is
`spacewasm_c_api -> spacewasm -> libm`, and `build.rs` only reaches for cbindgen
behind the `codegen` feature. Nothing in the cargo half of the build wants a C
compiler, an archiver or a sysroot.

## Upstream discussion

| Thread | What was reported | Outcome |
| --- | --- | --- |
| [PR #130](https://github.com/nasa/spacewasm/pull/130#issuecomment-5101181671) | `install()` calls with no `GNUInstallDirs` | Fixed the same day in `ca42f9c` |
| [Issue #112](https://github.com/nasa/spacewasm/issues/112#issuecomment-5110422185) | Triple derivation + C toolchain forwarding | Both withdrawn after [maintainer review](https://github.com/nasa/spacewasm/issues/112#issuecomment-5112166321) |
| [Issue #112](https://github.com/nasa/spacewasm/issues/112#issuecomment-5114286630) | The three-line cross-compile guard | Open |

## Reporting

Findings from this repo are reported upstream on the relevant issue or pull
request, with the pinned commit and the `run.sh` output. Per spacewasm's
[`AI_POLICY.md`](https://github.com/nasa/spacewasm/blob/main/AI_POLICY.md), any
AI assistance used in diagnosis is disclosed in the report itself.

## License

Apache-2.0, matching upstream.
