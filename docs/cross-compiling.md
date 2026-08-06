# Cross-compiling for the AK3918

Until 2026-08-06 everything this project shipped was **shell scripts and single-byte patches
to vendor binaries**. We could change what the vendor's code *did*; we could not add code of
our own. This page closes that.

**Status: the toolchain is installed and builds correctly-shaped binaries, including one
that links seven vendor SDK libraries. On-device execution is verified separately — see
"Proof" at the end, and do not treat a successful build as a working binary.**

---

## The target contract

Do not guess these. They were read out of a binary that demonstrably runs on the camera
(`/mnt/ak_drv_ir_demo`), and anything you build must match:

```
Class:          ELF32, little endian, EXEC
Flags:          0x5000202  -  Version5 EABI, soft-float ABI
Tag_CPU_name:   "ARM926EJ-S"
Tag_CPU_arch:   v5TEJ
Tag_ABI_align_needed: 8-byte
interpreter:    /lib/ld-uClibc.so.0
libc:           libc.so.0   (uClibc 0.9.33.2 - NOT glibc)
```

**This SoC has no FPU.** `-mfloat-abi=hard` produces a binary that links cleanly and dies on
the device. You should not need to pass any `-march`/`-mfloat` flags at all: the toolchain
below already defaults to exactly this.

Check any binary you build with:

```bash
arm-none-eabi-readelf -hA yourbin | grep -E 'Flags|CPU_name|CPU_arch'
arm-none-eabi-readelf -l yourbin  | grep -A1 INTERP
```

## The toolchain

