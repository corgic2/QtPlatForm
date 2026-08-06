# CMake toolchain file for building Qt APPLICATIONS targeting arm-linux-gnueabihf.
# Use together with the cross-built Qt in:
#   Qt/5.15.2/build/arm-linux-gnueabihf/install
#
# Invoke:
#   cmake -DCMAKE_TOOLCHAIN_FILE=toolchain/arm-linux-gnueabihf.cmake \
#         -DCMAKE_PREFIX_PATH=<repo>/Qt/5.15.2/build/arm-linux-gnueabihf/install \
#         <source>

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)

get_filename_component(_REPO_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(_VENDORED_TC "${_REPO_DIR}/tools/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-linux-gnueabihf")

if(EXISTS "${_VENDORED_TC}/bin/arm-none-linux-gnueabihf-g++")
  set(_TC_BIN "${_VENDORED_TC}/bin")
  set(_PREFIX "arm-none-linux-gnueabihf-")
  set(CMAKE_C_COMPILER   "${_TC_BIN}/${_PREFIX}gcc")
  set(CMAKE_CXX_COMPILER "${_TC_BIN}/${_PREFIX}g++")
else()
  set(_PREFIX "$ENV{CROSS_PREFIX}")
  if(NOT _PREFIX)
    set(_PREFIX "arm-linux-gnueabihf-")
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

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
