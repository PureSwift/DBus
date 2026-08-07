##
##  CMakeLists.txt
##  DBus
##
##  Builds `libdbus-swift.so.0` — the subset of the libdbus-1 C ABI
##  declared in `Sources/CDBusABI/include/dbus/dbus.h`, implemented in
##  Swift.
##
##  SwiftPM drives development and the test suites; CMake exists because
##  soname, symbol versioning and install name are not expressible in
##  `Package.swift`, and because the C ABI is only worth shipping as an
##  installable shared object.
##
##  The Ninja generator is required — CMake does not support the Swift
##  language with Makefiles.
##
##  Usage:
##      cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
##      cmake --build build
##      cmake --build build --target check-exports
##      cmake --build build --target check-abi
##      cmake --install build --prefix /usr/local
##

cmake_minimum_required(VERSION 3.26)

if(NOT CMAKE_GENERATOR MATCHES "Ninja")
    message(FATAL_ERROR
        "The Ninja generator is required for Swift targets; "
        "re-run with -G Ninja.")
endif()

project(DBusABI
    VERSION 0.1.0
    DESCRIPTION "Swift implementation of the libdbus-1 C ABI"
    LANGUAGES C Swift)

# ---------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------

option(DBUS_ABI_SHARED
    "Build the shared library (off builds the static archives only)" ON)

option(DBUS_ABI_STATIC_STDLIB
    "Statically link the Swift runtime into the shared library" OFF)

option(DBUS_ABI_INSTALL_HEADERS
    "Install dbus.h under <prefix>/include/dbus-swift/dbus" ON)

# The soname is this library's own, not libdbus-1's. It implements a
# subset of that ABI but is not a drop-in replacement for the whole of
# it, so it must not claim libdbus-1's soname: a program linked against
# the real thing would otherwise load this and fail at the first symbol
# outside the subset.
set(DBUS_SWIFT_SOVERSION 0)
set(DBUS_SWIFT_VERSION 0.1.0)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

include(GNUInstallDirs)

# ---------------------------------------------------------------------
# Socket — the transport dependency
# ---------------------------------------------------------------------
#
# `Sources/DBus` imports `Socket` and `SystemPackage`, which SwiftPM
# resolves from Package.swift. CMake has no package resolution, so the
# checkout SwiftPM already made is reused: configure once with
# `swift build` having been run, or point DBUS_SOCKET_SOURCE_DIR at a
# checkout.

set(DBUS_SOCKET_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.build/checkouts/Socket"
    CACHE PATH "PureSwift/Socket checkout")
set(DBUS_SYSTEM_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.build/checkouts/swift-system"
    CACHE PATH "apple/swift-system checkout")

foreach(dependency
        "${DBUS_SOCKET_SOURCE_DIR}"
        "${DBUS_SYSTEM_SOURCE_DIR}")
    if(NOT EXISTS "${dependency}")
        message(FATAL_ERROR
            "${dependency} not found. Run `swift build` first so SwiftPM "
            "resolves the dependencies, or set DBUS_SOCKET_SOURCE_DIR and "
            "DBUS_SYSTEM_SOURCE_DIR.")
    endif()
endforeach()

file(GLOB CSYSTEM_SOURCES CONFIGURE_DEPENDS
    "${DBUS_SYSTEM_SOURCE_DIR}/Sources/CSystem/*.c")

add_library(CSystem STATIC ${CSYSTEM_SOURCES})
target_include_directories(CSystem PUBLIC
    "${DBUS_SYSTEM_SOURCE_DIR}/Sources/CSystem/include")

file(GLOB_RECURSE SYSTEM_PACKAGE_SOURCES CONFIGURE_DEPENDS
    "${DBUS_SYSTEM_SOURCE_DIR}/Sources/System/*.swift")

