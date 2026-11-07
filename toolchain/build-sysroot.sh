#!/usr/bin/env bash
# Build a Pentium (P5)-safe mingw-w64 headers + CRT sysroot for THIS host.
#
# The CRT must match the host's own i686-w64-mingw32-gcc, so every machine builds its own copy
# into <repo>/sysroot/<hostname>/, where <repo> is the directory above this script (wherever
# the repository is checked out). win95-toolchain.cmake picks that directory up automatically
# (matched by hostname) and falls back to the distro's mingw-w64 when it is missing.
#
# usage: build-sysroot.sh <mingw-w64-source-dir>
# env:   JOBS=<n>          parallel make jobs (default: nproc)
#        WITH_WINPTHREADS=1  also build static winpthreads (not needed for win32-threads GCC)
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $(basename "$0") <mingw-w64-source-dir>" >&2; exit 2; }
SRC=$(realpath "$1")
HOST_NAME=$(hostname)                      # must match CMake's cmake_host_system_information(HOSTNAME)
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PREFIX="$REPO/sysroot/$HOST_NAME"
BUILD="$SRC/build-$HOST_NAME"              # per-host out-of-tree build dir
TARGET=i686-w64-mingw32
JOBS=${JOBS:-$(nproc)}
P5="-O2 -march=pentium -mtune=pentium"

die() { echo "build-sysroot: $*" >&2; exit 1; }

[ -f "$SRC/mingw-w64-crt/configure" ] || die "$SRC does not look like a mingw-w64 source tree"
command -v "$TARGET-gcc" >/dev/null     || die "$TARGET-gcc not found (install the i686 win32-threads mingw-w64 cross compiler)"
command -v "$TARGET-objdump" >/dev/null || die "$TARGET-objdump not found (install binutils-mingw-w64-i686)"
command -v make >/dev/null              || die "make not found"

echo "host:     $HOST_NAME ($TARGET-gcc $($TARGET-gcc -dumpversion))"
echo "source:   $SRC"
echo "build:    $BUILD"
echo "prefix:   $PREFIX"
echo

# Out-of-tree builds are refused while the source tree itself is configured.
if [ -f "$SRC/config.status" ] || [ -f "$SRC/mingw-w64-headers/config.status" ] || [ -f "$SRC/mingw-w64-crt/config.status" ]; then
    echo "== source tree was configured in-tree; running 'make distclean' there"
    for d in "$SRC" "$SRC/mingw-w64-headers" "$SRC/mingw-w64-crt"; do
        if [ -f "$d/config.status" ]; then
            if [ -f "$d/Makefile" ]; then make -C "$d" distclean >/dev/null; else rm -f "$d/config.status"; fi
        fi
    done
fi

rm -rf "$BUILD" "$PREFIX"
mkdir -p "$BUILD"

echo "== 1/3 headers"
mkdir -p "$BUILD/headers" && cd "$BUILD/headers"
"$SRC/mingw-w64-headers/configure" \
    --host=$TARGET \
    --prefix="$PREFIX" \
    --with-default-msvcrt=crtdll > configure.log
make install > make.log

echo "== 2/3 crt (CFLAGS: $P5)"
mkdir -p "$BUILD/crt" && cd "$BUILD/crt"
"$SRC/mingw-w64-crt/configure" \
    --host=$TARGET \
    --prefix="$PREFIX" \
    --with-sysroot="$PREFIX" \
    --enable-lib32 --disable-lib64 \
    --with-default-msvcrt=crtdll \
    CFLAGS="$P5" CXXFLAGS="$P5" CCASFLAGS="$P5" > configure.log
make -j"$JOBS" > make.log
make install > install.log

if [ "${WITH_WINPTHREADS:-0}" = 1 ]; then
    echo "== +   winpthreads (static)"
    mkdir -p "$BUILD/winpthreads" && cd "$BUILD/winpthreads"
    "$SRC/mingw-w64-libraries/winpthreads/configure" \
        --host=$TARGET --prefix="$PREFIX" --disable-shared \
        CFLAGS="$P5 -nostdinc -isystem $($TARGET-gcc -print-file-name=include) -isystem $($TARGET-gcc -print-file-name=include-fixed) -isystem $PREFIX/include" \
        LDFLAGS="-B$PREFIX/lib/" > configure.log
    make -j"$JOBS" > make.log
    make install > install.log
fi

echo "== 3/3 verify: P6-only instructions in installed runtime"
P6='\s(cmov|fcmov|fcomi|fucomi|ud2|sysenter|rdpmc)'
bad=0
for f in "$PREFIX"/lib/crt2.o "$PREFIX"/lib/dllcrt2.o "$PREFIX"/lib/libcrtdll.a "$PREFIX"/lib/libmsvcrt.a \
         "$PREFIX"/lib/libmingwex.a "$PREFIX"/lib/libmingw32.a "$PREFIX"/lib/libmoldname.a "$PREFIX"/lib/libwinpthread.a; do
    [ -f "$f" ] || continue
    n=$("$TARGET-objdump" -d "$f" 2>/dev/null | grep -cE "$P6" || true)
    printf '   %-20s %s\n' "$(basename "$f")" "$n"
    [ "$n" = 0 ] || bad=1
done
grep -q '__MSVCRT_VERSION__ 0x00' "$PREFIX/include/_mingw.h" \
    && echo "   _mingw.h: default __MSVCRT_VERSION__ is 0x00 (crtdll)" \
    || { echo "   _mingw.h: default __MSVCRT_VERSION__ is NOT crtdll"; bad=1; }

echo
if [ $bad = 0 ]; then
    echo "OK: $PREFIX is ready. Reconfigure projects (delete cmake-build-* or 'cmake --preset ... --fresh')."
else
    echo "WARNING: see above. libgcc is not covered by this script; the check-p5 guard still applies."
    exit 1
fi
