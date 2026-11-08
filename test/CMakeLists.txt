cmake_minimum_required(VERSION 3.20)
project(test C)

set(directxTest PROPERTIES
        CMAKE_C_STANDARD 90
        CMAKE_C_STANDARD_REQUIRED ON
        CMAKE_C_EXTENSIONS OFF
)
set(directxTest PROPERTIES
        CMAKE_CXX_STANDARD 98
        CMAKE_CXX_STANDARD_REQUIRED ON
        CMAKE_CXX_EXTENSIONS OFF
)

# 2. Add compiler-specific flags to break or disable post-1997 features
if(MSVC)
    target_compile_options(directxTest PRIVATE
            /Za       # Disable Microsoft extensions (enforce strict ANSI C++)
            /W4       # Set high warning level to catch compliance deviations
    )

    # Optional: Force the __cplusplus macro to report standard compliance
    # (Though MSVC will report 199711L for C++98, which is slightly newer than VC5)
    target_compile_options(directxTest PRIVATE /Zc:__cplusplus)

elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(directxTest PRIVATE
            -pedantic-errors # Treat language deviations as hard errors
            -Wold-style-cast # Force errors on modern casting style if preferred
    )
endif()

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
