# The SD card

**The SD card is the camera's brain.** `/Factory/config.sh` is what the stock firmware executes
at boot — that is the exploit — and `/anyka_hack/` holds every binary the hack starts. No card,
no RTSP, no PTZ, no telnet, no web UI.

**Each camera needs its own card.** Cards are not shareable between units, and with a bag of
these cameras, cloning cards is the normal workflow.

## Writing a card

```sh
sudo tools/write-sd-card.sh /dev/sdX [--ssid NAME]
```

[`tools/write-sd-card.sh`](../tools/write-sd-card.sh) writes a ready-to-run card from the
2026-08-05 backup. What it does, in order:

1. Refuses to run unless the target is a **removable whole disk** that is not hosting `/`, and
   makes you type `ERASE` to confirm.
2. `dd`s `header-first-4MB.img` — the partition table and FAT32 boot sector, byte-exact.
3. **Reformats partition 1 as FAT32** with label `YICAM` and volume id `8D1BDED7`. The header
   only carries FAT structures sized for the original 7.4 GB card, so the filesystem is always
   rebuilt to match whatever card is actually in hand.
4. Extracts `yicam-files.tar.gz` onto it.
5. With `--ssid NAME`, rewrites `wifi_ssid=` in `anyka_hack/gergesettings.txt`.
6. Prints the resulting WiFi/sensor settings, with the password withheld.

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

> ⚠️ **Editing `/etc/jffs2/gergesettings.txt` alone does not persist.** On the next boot
> `gergehack.sh` sees the difference, overwrites your edit from the card, and **reboots again**.
> The card always wins.
>
> This is not theoretical — it already happened here. `time_source` was edited in flash from
> `192.168.8.1` to `192.168.1.1` after the camera moved to the cams VLAN. Both copies now read
> `192.168.8.1`: the flash edit was reverted from the card. (An earlier note in
> `reference/sd-card-original/README.md` recorded the intended value; the camera disagrees.)

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
                                      (see docs/ptz.md — rate and volume both matter)
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
