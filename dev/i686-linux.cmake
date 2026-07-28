# Minimal cross-compilation toolchain file: 64-bit host -> 32-bit i686 Linux.
# Uses gcc-multilib (-m32) so no separate sysroot download is needed.
#
# Purpose: probe whether spacewasm_c_api's CMakeLists forwards CMake's
# cross-compilation intent (CMAKE_SYSTEM_PROCESSOR, compiler, sysroot) to the
# cargo invocation. See cases/cross-triple/ and nasa/spacewasm#112.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR i686)

set(CMAKE_C_COMPILER gcc)
set(CMAKE_CXX_COMPILER g++)

set(CMAKE_C_FLAGS_INIT "-m32")
set(CMAKE_CXX_FLAGS_INIT "-m32")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-m32")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-m32")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BEFORE)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
