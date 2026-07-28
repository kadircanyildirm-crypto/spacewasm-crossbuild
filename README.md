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
`gcc-multilib`, CMake, clang, and the `i686-unknown-linux-gnu`,
`wasm32-unknown-unknown` and `wasm32-wasip1` targets.

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

Each case is a single `run.sh` that fetches the pinned upstream commit, runs a
controlled experiment, and prints an explicit verdict. Run them inside the image:

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

### `cases/cross-triple/`

Records what target triple reaches cargo when CMake is configured with a
cross-compilation toolchain file, and reports the architecture of the resulting
`libspacewasm_c_api.a`.

This is an observation, not a defect report: `crates/spacewasm_c_api/README.md`
documents that cross compiling requires setting `SPACEWASM_TARGET` explicitly.
The case exists to give
[issue #112](https://github.com/nasa/spacewasm/issues/112) — which asks how
CMake builds should pass their linker and sysroots to cargo — a concrete
starting point, since the current default is the *host* triple from `rustc -vV`
and a mismatch surfaces only at link time.

## Reporting

Findings from this repo are reported upstream on the relevant issue or pull
request, with the pinned commit and the `run.sh` output. Per spacewasm's
[`AI_POLICY.md`](https://github.com/nasa/spacewasm/blob/main/AI_POLICY.md), any
AI assistance used in diagnosis is disclosed in the report itself.

## License

Apache-2.0, matching upstream.
