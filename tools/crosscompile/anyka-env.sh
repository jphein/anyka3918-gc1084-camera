#!/usr/bin/env bash
# Source this to get a working Anyka AK3918 cross-compiler on PATH:
#
#     . tools/crosscompile/anyka-env.sh
#     $CC -O2 -o hello hello.c
#
# WHY A WRAPPER AT ALL: the toolchain's cc1 is a 32-bit i386 binary from 2017 and
# needs libmpfr.so.4, a soname no current Ubuntu ships (we're on libmpfr.so.6).
# The fix is a privately vendored copy under hostlibs/ reached by LD_LIBRARY_PATH
# - deliberately NOT installed system-wide and NOT symlinked to libmpfr.so.6.
# MPFR 3 -> 4 was an ABI break; pointing a compiler at the wrong one risks
# MISCOMPILATION rather than a clean failure, which is far worse than not building.
#
# See docs/cross-compiling.md for install steps and the pinned versions.
ANYKA_TOOLCHAIN="${ANYKA_TOOLCHAIN:-$HOME/opt/arm-anykav200-crosstool}"

if [ ! -x "$ANYKA_TOOLCHAIN/usr/bin/arm-anykav200-linux-uclibcgnueabi-gcc" ]; then
  echo "anyka-env: toolchain not found at $ANYKA_TOOLCHAIN" >&2
  echo "anyka-env: see docs/cross-compiling.md - it is NOT in this repo (45 MB)" >&2
  return 1 2>/dev/null || exit 1
fi
if [ ! -f "$ANYKA_TOOLCHAIN/hostlibs/libmpfr.so.4" ]; then
  echo "anyka-env: hostlibs/libmpfr.so.4 missing - cc1 will fail to load" >&2
  echo "anyka-env: see docs/cross-compiling.md 'host dependencies'" >&2
  return 1 2>/dev/null || exit 1
fi

export ANYKA_TOOLCHAIN
export PATH="$ANYKA_TOOLCHAIN/usr/bin:$PATH"
export LD_LIBRARY_PATH="$ANYKA_TOOLCHAIN/hostlibs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CROSS_COMPILE="arm-anykav200-linux-uclibcgnueabi-"
export CC="${CROSS_COMPILE}gcc"
export CXX="${CROSS_COMPILE}g++"
export STRIP="${CROSS_COMPILE}strip"
export SYSROOT="$ANYKA_TOOLCHAIN/usr/arm-anykav200-linux-uclibcgnueabi/sysroot"

# No -march/-mfloat-abi needed: the toolchain already defaults to exactly what the
# device reports. Verified by readelf against a shipped vendor binary -
# 0x5000202 Version5 EABI soft-float, ARM926EJ-S, v5TEJ, /lib/ld-uClibc.so.0.
# Do not "helpfully" add -mfloat-abi=hard; this SoC has no FPU.
