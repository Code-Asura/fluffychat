# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(fluffychat LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "fluffychat")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# webcrypto requires NASM on Windows for BoringSSL assembly files.
if(NOT DEFINED CMAKE_ASM_NASM_COMPILER OR CMAKE_ASM_NASM_COMPILER STREQUAL "")
  set(_SECMESS_NASM_HINTS
    "$ENV{NASM}"
    "$ENV{LOCALAPPDATA}/bin/NASM/nasm.exe"
    "$ENV{LOCALAPPDATA}/vcpkg/downloads/tools/nasm/nasm-2.16.03/nasm.exe"
    "C:/Program Files/NASM/nasm.exe"
  )
  foreach(_nasm_exe IN LISTS _SECMESS_NASM_HINTS)
    if(_nasm_exe AND EXISTS "${_nasm_exe}")
      set(CMAKE_ASM_NASM_COMPILER "${_nasm_exe}" CACHE FILEPATH "NASM compiler path" FORCE)
      message(STATUS "Using NASM compiler: ${CMAKE_ASM_NASM_COMPILER}")
      break()
    endif()
  endforeach()
endif()

# sqlcipher_flutter_libs requires OpenSSL on Windows. Try to auto-detect a
# usable installation before plugin CMake files call find_package(OpenSSL).
if(NOT DEFINED OPENSSL_ROOT_DIR OR OPENSSL_ROOT_DIR STREQUAL "")
  set(_SECMESS_OPENSSL_HINTS
    "$ENV{OPENSSL_ROOT_DIR}"
    "C:/Program Files/PostgreSQL/16"
    "C:/Program Files/OpenSSL-Win64"
    "C:/OpenSSL-Win64"
    "C:/vcpkg/installed/x64-windows"
  )
  foreach(_openssl_root IN LISTS _SECMESS_OPENSSL_HINTS)
    if(
      _openssl_root
      AND EXISTS "${_openssl_root}/include/openssl/opensslv.h"
      AND EXISTS "${_openssl_root}/lib/libcrypto.lib"
    )
      set(OPENSSL_ROOT_DIR "${_openssl_root}" CACHE PATH "OpenSSL root path" FORCE)
      set(OPENSSL_INCLUDE_DIR "${_openssl_root}/include" CACHE PATH "OpenSSL include path" FORCE)
      set(OPENSSL_CRYPTO_LIBRARY "${_openssl_root}/lib/libcrypto.lib" CACHE FILEPATH "OpenSSL crypto library" FORCE)
      message(STATUS "Using OpenSSL from ${OPENSSL_ROOT_DIR}")
      break()
    endif()
  endforeach()
endif()

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
# Always install into the local build bundle to avoid requiring admin rights
# when IDE/CMake presets set CMAKE_INSTALL_PREFIX to Program Files.
set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