**`https://github.com/ricardojlrufino/arm-anykav200-crosstool`**, pinned at commit
**`a156c467d63b1abd5658b5f627140f8e9507d342`** (2022-02-27, the repo's only content commit).

```
arm-anykav200-crosstool.zip   45217158 bytes
sha256  283dd884823b348d60d706a3f77073fb599f5e5e0349b769b451eb9d5aeb630f
```

It is **not vendored in this repo** — 45 MB of prebuilt binaries does not belong in git.

Why this one rather than Debian's `gcc-arm-linux-gnueabi`: it reports

```
gcc version 4.8.5 (anyka (gcc-4.8.5 + binutils-2.24 + ulcibc-0.9.33.2)(20170223))
```

which is **byte-identical to the string in the camera's own `/proc/version`**. It is the
compiler that built the running kernel and the vendor binaries, with the matching uClibc.
A glibc toolchain can produce a working *static* hello-world, but it cannot link the vendor
SDK `.so` files, which are uClibc — and those are the whole point.

### Install

```bash
mkdir -p ~/opt && cd ~/opt
SHA=a156c467d63b1abd5658b5f627140f8e9507d342
curl -sSL -o arm-anykav200-crosstool.zip \
  "https://raw.githubusercontent.com/ricardojlrufino/arm-anykav200-crosstool/$SHA/arm-anykav200-crosstool.zip"
sha256sum arm-anykav200-crosstool.zip   # must be 283dd884...
unzip -q arm-anykav200-crosstool.zip
```

### ⚠️ Host dependencies — this is the part that wastes an afternoon

`arm-anykav200-linux-uclibcgnueabi-gcc --version` works immediately, which is misleading:
the driver runs, but the actual compiler `cc1` does not. **`cc1` is a 32-bit i386 binary
from 2017** and needs two host libraries:

| needs | status on Ubuntu 24.04 |
|---|---|
| `libgmp.so.10` (i386) | fine, already present |
| `libmpc.so.3` (i386) | `sudo apt install libmpc3:i386` |
| `libmpfr.so.4` (i386) | **does not exist in any current release** — we ship `libmpfr.so.6` |

The symptom is a clean-looking failure at the first compile:

```
cc1: error while loading shared libraries: libmpfr.so.4: cannot open shared object file
```

**Do not symlink `libmpfr.so.6` to `libmpfr.so.4`.** MPFR 3 → 4 was an ABI break, and
pointing a compiler at the wrong one risks **miscompilation** rather than a clean failure.
A compiler that silently emits wrong code is far worse than one that refuses to start.

The fix is a privately vendored copy, not a system install:

```bash
cd /tmp
curl -sfLO http://archive.debian.org/debian/pool/main/m/mpfr4/libmpfr4_3.1.5-1_i386.deb
dpkg-deb -x libmpfr4_3.1.5-1_i386.deb mpfr4x
mkdir -p ~/opt/arm-anykav200-crosstool/hostlibs
cp mpfr4x/usr/lib/i386-linux-gnu/libmpfr.so.4.1.5 \
   ~/opt/arm-anykav200-crosstool/hostlibs/libmpfr.so.4
# sha256 233097885ca2ae0b834fd806efb45785cd48901ddd88592345f024ce8e0223b3
```

`hostlibs/` is reached only via `LD_LIBRARY_PATH` from the env script below, so the host's
own `libmpfr.so.6` is untouched and nothing else on the machine can pick up the old ABI.

## Building

```bash
. tools/crosscompile/anyka-env.sh      # sets PATH, LD_LIBRARY_PATH, CC, CXX, STRIP, SYSROOT
$CC -O2 -o hello hello.c
```

The env script refuses to run if either the toolchain or `hostlibs/libmpfr.so.4` is missing,
rather than letting you discover it at the first compile.

Builds are **reproducible**: the same source through the same toolchain produced
byte-identical output across two invocations.

## Building against the vendor SDK

The SDK — headers *and* the matching `.so`/`.a` files — is in
**`ricardojlrufino/anyka_v380ipcam_experiments`** under `akv300-extract/libplat/`.

**It is the same SDK this camera runs.** Verified rather than assumed, by hashing two
libraries against the live device:

```
akv300-extract/libplat/lib/libplat_drv.so        f5769ff013d7a3094e73ee76e312cad0
  == camera /mnt/anyka_hack/ptz/lib/libplat_drv.so
akv300-extract/libplat/lib/libakaudiofilter.so   938d71ff80916dbedef9885a59a91cd3
  == camera /usr/lib/libakaudiofilter.so
```

That matters: it means the headers agree with the libraries, and link-time and run-time
libraries are the same objects. It removes the usual risk of SDK-linked cross builds.

```bash
git clone --depth 1 https://github.com/ricardojlrufino/anyka_v380ipcam_experiments.git ~/opt/anyka_v380ipcam_experiments
export PLAT_WORKDIR=~/opt/anyka_v380ipcam_experiments/akv300-extract
```

All seven libraries `ak_snapshot` needs (`libakuio`, `libakispsdk`, `libplat_common`,
`libplat_thread`, `libplat_vi`, `libplat_vpss`, `libplat_ipcsrv`) are present in `/mnt/lib`
on the camera, so a card-side binary finds them with no `LD_LIBRARY_PATH` gymnastics.

### Worked example: rebuilding `ak_snapshot`

```bash
cd ~/opt/anyka_v380ipcam_experiments/apps/ak_snapshot
. ~/Projects/anyka3918-gc1084-camera/tools/crosscompile/anyka-env.sh
export PLAT_WORKDIR=~/opt/anyka_v380ipcam_experiments/akv300-extract
export TARGET_BIN=ak_snapshot.rebuilt
make clean && make STATIC_LIBS=
```

Two things about that invocation:

- **`STATIC_LIBS=` is required.** The upstream Makefile has `STATIC_LIBS := libquirc` plus a
  hardcoded `-L/media/ricardo/...` from the author's own machine. `quirc` is vestigial —
  `src/main.c` declares a `struct quirc *qr;` and never links it, and upstream's own
  `build.sh` has `LIBQUIRC_PATH` commented out. Clearing it drops the dead dependency.
- **Do not run upstream's `build.sh`.** Its last step FTPs the binary to a hardcoded IP
  (`192.168.15.64`) that is not ours.

Result: **29740 bytes** against the repo's shipped `ak_snapshot` at **29767** — a 27-byte
difference consistent with build paths and timestamps, not with a different program. Same
`0x5000202` flags, same interpreter, all seven SDK libraries in `NEEDED`.

## Getting a binary onto the camera

**Card-side only. Nothing new goes in squashfs** — the root is read-only, and a card edit is
recoverable by pulling the card.

For a throwaway test, `/tmp` is tmpfs and vanishes on reboot, which is what you want while
iterating. For anything that should persist, put it under `/mnt/anyka_hack/` and add it to
`tools/write-sd-card.sh`, or **a camera out of the bag will not have it** — see the backlog's
"nothing counts until it is in the writer" rule.

Delivery over telnet, md5-gated (the pattern used throughout this project):

```python
import base64, hashlib, re, sys
sys.path.insert(0, 'scratch/anyka-white-led')     # adjust
from led_measure import Session                    # persistent telnet, no re-login per line
data = open('hello','rb').read(); want = hashlib.md5(data).hexdigest()
b64  = base64.b64encode(data).decode()
s = Session(); s.cmd('rm -f /tmp/x.b64')
for i in range(0, len(b64), 140):                  # tty input truncates near 255 bytes
    s.cmd(f"printf '%s' '{b64[i:i+140]}' >> /tmp/x.b64")
s.cmd('base64 -d /tmp/x.b64 > /tmp/hello; chmod +x /tmp/hello')
assert re.search(r'\b([0-9a-f]{32})\b', s.cmd('md5sum /tmp/hello')).group(1) == want
```

⚠️ **The base64 chunk filter is a real trap.** An earlier version of this loop dropped the
*final* short line when reassembling, producing a file 14 bytes short that still looked
plausible. It was caught only by the md5 gate. Keep the gate.

## Proof — and why a successful build is not it

`file`, `readelf` and a clean link all mean **"the toolchain believes it made an ARM
binary"**. This project's standing rule applies: *verify the effect, not the invocation*.

| step | evidence | status |
|---|---|---|
| toolchain installs and runs | version string matches `/proc/version` byte-for-byte | ✅ |
| hello-world compiles | 5255 bytes, contract-matching ELF | ✅ |
| build is reproducible | two runs byte-identical | ✅ |
| SDK is the camera's own SDK | two library md5s match the live device | ✅ |
| SDK-linked app rebuilds | `ak_snapshot` 29740 B, 7 SDK libs in `NEEDED` | ✅ |
| **hello-world RUNS on the camera** | — | see below |
| **rebuilt app behaves like the shipped one** | — | see below |

The last two rows are the only ones that close the gap. Fill them in with real output; do
not mark them from a green build.

## What this unblocks — and what it does not

**Unblocked.** Anything needing new code on the device: a purpose-built control daemon
instead of shelling out per request, a proper audio-stop mechanism if the shell one proves
insufficient, streaming work, anything that must call the vendor SDK directly rather than
driving a demo binary from a script.

**NOT unblocked, and worth being blunt about:**

- **Automatic day/night.** Not compiler-blocked. The sense input `gpio-rf_feed` does not
  exist on this board and the fallback `ain0` is a constant. No amount of new code invents a
  sensor.
- **The white LEDs.** Not compiler-blocked — the pin is electrically fine and drives nothing.
- **The audio stop verb.** Probably not compiler-blocked either: `killall ak_adec_demo` is
  shell. Write the shell version first and only reach for a binary if it proves inadequate.
- **Anything in squashfs.** Still read-only. A compiler does not change where things can live.

**And one caution about habits.** The md5 gates, `.orig` guards and self-checking assertions
throughout this repo exist *because* we were doing surgery on binaries we could not rebuild.
That constraint is what this page removes. Keep the gates on the **delivery** path — a
truncated transfer is still a truncated transfer — but do not carry byte-comparison
verification into compiled work: **two builds of the same source are not guaranteed
identical**, so `cmp` against a reference stops being the right test the moment a binary is
built rather than patched.
