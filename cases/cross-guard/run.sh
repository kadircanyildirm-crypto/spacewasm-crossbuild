#!/usr/bin/env bash
#
# Case: when a real F' cross-compilation toolchain file is used, does
#       spacewasm_c_api build for the target or silently for the host — and
#       does a three-line guard turn that into a configure error?
#
# F' ships its cross toolchains in nasa/fprime under cmake/toolchain/.
# aarch64-linux.cmake sets CMAKE_SYSTEM_PROCESSOR and includes
# helpers/arm-linux-base.cmake, which sets CMAKE_SYSTEM_NAME — so CMake enters
# cross-compiling mode and CMAKE_CROSSCOMPILING is TRUE. arm-hf-linux.cmake,
# arm-sf-linux.cmake and raspberrypi.cmake all include the same helper.
#
# Three variants, same commit and same toolchain file:
#   A) upstream as-is, SPACEWASM_TARGET unset  -> expect a host archive, exit 0
#   B) with the guard, SPACEWASM_TARGET unset  -> expect a configure error
#   C) with the guard, SPACEWASM_TARGET set    -> expect an AArch64 archive
#
# Context: nasa/spacewasm#112.
#
#   docker run --rm -v "$PWD:/repo" spacewasm-dev bash /repo/cases/cross-guard/run.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/proposed/SpacewasmCrossGuard.cmake"

UPSTREAM="https://github.com/nasa/spacewasm.git"
# Pinned to exact commits, not moving refs: refs/pull/130/head and fprime's
# devel branch both move, which would silently change what this case measures.
PINNED_SHA="ca42f9c255d083a7fdaabfcb33118846996b40b1"   # nasa/spacewasm#130, 2026-07-28
FPRIME_SHA="307acd782f6fb5a686babd4ef4f07085801ac575"   # nasa/fprime devel, 2026-07-28
FPRIME_RAW="https://raw.githubusercontent.com/nasa/fprime/${FPRIME_SHA}/cmake/toolchain"

WORK="${WORK:-/tmp/case-cross-guard}"
SRC="${SPACEWASM_SRC:-$WORK/spacewasm}"
TC="$WORK/fprime-toolchain"

[ -f "$GUARD" ] || { echo "FATAL: missing $GUARD"; exit 2; }

echo "== environment =="
cmake --version | head -1
echo "rustc host: $(rustc -vV | grep '^host:' | cut -d' ' -f2)"
for t in gcc g++ as ar; do
  printf 'aarch64-linux-gnu-%-3s : %s\n' "$t" "$(command -v aarch64-linux-gnu-$t || echo MISSING)"
done
echo

echo "== F' toolchain files (nasa/fprime@${FPRIME_SHA:0:7}) =="
mkdir -p "$TC/helpers"
for f in aarch64-linux.cmake helpers/arm-linux-base.cmake; do
  if [ ! -f "$TC/$f" ]; then
    wget -q "$FPRIME_RAW/$f" -O "$TC/$f" || { echo "FATAL: could not fetch $f"; exit 2; }
  fi
done
echo "the two lines that put CMake into cross-compiling mode:"
grep -n 'CMAKE_SYSTEM_PROCESSOR\|include(' "$TC/aarch64-linux.cmake" | sed 's/^/  aarch64-linux.cmake:/'
grep -n '^set(CMAKE_SYSTEM_NAME' "$TC/helpers/arm-linux-base.cmake" | sed 's/^/  arm-linux-base.cmake:/'
echo

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
cp "$CAPI/CMakeLists.txt" "$WORK/CMakeLists.pristine"
echo

# Report the architecture of the archive a build directory produced.
report_arch() {
  local b="$1" a x o
  a="$(find "$b" -name libspacewasm_c_api.a -print -quit 2>/dev/null)"
  if [ -z "$a" ]; then echo "  archive: (none)"; return 1; fi
  x="$WORK/x"; rm -rf "$x"; mkdir -p "$x"
  o="$(ar t "$a" | grep '\.o$' | head -1)"
  ( cd "$x" && ar x "$a" "$o" )
  echo "  cargo target dir : $(basename "$(dirname "$(dirname "$a")")")"
  echo "  ELF              : $(readelf -h "$x/$o" | awk -F: '/Class:/ {gsub(/ /,"",$2); print $2}') / $(readelf -h "$x/$o" | sed -n 's/.*Machine: *//p')"
  readelf -h "$x/$o" | sed -n 's/.*Machine: *//p' > "$WORK/machine-$(basename "$b")"
}

