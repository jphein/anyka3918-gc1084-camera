# Reference material

Third-party material this project depends on, vendored here so the camera can be re-hacked
without re-hunting downloads. Everything in this directory was copied out of `~/Downloads`
on 2026-08-05; the original archives are still there.

## Provenance

| Path | Upstream | License | Downloaded |
|---|---|---|---|
| `sd-card-hack/`, `isp_sensor_conf/`, `UART_logs/`, `hardware/`, `IR_shutter.txt`, `hack-process.md` | [Gerge — Anyka_ak3918_hacking_journey](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/) | GPL-3.0 | 2024-09-13 12:42 |
| `libre_anyka_app-standalone` | libre_anyka_app (prebuilt ARM binary) | GPL-3.0 | 2024-09-13 17:26 |
| `upstream/Anyka-Camera-Firmware-*` | Muhammed Kalkan — Anyka-Camera-Firmware | MIT | 2024-09-13 11:42 |
| `upstream/Anyka-*` | Anyka (filesystem / root-access notes) | unstated | 2024-09-14 12:33 |

This repo is GPL-3.0, which is compatible with both upstream licenses. Upstream license texts
are preserved verbatim in `upstream/`.

## What's here

- **`sd-card-hack/`** — the SD-card payload that bootstraps the hack. `Factory/config.sh` is the
  file the stock firmware executes from the SD card; `anyka_hack/gergehack.sh` is the hack script
  itself; `anyka_hack/gergesettings.txt` holds its settings. The subdirectories are prebuilt ARM
  binaries: `rtsp/` and `libre_anyka_app/` (video), `ptz/` (pan/tilt), `web_interface/` (the web UI
  — its CGI scripts are the source of truth for [`../docs/web-ui.md`](../docs/web-ui.md), and all
  twelve md5-match what is deployed on the camera), `snapshot/` + `jpeg_snapshot/` (stills), and
  the `*_demo/` dirs for audio and motion detection.
- **`isp_sensor_conf/`** — ISP sensor tuning configs. **Note the gap:** upstream ships configs for
  gc1034, gc1054, sc1135, sc1235, sc1245, sc2232, F37, and h63 — but *not* gc1084, which is this
  camera's sensor. See the warning below.
- **`hardware/`** — board photos and the AK3918 datasheet (`ak3918.pdf`).
- **`UART_logs/`** — serial boot logs, useful when the camera won't come up.
- **`hack-process.md`** — upstream's write-up of the hack procedure.
- **`IR_shutter.txt`** — upstream notes on the IR cut filter (the thing that clicks), which the
  root README covers.

## ✅ `isp_gc1084.conf` has been recovered

**This was previously listed here as missing and unrecoverable. It is not — it was recovered on
2026-08-05 and is committed.**

The GC1084 ISP config does not exist upstream and existed nowhere else on the workstation. It
lived **only on the camera**, compressed inside `/etc/jffs2/sensor.tgz` and extracted at boot to
`/tmp/sensor_ko_and_isp_conf/isp_gc1084.conf`. It is now in this repo:

| File | Path | Size | md5 |
|---|---|---|---|
| ISP tuning | [`sd-card-original/isp_gc1084.conf`](sd-card-original/isp_gc1084.conf) | 104238 | `85bab13dcdef87574341d713eb366f96` |
| Sensor module | [`sd-card-original/sensor_gc1084.ko`](sd-card-original/sensor_gc1084.ko) | 7551 | |
| Both, archived | [`sd-card-original/sensor.tgz`](sd-card-original/sensor.tgz) | 28805 | |

The checksum matches the copy on the running camera, verified over telnet.

So the irreplaceable artifact is no longer a single point of failure — if the camera's flash is
reset or the chip replaced, the sensor tuning can be restored from here. To re-pull it from a
camera anyway:

```
# on the camera
cat /tmp/sensor_ko_and_isp_conf/isp_gc1084.conf
# or grab the whole archive
cat /etc/jffs2/sensor.tgz
```

How the symlink works around the 64 KB flash partition is covered in
[`../docs/sd-card.md`](../docs/sd-card.md#the-sensor-problem).

## ⚠️ Before prepping an SD card — two traps in `gergesettings.txt`

`sd-card-hack/anyka_hack/gergesettings.txt` is the hack's config file, currently holding
upstream's **placeholders**. Two things to know:

1. **It is where the real WiFi credentials go** (`wifi_ssid=MyWifi`,
   `wifi_password=MyPassword`). This repo is public — do **not** commit the file with the real
   SSID and password in it. Edit the copy on the SD card, or `git update-index
   --skip-worktree` it locally. Same for `time_source=192.168.11.1`, which is a placeholder
   router IP.
2. **The sensor kernel module defaults to the wrong sensor:**
   `sensor_kern_module=/usr/modules/sensor_h63.ko`. This camera is a **GC1084**, so that line
   needs the GC1084 module instead. This is the same sensor mismatch the root README works
   around for the ISP config — it applies to the kernel module line too.

The rest of the settings match what the root README reports working: `run_telnet=1`,
`run_web_interface=1` (PTZ web UI), `run_ptz_daemon=1`, `run_libre_anyka=1` (RTSP + snapshot),
sub-channel `640x360`, and `run_ipc=0` / `rootfs_modified=1` to keep the stock `anyka_ipc`
cloud daemon from starting.

## Deliberate exclusions

- `ffmpeg` (37 MB) and `curl` (5.7 MB) from `anyka_hack/` — large general-purpose ARM builds,
  re-downloadable from upstream, and not needed for the RTSP + PTZ + audio path this project uses.
- `dropbear` host keys — the upstream archive ships a private `dropbear_ecdsa_host_key`. This repo
  is public, so all key material was filtered out. The `dropbear` binary is kept; generate a fresh
  host key on the camera instead of reusing a published one.
- Upstream's `cross-compile/` (27 MB toolchain), `Images/` (53 MB photos), `firmware_dump/`
  (8.1 MB), and `newroot/` (5.5 MB) — pull from upstream if a rebuild or firmware restore is
  ever needed.
