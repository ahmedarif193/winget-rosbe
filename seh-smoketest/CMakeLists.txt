cmake_minimum_required(VERSION 3.20)

# This project is configured once per (backend, optimization level) by
# pseh_harness.py.  Every build directory is therefore a normal incremental
# Ninja tree: running `ninja` there rebuilds only inputs that changed.
project(pseh_conformance C ASM)

foreach(required_var
        PSEH_PROFILE_NAME
        PSEH_HARNESS_ROOT)
    if(NOT DEFINED ${required_var} OR "${${required_var}}" STREQUAL "")
        message(FATAL_ERROR "${required_var} must be supplied by pseh_harness.py")
    endif()
endforeach()

file(GLOB PSEH_MS_TEST_SOURCES CONFIGURE_DEPENDS
    "${PSEH_HARNESS_ROOT}/vendor/ms_seh/seh[0-9][0-9][0-9][0-9].c")
file(GLOB PSEH_STRESS_TEST_SOURCES CONFIGURE_DEPENDS
    "${PSEH_HARNESS_ROOT}/stress/stress[0-9][0-9][0-9][0-9].c")
set(PSEH_TEST_SOURCES ${PSEH_MS_TEST_SOURCES} ${PSEH_STRESS_TEST_SOURCES})
if(NOT PSEH_TEST_SOURCES)
    message(FATAL_ERROR "No SEH tests found below ${PSEH_HARNESS_ROOT}")
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

set(PSEH_INCLUDE_DIRS
    "${PSEH_HARNESS_ROOT}/pseh/include"
    "${PSEH_HARNESS_ROOT}/vendor/ms_seh"
    "${PSEH_HARNESS_ROOT}/stress"
    "${PSEH_HARNESS_ROOT}/runner")

# Read the cache value even for profiles without a support library, avoiding a
# misleading "unused variable" warning in those otherwise-valid trees.
set(_PSEH_LIB_OPTIONS ${PSEH_LIB_OPTIONS})

add_library(pseh_runner OBJECT
    "${PSEH_HARNESS_ROOT}/runner/runner_main.c")
target_include_directories(pseh_runner PRIVATE ${PSEH_INCLUDE_DIRS})
target_compile_options(pseh_runner PRIVATE
    ${PSEH_PROFILE_OPTIONS}
    ${PSEH_OPT_OPTIONS})

if(PSEH_SUPPORT_SOURCES)
    add_library(pseh_support STATIC ${PSEH_SUPPORT_SOURCES})
    target_include_directories(pseh_support PRIVATE ${PSEH_INCLUDE_DIRS})
    target_compile_options(pseh_support PRIVATE
        ${PSEH_PROFILE_OPTIONS}
        ${_PSEH_LIB_OPTIONS}
        # pseh3.c includes "pseh3.h" directly.  -iquote finds that private
        # header without letting ReactOS's excpt.h shadow mingw-w64's
        # <excpt.h> for angle-bracket includes.
        -iquote "${PSEH_HARNESS_ROOT}/pseh/include/pseh")

    foreach(source IN LISTS PSEH_SUPPORT_SOURCES)
        if(source MATCHES "\\.S$")
            set_source_files_properties("${source}" PROPERTIES
                COMPILE_DEFINITIONS __ASM__)
        endif()
    endforeach()
endif()

