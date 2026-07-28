#!/usr/bin/env bash
#
# Case: when CMake is configured with a cross-compilation toolchain file, what
#       target triple reaches cargo, and what architecture is the resulting
#       libspacewasm_c_api.a?
#
# This is an OBSERVATION, not a defect report. crates/spacewasm_c_api/README.md
# documents that cross compiling requires setting SPACEWASM_TARGET explicitly.
# The point is that the default is the *host* triple from `rustc -vV`, so an
# unset SPACEWASM_TARGET produces a host-architecture archive with no diagnostic
# from CMake — the mismatch surfaces only at link time.
#
# Context: nasa/spacewasm#112 asks how CMake builds should pass their linker and
# sysroots over to cargo.
#
# Run inside the dev image:
#   docker run --rm -v "$PWD:/repo" spacewasm-dev bash /repo/cases/cross-triple/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLCHAIN="$REPO_ROOT/dev/i686-linux.cmake"

UPSTREAM="https://github.com/nasa/spacewasm.git"
PR_REF="refs/pull/130/head"
PINNED_SHA="a1ef2caff5e79eb3249d26531dafc93dbcd91bcc"   # nasa/spacewasm#130 head, 2026-07-27

WORK="${WORK:-/tmp/case-cross-triple}"
SRC="${SPACEWASM_SRC:-$WORK/spacewasm}"

[ -f "$TOOLCHAIN" ] || { echo "FATAL: toolchain file missing: $TOOLCHAIN"; exit 2; }

echo "== environment =="
cmake --version | head -1
echo "rustc host: $(rustc -vV | grep '^host:' | cut -d' ' -f2)"
echo

echo "== source =="
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$UPSTREAM"
  git -C "$SRC" fetch -q --depth 1 origin "$PR_REF" || {
    echo "FATAL: could not fetch $PR_REF from $UPSTREAM"; exit 2; }
  git -C "$SRC" checkout -q FETCH_HEAD
fi
ACTUAL_SHA="$(git -C "$SRC" rev-parse HEAD)"
echo "pinned: $PINNED_SHA"
echo "actual: $ACTUAL_SHA"
[ "$ACTUAL_SHA" != "$PINNED_SHA" ] && echo "NOTE: upstream ref moved; observation may not apply."
echo

CAPI="$SRC/crates/spacewasm_c_api"
BUILD="$WORK/build"

echo "== configure with i686 toolchain file, SPACEWASM_TARGET unset =="
echo "   (install dirs passed explicitly to get past the GNUInstallDirs issue —"
echo "    see cases/gnuinstalldirs/)"
cmake -S "$CAPI" -B "$BUILD" \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
      -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_INSTALL_INCLUDEDIR=include \
      -DCMAKE_INSTALL_LIBDIR=lib 2>&1 | tail -4
CFG_EXIT=${PIPESTATUS[0]}
echo "CONFIGURE_EXIT=$CFG_EXIT"
[ "$CFG_EXIT" -ne 0 ] && { echo "FATAL: configure failed"; exit 2; }
echo

echo "== what CMake was told (toolchain file) =="
grep -E "CMAKE_SYSTEM_NAME|CMAKE_SYSTEM_PROCESSOR|CMAKE_C_FLAGS_INIT" "$TOOLCHAIN"
echo
echo "== what CMake recorded =="
grep -E "CMAKE_TOOLCHAIN_FILE|SPACEWASM_TARGET" "$BUILD/CMakeCache.txt" 2>/dev/null || true
echo "   (SPACEWASM_TARGET empty in cache => the if() branch set a normal"
echo "    variable, i.e. the rustc host triple was used)"
echo

echo "== build =="
cmake --build "$BUILD" -j "${JOBS:-4}" 2>&1 | tail -6
echo

echo "== resulting archive =="
ARCHIVE="$(find "$BUILD" -name libspacewasm_c_api.a -print -quit 2>/dev/null)"
if [ -z "$ARCHIVE" ]; then
  echo "FATAL: no libspacewasm_c_api.a produced"; exit 2
fi
echo "path: $ARCHIVE"
echo "cargo target dir component: $(basename "$(dirname "$(dirname "$ARCHIVE")")")"

TMPX="$WORK/extract"; rm -rf "$TMPX"; mkdir -p "$TMPX"
OBJ="$(ar t "$ARCHIVE" | grep '\.o$' | head -1)"
( cd "$TMPX" && ar x "$ARCHIVE" "$OBJ" )
CLASS="$(readelf -h "$TMPX/$OBJ" | awk -F: '/Class:/ {gsub(/ /,"",$2); print $2}')"
MACHINE="$(readelf -h "$TMPX/$OBJ" | sed -n 's/.*Machine: *//p')"
echo "ELF class:   $CLASS"
echo "ELF machine: $MACHINE"
echo

echo "== observation =="
if [ "$CLASS" = "ELF32" ]; then
  echo "Archive is 32-bit — CMake's cross-compilation intent reached cargo."
else
  echo "CMake was configured for i686 (CMAKE_SYSTEM_PROCESSOR=i686) but the"
  echo "archive is $CLASS/$MACHINE, i.e. the host architecture."
  echo "SPACEWASM_TARGET defaulted to the rustc host triple; nothing in the"
  echo "CMake toolchain file influenced the cargo invocation, and the build"
  echo "reported success. The mismatch would surface only when linking."
fi
