# Refuse to substitute the host triple when CMake is already cross-compiling.
#
# Proposed on nasa/spacewasm#112. This derives nothing: specifying
# SPACEWASM_TARGET by hand stays the contract, exactly as in Wasmtime's c-api.
# It only declines to fall back to the rustc host triple, silently and with a
# zero exit code, when a toolchain file has put CMake into cross-compiling mode.
#
# Insert after `set(SPACEWASM_TARGET "" CACHE STRING ...)` and before the
# existing `if(SPACEWASM_TARGET STREQUAL "")` block that fills in the host.
#
# Known limits:
#  - A toolchain file that sets CMAKE_SYSTEM_PROCESSOR without CMAKE_SYSTEM_NAME
#    leaves CMAKE_CROSSCOMPILING false, and CMake resets the processor to the
#    host value, so no signal survives for this to read.
#  - A toolchain file that deliberately targets the host now has to say so.
if(CMAKE_CROSSCOMPILING AND SPACEWASM_TARGET STREQUAL "")
  message(FATAL_ERROR "SPACEWASM_TARGET must be set explicitly when cross-compiling")
endif()