if(PSEH_NEEDS_PLUGIN)
    if(NOT PSEH_HOST_CXX)
        message(FATAL_ERROR "PSEH_HOST_CXX is required for the GCC SEH plugin")
    endif()

    execute_process(
        COMMAND "${CMAKE_C_COMPILER}" -print-file-name=plugin
        OUTPUT_VARIABLE PSEH_GCC_PLUGIN_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE PSEH_GCC_PLUGIN_QUERY_RESULT)
    if(NOT PSEH_GCC_PLUGIN_QUERY_RESULT EQUAL 0 OR
       NOT IS_DIRECTORY "${PSEH_GCC_PLUGIN_DIR}/include")
        message(FATAL_ERROR
            "${CMAKE_C_COMPILER} does not expose GCC plugin headers")
    endif()

    set(PSEH_PLUGIN_OUTPUT "${CMAKE_BINARY_DIR}/gcc_plugin_seh.so")
    set(PSEH_PLUGIN_DEPFILE "${CMAKE_BINARY_DIR}/gcc_plugin_seh.d")
    set(PSEH_PLUGIN_LINK_OPTIONS)
    # CMAKE_SYSTEM_NAME is Windows for the test executables, so APPLE is
    # false even though this host-side shared object is linked on macOS.
    if(CMAKE_HOST_APPLE)
        list(APPEND PSEH_PLUGIN_LINK_OPTIONS -undefined dynamic_lookup)
    endif()

    add_custom_command(
        OUTPUT "${PSEH_PLUGIN_OUTPUT}"
        COMMAND "${PSEH_HOST_CXX}"
            -std=c++14 -shared -fPIC -fno-rtti
            -I "${PSEH_HARNESS_ROOT}/gcc_plugin_seh"
            -I "${PSEH_GCC_PLUGIN_DIR}/include"
            ${PSEH_PLUGIN_LINK_OPTIONS}
            "${PSEH_HARNESS_ROOT}/gcc_plugin_seh/main.cpp"
            -MMD -MF "${PSEH_PLUGIN_DEPFILE}"
            -o "${PSEH_PLUGIN_OUTPUT}"
        DEPENDS
            "${PSEH_HOST_CXX}"
            "${PSEH_HARNESS_ROOT}/gcc_plugin_seh/main.cpp"
            "${PSEH_HARNESS_ROOT}/gcc_plugin_seh/gmp.h"
        DEPFILE "${PSEH_PLUGIN_DEPFILE}"
        VERBATIM
        COMMENT "Building host GCC SEH plugin for ${PSEH_PROFILE_NAME}")
    add_custom_target(pseh_gcc_plugin DEPENDS "${PSEH_PLUGIN_OUTPUT}")
endif()

set(PSEH_TEST_TARGETS)
foreach(test_source IN LISTS PSEH_TEST_SOURCES)
    get_filename_component(test_name "${test_source}" NAME_WE)
    add_executable("${test_name}"
        "${test_source}"
        $<TARGET_OBJECTS:pseh_runner>)
    target_include_directories("${test_name}" PRIVATE ${PSEH_INCLUDE_DIRS})
    target_compile_definitions("${test_name}" PRIVATE main=pseh_test_entry)
    target_compile_options("${test_name}" PRIVATE
        ${PSEH_PROFILE_OPTIONS}
        ${PSEH_OPT_OPTIONS})
    target_link_options("${test_name}" PRIVATE ${PSEH_LINK_OPTIONS})

    if(TARGET pseh_support)
        target_link_libraries("${test_name}" PRIVATE pseh_support)
    endif()

    if(PSEH_NEEDS_PLUGIN)
        add_dependencies("${test_name}" pseh_gcc_plugin)
        # The plugin participates in compilation, not merely target ordering.
        # Recompile this source when the plugin changes so Ninja cannot reuse an
        # object produced by stale compiler behavior.
        set_property(SOURCE "${test_source}" APPEND PROPERTY
            OBJECT_DEPENDS "${PSEH_PLUGIN_OUTPUT}")
        target_compile_options("${test_name}" PRIVATE
            "-fplugin=${PSEH_PLUGIN_OUTPUT}")
    endif()

    list(APPEND PSEH_TEST_TARGETS "${test_name}")
endforeach()

# `ninja` in an output tree builds the complete corpus for that one backend
# and optimization level.  Individual tests remain addressable by name, e.g.
# `ninja seh0031 stress0028`.
add_custom_target(pseh_tests ALL DEPENDS ${PSEH_TEST_TARGETS})
