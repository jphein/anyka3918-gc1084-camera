# Original SD card — the actual working configuration

Recovered 2026-08-05 from the camera's original SD card (FAT32, label `YICAM`). This is the
real, known-good configuration, as opposed to upstream's templates in `../sd-card-hack/`.

## The irreplaceable files

| File | Why it matters |
|---|---|
| `isp_gc1084.conf` | ISP sensor tuning for the GC1084. **Exists nowhere upstream and nowhere else on disk.** Upstream ships gc1034/gc1054/sc1135/etc. but never gc1084. |
| `sensor_gc1084.ko` | The GC1084 sensor kernel module. Also absent upstream. |
| `sensor.tgz` | The archive the camera carries in `/etc/jffs2/`, containing both files above. |

A full backup of the card lives outside the repo at
`~/Backups/anyka-yicam-sd-2026-08-05/` (files archive + FAT32 boot sector + a compact
mountable image).

## What the working settings actually were

From `anyka_hack/gergesettings.txt` (WiFi password redacted). The values that differ from
upstream's defaults are the interesting ones:

| Setting | Value | Note |
|---|---|---|
| `wifi_ssid` | `iot` | See the WiFi section below — this is what broke. |
| `sensor_kern_module` | `/mnt/sensor_gc1084.ko` | **The fix for the sensor mismatch.** Upstream defaults to `/usr/modules/sensor_h63.ko`, the wrong sensor. Pointing it at the `.ko` on the SD card is how this camera works. |
| `time_source` | `10.0.8.1` | The camera lived on the IoT VLAN (VLAN 8). |
| `rootfs_modified` | `0` | Upstream default is `1`. |
| `run_ipc` | `0` | Stock `anyka_ipc` cloud daemon stays off. |
| `image_width`/`image_height` | `640` / `360` | Sub-channel resolution. |
| `extra_args` | `-i 4 -u` | Passed to `libre_anyka_app`. |
| `run_telnet`, `run_ftp`, `run_web_interface`, `run_ptz_daemon`, `run_libre_anyka` | all `1` | Matches what the root README reports working. |

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

So the camera works only as long as the `isp_gc1084.conf` symlink already exists in the
`/etc/jffs2` flash partition. If flash is ever reset, this script will silently fail to
recreate it and you will get a camera with no working sensor config. The same typo is in the
root README's snippet. Fix it in both if you rebuild the card.

## The WiFi problem that took this camera offline

`wifi_ssid=iot`, but as of 2026-08-05 **no access point on the property broadcast `iot`** — all
12 APs were checked. The SSID had been renamed to `jplovescl` (same VLAN 8, and verified to use
the **same PSK**), so the camera was looking for a network that no longer existed. That is why
it never even attempted 802.11 association and no AP logged a failed auth from it.

Pinned to the exact date: north-office still has the pre-change backups, and
`/etc/config/wireless.pre-iot-prefix-delete-2026-04-28` contains `option ssid 'iot'` and
`option ssid 'iot-office'`. So the SSID was removed on **2026-04-28**, and the camera has been
offline since.

Resolved by adding an `iot` SSID on the **north-office** AP (`10.0.6.101`) as a mirror of
`jplovescl` — `radio0` (2.4 GHz channel 6; the camera is 2.4 GHz only), `psk2`, same key —
bridged to a new `network.cams` interface on `br-lan.10`, the **cams VLAN**, so the camera now
sits with the Hikvisions at `10.0.10.20` and inherits that VLAN's cloud-egress blocking. VLAN 10
was already tagged on the AP's trunk; only the interface definition was missing. Prior configs
are backed up on the AP at `/root/backups/wireless-backup-20260805-preiot.conf` and
`/root/backups/network-backup-20260805-precams.conf`.

Two consequences of living on the cams VLAN:

* `time_source` was updated in the camera's flash copy (`/etc/jffs2/gergesettings.txt`) from
  `10.0.8.1` to `10.0.10.1`. It still doesn't sync — NTP to the router is blocked from that
  zone — so the camera clock reads 1969. Harmless for HA, which timestamps its own frames.
* The copy of `gergesettings.txt` in this directory is the **card's** version and still says
  `time_source=10.0.8.1`. Update it before rebuilding a card.

The longer-term choice is either to keep that mirror SSID, or to edit `gergesettings.txt` to say
`wifi_ssid=jplovescl` and drop the mirror.
