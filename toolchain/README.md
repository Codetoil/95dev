# Per-host Win95 (P5) toolchain sysroot

The projects in this repository cross-compile for Windows 95 on a P5 Pentium (86Box). The distro
mingw-w64 runtime (libcrtdll.a, libmingwex.a, libmingw32.a) is prebuilt for i686 and contains
Pentium Pro-only instructions (CMOV etc.), e.g. in `sqrt`, `pow`, `strtof` and mingw's printf.
Running those on a P5 crashes with "invalid instruction".

`build-sysroot.sh` rebuilds the mingw-w64 headers and CRT from source with `-march=pentium` and
`--with-default-msvcrt=crtdll`. The CRT has to match the host's own `i686-w64-mingw32-gcc`,
which differs between distributions and releases. So each host builds its own sysroot inside
the repository (`<repo>` below is wherever it's checked out; it need not
be in your home directory):

```
<repo>/sysroot/<hostname>/include   mingw-w64 headers (__MSVCRT_VERSION__ = 0x00, CRTDLL)
<repo>/sysroot/<hostname>/lib       crt2.o, libcrtdll.a (= libmsvcrt.a), libmingwex.a, import libs
```

The script finds `<repo>` from its own location (`toolchain/..`), and each project's
`win95-toolchain.cmake` finds it as the project's parent directory, then looks up
`<repo>/sysroot/<hostname>` (hostname as
reported by CMake, which matches `hostname`). If that sysroot is present, the toolchain uses it.
If it is missing, the toolchain falls back to the distro mingw-w64 with the old CRTDLL specs
patch, and configure prints which one it picked:

```
-- win95: using per-host sysroot <repo>/sysroot/<hostname>
-- win95: no sysroot at ...; using distro mingw-w64 + CRTDLL specs (run <repo>/toolchain/build-sysroot.sh ...)
```

## Building on a host

Do this once per machine, and again after the distro's mingw-w64 GCC is upgraded.

1. **Prerequisites** (Debian/Ubuntu package names):
   `gcc-mingw-w64-i686-win32 binutils-mingw-w64-i686 make cmake ninja-build` (and `wine` if you
   want to run the test exes locally). This builds with the distro cross compiler; GCC itself
   is not rebuilt.

2. **mingw-w64 source.** The build was written against the `v14.x` release branch at commit
   `8acff4e19` (2026-05-23; `v14.0.0` plus two fixes). Check out the same commit on every host
   so the sysroots agree:
   ```sh
   git clone -b v14.x https://git.code.sf.net/p/mingw-w64/mingw-w64 <mingw-w64 source>
   git -C <mingw-w64 source> checkout 8acff4e19
   ```

3. **Build** (about 5–15 min depending on the machine; `JOBS` defaults to `nproc`):
   ```sh
   <repo>/toolchain/build-sysroot.sh <mingw-w64 source>
   # add WITH_WINPTHREADS=1 to also build static winpthreads (not needed; GCC uses win32 threads)
   ```
   What the script does:
   - Runs `make distclean` in the source tree if it was configured in-tree (an in-tree
     configure blocks out-of-tree builds).
   - Builds out-of-tree in `<mingw-w64 source>/build-<hostname>/`, so hosts sharing one source tree
     don't collide. It logs to `configure.log`/`make.log` in each step's directory.
   - Wipes and reinstalls `<repo>/sysroot/<hostname>/`.
   - Verifies the result: the installed CRT objects must contain no P6-only instructions, and
     the headers must default to CRTDLL. It exits non-zero if either check fails.

4. **Reconfigure projects** so CMake picks up the sysroot (the toolchain file is only read at
   configure time):
   ```sh
   cd <repo>/<project>
   cmake --preset win95-release --fresh && cmake --build --preset win95-release
   ```

### Multiple hosts

Each machine has its own checkout of this repository, at whatever path suits it. Its
`.gitignore` excludes `sysroot/` and `cmake-build-*/`: both are per-host build output (absolute
paths, host-specific CMake caches, CRTs matched to that host's GCC) and must not be shared.
On each host, check out the repository, clone mingw-w64 (step 2), build the sysroot (step 3),
and configure the projects there (step 4).

If you copy instead of using git, leave the same directories out:

```sh
rsync -a --exclude /sysroot --exclude 'cmake-build-*' <repo>/ <user>@<host>:<dest>/
```

## Options

- `-DWIN95_SYSROOT=<dir>`: use a sysroot somewhere else.
- `-DWIN95_SYSROOT=OFF`: force the distro fallback even if a sysroot exists.

## What it does not cover

- **libgcc.** libgcc is part of GCC, not mingw-w64, so it is still the distro's i686 build.
  `__fixdfdi`, `__fixsfdi`, `__fixunsdfsi`/`__fixunssfsi` (casts from float/double to
  `long long`/`unsigned`) and `__powidf2` contain CMOV. Rebuilding GCC with
  `--with-arch=pentium` is the only full fix. Until then, each project's `cmake/check-p5.cmake`
  post-build guard fails the build if any of these is linked in. Keep that guard.
- **C++.** Statically linked libstdc++ doesn't link against CRTDLL with or without the
  sysroot: `random.o` imports `rand_s`, which only msvcrt.dll has, and it gets pulled in even
  for trivial programs. The projects are C, so this hasn't mattered yet.
- **`__USE_MINGW_ANSI_STDIO=0`** stays in the projects. mingw's printf would be P5-safe with
  the sysroot, but it is large and its float formatting may still pull in the libgcc helpers
  above.
