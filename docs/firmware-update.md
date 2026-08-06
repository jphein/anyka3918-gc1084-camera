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

> ⚠️ **Scope: this applies to ONE camera, not the fleet.** JP has **one Anyka**
> and twelve **EYEPLUS** icam365s — a different SoC, a different updater, a
> different everything. The card writer, this update tooling and the OTA path are
> Anyka-only.
>
> **The parts that generalise are [identity](identity.md) and inventory**, and
> even those need a different *read* path on the EYEPLUS units — the scheme
> travels, the transport does not. Do not mistake this page for the fleet's
> upgrade path; **it is the upgrade path for a thirteenth of it.**
>
> ❌ **This said "two Anykas… a sixth of it" until 2026-08-06.** The second unit
> was an **icam365 in an identical case** —
> [tell them apart by OUI](hardware.md#-two-vendors-one-case--tell-them-apart-by-oui)
> before assuming anything about a device in your hand.
>
> 🔑 **The consequence that matters is not the arithmetic.** With one Anyka and no
> UART wired to it, **the spare card is that camera's only recovery path** — there
> is no second unit to fall back on and no partition whose loss leaves a reachable
> device. That raises the spare card from convenience to the sole fallback, which
> is [what the gate below is protecting](#the-gate-recovery-first).

---

## The gate: recovery first

### The bootloader is out of the updater's reach — MEASURED

Flash layout, anchored on `kernel_addr=0x31000` from the `ENV` partition and
sized from `/proc/mtd`. **Every partition boundary below was confirmed by
dumping 4 KB at the computed offset and md5-matching it against the
corresponding `/dev/mtdblockN`** (`lucid-camera`, 2026-08-06) — not derived,
checked:

| offset | region | size |
|---|---|---|
| `0x000000` | **u-boot + strings** | ~196 KB — **no partition name maps here** |
| `0x031000` | `KERNEL` | 0x180000 |
| `0x1B1000` | `MAC` | 0x1000 |
| `0x1B2000` | `ENV` | 0x1000 |
| `0x1B3000` | `A` (`/`) | 0x100000 |
| `0x2B3000` | `B` (`/usr`) | 0x2F5000 |
| `0x5A8000` | `C` (`/etc/jffs2`) | 0x10000 |
| `0x5B8000` | `D` (`/data`) | 0x22A000 |
| `0x7E2000` | spare | ~120 KB |

**Nothing maps below `0x31000`.** Combined with the fact that nothing resolves
to `mtd0` either — `updater` builds
`/sys/kernel/partition_table/<NAME>/mtd_index` and errors when the directory is
absent — **there is no string you can pass that reaches the bootloader.** Not a
convention being honoured; there is no name to type.

> ⚠️ **This page briefly claimed `MAC` and `ENV` were inside the pre-`KERNEL`
> span. They are not — they sit at `0x1B1000`/`0x1B2000`, after the kernel.**
>
> That was a **correction that made a correct statement wrong**, which is worse
> than the original error and worth recording as its own failure. The original
> said "196 KB before `KERNEL`, none of it inside a named partition" — true. I
> then found `erase_env=sf erase 0x20000 0x2000`, took `0x20000` to be the
> environment, and rewrote the layout around it.
>
> **The single piece of contradicting evidence was real; my reading of what it
> pointed at was not.** Reading the actual bytes at `0x20000` settles it: they
> are u-boot's own code and strings (`Check read OK`), not an environment. See
> [backlog](backlog.md) — *a correction is trusted more than the original.*
>
> `erase_env` therefore points **into u-boot's code region**. Stale, from another
> board revision, or a vendor bug that would erase part of the bootloader —
> unknown, and **not evidence about anything.**

### 🔴 `bootdelay=0` — MEASURED, and it is the open risk

```
bootdelay=0
console=ttySAK0,115200n8
bootcmd=run boot_normal
boot_normal=readcfg; run read_kernel; bootm ${loadaddr}
```

**There is no countdown to interrupt.** Whether this build still polls for a
keypress at zero delay is a compile-time option that **cannot be read from the
environment** — it needs the case open to settle. Until then, *a prompt is
reachable* is an assumption, not a fact.

### The `ENV` slot is writable — and nobody can build an image for it

`ENV` is slot `3`, and `updater` resolves slots by generic sysfs lookup with **no
name whitelist**, so `updater local ENV=<image>` would rewrite the environment
over the network with no console. Setting `bootdelay=3` that way would make every
future flash recoverable at a prompt — turning "no partition is survivable" into
a one-time setup step.

**It is blocked on something simpler than risk: the format is not standard
u-boot, so there is no way to produce a valid image.**

```
offset 0:  ff ff ff ff        offset 4:  b6 f1 7b fa
offset 8:  backuppage=ffffffff\0baudrate=115200\0boot_normal=...
variables end at 0x320; the remaining 3.3 KB is 0x00 padding
```

A standard u-boot environment is `crc32 || data`, or `crc32 || flags || data`.
**This is neither.** crc32 was computed over every plausible range — `4..end`,
`5..end`, `8..end`, `8..end+2`, `8..len`, `4..len`, `0..len`, `0..4`+`8..len`,
with and without the terminating NUL — and **none matches the field at offset 4**
in either endianness.

Two leads if anyone ever reverses it: the first variable is literally
**`backuppage=ffffffff`**, mirroring the first four bytes — so the vendor appears
to have its own backup-page scheme rather than u-boot's redundant-env format.
And `boot_normal` begins with **`readcfg`**, a *custom* u-boot command; whatever
parses this partition is inside that.

> **The practical upshot: a hand-built env would be rejected and u-boot would
> fall back to compiled-in defaults — silently.** Which is the failure this
> project keeps meeting, arriving by a new route.

**That is not inference from how u-boot usually behaves — it is compiled into
this one.** Strings from the `0x20000` region (`lucid-camera`):

```
## Error: bad CRC, import failed
## Resetting to default environment
Saving Environment to %s...
env_buf [%d bytes] too small for value of "%s"
```

Which also explains why `erase_env` was so convincing: **`0x20000` is where
u-boot's environment-*handling code* lives.** The address sits right beside the
subsystem it appears to describe — a plausible-looking wrong constant, adjacent
to the thing it seems to name. Both readers took it as evidence for the same
reason.

`readcfg` is **not** in that 8 KB window; it is elsewhere in the `0x00000–0x20000`
bootloader region, which is where anyone reversing this format should look.

*(An earlier draft here argued the risk was a redundant 4 KB/8 KB env pair. That
rested on `erase_env` pointing at the environment, which it does not. **Refuted —
the inference was reasonable and the anchor beneath it was wrong.**)*

> **Order stands: get a console once with the clip and establish whether a prompt
> is reachable at all.** There is now no shortcut worth weighing it against — the
> shortcut needs a format nobody has.

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
