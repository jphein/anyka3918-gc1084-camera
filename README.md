# ak3918-gc1084-camera RTSP integration for Home Assistant with go2rtc
## 
* Brand: Teruhal
* Model: TC20
* FCC ID: 2BEXJ-TC20
* MPU: AK3918EN080 V200 CDSJ09J23
* WiFi: ZT9101UV20
* Camera sensor: GC1084
* APP: [Yi IOT](https://play.google.com/store/apps/details?id=com.yunyi.smartcamera&pcampaignid=web_share)

## What's working?
* WiFi
* Video
* Sound
* PTZ - Pan and Tilt (Oly from the webui. Haven't figured this out from Home Assistant yet)

I got my camera from temu: https://share.temu.com/A5qeTOEZVbA Price is in the $3 to $8 range. 
![image](https://github.com/user-attachments/assets/c23b2242-16df-46c6-87fc-d2d16095efb9)

I took apart using the 3 screws on the main body. 
The antennas on the outside are fake. It has a small printed circuit board antenna taped to the inside of the main compartment instead. 
The main chip is the anyka ak3918. The camera sensor chip is the gc1084.

Since my camera used the exact same micro controller chip, and wifi card. I was able to use this great project:
https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/
I was able to telnet in after changing the root password.

Then since this I had a different camera sensor then the original camera the Gerge worked on, I had to make a few changes. Add to the bottome of the /Factory/config.sh file the following. Before the gergehack.sh script is run.
```
#gergedaemon and time_zone are not needed for the SD exploit
/etc/jffs2/gergehack.sh
```

To change the root password.
```
#change root password
#!/bin/bash

USER="root"
NEW_PASSWORD="newrootpassword"

# Use a here-document to send password input to the passwd command
(echo "$NEW_PASSWORD"; echo "$NEW_PASSWORD") | passwd $USER
```

To uncompress the module conf file, and make a symlink to it on the sd card since there is not enough room in the /etc/jffs2 partition. 
```
#extract sensor.tgz into the sdcard if not there.
FILE="/mnt/isp_gc1084.conf"
if [ ! -e "$FILE"; then
  tar -xzf /etc/jffs2/sensor.tgz -C /mnt
  #make the symlink
  ln -s /mnt/isp_gc1084.conf /etc/jffs2/
fi
```

Actually, I already found it decompressed in /tmp
I can just make a symlink from there.
```
ln -s /tmp/sensor_ko_and_isp_conf/isp_gc1084.conf /etc/jffs2/
```

## What is working
Camera works from both main freed and sub feed. pretty good quality, but pretty slow high latency at 5-15fps. PTZ works well, and so does the microphone. 
PTZ? = 
Pan Tilt Zoom - basically the camera controls.

## Lights and IR
I can't get the lights or the IR lights to work yet.
I tried:
```
echo "1" > /sys/user-gpio/WHITE_LED
echo "1" > /sys/user-gpio/IR_LED
```
the IR LEDs are automaticly controlled by a photoresistor? 

## Sound from the builtin speaker in the camera
I haven't yet figured out how to use the speaker.
https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/src/branch/main/SD_card_contents/anyka_hack/ak_adec_demo

## IR shutter/filter operation (the thing that makes the CLICK sound)
This is different from the IR LEDs, the LEDs are automaticly controlled by a photoresistor
When this is on it makes everything pink. It was stuck on for me the next day for some reason. 
To turn off
```
echo "1" > /sys/user-gpio/ircut_a
#echo "1" > /sys/user-gpio/ircut_b
```
## PTZ from Home assistant
I will probably use the telnet integration, or maybe the webui endpoints if I can figure out the token, and auth. 
After that I'll use the [webrtc custom card](https://github.com/AlexxIT/WebRTC?tab=readme-ov-file#custom-card) ptz controls:
```
##Custom
##configuration.yaml

script:
  camera_ptz:
    sequence:
      - service: rest_command.camera_ptz_start
        data:
          param: "{{ direction }}"
      - service: rest_command.camera_ptz_stop
        data:
          param: "{{ direction }}"
##card

type: 'custom:webrtc-camera'
entity: ...
ptz:
  service: script.camera_ptz
  data_left:
    direction: directionleft
  data_right:
    direction: directionright
  data_up:
    direction: directionup
  data_down:
    direction: directiondown
```
From: https://github.com/AlexxIT/WebRTC/wiki/PTZ-Config-Examples

## Home assistant with the webrtc custom card works well for video and audio
What works
* Fullscreen
* Picture in Picture
* Digital Zoom with scroll wheel
* Download a snapshot
* One way audio

## Current setup (verified working 2026-08-05)

| | |
|---|---|
| Address | `10.0.10.20` — **cams VLAN (VLAN 10)**, alongside the Hikvisions |
| DHCP | Static reservation `anyka-cam1` on the router, so the IP can't be recycled |
| SSID | `iot` (2.4 GHz only) |
| Main stream | `rtsp://10.0.10.20:554/vs1` — h264 640x360 @20fps, PCM A-law audio |
| Still image | `http://10.0.10.20:3000/snapshot.jpeg` — ~60 KB JPEG, no auth |
| Telnet | port 23, root login |

Note `/vs2` now returns **404** — only one stream is published, at the `image_width`/
`image_height` from `gergesettings.txt` (640x360). Neither endpoint uses authentication.

In Home Assistant this is a **Generic Camera** entry with `rtsp_transport: tcp`. The entity ID
is still the legacy `camera.10_0_8_106` from when the camera lived on the IoT VLAN — the name is
cosmetic, the URLs inside it are current. `/api/camera_proxy` returns HTTP 200 with a real
frame. Be aware a camera entity reports `idle` whether or not it works, so **the proxy fetch is
the only real liveness test.**

The port-3000 snapshot server plus the `/vs1` path is the `libre_anyka_app` signature, and is
the most reliable way to find one of these cameras:
```
nmap -n -Pn -p 3000,554 --open 10.0.10.0/24
```

## Why it broke, and what fixed it (2026-08-05)

The camera had been offline since **2026-04-28**. It hardcodes `wifi_ssid=iot` in
`gergesettings.txt`, and on that date an "iot prefix delete" change removed the `iot` and
`iot-office` SSIDs, consolidating onto `jplovescl` (same VLAN, **same PSK** — only the name
changed). The camera was hunting for a network that no longer existed.

That failure mode is nearly invisible, which is what made it hard: a station configured for an
absent SSID never sends auth frames, so it appears in **no** association list and produces **no**
failed-auth log line anywhere. Absence of evidence looked exactly like dead hardware. The
give-away was reading `gergesettings.txt` off the SD card rather than inferring from the network.

Fixed by adding an `iot` SSID on the **north-office** AP (`10.0.6.101`) mirroring `jplovescl` —
`radio0` (2.4 GHz ch 6), `psk2`, same key — bridged to a new `network.cams` interface on
`br-lan.10`. VLAN 10 was already tagged on that AP's trunk, so only the interface definition was
missing. Configs were backed up on the AP at `/root/backups/`.

**Moving VLANs requires a camera reboot.** Re-pointing the SSID to a different VLAN leaves the
camera associated but still holding its old lease, which strands it — its `udhcpc` won't
re-request until the lease renews (hours). Reboot it over telnet while it's still reachable on
the old VLAN, and flip the SSID during the boot.

## Hardware specs

Read from the running camera (`/proc/cpuinfo`, `/proc/mtd`, `dmesg`) and cross-checked against
`reference/hardware/ak3918.pdf`.

| | |
|---|---|
| SoC | Anyka **AK3918EN080**, chip ID `0x20150200`, board `Cloud39EV2_AK3918E80PIN_MNBD` |
| CPU | ARM926EJ-S rev 5, ARMv5TEJ, **400 MHz**, 16 KB I-cache + 16 KB D-cache (VIVT), MMU, little-endian only |
| Clocks | `AK39 clocks: CPU 400MHz, MEM 200MHz, ASIC 100MHz` |
| RAM | Embedded DDR2 @200 MHz — 64 MB total, **36.5 MB visible to Linux** (the rest is carved out for ISP/video) |
| Flash | 8 MB SPI NOR |
| Video | H.264 hardware encoder 720p30, MJPEG 720p30, multi-stream; ISP + CCIR601/656 sensor interface with scaling |
| Audio | MP3 / ADPCM / WAV / Speex encoders, 2 ADCs (mic + battery), 2 sigma-delta DACs, headphone driver, I2S slave, I2C master |
| Crypto | AES / DES / 3DES |
| Storage I/O | MMC/SD (MMC 4.2, SD 2.0), SDIO 1.1 |
| Other I/O | 2 UART, USB 2.0 HS host/slave, 2 SPI, 5 PWM, 5 timers, watchdog, 32.768 kHz RTC, 64 GPIO (7 dedicated) |
| Firmware | Linux **3.4.35**, uClibc 0.9.33.2, gcc 4.8.5, Anyka `AKV_2.5.04`, built 2023-09-25 |

BogoMIPS reads 199.06, which is about half the 400 MHz core clock — that's normal for the
ARM926 delay loop, not an underclock.

### Flash layout

```
mtd0  8.00 MB  spi0.0     whole device
mtd1  1.50 MB  KERNEL
mtd2  4.00 KB  MAC
mtd3  4.00 KB  ENV
mtd4  1.00 MB  A
mtd5  3.02 MB  B          -> /usr        (100% full)
mtd6    64 KB  C          -> /etc/jffs2  (88% full)
mtd7  2.20 MB  D          -> /data
```

**That 64 KB `/etc/jffs2` partition at 88% full is the whole reason** the root README works
around the sensor config with a symlink instead of just copying `isp_gc1084.conf` (104 KB) into
flash — it physically does not fit, and it's the only writable place the hack persists to.

> ⚠️ The datasheet in `reference/hardware/ak3918.pdf` is v1.0 (July 2014) and describes the
> **152-pin LFBGA** part. This camera uses the **80-pin** variant (`AK3918EN080`, board string
> `...E80PIN...`), so the pinout and some peripherals do not carry over — notably the Ethernet
> MAC, which this board doesn't wire up since it's WiFi-only. Treat the feature list as
> family-level, not part-exact.

## PTZ — working from Home Assistant

Pan/tilt runs through kuhnchris' `ptz_daemon`, which reads commands from the FIFO
`/tmp/ptz.daemon` on the camera. Relative moves are 10 degrees per step:

```
echo "init_ptz"     > /tmp/ptz.daemon   # home both axes — REQUIRED first
echo "left"         > /tmp/ptz.daemon   # also up / down / right
echo "t2p 190 95"   > /tmp/ptz.daemon   # absolute: pan 190, tilt 95 (0 = top)
```

### ⚠️ The homing command is `init_ptz`, not `init`

The upstream `anyka_hack/ptz/README.md` says to home the axes with `init`. **That is
wrong** — the daemon accepts the write, spawns a worker, and silently does nothing.
Every subsequent move then fails with:

```
[ak_drv_ptz_turn_to_pos:1027] not init.
```

`gergehack.sh` has the correct spelling — it sends **`init_ptz`**. With that, the daemon
reports real motor parameters (`angle2step steps: 4209`, `MaxHit=369` for pan; `2161`/`189`
for tilt) and the motors move. This cost a full debugging cycle: PTZ looked "connected but
dead" because the daemon and `cmd_serverd` were both running and every command was accepted
without error.

`ptz_init_on_boot=1` is now set in `gergesettings.txt` (both the flash copy and the SD card
copy), so gergehack homes the axes ~10s into every boot.

In Home Assistant this is five `shell_command` services — `anyka_ptz_left`, `_right`, `_up`,
`_down`, `_home` — wired to buttons in the Anyka section of the Cameras view. They live in
`packages/anyka_camera.yaml` in the `ha` repo, calling a helper deployed to
`/config/scripts/anyka_ptz.py`.

## No microphone toggle is possible

The camera's audio is always on, and there is no way to mute it at the source:

* `libre_anyka_app`'s option string is `w:h:m:i:u` — width, height, motion-record seconds,
  `-i <n>`, and a boolean `-u`. **There is no audio flag**, so restarting the app can't
  disable the mic either.
* `/sys/user-gpio/` exposes only `IR_LED`, `SPK_PA`, `WHITE_LED`, `ircut_a`, `ircut_b` and
  `wifi_en`. `SPK_PA` is the *speaker* power amp (output); there is no mic GPIO.
* There is no `amixer` and no `/proc/asound`, so there's no ALSA mixer to mute.

The mic is hardwired on and always encoded into the RTSP stream as PCM A-law. The only
"mute" available is on the consuming side — dropping the audio track in go2rtc or muting in
the player, which is a playback choice rather than a hardware mute. `SPK_PA` would make a
genuine *speaker* toggle if that's ever wanted.

## Known rough edges

* **The IR-cut filter drifts back on its own.** `echo 1 > /sys/user-gpio/ircut_a` clears the
  heavy purple cast, but nothing in `gergesettings.txt` controls it and it re-engages by
  itself — observed reverting mid-session, which matches the "it was stuck on the next day"
  note above. It is now re-applied on every boot from `/Factory/config.sh` on the SD card:
  ```sh
  # keep the IR cut filter in the non-pink position on every boot
  (sleep 60; echo 1 > /sys/user-gpio/ircut_a) &
  ```
  The 60-second delay lets the video pipeline come up first. For the times it drifts while
  running, `switch.anyka_cam_ir_cut_filter` in Home Assistant toggles it live. Note this
  pins the filter in its daytime position, which may cost some night-time IR sensitivity —
  drop the boot line if nights look worse.
* **The camera's clock stays at 1969.** Cloud access is firewalled on the cams VLAN, and NTP to
  `10.0.10.1` also fails (`ntpd -q -p 10.0.10.1` times out), so `time_source` never syncs. Only
  affects the camera's own timestamps; HA supplies its own. Allow UDP 123 from the cams zone to
  the router if you want it fixed.
* **The WebRTC integration is disabled**, so `custom:webrtc-camera` cards render as "Custom
  element doesn't exist". `go2rtc` is still enabled. Re-enable WebRTC before re-adding the card.
* Of the ~3 cameras originally set up, **only this one** was ever in Home Assistant. The other
  HA cameras are unrelated: two Hikvisions on `10.0.10.x`, three `video.cgi` MJPEG cams, and an
  iCam365 over ONVIF.

## Debugging notes worth keeping

* **`logread` on the router holds only ~3 minutes**, because dnsmasq logs every DNS query and
  floods the ring buffer. For longer lookbacks use lease arithmetic — leases are a uniform 12 h,
  so `issued_at = expiry - 43200` dates every lease granted in the last 12 hours.
* **Port scans can't tell a dead device from a cloud-only one** — both show nothing open. Read
  `/proc/net/nf_conntrack` on the router instead: the outbound destination port identifies the
  protocol (8883/8886 = MQTT/TLS = smart-plug class) and the byte counters separate telemetry
  (~3 KB) from video (megabytes).
* Don't trust an unregistered MAC OUI as a device fingerprint. `18:DE:50` looked like a camera
  marker but turned out to be shared with smart bulbs; the real camera is `C0:4B:24:6D:9F:FD`.

See [`reference/`](reference/) for the vendored upstream material and
[`reference/sd-card-original/`](reference/sd-card-original/) for this camera's actual working
config — including `isp_gc1084.conf`, which exists nowhere else.

