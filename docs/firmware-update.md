# Custom firmware — the updater, and how to use it without bricking a camera

The stock firmware ships a **complete, working updater** with no cloud and no
account. Nobody had read it until 2026-08-06. This is what it does, what it does
*not* check, and the sequence for getting our own image onto a camera.

> 🔴 **Nothing in this repo has been flashed to a camera.** Every tool here
> produces files. As of 2026-08-06 no camera has taken a custom image.
>
> **Recovery on cam1 is: open the case, clip on a pogo clip, connect
> USB-serial.** JP has done this before — it is how the hack was worked out.
> **There is no network recovery from any bad flash**, because the exploit
> trigger lives on `B`. See [the gate](#the-gate-recovery-first).

---

## The gate: recovery first

### The bootloader is out of the updater's reach — MEASURED

The `ENV` partition (`mtd3`, read out 2026-08-06) gives the layout directly:

```
kernel_addr=31000        erase_env=sf probe ...; sf erase 0x20000 0x2000
```

which matches the boot log's `SF: 1417200 bytes @ 0x31000 Read: OK`. So:

| region | span | contents |
|---|---|---|
| **0x00000 – 0x20000** | **128 KB** | **u-boot — no partition name maps here** |
| 0x20000 – 0x22000 | 8 KB | the u-boot environment (`erase_env` erases this) |
| 0x22000 – 0x31000 | 60 KB | unaccounted |
| 0x31000 → | | `KERNEL`, `A`, `B`, `C`, `D` in order |
| 0x7E0000 – 0x800000 | 128 KB | spare at the end |

> ⚠️ **An earlier version of this page said "196 KB before `KERNEL`, neither
> inside any named partition." The first half is right and the second is wrong.**
> `MAC` and `ENV` *are* named partitions and they sit inside that 196 KB, at
> 0x20000. The arithmetic was sound; the sentence summarising it over-reached —
> the same shape as the collision-cap claim in
> [identity.md](identity.md). **Prose drifts, data doesn't.**

**The narrower claim is the true one, and it is still sufficient: u-boot
occupies roughly the first 128 KB, and no partition name maps to it.**

**ANSWERED 2026-08-06 (`lucid-camera`): nothing resolves to `mtd0` either.** The
table is exactly `KERNEL→1 MAC→2 ENV→3 A→4 B→5 C→6 D→7`; `mtd0` is `"spi0.0"`,
the whole 8 MB flash, and no name maps to it. Since `updater` builds
`/sys/kernel/partition_table/<NAME>/mtd_index` and errors when the directory is
absent, **there is no string you can pass that reaches the bootloader.** Not a
convention being honoured — there is no name to type.

### 🔴 `bootdelay=0` — MEASURED, and it is the open risk

Straight out of the environment:

```
bootdelay=0
console=ttySAK0,115200n8
bootargs=... root=/dev/mtdblock4 rootfstype=squashfs init=/sbin/init
```

**There is no countdown to interrupt.** Whether this u-boot build still polls
for a keypress at zero delay is a compile-time option that **cannot be read from
the environment** — it needs the case open to settle. Until then, *a prompt is
reachable* is an assumption, not a fact.

### The `ENV` slot is writable from a running system — and that cuts both ways

`ENV` is slot `3`, and `updater` resolves slots by generic sysfs lookup with **no
name whitelist**. So `updater local ENV=<image>` would rewrite the u-boot
environment **over the network, with no serial console** — and setting
`bootdelay=3` would make every future flash recoverable at a prompt. `ipaddr`,
`serverip` and `netmask` are already populated, which suggests network support
is compiled in, so a reachable prompt plausibly means TFTP recovery rather than
just a prompt.

**Not recommended yet, for three reasons — the third found by arithmetic:**

1. **A bad `ENV` write is a brick upstream of everything, including the clip.**
   If u-boot cannot parse its environment it falls back to compiled-in defaults,
   which may or may not boot this board.
2. **`updater local ENV=` has never been run.** The mechanism is established;
   that it works is **inferred from how `updater` resolves names, not measured.**
3. ⚠️ **`/proc/mtd` says `ENV` is 4 KB. `erase_env` erases 8 KB at 0x20000.**
   That is the signature of a *redundant* u-boot environment — two 4 KB copies
   with a flags byte, where u-boot picks the valid one. **Writing only `mtd3`
   would update one copy and leave the other stale**, and which one wins is
   decided by a flags byte a naive image would get wrong. A u-boot environment
   is `crc32 + data`; a wrong CRC is silently rejected and you get defaults.

> **Order: get a console once with the clip and establish whether a prompt is
> reachable at all. Only then consider setting `bootdelay` remotely.** Doing it
> the other way risks bricking to gain a recovery path nobody has confirmed
> exists.

### The console IS reachable — and my earlier write-up was wrong about this

u-boot is interactive (`U-Boot 2013.10.0-AK_V2.0.04`, console
`ttySAK0,115200n8`).

> 🔴 **This page previously said "nobody has had a serial console on one of JP's
> cameras." That was false.** JP has had UART on his own camera — *"uart is how
> we figured all this out"* — and he uses a **pogo clip**: spring-loaded pins
> held against the pads. No soldering, no pin header, nothing permanent.
>
> **The claim was an inference from the absence of artifacts in this repo.** Every
> UART log here is from a different board revision, so "the repo has no evidence
> of a console on JP's units" was true — and it was reported as "no console has
> ever been brought up on JP's units", which is a claim about the world. JP's own
> work simply isn't in the repo. See [backlog](backlog.md) — *the repo is not the
> world.*

**So the real recovery cost is: unscrew the case, clip on, connect USB-serial.**
Repeatable, non-destructive, on demand, with a tool JP already owns and has
already used successfully on this hardware. Not "solder blind to bare pads using
another revision's photos".

### ⚠️ But *had UART once* is not *can interrupt u-boot now*

Two different facts, and only the second is a recovery path:

| fact | status |
|---|---|
| a console can be brought up on cam1 | **established** — JP has done it |
| **the boot can be interrupted to reach a u-boot prompt** | **unverified on cam1** |

**Autoboot delay is 0** on the revision we have logs for, so catching u-boot
means spamming the serial line from power-on rather than waiting for a prompt.
A console that comes up *after* the kernel has already booted shows you a login,
not a bootloader — and a bootloader is what re-flashes a dead partition.

> **Confirm a u-boot prompt actually appears on cam1 the next time the case is
> open.** It costs nothing extra while in there, and it is the distinction that
> would otherwise be discovered at the worst possible moment.

### The gate as it now stands

- **Steps 2 and 3 (no flash writes): proceed.** Unchanged.
- **Step 4 (first real flash): JP has the clip and adapter to hand when it
  runs.** The meaningful precaution is *not flashing unattended*, so recovery is
  minutes away rather than a discovery. Requiring UART be *proven* first would
  mean opening the case to establish that we could open the case.

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
| `B` | 5 | `/usr` squashfs | **No** — see below. Answered 2026-08-06. |
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

### `B` is NOT survivable — the exploit trigger lives on it

`B` mounts *after* boot, so a corrupt `/usr` looked like it might still leave a
booting device. It does not, and the reason is exact.

**`/usr/sbin/service.sh` is what executes `/Factory/config.sh`** — and
`/usr/sbin` is `/dev/mtdblock5`, which is slot `B` (confirmed with `df /usr/sbin`
by `lucid-camera`, 2026-08-06):

```
service.sh:179   if test -d /mnt/Factory ; then
service.sh:180       FACTORY_TEST=1
service.sh:90    if [ $FACTORY_TEST = 1 ]; then
service.sh:91        /mnt/Factory/config.sh
```

**The entire SD exploit is a directory-existence test on removable media.** And
the chain that reaches it is on `B` too: `rc.local:34` → `/usr/sbin/service.sh start`.

> **So a bad `B` flash destroys `service.sh`, the exploit never fires,
> `gergehack.sh` never runs, telnet never comes up.** No network recovery, for
> any partition.

**Every flash write on this hardware has exactly one recovery path: the pogo
clip and a u-boot prompt.** There is no partition whose loss leaves a
network-reachable device.

*(`/` is `/dev/root` = mtd4 = `A`, confirmed separately — so `A` was correctly
ruled out; the trigger simply isn't there either.)*

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

The three properties it does assert:

1. **Content equivalence** — unpack the dump, rebuild, unpack the rebuild,
   compare the trees including **modes, types, sizes and symlink targets**. A
   `/usr` that lost its exec bits mounts perfectly and boots to nothing.
2. **Determinism** — build twice, compare bytes. Without it, "the image I
   tested" and "the image I flashed" are two artefacts that merely came from the
   same command.
3. **Superblock equivalence** — every field but the creation timestamp. Content
   equivalence proves the *files* match; it says nothing about how they are
   packed, **and the vendor kernel mounts the packing, not the tree.** A rebuild
   at the wrong block size unpacks to a perfect tree and may not mount at all.

Vendor byte-identity is reported when it happens, as a bonus signal. It is never
required and never the reason to proceed.

### Measured against the real partition — 2026-08-06

`/dev/mtdblock5` dumped read-only by `lucid-camera`
(md5 `55cc1df1becd3d78d9ea84f99dd43370`, gated both ways) and run through the
tool:

| check | result |
|---|---|
| determinism | two builds byte-identical |
| fits slot `B` | **2,826,240 of 3,100,672** — 91% full, **274,432 spare** |
| content | tree identical, contents and symlinks |
| metadata | modes, types, sizes, symlink targets preserved |
| superblock | **matches on every field but the timestamp** — xz, 131072, 6 fragments, 281 inodes, and the same 2,824,044-byte filesystem size |
| byte-identity | differs in 2,214,567 payload bytes — **expected**, a different xz encoder |

**So a verified `usr.sqsh4` can be built from the camera's own `/usr` on demand,
with 274 KB of headroom for anything added.** It is not armed: arming means
passing it to `build-update-tar.sh --usr-sqsh4` and putting the result on a card.

---

## Sequence

| # | step | writes flash? | precondition |
|---|---|---|---|
| 1 | Confirm a **u-boot prompt** appears on cam1 (not just a console) | no | next time the case is open |
| 2 | `special.sh`-only tarball, self-disarming, TF path | **no** | none — recovery is pulling the card |
| 3 | Round-trip `B` unchanged, verify, build image | **no** | a read-only `mtdblock5` dump |
| 4 | Flash that image to `B` | **yes** | **clip + adapter to hand, not unattended** |
| 5 | `B` plus one added file | **yes** | same |
| 6 | `A`, then `KERNEL` | **yes** | same |

Steps 2 and 3 are **built and tested** (`tools/fw/selftest.sh`, 25 assertions,
no camera required). Step 3 needs a dump before it can run against the real
partition.

**Never `C`. Never `D`.**

> The precaution on step 4 is *not flashing unattended* — so that a bad write is
> minutes from recovery rather than a discovery. Requiring UART be *proven*
> first would mean opening the case to establish that we could open the case.
