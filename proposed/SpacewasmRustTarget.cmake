# Derive SPACEWASM_TARGET (a Rust target triple) from CMake's own
# cross-compilation variables, so a consuming project does not have to keep a
# hand-written triple in sync with its toolchain file.
#
# Drop-in: include() this BEFORE add_subdirectory(<...>/spacewasm_c_api).
# It sets SPACEWASM_TARGET as a cache variable, so the `if(SPACEWASM_TARGET
# STREQUAL "")` branch in spacewasm_c_api/CMakeLists.txt leaves it alone.
#
# Context: nasa/spacewasm#112 — "how we can have CMake builds pass their
# linker/sysroots over to cargo".
#
# Scope note: this covers the triple only. Forwarding the C toolchain
# (CC_<triple>, AR_<triple>, CFLAGS_<triple>, CARGO_TARGET_<TRIPLE>_LINKER) has
# to happen on the cargo invocation itself, which lives in the ExternalProject
# BUILD_COMMAND upstream — see README for the proposed change.

if(DEFINED SPACEWASM_TARGET AND NOT SPACEWASM_TARGET STREQUAL "")
  message(STATUS "spacewasm: SPACEWASM_TARGET already set to '${SPACEWASM_TARGET}', not deriving")
  return()
endif()

set(_sw_triple "")
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _sw_proc)

if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  if(_sw_proc MATCHES "^(i[3-6]86|x86)$")
    set(_sw_triple "i686-unknown-linux-gnu")
  elseif(_sw_proc MATCHES "^(x86_64|amd64)$")
    set(_sw_triple "x86_64-unknown-linux-gnu")
  elseif(_sw_proc MATCHES "^(aarch64|arm64)$")
    set(_sw_triple "aarch64-unknown-linux-gnu")
  elseif(_sw_proc MATCHES "^armv7")
    set(_sw_triple "armv7-unknown-linux-gnueabihf")
  endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  if(_sw_proc MATCHES "^(aarch64|arm64)$")
    set(_sw_triple "aarch64-apple-darwin")
  elseif(_sw_proc MATCHES "^x86_64$")
    set(_sw_triple "x86_64-apple-darwin")
  endif()
endif()

if(_sw_triple STREQUAL "")
  if(CMAKE_CROSSCOMPILING)
    # Refusing here is the point: the current default is the rustc *host*
    # triple, so an unmapped cross build silently produces a host-architecture
    # archive and only fails much later, at link time.
    message(FATAL_ERROR
      "spacewasm: cross-compiling for ${CMAKE_SYSTEM_NAME}/${CMAKE_SYSTEM_PROCESSOR} "
      "but no Rust target triple is known for that combination. "
      "Set -DSPACEWASM_TARGET=<triple> explicitly.")
  endif()
  message(STATUS "spacewasm: native build, leaving SPACEWASM_TARGET to the rustc host triple")
  return()
endif()

set(SPACEWASM_TARGET "${_sw_triple}" CACHE STRING "Target triple for Rust compiler" FORCE)
message(STATUS "spacewasm: derived SPACEWASM_TARGET=${SPACEWASM_TARGET} "
               "from ${CMAKE_SYSTEM_NAME}/${CMAKE_SYSTEM_PROCESSOR}")
