# The SD card

**The SD card is the camera's brain.** `/Factory/config.sh` is what the stock firmware executes
at boot — that is the exploit — and `/anyka_hack/` holds every binary the hack starts. No card,
no RTSP, no PTZ, no telnet, no web UI.

**Each camera needs its own card.** Cards are not shareable between units, and with a bag of
these cameras, cloning cards is the normal workflow.

## Writing a card

```sh
sudo tools/write-sd-card.sh /dev/sdX (--ssid NAME | --keep-ssid) \
                            [--time-source IP] [--unit-name "Front Door"] [--stock]
                            [--force-wipe]
```

[`tools/write-sd-card.sh`](../tools/write-sd-card.sh) writes a ready-to-run card from the
2026-08-05 backup, **with this project's fixes baked in**. What it does, in order:

1. Refuses to run unless the target is a **removable whole disk** that is not hosting `/`, and
   makes you type `ERASE` to confirm.
2. `dd`s `header-first-4MB.img` — the partition table and FAT32 boot sector, byte-exact.
3. **Reformats partition 1 as FAT32** with label `YICAM` and volume id `8D1BDED7`. The header
   only carries FAT structures sized for the original 7.4 GB card, so the filesystem is always
   rebuilt to match whatever card is actually in hand.
4. Extracts `yicam-files.tar.gz` onto it.
5. Applies the fixes below.
6. Prints the resulting settings, with the password withheld, plus any warnings.

| Flag | Effect |
|---|---|
| `--ssid NAME` | Rewrites `wifi_ssid=`. **Does not change the PSK.** |
| `--keep-ssid` | Accept the backup's baked-in SSID. **One of these two is required** — see below |
| `--time-source IP` | Rewrites `time_source=`. Worth using — see the warning below. |
| `--unit-name NAME` | Names this camera, e.g. `"Front Door"`. **Optional** — an unnamed camera [names itself from its own MAC at first boot](identity.md). Only takes effect on a camera that has never been named |
| `--stock` | Writes the backup **unmodified**, with no project fixes. Escape hatch. |
| `--force-wipe` | Overrides the "this does not look like a camera card" refusal. **Read the section below before using it.** |

## The tool refuses a device that does not look like a camera card

Before erasing anything, the writer checks the **shape** of the target. A camera
card is one of exactly two things:

- **blank / unpartitioned**, or
- **a single FAT32 partition** — a card this tool wrote before, or a new card as
  sold.

Anything else is refused, by name:

```
error: /dev/sdc does not look like a camera card, so this tool is refusing it.

  A camera card is blank, or a single FAT32 partition. This device has 3
  partitions:

      sdc1 ntfs     MULTITOOL
      sdc2 vfat     BOOTSTRAP
      sdc3 squashfs

  and these are MOUNTED RIGHT NOW - something is using this device:

      /dev/sdc1 -> /media/jp/MULTITOOL
      /dev/sdc2 -> /media/jp/BOOTSTRAP
      /dev/sdc3 -> /media/jp/disk

  If that is genuinely the card you meant, pass --force-wipe. If it is a
  multitool, an installer, a backup or somebody's photos, this refusal just
  saved it.
```

### Why it exists

That is not a hypothetical. On 2026-08-06, asked to write a card, **the only
removable device present was JP's bootable Multitool card** — and it passed every
check the tool had at the time. `removable=1`: yes. Not the system disk: correct.
Backup present: yes.

**The only thing between it and an erase was a human reading an `lsblk` listing
at the ERASE prompt**, at the end of a long session. It then happened *again*,
to a second person, thirty minutes later.

> **Printing evidence and requiring interpretation is not a guard.** It fails
> precisely when the operator is in a hurry — which is when destructive tools get
> run.

The `lsblk` print before the ERASE prompt is still there and is still right. It
just needed a refusal behind it.

### `--force-wipe` — and why the override is correct

**Use it when the device really is the card you meant** and it happens to carry
something else: a card previously used for another purpose, a multi-partition
layout, a non-FAT filesystem.

The override existing is not a weakness in the guard. **The guard's job is to
convert *"an operator skims a partition table"* into *"a human is asked a direct
question about a specific named artifact."*** It succeeded the first time it
fired: the refusal named `MULTITOOL`, that was taken to JP rather than overridden,
JP said *"yes, I don't even remember that multitool"*, and only then was
`--force-wipe` used.