add_library(SystemPackage STATIC ${SYSTEM_PACKAGE_SOURCES})
set_target_properties(SystemPackage PROPERTIES Swift_MODULE_NAME SystemPackage)
target_compile_definitions(SystemPackage PRIVATE SYSTEM_PACKAGE)
target_link_libraries(SystemPackage PUBLIC CSystem)

file(GLOB CSOCKET_SOURCES CONFIGURE_DEPENDS
    "${DBUS_SOCKET_SOURCE_DIR}/Sources/CSocket/*.c")

add_library(CSocket STATIC ${CSOCKET_SOURCES})
target_include_directories(CSocket PUBLIC
    "${DBUS_SOCKET_SOURCE_DIR}/Sources/CSocket/include")

file(GLOB_RECURSE SOCKET_SOURCES CONFIGURE_DEPENDS
    "${DBUS_SOCKET_SOURCE_DIR}/Sources/Socket/*.swift")

add_library(Socket STATIC ${SOCKET_SOURCES})
set_target_properties(Socket PROPERTIES Swift_MODULE_NAME Socket)
target_link_libraries(Socket PUBLIC SystemPackage CSocket)

# ---------------------------------------------------------------------
# CDBusABI — the C surface
# ---------------------------------------------------------------------
#
# The header plus the four variadic entry points, which Swift cannot
# declare. They contain no protocol logic: each walks a `va_list` and
# calls the Swift iterator entry points.

add_library(CDBusABI STATIC
    Sources/CDBusABI/varargs.c)

