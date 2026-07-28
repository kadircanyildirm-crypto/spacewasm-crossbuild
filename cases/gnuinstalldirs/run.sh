#!/usr/bin/env bash
#
# Case: does spacewasm_c_api's documented add_subdirectory() integration
#       configure successfully?
#
# Hypothesis: it fails unless the consuming project has already called
#             include(GNUInstallDirs), because CMAKE_INSTALL_INCLUDEDIR and
#             CMAKE_INSTALL_LIBDIR are defined only by that module.
#
# Controlled variable: the single include(GNUInstallDirs) line in the parent.
#
# Run inside the dev image:
#   docker run --rm -v "$PWD:/repo" spacewasm-dev bash /repo/cases/gnuinstalldirs/run.sh

set -uo pipefail

UPSTREAM="https://github.com/nasa/spacewasm.git"
PR_REF="refs/pull/130/head"
PINNED_SHA="a1ef2caff5e79eb3249d26531dafc93dbcd91bcc"   # nasa/spacewasm#130 head, 2026-07-27

WORK="${WORK:-/tmp/case-gnuinstalldirs}"
SRC="${SPACEWASM_SRC:-$WORK/spacewasm}"

echo "== environment =="
cmake --version | head -1
gcc --version | head -1
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
if [ "$ACTUAL_SHA" != "$PINNED_SHA" ]; then
  echo "NOTE: upstream ref moved since this case was written."
  echo "      The observation below may no longer apply."
fi

CAPI="$SRC/crates/spacewasm_c_api"
if [ ! -f "$CAPI/CMakeLists.txt" ]; then
  echo "FATAL: $CAPI/CMakeLists.txt not present — wrong ref?"; exit 2
fi
echo

make_parent() {
  # $1 = dir, $2 = "with" | "without"
  local dir="$1" mode="$2"
  rm -rf "$dir"; mkdir -p "$dir"
  {
    echo 'cmake_minimum_required(VERSION 3.12)'
    echo 'project(parent_app C)'
    [ "$mode" = "with" ] && echo 'include(GNUInstallDirs)'
    echo "add_subdirectory($CAPI spacewasm_c_api)"
    echo 'add_executable(app main.c)'
    echo 'target_link_libraries(app PRIVATE spacewasm)'
  } > "$dir/CMakeLists.txt"
  echo 'int main(void) { return 0; }' > "$dir/main.c"
}

echo "== A: parent WITHOUT include(GNUInstallDirs) =="
echo "   (this is the example from crates/spacewasm_c_api/README.md)"
make_parent "$WORK/parent-a" without
cmake -S "$WORK/parent-a" -B "$WORK/build-a" -DCMAKE_BUILD_TYPE=Debug 2>&1 | tail -8
A_EXIT=${PIPESTATUS[0]}
echo "A_EXIT=$A_EXIT"
echo

echo "== B: same parent WITH include(GNUInstallDirs) =="
make_parent "$WORK/parent-b" with
cmake -S "$WORK/parent-b" -B "$WORK/build-b" -DCMAKE_BUILD_TYPE=Debug 2>&1 | tail -4
B_EXIT=${PIPESTATUS[0]}
echo "B_EXIT=$B_EXIT"
echo

echo "== verdict =="
if [ "$A_EXIT" -ne 0 ] && [ "$B_EXIT" -eq 0 ]; then
  echo "REPRODUCED: configure fails only when the parent omits include(GNUInstallDirs)."
  echo "Suggested fix: add 'include(GNUInstallDirs)' near the top of"
  echo "               crates/spacewasm_c_api/CMakeLists.txt"
  exit 0
elif [ "$A_EXIT" -eq 0 ] && [ "$B_EXIT" -eq 0 ]; then
  echo "NOT REPRODUCED: both configure cleanly — likely fixed upstream."
  exit 1
else
  echo "INCONCLUSIVE: A_EXIT=$A_EXIT B_EXIT=$B_EXIT — unexpected combination."
  exit 1
fi
