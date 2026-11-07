# Cross toolchain: Linux host -> Win32 (Windows 95 / NT 4.0 baseline), mingw-w64 i686.
# Must be loaded via CMAKE_TOOLCHAIN_FILE (see CMakePresets.json) *before* project().
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR i586)
set(CMAKE_SYSTEM_VERSION 4.0)

set(TOOLCHAIN_PREFIX i686-w64-mingw32)
set(CMAKE_C_COMPILER   ${TOOLCHAIN_PREFIX}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_PREFIX}-g++)
set(CMAKE_RC_COMPILER  ${TOOLCHAIN_PREFIX}-windres)

set(CMAKE_FIND_ROOT_PATH /usr/${TOOLCHAIN_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Run built .exe files through Wine (used by try_run / ctest)
set(CMAKE_CROSSCOMPILING_EMULATOR wine)

# --- C runtime: CRTDLL.dll (ships with every Win95/NT install) instead of msvcrt.dll ---
#
# Preferred: this host's P5-safe sysroot, built by <repo>/toolchain/build-sysroot.sh into
# <repo>/sysroot/<hostname>/ (see <repo>/toolchain/README.md). <repo> is the directory above
# this project, wherever the repository is checked out. The sysroot is configured with
# --with-default-msvcrt=crtdll, so libmsvcrt.a already *is* CRTDLL and no specs patch is needed.
# Override with -DWIN95_SYSROOT=<dir>, or -DWIN95_SYSROOT=OFF to force the distro fallback.
cmake_host_system_information(RESULT WIN95_HOST QUERY HOSTNAME)
get_filename_component(WIN95_REPO "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
set(WIN95_SYSROOT "${WIN95_REPO}/sysroot/${WIN95_HOST}" CACHE PATH
        "Per-host P5-safe mingw-w64 sysroot (from build-sysroot.sh); OFF = use distro mingw-w64")

# Default system include list of <compiler> with the distro mingw-w64 include dir swapped
# for the sysroot's, as -nostdinc -isystem ... flags (keeps GCC/libstdc++ dirs in order).
function(win95_sysroot_flags compiler lang out)
    execute_process(COMMAND ${compiler} -x ${lang} -E -Wp,-v -
            INPUT_FILE /dev/null OUTPUT_QUIET ERROR_VARIABLE _err RESULT_VARIABLE _rc)
    if(NOT _rc EQUAL 0)
        message(FATAL_ERROR "${compiler}: could not query its include search list")
    endif()
    string(REGEX MATCH "#include <...> search starts here:\n(.*)End of search list" _ "${_err}")
    string(REGEX REPLACE "\n" ";" _dirs "${CMAKE_MATCH_1}")
    get_filename_component(_distro "/usr/${TOOLCHAIN_PREFIX}/include" REALPATH)
    set(_flags "-nostdinc")
    set(_swapped FALSE)
    foreach(_d IN LISTS _dirs)
        string(STRIP "${_d}" _d)
        if(_d STREQUAL "")
            continue()
        endif()
        get_filename_component(_r "${_d}" REALPATH)
        if(_r STREQUAL _distro)
            set(_r "${WIN95_SYSROOT}/include")
            set(_swapped TRUE)
        endif()
        string(APPEND _flags " -isystem ${_r}")
    endforeach()
    if(NOT _swapped)
        message(FATAL_ERROR "${compiler}: ${_distro} not in its include path; cannot redirect to ${WIN95_SYSROOT}")
    endif()
    # -B: crt2.o and libraries come from the sysroot first (-L alone would miss crt2.o).
    set(${out} "${_flags} -B${WIN95_SYSROOT}/lib/" PARENT_SCOPE)
endfunction()

if(WIN95_SYSROOT AND EXISTS "${WIN95_SYSROOT}/lib/crt2.o" AND EXISTS "${WIN95_SYSROOT}/include/_mingw.h")
    win95_sysroot_flags(${CMAKE_C_COMPILER} c CMAKE_C_FLAGS_INIT)
    find_program(_win95_cxx ${CMAKE_CXX_COMPILER})
    if(_win95_cxx)
        win95_sysroot_flags(${CMAKE_CXX_COMPILER} c++ CMAKE_CXX_FLAGS_INIT)
    endif()
    set(CMAKE_FIND_ROOT_PATH "${WIN95_SYSROOT}" /usr/${TOOLCHAIN_PREFIX})
    message(STATUS "win95: using per-host sysroot ${WIN95_SYSROOT}")
else()
    # Fallback: distro mingw-w64 (prebuilt for i686 -> CMOV in libcrtdll.a/libmingwex.a;
    # the check-p5 post-build guard catches it). GCC 13 has no -mcrtdll= switch, so derive a
    # specs file whose libgcc rule links -lcrtdll where it would have linked -lmsvcrt.
    # mingw-w64's libcrtdll.a supplies the CRT-specific glue (e.g. _iob instead of __p__iob).
    message(STATUS "win95: no sysroot at ${WIN95_SYSROOT}; using distro mingw-w64 + CRTDLL specs "
            "(run ${WIN95_REPO}/toolchain/build-sysroot.sh on this host for a P5-safe CRT)")
    set(WIN95_SPECS "${CMAKE_BINARY_DIR}/crtdll.specs")
    if(NOT EXISTS "${WIN95_SPECS}")
        execute_process(COMMAND ${CMAKE_C_COMPILER} -dumpspecs
                OUTPUT_VARIABLE _specs RESULT_VARIABLE _rc)
        if(NOT _rc EQUAL 0)
            message(FATAL_ERROR "${CMAKE_C_COMPILER} -dumpspecs failed")
        endif()
        string(REPLACE "-lmsvcrt " "-lcrtdll " _patched "${_specs}")
        if(_patched STREQUAL _specs)
            message(FATAL_ERROR "Could not find -lmsvcrt in GCC specs; CRTDLL patch not applied")
        endif()
        file(WRITE "${WIN95_SPECS}" "${_patched}")
    endif()
    set(CMAKE_C_FLAGS_INIT   "-specs=${WIN95_SPECS}")
    set(CMAKE_CXX_FLAGS_INIT "-specs=${WIN95_SPECS}")
endif()
