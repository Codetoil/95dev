cmake_minimum_required(VERSION 3.20)
project(test C)

set(CMAKE_C_STANDARD 11)

add_executable(test main.c)

# Pentium (P54C) codegen; Win95-era API surface in the headers.
target_compile_options(test PRIVATE -march=pentium -mtune=pentium)
target_compile_definitions(test PRIVATE _WIN32_WINNT=0x0400 WINVER=0x0400 _WIN32_WINDOWS=0x0400)
# Use CRTDLL's own printf family. Otherwise C99+ mode routes printf to mingw-w64's
# __mingw_printf (libmingwex), which is prebuilt for i686 and contains CMOV -> #UD on a P5.
# Side effect: no %lld/%zu/%Lf (CRTDLL doesn't support them).
target_compile_definitions(test PRIVATE __USE_MINGW_ANSI_STDIO=0)

# PE header: subsystem + OS version 4.0, otherwise Win95's loader refuses the image.
# Use "console" for main()/printf programs, "windows" for WinMain GUI programs.
target_link_options(test PRIVATE
        -static
        -Wl,--subsystem,console:4.0
        -Wl,--major-os-version,4 -Wl,--minor-os-version,0)

# P5 guard (see cmake/check-p5.cmake), run on the unstripped image so function names are
# available; Release/MinSizeRel are stripped afterwards (replaces the old -s link flag).
add_custom_command(TARGET test POST_BUILD
        COMMAND ${CMAKE_COMMAND} -DOBJDUMP=${CMAKE_OBJDUMP} -DNM=${CMAKE_NM}
                -DEXE=$<TARGET_FILE:test> -P ${CMAKE_SOURCE_DIR}/cmake/check-p5.cmake
        VERBATIM)
if(CMAKE_BUILD_TYPE MATCHES "^(Release|MinSizeRel)$")
    add_custom_command(TARGET test POST_BUILD
            COMMAND ${CMAKE_STRIP} $<TARGET_FILE:test>
            VERBATIM)
endif()
