# Custom firmware — the updater, and how to use it without bricking a camera

The stock firmware ships a **complete, working updater** with no cloud and no
account. Nobody had read it until 2026-08-06. This is what it does, what it does
*not* check, and the sequence for getting our own image onto a camera.

> 🔴 **Nothing in this repo has been flashed to a camera.** Every tool here
> produces files. As of 2026-08-06 no camera has taken a custom image, and
> **cam1 has no recovery path** — see [the gate](#the-gate-recovery-first).

---

## The gate: recovery first

### The bootloader is out of the updater's reach — MEASURED

The boot log gives the offset directly:

```
SF: 1417200 bytes @ 0x31000 Read: OK        u-boot reads the kernel from 0x31000
```

So `KERNEL` (mtd1) begins at **0x31000 = 196 KB**, and the partition sizes close
the arithmetic exactly:

| region | bytes |
|---|---|
| before `KERNEL` (0x31000) | 200,704 |
| `mtd1`…`mtd7` | 8,065,024 |
| **flash total** (`mtd0`, 0x800000) | **8,388,608** |
| unallocated at the end | 122,880 |

**196 KB before `KERNEL` and 120 KB after `D`, neither inside any named
partition.** `updater` resolves targets *only* by name through
`/sys/kernel/partition_table/<NAME>/mtd_index`, and the live table is
`KERNEL→1 MAC→2 ENV→3 A→4 B→5 C→6 D→7`. **No name maps to the bootloader, so no
invocation can erase u-boot.**

*Inferred:* that the 196 KB sits at offset 0. It must — the SoC boots from the
start of SPI flash — but no dump has been read.

*Open:* whether anything in `/sys/kernel/partition_table/` resolves to **mtd0**
(the whole flash). If nothing does, "the updater cannot erase u-boot" is
structural rather than a convention we are honouring.

### But that console is not reachable on our cameras — and this is the blocker

u-boot is interactive (`U-Boot 2013.10.0-AK_V2.0.04`, console
`ttySAK0,115200n8`), so recovery is *possible*. Reaching it is the problem.
Upstream, `reference/hack-process.md:149`:

> *"**Soldered a pin header** to the RX0 TX0 GND points **next to the wifi
> chip**."*

Bare pads. **Open the case, identify the pads on this board, solder three wires,
attach a USB-serial adapter.**

⚠️ **Every UART artifact we hold is from a different board revision** —
`#1 Nov 14 2022 zhoujiahui` versus our `#2 Sep 25 2023 chensheng`. So pad
location, u-boot version and autoboot behaviour on our units are **family-level
inference, not measurement**. Nobody has had a serial console on one of JP's
cameras.

⚠️ **Autoboot delay is 0** on the revision we have logs for. Catching u-boot
means spamming the serial line from power-on, not waiting for a prompt.

> **The rule: no partition is flashed on a unit until UART is wired on *that*
> unit and a u-boot prompt has actually been seen on it.**
>
> Not because a flash is likely to fail. Because **the first failure is also the
> last thing you learn** — `updater` reports success and reboots, and the device
> dies later at first read of the missing region.

---

## What the updater actually checks

**Two things: the image opens, and it fits.** That is the complete list.

| check | present? |
|---|---|
| size ≤ partition | ✅ **yes**, and sound — evaluated *before* the erase, rejects untouched |
| md5 | ⚠️ only when a `.md5` file happens to be present (`if [ -e ]`), and the hash ships **inside** the artefact it verifies |
| squashfs magic | ❌ none |
| header/length consistency | ❌ none |
| signature | ❌ none |

So md5 here is **integrity against a corrupt card, never authenticity**. A
truncated image is erased in and written verbatim.

**Every guard worth having therefore lives on the workstation**, in
`tools/fw/build-update-tar.sh`. That is not belt-and-braces; it is the only
place a guard can exist.

## The two entry points

| mode | trigger | version gate |
|---|---|---|
| **TF (card)** | `/mnt/update/update.tar` | `tar_ver != dev_ver` — *any* change, including a downgrade |
| **OTA (network)** | `/tmp/update.tar` | `tar_ver > dev_ver` — and **it does not mean that** |

⚠️ **The OTA "newer only" gate is a string compare** (`[ "$tar_ver" \> "$dev_ver" ]`)
and the installed `6.0.24.10_202401091113` is already past the digit-width
boundary where it inverts: `6.0.24.9 > 6.0.24.10` is **TRUE**. Tested in `sh`,
`dash` and busybox. **The difference between the two entry points is
presentational, not protective.**

## Tarball members

```
uImage  root.sqsh4  usr.sqsh4  usr.jffs2  audio_update.tgz
  + optional  <name>.md5  for each
  + REQUIRED  fw_version          (read unconditionally at line 271)
  + optional  special.sh          (executed if present, when /data exists)
  + optional  9.aac
```

## Slots — and the two that are never targets

| slot | mtd | is | bad flash survivable? |
|---|---|---|---|
| `KERNEL` | 1 | uImage | **No** — u-boot loads it, nothing boots |
| `A` | 4 | `/` squashfs | **No** — `root=/dev/mtdblock4`, kernel panics |
| `B` | 5 | `/usr` squashfs | **Candidate** — see below |
| `C` | 6 | `/etc/jffs2` | 🔴 **NEVER** |
| `D` | 7 | `/data` | 🔴 **FORBIDDEN** |

### 🔴 Why `C` is never a target

`C=` is a **whole-partition erase** — `erase_info.start = 0`,
`length = mtd_info.size`, one `MEMERASE` ioctl over all 64 KB. Confirmed at the
instruction level.

`/etc/jffs2` holds **the entire hack**: the exploit entry point, `gergehack.sh`,
the root password, `webui.hash`, `gergesettings.txt` — **and `anyka_cfg.ini`,
which carries the WiFi SSID and PSK.**

**One write costs telnet, the hack, both passwords and the network
configuration, together.** The result is not a camera you debug remotely; it is a
camera you go and fetch. `build-update-tar.sh` has no flag, path or escape that
can produce a `usr.jffs2` — the rail is absence, not a gate.

### 🔴 Why `D` is forbidden

`/data` holds unit identity ([identity.md](identity.md)). `update.sh` never
invokes `D=` — a property of the *script* — but `updater` has no name whitelist
and `D → 7` resolves, so **`D=` would flash it**. Any update tooling we write
must treat it as forbidden; invoking it erases identity on every camera it
touches.

### Is `B` survivable? One unknown decides it

`B` mounts *after* boot: the kernel starts, `/` mounts from `A`,
`init=/sbin/init` runs from `A`. So a corrupt `/usr` may still leave a booting
device.

**The deciding fact: which partition holds the binary that executes
`/Factory/config.sh`?**

- On **`A`** → a bad `B` still boots, the card's exploit still fires, telnet
  still comes up, and `B` can be re-flashed over the network. **`B` becomes
  recoverable without UART.**
- On **`B`** → nothing is survivable and everything gates on the soldering iron.

**Unresolved.** `reference/usr-sbin/` contains no reference to `Factory` or
`config.sh`, so the trigger is in a binary or a script not yet dumped.

---

## 🔴 The hazard that fires on every update, even one that flashes nothing

`update_ispconfig()` (line 109) is **unconditional and unguarded**:

```sh
update_ispconfig() { rm -rf /etc/jffs2/isp*.conf ; }
```

That symlink is what points the ISP at its sensor config. Without it, **no
video**.

**And `Factory/config.sh` will not put it back**, because it guards on the wrong
file:

```sh
FILE="/mnt/isp_gc1084.conf"
if [ ! -e "$FILE" ]; then          # tests the TARGET on the card, not the symlink
  tar -xzf /etc/jffs2/sensor.tgz -C /mnt
  ln -s /mnt/isp_gc1084.conf /etc/jffs2/
fi
```

The card's copy still exists, so the condition is **false** and the symlink is
never recreated. This is **separate from the known bracket bug and is not fixed
by fixing it** — the guard tests the wrong path.

**Two fixes, both needed:**

1. `tools/fw/special.sh` restores it inside the update itself — rebuilt from
   whatever `isp_*.conf` the card actually carries, not a hardcoded `gc1084`,
   because the bag is not all one sensor.
2. `Factory/config.sh`'s guard should test the **symlink**, not the target. Not
   yet applied — see [backlog](backlog.md).

---

## The zero-write proof — and why the TF path is where we experiment

`special.sh` runs at **line 355**, before every flash write:

```
350  update_ispconfig
355  $DIR1/special.sh        <-- our code, as root
359  update_kernel        ]
360  update_jffs2         ]  all flash writes are AFTER this
361  update_squash        ]
362  update_rootfs_squash ]
```

> **A tarball of `fw_version` + `special.sh` and no images proves the entire
> pipeline — discovery, extraction, version gate, root execution — while erasing
> nothing.** That is not risk mitigated; it is risk absent.

### Its failure mode is a physical undo, and that is a property, not a quirk

Three measured facts compose:

1. `/usr/fw_version` lives on `B`, so a tarball that flashes nothing **cannot**
   change `dev_ver`.
2. `#rm -rf /mnt/update` (line 332) is **commented out** — the tarball stays.
3. `reboot -f` (line 371) is **unconditional**.

TF gate is `!=`, so it fires again every boot: **a reboot loop, recoverable by
pulling the card.**

**Do not treat that as a bug to design around.** It is the reason the TF path is
the correct place to experiment on this hardware — its worst case is a physical
undo rather than a brick. `special.sh` disarms itself to make the run one-shot,
and it must **re-mount the card to do so**: `umount /mnt/ -l` at line 344 runs
*before* `special.sh`. Miss that and the removal silently does nothing — the
exact detail that turns a one-shot into a loop nobody expected.

---

## Tools

```bash
# zero-write pipeline proof
tools/fw/build-update-tar.sh --out update.tar \
    --fw-version 6.0.24.11_<stamp> --special tools/fw/special.sh

# rebuild the camera's own /usr through our pipeline and prove it
tools/fw/roundtrip-squashfs.sh --dump mtdblock5.bin --slot B --out usr.sqsh4

# everything above, no camera required
tools/fw/selftest.sh
```

### What `roundtrip-squashfs.sh` claims — and what it deliberately does not

It does **not** claim byte-identity to the vendor image. That phrasing was
proposed and withdrawn: the vendor built with a different `mksquashfs`, so byte
equality would fail for a reason that does not matter — and worse, would tempt
someone to tune flags until it passed, which proves nothing about the
filesystem.

The two properties it does assert:

1. **Content equivalence** — unpack the dump, rebuild, unpack the rebuild,
   compare the trees including **modes, types, sizes and symlink targets**. A
   `/usr` that lost its exec bits mounts perfectly and boots to nothing.
2. **Determinism** — build twice, compare bytes. Without it, "the image I
   tested" and "the image I flashed" are two artefacts that merely came from the
   same command.

Vendor byte-identity is reported when it happens, as a bonus signal. It is never
required and never the reason to proceed.

---

## Sequence

| # | step | writes flash? | gated on UART? |
|---|---|---|---|
| 1 | Wire UART on the target unit, see a u-boot prompt | no | — |
| 2 | `special.sh`-only tarball, self-disarming, TF path | **no** | no |
| 3 | Round-trip `B` unchanged, verify, build image | **no** | no |
| 4 | Flash that image to `B` | **yes** | **yes** |
| 5 | `B` plus one added file | **yes** | **yes** |
| 6 | `A`, then `KERNEL` | **yes** | **yes** |

Steps 2 and 3 are built and tested. **Never `C`. Never `D`.**
