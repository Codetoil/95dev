# Post-build guard: fail if the linked image contains P6-only instructions (CMOVcc, FCMOVcc,
# FCOMI/FUCOMI, UD2, SYSENTER, RDPMC) that a P5 Pentium would fault on with #UD.
# The prebuilt mingw-w64 runtime (libmingwex, crt) is compiled for i686, so -march=pentium on
# our own sources does not cover code pulled in from those libraries.
#
# Known-unreachable exceptions: the two CMOVs in the CRT pseudo-relocation handler
# (_mark_section_writable, __GetPEImageBase) run only if the pseudo-reloc list is non-empty.
# The check verifies that the list is empty instead of silently trusting it.
#
# Invoked as: cmake -DOBJDUMP=... -DNM=... -DEXE=... -P check-p5.cmake
execute_process(COMMAND ${OBJDUMP} -d ${EXE} OUTPUT_VARIABLE dis RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "check-p5: objdump failed on ${EXE}")
endif()
string(REPLACE ";" "\;" dis "${dis}")
string(REPLACE "\n" ";" lines "${dis}")
set(fn "?")
set(bad "")
foreach(l IN LISTS lines)
    if(l MATCHES "^[0-9a-f]+ <(.*)>:$")
        set(fn "${CMAKE_MATCH_1}")
    elseif(l MATCHES "\t(cmov|fcmov|fcomi|fucomi|ud2|sysenter|rdpmc)")
        if(NOT fn MATCHES "^(_mark_section_writable|__GetPEImageBase)$")
            string(STRIP "${l}" l)
            list(APPEND bad "  ${fn}: ${l}")
        endif()
    endif()
endforeach()

execute_process(COMMAND ${NM} ${EXE} OUTPUT_VARIABLE syms)
string(REGEX MATCH "([0-9a-f]+) R __RUNTIME_PSEUDO_RELOC_LIST__\n" _ "${syms}")
set(lo "${CMAKE_MATCH_1}")
string(REGEX MATCH "([0-9a-f]+) R __RUNTIME_PSEUDO_RELOC_LIST_END__\n" _ "${syms}")
set(hi "${CMAKE_MATCH_1}")
if(NOT lo STREQUAL hi)
    list(APPEND bad "  pseudo-relocation list is non-empty (${lo}..${hi}): the CRT's CMOV in _mark_section_writable WILL run")
endif()

if(bad)
    list(JOIN bad "\n" msg)
    message(FATAL_ERROR "check-p5: ${EXE} contains instructions a P5 Pentium cannot execute:\n${msg}")
endif()
message(STATUS "check-p5: ${EXE} OK (no reachable P6-only instructions)")
