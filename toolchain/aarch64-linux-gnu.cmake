# CMake toolchain file for building Qt APPLICATIONS targeting aarch64-linux-gnu.
# Use together with the cross-built Qt in:
#   Qt/5.15.2/build/aarch64-linux-gnu/install
#
# Invoke:
#   cmake -DCMAKE_TOOLCHAIN_FILE=toolchain/aarch64-linux-gnu.cmake \
#         -DCMAKE_PREFIX_PATH=<repo>/Qt/5.15.2/build/aarch64-linux-gnu/install/lib/cmake \
#         <source>
#
# Compiler resolution order:
#   1. the vendored ARM GNU Toolchain committed under tools/ (self-contained)
#   2. aarch64-linux-gnu-gcc/g++ from PATH (distro package or CROSS_PREFIX env)
#
# If the app must build against an embedded board sysroot, set SYSROOT in the
# environment (same value that was used for the Qt build).
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

get_filename_component(_REPO_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(_VENDORED_TC "${_REPO_DIR}/tools/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu")

if(EXISTS "${_VENDORED_TC}/bin/aarch64-none-linux-gnu-g++")
  set(_TC_BIN "${_VENDORED_TC}/bin")
  set(_PREFIX "aarch64-none-linux-gnu-")
  set(CMAKE_C_COMPILER   "${_TC_BIN}/${_PREFIX}gcc")
  set(CMAKE_CXX_COMPILER "${_TC_BIN}/${_PREFIX}g++")
else()
  set(_PREFIX "$ENV{CROSS_PREFIX}")
  if(NOT _PREFIX)
    set(_PREFIX "aarch64-linux-gnu-")
  endif()
  find_program(CMAKE_C_COMPILER   "${_PREFIX}gcc" REQUIRED)
  find_program(CMAKE_CXX_COMPILER "${_PREFIX}g++" REQUIRED)
endif()
find_program(CMAKE_AR     "${_PREFIX}ar"     HINTS "${_TC_BIN}")
find_program(CMAKE_RANLIB "${_PREFIX}ranlib" HINTS "${_TC_BIN}")
find_program(CMAKE_STRIP  "${_PREFIX}strip"  HINTS "${_TC_BIN}")

if(DEFINED ENV{SYSROOT} AND NOT "$ENV{SYSROOT}" STREQUAL "")
  set(CMAKE_SYSROOT "$ENV{SYSROOT}")
endif()

# never pick up host programs/libraries/headers while cross-compiling
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