target_include_directories(CDBusABI PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/CDBusABI/include")

# ---------------------------------------------------------------------
# DBus — the Swift implementation
# ---------------------------------------------------------------------

file(GLOB_RECURSE DBUS_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/DBus/*.swift")

add_library(DBus STATIC ${DBUS_SOURCES})
set_target_properties(DBus PROPERTIES Swift_MODULE_NAME DBus)
target_link_libraries(DBus PUBLIC Socket)

# ---------------------------------------------------------------------
# DBusABI — the Swift implementations of the C entry points
# ---------------------------------------------------------------------

file(GLOB DBUS_ABI_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/Sources/DBusABI/*.swift")

add_library(DBusABI STATIC ${DBUS_ABI_SOURCES})
set_target_properties(DBusABI PROPERTIES Swift_MODULE_NAME DBusABI)
target_link_libraries(DBusABI PUBLIC DBus CDBusABI)

# ---------------------------------------------------------------------
# libdbus-swift.so.0 — the installable artifact
# ---------------------------------------------------------------------

if(DBUS_ABI_SHARED)

    set(DBUS_SWIFT_VERSION_SCRIPT
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/libdbus-swift.map")

    # A shared library needs at least one of its own objects; the Swift
    # and C implementations arrive through --whole-archive below.
    add_library(dbus-swift SHARED cmake/empty.swift)

    set_target_properties(dbus-swift PROPERTIES
        OUTPUT_NAME dbus-swift
        SOVERSION ${DBUS_SWIFT_SOVERSION}
        VERSION ${DBUS_SWIFT_VERSION}
        # swiftc must drive the link, so that the Swift runtime is recorded
        # as a dependency of the library; CMake would otherwise pick C from
        # the lone placeholder source and produce an object with unresolved
        # stdlib symbols. `dbus-swift` is not a valid Swift identifier, so
        # the vestigial module is named explicitly.
        LINKER_LANGUAGE Swift
        Swift_MODULE_NAME dbus_swift)

    # Every entry point is referenced only from outside, so the archives
    # holding them must be linked whole or the linker drops the lot.
    #
    # The archives are named explicitly through `LINKER:` rather than via
    # `$<LINK_LIBRARY:WHOLE_ARCHIVE>`: the link is driven by swiftc, whose
    # driver silently discards bare `.a` arguments, so the result would be
    # a shared library with no symbols in it. `add_dependencies` below
    # restores the build ordering that naming targets directly would give.
    #
    # The engine archives that follow are named the same way, and for the
    # same reason, even though they are linked normally rather than whole:
    # `target_link_libraries` would hand swiftc bare `.a` paths, and the
    # result is a library missing every symbol they define.
    target_link_options(dbus-swift PRIVATE
        "LINKER:--whole-archive"
        "LINKER:$<TARGET_FILE:DBusABI>"
        "LINKER:$<TARGET_FILE:CDBusABI>"
        "LINKER:--no-whole-archive"
        # Ordered as the linker resolves them: each may only depend on the
        # archives that follow it.
        "LINKER:$<TARGET_FILE:DBus>"
        "LINKER:$<TARGET_FILE:Socket>"
        "LINKER:$<TARGET_FILE:SystemPackage>"
        "LINKER:$<TARGET_FILE:CSocket>"
        "LINKER:$<TARGET_FILE:CSystem>")

    add_dependencies(dbus-swift
        DBusABI CDBusABI DBus Socket SystemPackage CSocket CSystem)

    # `add_dependencies` only orders the build. The archives above reach the
    # link as opaque `LINKER:` strings, so without naming them here as link
    # inputs the library is not relinked when one of them changes, and the
    # build silently keeps shipping the previous object code.
    set_target_properties(dbus-swift PROPERTIES
        LINK_DEPENDS "$<TARGET_FILE:DBusABI>;$<TARGET_FILE:CDBusABI>;$<TARGET_FILE:DBus>;$<TARGET_FILE:Socket>;$<TARGET_FILE:SystemPackage>;$<TARGET_FILE:CSocket>;$<TARGET_FILE:CSystem>;${DBUS_SWIFT_VERSION_SCRIPT}")

    # Pin the export list, so the ABI surface is asserted rather than
    # incidental.
    target_link_options(dbus-swift PRIVATE
        "LINKER:--version-script=${DBUS_SWIFT_VERSION_SCRIPT}")

    if(DBUS_ABI_STATIC_STDLIB)
        # Any process loading this library otherwise pulls in libswiftCore;
        # static linking trades size for isolation.
        target_link_options(dbus-swift PRIVATE "-static-stdlib")
    endif()

    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/dbus-swift.pc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/dbus-swift.pc"
        @ONLY)

    install(TARGETS dbus-swift
        LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}")

    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/dbus-swift.pc"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig")
endif()

if(DBUS_ABI_INSTALL_HEADERS)
    # Under `dbus-swift/dbus/` rather than `dbus/`, so installing this
    # alongside the real libdbus-1 development headers cannot shadow them.
    install(FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/CDBusABI/include/dbus/dbus.h"
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/dbus-swift/dbus")
endif()

# ---------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------

if(DBUS_ABI_SHARED)

    # `check-exports` diffs the built library's dynamic symbol table
    # against cmake/symbols.txt. Both a missing and an extra symbol fail,
    # so the export surface cannot drift silently.
    add_custom_target(check-exports
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/Scripts/check-exports.sh"
                "$<TARGET_FILE:dbus-swift>"
                "${CMAKE_CURRENT_SOURCE_DIR}/cmake/symbols.txt"
        DEPENDS dbus-swift
        COMMENT "Checking exported symbols against cmake/symbols.txt"
        VERBATIM)

    # `check-abi` builds and runs a C program against the shared library.
    # It is the only thing that can exercise the variadic entry points —
    # Swift cannot call a C variadic function, so the SwiftPM test suite
    # reaches everything except those.
    # Links only the shared library, exactly as a consumer would: linking the
    # static archives too would resolve some entry points from a second copy
    # and prove nothing about the installed artifact.
    add_executable(dbus-abi-smoke Tests/CABI/smoke.c)
    target_include_directories(dbus-abi-smoke PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/Sources/CDBusABI/include")
    target_link_libraries(dbus-abi-smoke PRIVATE dbus-swift)

    add_custom_target(check-abi
        COMMAND dbus-abi-smoke
        DEPENDS dbus-abi-smoke
        COMMENT "Running the C ABI smoke test"
        VERBATIM)
endif()
