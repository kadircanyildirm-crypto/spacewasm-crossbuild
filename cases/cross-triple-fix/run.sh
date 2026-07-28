#!/usr/bin/env bash
#
# Case: does deriving SPACEWASM_TARGET from CMake's own cross-compilation
#       variables actually produce a correct-architecture archive?
#
# Compares, on the same upstream commit and the same toolchain file:
#   A) unpatched  -> expect ELF64 / x86-64 (the host), build "succeeds"
#   B) with proposed/SpacewasmRustTarget.cmake included by the parent
#      -> expect ELF32 / Intel 80386
#
# The module needs no upstream change: SPACEWASM_TARGET is a CACHE STRING, so
# setting it before add_subdirectory() makes the existing
# `if(SPACEWASM_TARGET STREQUAL "")` branch leave it alone.
#
#   docker run --rm -v "$PWD:/repo" spacewasm-dev bash /repo/cases/cross-triple-fix/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOOLCHAIN="$REPO_ROOT/dev/i686-linux.cmake"
MODULE="$REPO_ROOT/proposed/SpacewasmRustTarget.cmake"

UPSTREAM="https://github.com/nasa/spacewasm.git"
# Pinned to the exact commit, not refs/pull/130/head: that ref moves whenever the
# author pushes, which would silently change what this case measures.
PINNED_SHA="ca42f9c255d083a7fdaabfcb33118846996b40b1"   # nasa/spacewasm#130, 2026-07-28

WORK="${WORK:-/tmp/case-cross-triple-fix}"
SRC="${SPACEWASM_SRC:-$WORK/spacewasm}"

for f in "$TOOLCHAIN" "$MODULE"; do
  [ -f "$f" ] || { echo "FATAL: missing $f"; exit 2; }
done

echo "== source =="
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin "$UPSTREAM"
  git -C "$SRC" fetch -q --depth 1 origin "$PINNED_SHA" || { echo "FATAL: fetch failed"; exit 2; }
  git -C "$SRC" checkout -q FETCH_HEAD
fi
ACTUAL_SHA="$(git -C "$SRC" rev-parse HEAD)"
echo "pinned: $PINNED_SHA"
echo "actual: $ACTUAL_SHA"
[ "$ACTUAL_SHA" != "$PINNED_SHA" ] && { echo "FATAL: not the pinned commit."; exit 2; }
CAPI="$SRC/crates/spacewasm_c_api"
echo

# $1 = tag, $2 = "plain" | "derived"
build_variant() {
  local tag="$1" mode="$2"
  local pdir="$WORK/parent-$tag" bdir="$WORK/build-$tag"
  rm -rf "$pdir" "$bdir"; mkdir -p "$pdir"
  {
    echo 'cmake_minimum_required(VERSION 3.12)'
    echo 'project(parent_app C)'
    echo 'include(GNUInstallDirs)'
    [ "$mode" = "derived" ] && echo "include($MODULE)"
    echo "add_subdirectory($CAPI spacewasm_c_api)"
  } > "$pdir/CMakeLists.txt"

  cmake -S "$pdir" -B "$bdir" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Debug 2>&1 | grep -E "spacewasm:|Error|error" | head -5
  local cfg=${PIPESTATUS[0]}
  if [ "$cfg" -ne 0 ]; then echo "  configure FAILED"; return 1; fi

  cmake --build "$bdir" -j "${JOBS:-4}" >/dev/null 2>&1
  local a
  a="$(find "$bdir" -name libspacewasm_c_api.a -print -quit 2>/dev/null)"
  if [ -z "$a" ]; then echo "  no archive produced"; return 1; fi

  local x="$WORK/x-$tag"; rm -rf "$x"; mkdir -p "$x"
  local obj; obj="$(ar t "$a" | grep '\.o$' | head -1)"
  ( cd "$x" && ar x "$a" "$obj" )
  local cls mach
  cls="$(readelf -h "$x/$obj" | awk -F: '/Class:/ {gsub(/ /,"",$2); print $2}')"
  mach="$(readelf -h "$x/$obj" | sed -n 's/.*Machine: *//p')"
  echo "  target dir : $(basename "$(dirname "$(dirname "$a")")")"
  echo "  ELF        : $cls / $mach"
  echo "$cls" > "$WORK/class-$tag"
}

echo "== A: unpatched (current PR #130 behaviour) =="
build_variant a plain
echo

echo "== B: parent includes proposed/SpacewasmRustTarget.cmake =="
build_variant b derived
echo

CLS_A="$(cat "$WORK/class-a" 2>/dev/null || echo NONE)"
CLS_B="$(cat "$WORK/class-b" 2>/dev/null || echo NONE)"

echo "== verdict =="
echo "A (unpatched) : $CLS_A"
echo "B (derived)   : $CLS_B"
if [ "$CLS_A" = "ELF64" ] && [ "$CLS_B" = "ELF32" ]; then
  echo "WORKS: deriving the triple from CMAKE_SYSTEM_NAME/PROCESSOR turns a silent"
  echo "       host-architecture build into a correct 32-bit one, with no change"
  echo "       to spacewasm_c_api/CMakeLists.txt."
  exit 0
fi
echo "UNEXPECTED: see output above."
exit 1
