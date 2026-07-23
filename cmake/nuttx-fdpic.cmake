# nuttx-fdpic.cmake -- CMake toolchain file for out-of-tree NuttX FDPIC
# modules.
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=/path/to/sdk/cmake/nuttx-fdpic.cmake \
#         -DNUTTX_DIR=/path/to/nuttx ..
#
# Then in CMakeLists.txt:
#
#   nuttx_fdpic_module(hello hello.c)
#
# Same split as nuttx-fdpic.mk: the stock Arm bare-metal toolchain compiles,
# arm-uclinuxfdpiceabi *binutils* links.  No FDPIC GCC is required.

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

if(NOT DEFINED ARM_TOOLCHAIN)
  set(ARM_TOOLCHAIN arm-none-eabi)
endif()

if(NOT DEFINED FDPIC_TOOLCHAIN)
  set(FDPIC_TOOLCHAIN arm-uclinuxfdpiceabi)
endif()

if(NOT DEFINED NUTTX_FDPIC_CPU)
  set(NUTTX_FDPIC_CPU cortex-m33)
endif()

set(CMAKE_C_COMPILER   ${ARM_TOOLCHAIN}-gcc)
set(CMAKE_CXX_COMPILER ${ARM_TOOLCHAIN}-g++)
set(CMAKE_READELF      ${FDPIC_TOOLCHAIN}-readelf)
set(NUTTX_FDPIC_LD     ${FDPIC_TOOLCHAIN}-ld)

# The compiler cannot link a normal test executable: modules are shared
# objects with unresolved imports by design.

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(NUTTX_FDPIC_SDK ${CMAKE_CURRENT_LIST_DIR}/..)

# See nuttx-fdpic.mk for why each of these is here.  In short: -fPIC because
# -mfdpic does not imply it on the bare-metal target and TEXTREL cannot work
# from flash; -fno-builtin so libc calls are imported rather than open-coded;
# __STDC_NO_ATOMICS__ to steer NuttX's <nuttx/atomic.h> away from redefining
# <stdatomic.h>'s macros.

set(NUTTX_FDPIC_COMMON
    -mcpu=${NUTTX_FDPIC_CPU} -mthumb -mfdpic -fPIC
    -fno-builtin -Wa,--noexecstack -D__STDC_NO_ATOMICS__ -D__NuttX__)

set(NUTTX_FDPIC_CFLAGS ${NUTTX_FDPIC_COMMON})

# -fno-use-cxa-atexit is not optional: the default routes destructors
# through __dso_handle, which comes from crtbegin and a module does not link
# it, so the link fails outright.  It is also what puts destructors in
# .fini_array, which is what the loader walks.

set(NUTTX_FDPIC_CXXFLAGS ${NUTTX_FDPIC_COMMON}
    -fno-exceptions -fno-rtti -fno-use-cxa-atexit)

# Link rules.
#
# CMake would drive the link with the compiler, which cannot do it: the
# bare-metal ld carries only the `armelf` emulation.  Both language link
# rules are therefore replaced with a direct call to the FDPIC linker.
#
# -shared preserves R_ARM_FUNCDESC_VALUE for imports; -z now keeps them in
# DT_REL rather than the lazy table.

set(NUTTX_FDPIC_LDFLAGS "-m armelf_linux_fdpiceabi -shared -z now")

set(CMAKE_C_LINK_EXECUTABLE
    "${NUTTX_FDPIC_LD} ${NUTTX_FDPIC_LDFLAGS} <LINK_FLAGS> <OBJECTS> \
-o <TARGET> <LINK_LIBRARIES>")

set(CMAKE_CXX_LINK_EXECUTABLE
    "${NUTTX_FDPIC_LD} ${NUTTX_FDPIC_LDFLAGS} <LINK_FLAGS> <OBJECTS> \
-o <TARGET> <LINK_LIBRARIES>")

function(nuttx_fdpic_module name)
  if(NOT DEFINED NUTTX_DIR)
    message(FATAL_ERROR "Set NUTTX_DIR to a configured, built NuttX tree")
  endif()

  set(entry main)
  if(DEFINED NUTTX_FDPIC_ENTRY)
    set(entry ${NUTTX_FDPIC_ENTRY})
  endif()

  add_executable(${name} ${ARGN})
  set_target_properties(${name} PROPERTIES
                        OUTPUT_NAME "${name}.fdpic" SUFFIX "")
  target_compile_options(${name} PRIVATE
      "$<$<COMPILE_LANGUAGE:C>:${NUTTX_FDPIC_CFLAGS}>"
      "$<$<COMPILE_LANGUAGE:CXX>:${NUTTX_FDPIC_CXXFLAGS}>")
  target_include_directories(${name} PRIVATE
      "$<$<COMPILE_LANGUAGE:CXX>:${NUTTX_DIR}/include/cxx>"
      ${NUTTX_DIR}/include)

  # Bare ld flags, not -Wl, -- nothing routes through a compiler driver here

  target_link_options(${name} PRIVATE -e ${entry})

  # Verify as part of the build, not as an afterthought: an import the
  # firmware does not export links cleanly and only fails on the target.

  add_custom_command(
    TARGET ${name} POST_BUILD
    COMMAND ${NUTTX_FDPIC_SDK}/tools/nuttx-exports ${NUTTX_DIR}
            > ${CMAKE_CURRENT_BINARY_DIR}/.nuttx-exports
    COMMAND ${CMAKE_COMMAND} -E env READELF=${CMAKE_READELF}
            ${NUTTX_FDPIC_SDK}/tools/fdpic-verify
            $<TARGET_FILE:${name}>
            ${CMAKE_CURRENT_BINARY_DIR}/.nuttx-exports
    VERBATIM)
endfunction()