COMMON=(-DCMAKE_BUILD_TYPE=Debug
        -DCMAKE_TOOLCHAIN_FILE="$TC/aarch64-linux.cmake"
        -DARM_TOOLS_PATH=/usr)

echo "== A: upstream as-is, F' aarch64 toolchain, SPACEWASM_TARGET unset =="
cp "$WORK/CMakeLists.pristine" "$CAPI/CMakeLists.txt"
rm -rf "$WORK/bA"
cmake -S "$CAPI" -B "$WORK/bA" "${COMMON[@]}" > "$WORK/logA" 2>&1
A_CFG=$?
echo "  configure exit: $A_CFG"
[ "$A_CFG" -ne 0 ] && { echo "  unexpected — see $WORK/logA"; tail -5 "$WORK/logA"; exit 2; }
cmake --build "$WORK/bA" -j "${JOBS:-4}" > "$WORK/logAb" 2>&1
echo "  build exit: $?"
report_arch "$WORK/bA"
echo

echo "== B: same, with proposed/SpacewasmCrossGuard.cmake applied =="
cp "$WORK/CMakeLists.pristine" "$CAPI/CMakeLists.txt"
# The guard has to run before the existing `if(SPACEWASM_TARGET STREQUAL "")`
# block fills in the host triple, so insert it right after the cache variable.
sed -i "/^set(SPACEWASM_TARGET \"\" CACHE STRING/r $GUARD" "$CAPI/CMakeLists.txt"
rm -rf "$WORK/bB"
cmake -S "$CAPI" -B "$WORK/bB" "${COMMON[@]}" > "$WORK/logB" 2>&1
B_CFG=$?
echo "  configure exit: $B_CFG"
grep -A1 "CMake Error" "$WORK/logB" | head -3 | sed 's/^/  /'
echo

echo "== C: guard applied, SPACEWASM_TARGET given explicitly =="
rm -rf "$WORK/bC"
cmake -S "$CAPI" -B "$WORK/bC" "${COMMON[@]}" \
      -DSPACEWASM_TARGET=aarch64-unknown-linux-gnu > "$WORK/logC" 2>&1
C_CFG=$?
echo "  configure exit: $C_CFG"
[ "$C_CFG" -ne 0 ] && { echo "  unexpected — see $WORK/logC"; tail -5 "$WORK/logC"; exit 2; }
cmake --build "$WORK/bC" -j "${JOBS:-4}" > "$WORK/logCb" 2>&1
echo "  build exit: $?"
report_arch "$WORK/bC"
echo

MACH_A="$(cat "$WORK/machine-bA" 2>/dev/null || echo NONE)"
MACH_C="$(cat "$WORK/machine-bC" 2>/dev/null || echo NONE)"

echo "== verdict =="
echo "A (as-is, target unset)  : configure=$A_CFG  archive=$MACH_A"
echo "B (guard, target unset)  : configure=$B_CFG"
echo "C (guard, target given)  : configure=$C_CFG  archive=$MACH_C"
if [ "$A_CFG" -eq 0 ] && [ "$MACH_A" != "${MACH_A#Advanced Micro Devices}" ] \
   && [ "$B_CFG" -ne 0 ] \
   && [ "$C_CFG" -eq 0 ] && [ "$MACH_C" != "${MACH_C#AArch64}" ]; then
  echo
  echo "CONFIRMED: with F's own aarch64 toolchain file and no explicit triple,"
  echo "           the build succeeds and produces a host x86-64 archive. The"
  echo "           guard turns that into a configure error without changing what"
  echo "           an explicit triple does."
  exit 0
fi
echo "UNEXPECTED: see output above."
exit 1