> **The override has to cost a sentence, not a battle.** A guard with no escape
> hatch teaches people to reach for `dd`, which has no guard at all — so an
> undocumented override makes a correctly-working refusal *less* safe, not more.

**Before typing `--force-wipe`, name out loud what is on the device and who owns
it.** If you cannot, that is the answer.

> **Why `--ssid` is required and `--unit-name` is not**, since the asymmetry looks arbitrary: a
> wrong SSID **strands the camera**, and a missing name strands nothing — the camera derives one.
> Required-ness here tracks *what happens when you omit it*, not how important the field feels.

### 🔴 The SSID decision is required, and the reason is the worst failure this hardware has

**The tool refuses to run without `--ssid NAME` or `--keep-ssid`.** That is deliberate friction.

The backup carries a baked-in `wifi_ssid`, and **a card written for a retired SSID produces a
camera with no network path and no console.** There is nothing to log into, nothing to look at,
and — because a station configured for an absent SSID never sends auth frames — **nothing appears
in any association list or failed-auth log anywhere.** It is indistinguishable from dead hardware.

This project already lost a camera for **four months** to exactly that.
[The post-mortem](troubleshooting.md#the-2026-outage-a-renamed-ssid) is worth reading before you
write a card for a network you have not checked.

> **`--keep-ssid` is a one-word affirmation, not an obstacle.** It means *"I know what SSID is
> baked in and I want it."* The point is only that the value is never chosen **by default**.

**Before erasing anything**, the tool prints the SSID and `time_source` the card will carry, and
flags each one as *set by flag* or *inherited from the backup*.

> 🔑 **That preflight replaced a warning that fired at the end of the run** — and the distinction
> generalises past this tool. **A warning that arrives after the destructive step is documentation,
> not a guard**, because by then the only available action is to do the whole thing again. Both
> values are silent-failure modes on the camera: a wrong SSID never associates, a wrong
> `time_source` never syncs. Neither announces itself.
>
> If the SSID cannot be read out of the backup, `--keep-ssid` **fails hard** rather than warning.
> "Keep the value I can see" is meaningless when nobody can see it.

### What gets fixed

Without these, a fresh card boots a camera with a **15-hour-wrong clock**, a **live pre-auth root
RCE**, and an **IR-cut filter stuck in the magenta position**.

| Fix | Why |
|---|---|
| `time_zone=PST8PDT,M3.2.0,M11.1.0` | The backup ships `GMT-08:00`, which POSIX reads as **UTC+8**. [Detail](troubleshooting.md#the-clock--ntp-works-the-timezone-was-15-hours-wrong-on-every-service) |
| `ptz_init_on_boot=1` | The daemon needs homing before it will move. [Detail](ptz.md#-the-homing-command-is-init_ptz-not-init) |
| `cgi-bin/ctl` installed, mode 755 | Our fast control endpoint — not upstream's. [Detail](web-ui.md#cgi-binctl--our-fast-control-endpoint) |
| `/sounds/` created | Where `ctl`'s `play` and `sounds` commands look |
| Missing `]` in `Factory/config.sh` | [Upstream's bracket bug](#-latent-bug-in-factoryconfigsh), which stops the sensor symlink ever being recreated |
| `cgi-bin/header` hardened | Closes the [pre-auth root RCE](web-ui.md#the-fix) on port 80. **Not** kernel-specific — applies unconditionally |
| Boot-time IR-cut write in `Factory/config.sh` | Puts the filter in the non-magenta position 60 s into every boot. **JP relies on this**, and it was missing from the backup — [detail](ptz.md#the-boot-time-mitigation-is-user-relied-on-behaviour) |

**Exactly one binary is patched: `cgi-bin/header`.** It earns its place by closing a live remote
root hole, and it is kernel-agnostic. Everything else on the card is stock.

> ⛔ **Do not add a `libplat_drv.so` patch, and do not re-enable the `libre_anyka_app` one.**
>
> This warning has said several wrong things and is now on firm ground. It once said `ptz_daemon`
> "has the same bug" and a card should patch it too — **retracted**, that binary never runs. It
> then said the app patch should merely default to off — **also retracted**, it is confirmed inert
> and shipping it buys nothing while costing a whole detection scheme.
>
> [The full story](ptz.md#-root-cause-the-libplat_drvso-patch-tipped-the-driver-into-a-mode-for-other-hardware).

### ⛔ No binary IR-cut patch ships. Two were tried; neither belongs on a card.

| Patch | Verdict |
|---|---|
| `libre_anyka_app` (`gpio-ircut_a` → `ircut_a`) | **Confirmed inert.** It repairs the *write* end while the *sense* end stays broken in a different, unpatched `libplat_drv.so`, so the day/night thread bails before reaching any write |
| `ptz/lib/libplat_drv.so` (both names + `ir-led`) | **A regression.** Renaming *both* ircut names tips the driver into a 2-line pulse mode meant for a latching solenoid; this board's filter is hold-to-engage, so every command parked it **out** (magenta) |

**Automatic day/night is not fixable on this board at all** — the sense input is `gpio-rf_feed`,
which does not exist here, and the fallback ADC reads a constant. Nothing is lost by shipping
stock. [Full story](ptz.md#-automatic-daynight-is-not-fixable-on-this-board).

**What ships instead**, and it works: `ctl` writes `/sys/user-gpio/ircut_a` directly, and
`Factory/config.sh` puts the filter in the non-magenta position 60 s into every boot.

### 🔑 The per-boot selection: retained for reference, no longer used

**This machinery is dormant** — nothing shipped on the card is kernel-build-specific any more, so
there is nothing to select between. **It is documented because the two design insights in it are
good** and may be wanted again: *test the node, not the build string*, and *decide every boot, not
once*.

`libre_anyka_app` hard-codes the sysfs path it uses to move the IR-cut filter, and the two
vendor kernel builds disagree about that path:

| Build | Node |
|---|---|
| 2023 (`chensheng`) | `/sys/user-gpio/ircut_a` — **unprefixed** |
| 2022 (`zhoujiahui`) | `/sys/user-gpio/gpio-ircut_a` — **prefixed** |

The stock binary writes the prefixed name, so on a 2023 camera it gets `ENOENT` on every
transition. A patched binary writes the unprefixed name — and is then wrong on a 2022 camera,
for the same reason in reverse.

The scheme was: **carry both binaries and pick one at every boot**, by testing which node actually
exists:

```
libre_anyka_app.node-ircut_a         patched  -> 2023 build
libre_anyka_app.node-gpio-ircut_a    stock    -> 2022 build
```

The choice was made in [our `run_libre_anyka_app.sh`](../tools/card-overlay/anyka_hack/libre_anyka_app/run_libre_anyka_app.sh),
which is **still in the repo and no longer installed**.

Four properties followed, and they are why this is documented rather than deleted:

* **Swapping a card between cameras is safe and self-correcting.** It re-detects on the new
  unit. A one-shot first-boot marker would have been silently wrong after a swap — which is a
  thing that has already happened here.
* **Nothing is written at boot.** No binary is patched in place, so a power cut mid-boot cannot
  leave a corrupt executable.
* **No state.** No marker file, nothing to go stale, no "has this run?" logic.
* **It fails loudly.** If neither node exists, it says so on the console and falls back to stock
  rather than guessing.

> **Why the node name and not the kernel build string?** Parsing `/proc/version` for `chensheng`
> vs `zhoujiahui` would work today, but the build string is only a *proxy* for the thing the
> binary actually depends on. Testing the node directly handles a third vendor build for free
> and does not bet on a username.

The patched binary is kept at
[`reference/patches/libre_anyka_app.node-ircut_a`](../reference/patches/) **for documentation
only** — offset, bytes and md5 [are recorded there](../reference/patches/README.md). **The tool no
longer installs it.** It does check that the card's `libre_anyka_app` is the expected stock md5
and warns loudly if it is not, so a patched backup cannot slip onto a card unnoticed.

> ❌ **RETRACTED: "verified applied — effect not yet validated."** This block said the patch was
> correct and running and merely awaiting its first day/night transition. **The transition never
> came and never will** — [the day/night thread bails before reaching any
> write](ptz.md#the-vendor-apps-daynight-loop-is-confirmed-inert), because the *sense* end of the
> chain is broken in a different library nobody patched.
>
> The wording was careful and still not careful enough: *"the binary is correct and running"* was
> true, and it framed the only open question as **whether** the feature would work — when the two
> live questions were *what else changes when it does*, and *is anything else in the chain also
> broken?* **A patch awaiting validation is not a neutral state.**

> ⚠️ **The discriminator is `ircut_b`, not `ircut_a`.** Both would work, but `ircut_b` exists
> **only** in the 2023 build — verified by decompressing the 2022 kernel and counting
> NUL-delimited string-table entries, which found `gpio-ircut_a` and **no `ircut_b` at all**.
> Whereas `ircut_a` appears as a **substring inside `gpio-ircut_a`**, so a less careful test
> could match the wrong build. The launcher falls back to `uname -v` if no node is present, logs
> which branch it took, and defaults to stock when ambiguous.

The backup lives **outside the repo** at `~/Backups/anyka-yicam-sd-2026-08-05/`, because it
contains real credentials:

| File | What it is |
|---|---|
| `header-first-4MB.img` | Partition table + FAT32 boot sector |
| `yicam-files.tar.gz` | The card's file tree (~28 MB) |
| `yicam-compact.img` | A compact mountable image (256 MB) |
| `layout-lsblk.txt` | The original card's geometry |

Override the location with `BACKUP=/path/to/backup sudo -E tools/write-sd-card.sh ...`.

> ⚠️ `--ssid` changes the SSID but **not the PSK**. If the new network uses a different key,
> edit `wifi_password=` in `anyka_hack/gergesettings.txt` on the card afterwards. The script
> says so too.

### After writing

* The card sets the **root password** from `Factory/config.sh` on every boot. If you are
  deploying a camera somewhere less trusted, change it there before first boot.
* `sensor_kern_module` points at the GC1084 module **on this card**. A camera with a different
  image sensor will not produce video until that line and `isp_gc1084.conf` are swapped for the
  right sensor.
> ⚠️ **Only the 37 MB `ffmpeg` binary is excluded from this repo.** The two shell scripts that
> live alongside it — `app_restarter.sh` and `wrap_mp4.sh` — *are* vendored, at
> [`reference/sd-card-hack/anyka_hack/ffmpeg/`](../reference/sd-card-hack/anyka_hack/ffmpeg/).
>
> | Missing | Consequence |
> |---|---|
> | `ffmpeg` (37 MB binary) | Motion clips are never wrapped into MP4, and the Events page's "Run FFMPEG" button fails |
>
> They were originally excluded along with the binary simply because they share its directory,
> which took the **watchdog** with them — `app_restarter.sh` is what restarts `libre_anyka_app`
> when it dies, and `start_web_interface.sh` launches it unconditionally, so a card without it
> fails quietly at every boot and then has nothing keeping the camera alive.
>
> The backup at `~/Backups/anyka-yicam-sd-2026-08-05/` is a copy of the real card and **does**
> include all three, so `tools/write-sd-card.sh` produces a complete card. Only a card assembled
> by hand from `reference/sd-card-hack/` is affected.

## Settings precedence

This is the single most confusing part of the hack, and it is worth getting right before you
spend an evening on a setting that keeps reverting.

There are **two** copies of `gergesettings.txt`:

| Copy | Path | Role |
|---|---|---|
| SD card | `/mnt/anyka_hack/gergesettings.txt` | **Authoritative** |
| Flash | `/etc/jffs2/gergesettings.txt` | What the scripts actually read |

`Factory/config.sh` copies the SD version into flash **only if flash has none**. But
`gergehack.sh` then does this on *every* boot:

```sh
if [[ -f /mnt/anyka_hack/gergesettings.txt ]]; then
  myresult=$( diff /mnt/anyka_hack/gergesettings.txt /etc/jffs2/gergesettings.txt )
  if [[ ${#myresult} -gt 0 ]]; then
    cp /mnt/anyka_hack/gergesettings.txt /etc/jffs2/gergesettings.txt
    reboot
  fi
fi
```

It does the same for `gergehack.sh` itself.

### The WiFi credentials self-heal from `gergesettings.txt` on every boot

**There is a third copy of the WiFi config, and it is not one you edit.** `input_wifi_creds()` in
`gergehack.sh` compares the vendor's `anyka_cfg.ini` against `gergesettings.txt` on every boot and
**rewrites the vendor config on mismatch.**

Two consequences, and the second is the one that cost four months:

* ✅ **Editing `gergesettings.txt` alone is sufficient.** You never have to touch `anyka_cfg.ini` —
  the self-heal propagates the change for you. That is why `--ssid` only rewrites one file.
* 🔴 **A camera pointed at a dead SSID re-heals itself to the wrong value forever.** The mechanism
  only ever reads *from* `gergesettings.txt`; nothing ever writes *back* into it. So a stale SSID
  is not a value that drifts and might recover — it is **actively restored on every boot**, for as
  long as the card says so.

> 🔑 **This is what made [the 2026 outage](troubleshooting.md#the-2026-outage-a-renamed-ssid)
> permanent rather than transient**, and it is the part most people would guess wrong. Self-healing
> config sounds like a resilience feature. It is resilience *toward whatever the card says* — which
> is indistinguishable from resilience when the card is right, and is a latch that holds the fault
> in place when it is wrong.
>
> **The fix is always the card**, never the camera. A camera you cannot reach over the network
> cannot be fixed over the network, and this mechanism guarantees the wrong value comes back.

> ⚠️ **Editing `/etc/jffs2/gergesettings.txt` alone does not persist.** On the next boot
> `gergehack.sh` sees the difference, overwrites your edit from the card, and **reboots again**.
> The card always wins.
>
> This is not theoretical — it happened here. When the camera moved to the camera VLAN (VLAN 20),
> `time_source` was edited in flash from the old IoT-VLAN router to the new one, and the card
> reverted it on the next boot, leaving NTP pointed at an unreachable address. It was only fixed
> for good once **both** copies were changed. The docs then spent a while asserting the clock
> could not sync, long after it could — see
> [troubleshooting.md](troubleshooting.md#the-clock--ntp-works-the-timezone-was-15-hours-wrong-on-every-service).

So:

* **Changing settings for good** → edit the copy on the SD card, or edit both. Expect one extra
  reboot as they converge.
* **Testing a setting for this boot only** → edit flash, and remember it is temporary.
* **Via the web UI** → `settings_submit.sh` writes **both** copies when the card is mounted, so
  web UI changes stick correctly. That is the easiest correct path.

`tools/write-sd-card.sh` prints this as its first reminder after writing a card, so you get told
at the point it matters.

## The sensor problem

This camera's sensor is a **GC1084**. Upstream supports gc1034, gc1054, sc1135, sc1235, sc1245,
sc2232, F37 and h63 — but **not** gc1084. Two files bridge the gap, and neither exists upstream:

| File | Size | Purpose |
|---|---|---|
| `isp_gc1084.conf` | 104 KB | ISP tuning for the GC1084 |
| `sensor_gc1084.ko` | 7.5 KB | The sensor kernel module |

Both are now committed at [`reference/sd-card-original/`](../reference/sd-card-original/), along
with `sensor.tgz`, the archive the camera carries in `/etc/jffs2/`.

Two settings changes make it work:

```ini
sensor_kern_module=/mnt/sensor_gc1084.ko    # upstream default is /usr/modules/sensor_h63.ko
```

and the ISP config, which is where the 64 KB flash partition bites. `isp_gc1084.conf` is 104 KB
and **cannot fit in `/etc/jffs2`**, so it is a symlink instead:

```
/etc/jffs2/isp_gc1084.conf -> /mnt/isp_gc1084.conf
```

The camera also extracts `sensor.tgz` to `/tmp/sensor_ko_and_isp_conf/` at boot, so
`ln -s /tmp/sensor_ko_and_isp_conf/isp_gc1084.conf /etc/jffs2/` is an equivalent target. The
`/mnt` symlink is the one this camera actually uses, and it is the sturdier choice — `/tmp` is
tmpfs and the extraction has to have succeeded.

> ⚠️ **The sensor dropdown in the web UI cannot represent this configuration.** It is populated
> from `ls /usr/modules/sensor*.ko`, and this camera's module is on the SD card. Saving the
> Sensor & Image form will silently reset `sensor_kern_module` to an in-flash module and break
> video on the next boot. Edit `gergesettings.txt` directly.

## ⚠️ Latent bug in `Factory/config.sh`

Line 24 is missing its closing bracket:

```sh
FILE="/mnt/isp_gc1084.conf"
if [ ! -e "$FILE"; then      # <-- should be:  if [ ! -e "$FILE" ]; then
  tar -xzf /etc/jffs2/sensor.tgz -C /mnt
  ln -s /mnt/isp_gc1084.conf /etc/jffs2/
fi
```

To be precise about the impact, because it is easy to overstate:

* This is a **runtime** error, not a parse error. The shell parses `if <command>; then` fine —
  `[` is just a command, and the `;` terminates it. So `[` runs, complains `missing ]`, and
  exits non-zero.
* Because the test always fails, **the `tar` and the `ln -s` never execute.**
* It does **not** prevent `/etc/jffs2/gergehack.sh` on line 30 from running. The hack itself
  still starts.

So the camera works only as long as the `isp_gc1084.conf` symlink already exists in flash. If
flash is ever reset, this script will silently fail to recreate it and you get a camera with no
working sensor config. Fix it if you rebuild the card.

## Card contents

```
/Factory/config.sh                    the exploit entry point — stock firmware runs this
/anyka_hack/gergehack.sh              the hack itself
/anyka_hack/gergesettings.txt         settings (authoritative copy)
/anyka_hack/ptz/                      pan/tilt daemon
/anyka_hack/libre_anyka_app/          RTSP (554) + snapshots (3000)
/anyka_hack/web_interface/            busybox httpd + CGI web UI
/anyka_hack/web_interface/www/cgi-bin/ctl   fast control endpoint — OURS, not upstream
/anyka_hack/snapshot/, jpeg_snapshot/ stills helpers
/anyka_hack/rtsp/                     standalone RTSP
/anyka_hack/ffmpeg/                   MP4 wrapping + app_restarter watchdog
                                      (scripts vendored; 37 MB binary excluded)
/anyka_hack/*_demo/                   audio and motion-detection demos
/sounds/                              MP3 clips for ctl's play command, 16 kHz mono
                                      (rate matters; do NOT pre-attenuate - see docs/ptz.md)
/anyka_hack/dropbear/                 SSH (host keys stripped from this repo)
/isp_gc1084.conf, /sensor_gc1084.ko   the GC1084 files, symlink target for /etc/jffs2
```

## Building a card from upstream, from scratch

If you are starting from [Gerge's payload](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/)
rather than from the backup — for a camera that is not this exact model, say — this is what had
to be added on top for the TC20/GC1084.

**1. Invoke the hack from `Factory/config.sh`.** Add this at the bottom, before anything else
runs:

```sh
#gergedaemon and time_zone are not needed for the SD exploit
/etc/jffs2/gergehack.sh
```

**2. Set the root password**, so telnet is usable:

```sh
USER="root"
NEW_PASSWORD="<choose one>"
(echo "$NEW_PASSWORD"; echo "$NEW_PASSWORD") | passwd $USER
```

**3. Deal with the ISP config not fitting in flash.** The intended approach is to extract
`sensor.tgz` onto the card and symlink it — note the bracket bug documented above, which is in
upstream's snippet too:

```sh
FILE="/mnt/isp_gc1084.conf"
if [ ! -e "$FILE" ]; then          # upstream is missing the "]"
  tar -xzf /etc/jffs2/sensor.tgz -C /mnt
  ln -s /mnt/isp_gc1084.conf /etc/jffs2/
fi
```

In practice the camera already extracts the archive at boot, so symlinking the extracted copy
works too and needs no `tar`:

```sh
ln -s /tmp/sensor_ko_and_isp_conf/isp_gc1084.conf /etc/jffs2/
```

The `/mnt` target is the sturdier of the two, since `/tmp` is tmpfs.

**4. Point `sensor_kern_module` at the right module** — see [above](#the-sensor-problem).

Upstream's own write-up of the exploit is vendored at
[`reference/hack-process.md`](../reference/hack-process.md).

## Bringing up a new camera

1. Write a card: `sudo tools/write-sd-card.sh /dev/sdX --ssid <your-ssid>`.
2. If the SSID's key differs from the backup's, edit `wifi_password=` on the card.
3. Change `NEW_PASSWORD=` in `Factory/config.sh` on the card if you want a per-camera root
   password.
4. Consider setting `run_ftp=0` — FTP is on by default and is writable over the whole
   filesystem. See [web-ui.md](web-ui.md#other-listening-ports).
5. Boot the camera. Expect it to reboot itself once while the settings converge.
6. Find it: `nmap -n -Pn -p 3000,554 --open <subnet>/24`.
7. Give it a **DHCP reservation** so the address cannot be recycled.
8. If the sensor is not a GC1084, swap `sensor_kern_module` and the ISP config.

## See also

* [`reference/sd-card-original/`](../reference/sd-card-original/) — this camera's real config
* [`reference/sd-card-hack/`](../reference/sd-card-hack/) — upstream's template payload
* [`reference/README.md`](../reference/README.md) — provenance, licensing, what was excluded
* [troubleshooting.md](troubleshooting.md) — when a fresh card does not come up
