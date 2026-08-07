# Anyka AK3918 + GC1084 IP camera — RTSP, PTZ and Home Assistant

Notes, recovered configuration and a full HTTP API reference for cheap **Anyka AK3918 / GC1084**
IP cameras — sold as the **Teruhal TC20** and driven by the Yi IOT app, typically $3–$8 on Temu.

Freed from the cloud with [Gerge's SD-card
exploit](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/), these give you local
RTSP with audio, pan/tilt, snapshots and telnet, with no vendor account involved.

This repo exists because two things are documented nowhere else: the **GC1084 sensor files**
(upstream ships every sensor except this one), and the hacked firmware's **web UI / HTTP API**.

## What works

| | |
|---|---|
| ✅ Video | h264, 720p or 640×360, [**15.2 fps measured**](docs/home-assistant.md#streams), RTSP with no auth |
| ✅ Audio | PCM A-law, always on — [and it cannot be muted](docs/ptz.md#-the-microphone-cannot-be-muted) |
| ✅ Pan / tilt | 10° relative steps and absolute positioning. No zoom — the lens is fixed. |
| ✅ Snapshots | JPEG on port 3000, no auth |
| ✅ WiFi | 2.4 GHz only |
| ✅ Web UI | Port 80, PTZ pad and live preview — [but see the security warning](#-security) |
| ✅ Home Assistant | Generic Camera + go2rtc, PTZ buttons |
| ✅ IR-cut filter | Works — manually. **Write `/sys/user-gpio/ircut_a` directly**; that is what `ctl` and the Home Assistant switch now do. [Every vendor route is dead](docs/ptz.md#-one-write-works-every-vendor-route-is-dead-and-they-die-in-the-same-place), and a boot-time write keeps it out of the magenta position |
| ❌ Automatic day/night | **Not fixable on this board**, and not for want of patching: the driver's ambient input is `gpio-rf_feed`, a pin this hardware does not route, and its fallback ADC reads a constant. [Do not spend a day on it](docs/ptz.md#-automatic-daynight-is-not-fixable-on-this-board) |
| ❌ IR LEDs | Pin and pad both toggle correctly, but **the ring is dark** — confirmed with a phone that demonstrably sees another camera's emitters. [Why is still open](docs/ptz.md#-ir-confirmed-dark) |
| ❌ White LEDs | Present in hardware (4 on the ring) but dark. The **pad demonstrably swings** and nothing lights, the vendor firmware **declares this PTZ variant unsupported**, and there is **no software fix** — [all other candidates refuted](docs/ptz.md#-white-leds--the-vendor-firmware-disables-them-on-this-variant) |
| ✅ Speaker | MP3 playback out of the built-in speaker. **You do not need to raise `SPK_PA`** — the player does it [(that was retracted)](docs/ptz.md#speaker--audio-out-works) |
| ✅ Speaker volume | **Six rungs, `ak_adec_demo.vol1..6` on the card, default 4.** Upstream called the control broken; it was **hardcoded at maximum and never exposed** — one byte. ⚠️ Do **not** pre-attenuate clips: the file sits upstream of a compressor that undoes it. [Detail and the caveats](docs/ptz.md#-volume-a-six-rung-ladder-shipped-on-the-card) |
| ✅ Identity | Each camera **names itself from its own MAC** at first boot, write-once, no registry — and the name stays with the camera while the build version follows the card. [How](docs/identity.md) |
| ✅ Firmware update | The stock updater is documented, including **what it does not check** — no signature, and a "newer only" gate that is a string compare and inverts at this version. [Read the gate first](docs/firmware-update.md) |
| ✅ Cross-compiling | A toolchain exists and is **proven on hardware**. [What it does — and does not — unblock](docs/cross-compiling.md) |
| ✅ Clock | NTP syncs. No RTC battery, so it boots to 1969 and depends on it. The timezone was **15 hours wrong on every service** while `date` in a shell looked fine — [now fixed](docs/troubleshooting.md#the-clock--ntp-works-the-timezone-was-15-hours-wrong-on-every-service) |

## Working configuration

Verified against a live camera on **2026-08-05**.

| | |
|---|---|
| Address | `192.168.1.20` — the camera VLAN, alongside the other cameras |
| DHCP | Static reservation `anyka-cam1`, so the address cannot be recycled |
| SSID | `my-iot-ssid` (2.4 GHz only) |
| Main stream | `rtsp://192.168.1.20:554/vs0` — h264 **1280×720** @ **15.2 fps** + PCM A-law |
| Sub stream | `rtsp://192.168.1.20:554/vs1` — h264 640×360 @ **15.2 fps** + PCM A-law |
| Snapshot | `http://192.168.1.20:3000/snapshot.jpeg` — ~32 KB JPEG, no auth |
| Web UI | `http://192.168.1.20/` — default password `webui` |
| Telnet | Port 23, root login |
| FTP | Port 21, root login, **writable over `/`** — turn it off unless needed |

`/vs2` returns 404. `image_width`/`image_height` in `gergesettings.txt` set the **sub** channel
only — they do not constrain `/vs0`.

## Quick start

Find one on your network — the port-3000 snapshot server is the best fingerprint:

```sh
nmap -n -Pn -p 3000,554 --open 192.168.1.0/24
```

Grab a frame, no credentials needed:

```sh
curl -o frame.jpg http://<ip>:3000/snapshot.jpeg
```

Move it (over telnet — `init_ptz` first, always):

```sh
echo "init_ptz" > /tmp/ptz.daemon
echo "left"     > /tmp/ptz.daemon
```

Or over HTTP:

```sh
TOKEN=$(curl -s "http://<ip>/cgi-bin/login_validate.sh?p=webui" \
        | sed -n 's/.*token=\([A-Za-z0-9]*\).*/\1/p')
curl -s "http://<ip>/cgi-bin/webui?token=$TOKEN&command=ptzinit" >/dev/null
curl -s "http://<ip>/cgi-bin/webui?token=$TOKEN&command=ptzl"    >/dev/null
```

Write a card for a new camera:

```sh
sudo tools/write-sd-card.sh /dev/sdX --ssid <your-ssid>
```

> ⚠️ **Never open a bare TCP connection to port 3000** — a socket opened and closed without a
> valid HTTP request **kills the snapshot server** until the camera restarts it. That rules out
> recurring port scans and TCP-only uptime checks; use a real
> `curl http://<ip>:3000/snapshot.jpeg` instead.
>
> More generally, go easy: this is a 400 MHz single-core ARM926 with ~36 MB of RAM doing H.264
> encode, RTSP, snapshots and a CGI web server at once. Poll in minutes rather than seconds, and
> point automation at [`/cgi-bin/ctl`](docs/web-ui.md#cgi-binctl--our-fast-control-endpoint)
> rather than the stock web UI, which costs 0.2–1.0 s of camera CPU per request.
> [→ budget guidance](docs/troubleshooting.md#be-economical-with-requests)

## ⚠️ Security

**These cameras must live on an isolated, cloud-blocked VLAN.** That is not generic caution, and
it is **not a consequence of hacking them.**

### 🔴 A stock, un-hacked camera is the worse case

**This page used to scope the whole section to "the hacked firmware", which implied leaving a
camera stock was the safe option. It is not.**

`rc.local` line 12, on **every stock boot**, as root:

```sh
/usr/bin/tcpsvd 0 21 ftpd -w / -t 600 &
```

That is `0` = **all interfaces**, `-w` = **writes enabled**, `/` = **served from the filesystem
root**. A stock camera runs a **permanently-enabled, network-facing, writable file service rooted
at `/`** — and `run_ftp=0` does **not** reach it, because that is a *hack* setting and this is
vendor `rc.local`.

> ⚠️ **It is a complete root chain built entirely from vendor components.** Anyone who can
> authenticate to that FTP can write `/tmp/update.tar`, which `update.sh` will flash **with no
> signature check at all**. Gated only by the FTP credential.
>
> [The finding](docs/stock-attack-surface.md#1--the-finding-that-stands-regardless-of-everything-else)
> · [the updater's missing checks](docs/firmware-update.md)

**So "don't hack it" is not a mitigation. Isolation is the mitigation.**

### Problems the hack adds or changes

* **Unauthenticated remote root command execution on port 80 — ✅ now fixed, but only on cards
  written since 2026-08-06.** `cgi-bin/header` `eval`'d the query string as root *before* the
  token check, so `GET /cgi-bin/webui?a=1;id` returned `uid=0(root)`. **Any camera still running
  an older card remains fully exploitable.**
  [The hole, and the fix](docs/web-ui.md#security-the-auth-is-cosmetic).
  **This one really is hack-only** — `gergehack` installs the web UI containing it; a stock unit
  has nothing at that address.
* **Telnet becomes a persistent root shell.** On stock it is a **boot-window race**, not a
  service — `rcS` starts `telnetd`, and `service.sh` runs `killall telnetd` shortly after. The
  hack keeps it up, which is the point of it.
* **RTSP and the snapshot server have no authentication at all**, on any port.
* FTP serves the file containing your **WiFi PSK in cleartext** — a hack-specific file on a
  vendor-enabled service.
* No TLS anywhere on the device, stock or hacked.

On a segregated camera VLAN with no untrusted clients, this is an acceptable trade for a $3–$8
camera. Anywhere else it is not. **Do not port-forward it.** If you cannot segregate it, setting
`run_web_interface=0` and `run_ftp=0` closes the hack's additions — **it does not close the stock
FTP service above.**

## Documentation

| | |
|---|---|
| [docs/web-ui.md](docs/web-ui.md) | **Complete HTTP API reference** — every endpoint, the auth scheme, and the security analysis |
| [docs/ptz.md](docs/ptz.md) | PTZ daemon commands, the `init_ptz` trap, IR-cut filter, GPIO map |
| [docs/sd-card.md](docs/sd-card.md) | Writing and cloning cards, settings precedence, the GC1084 sensor files |
| [docs/hardware.md](docs/hardware.md) | SoC, flash layout, mounts, serial console |
| [docs/home-assistant.md](docs/home-assistant.md) | Streams, entities, WebRTC card, PTZ services |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Decision tree, the 2026 outage post-mortem, network debugging |
| [docs/identity.md](docs/identity.md) | **Which camera is this, and what is it running?** Self-naming from the MAC, write-once, no registry |
| [docs/firmware-update.md](docs/firmware-update.md) | The stock updater, what it does **not** check, and the recovery gate |
| [docs/stock-attack-surface.md](docs/stock-attack-surface.md) | **What an un-hacked camera exposes** — read before assuming stock is safer |
| [docs/cross-compiling.md](docs/cross-compiling.md) | The toolchain, proven on hardware — and what a compiler does **not** unblock |
| [docs/backlog.md](docs/backlog.md) | Live queue, and **the rules section** — the part that transfers to devices that are not this one |
| [reference/](reference/) | Vendored upstream material, provenance and licensing |
| [reference/sd-card-original/](reference/sd-card-original/) | **This camera's real working config**, including `isp_gc1084.conf` |

> **Every entry from `identity.md` down was written on 2026-08-06 and was missing from this
> index until the same evening.** Worth stating rather than quietly fixing: nobody wrote anything
> *wrong* — five documents were created and none were linked, and **an omission has no tell.**
> The [rule this repo files for it](docs/backlog.md) is *"the backlog is what we read, the README
> is what a stranger reads"*; this was that failure at **directory** scale.

## Four things that cost the most time

Recorded up front because each one looks like dead hardware — except the last, which looks like a
bug you can fix in one line:

1. **The homing command is `init_ptz`, not `init`.** Upstream's PTZ README has it wrong. The
   daemon accepts `init` and silently does nothing, then every move fails with `not init.` —
   while the daemon and `cmd_serverd` both look perfectly healthy.
   [→](docs/ptz.md#-the-homing-command-is-init_ptz-not-init)

2. **A renamed SSID is invisible.** This camera hardcodes its SSID and was offline for three
   months after the network was renamed. A station looking for an absent SSID never sends auth
   frames, so it shows up in no association list and no failed-auth log. When a device vanishes,
   go read its configuration instead of interrogating the network.
   [→](docs/troubleshooting.md#the-2026-outage-a-renamed-ssid)

3. **The SD card overwrites your settings.** `gergehack.sh` re-syncs `gergesettings.txt` from
   the card on every boot and reboots if it differs, so edits made only in `/etc/jffs2` quietly
   revert. [→](docs/sd-card.md#settings-precedence)

4. **A string that looks broken may be a dead path whose failure is load-bearing.** These
   binaries are full of hard-coded sysfs paths that do not exist on this kernel. They are bugs by
   inspection and they look like one-line fixes.

   **One was fixed, and it broke the IR-cut filter.** `libplat_drv.so`'s driver stats *two* node
   names to decide its mode: neither present → disabled; **one** → write-and-hold, which is right
   for this board; **both** → a 10 ms pulse meant for a latching solenoid this camera does not
   have. Correcting **both** strings tipped it from *disabled* straight into *pulse*, so every
   command released the pin and parked the filter in magenta. **Renaming one string would have
   worked. Renaming both broke it** — the more thorough fix was the harmful one, and no normal
   engineering instinct protects against that.

   **Before repairing a wrong-looking path, establish (a) that it is actually executed and (b)
   what currently depends on it failing.** [→](docs/ptz.md#-root-cause-the-libplat_drvso-patch-tipped-the-driver-into-a-mode-for-other-hardware)

## Credits

* [Gerge — Anyka_ak3918_hacking_journey](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/)
  (GPL-3.0) — the SD-card exploit, `gergehack.sh`, and the web interface this repo documents
* [kuhnchris — IOT-ANYKA-PTZdaemon](https://github.com/kuhnchris/IOT-ANYKA-PTZdaemon) — the PTZ daemon
* `libre_anyka_app` — RTSP and snapshot server
* [Muhammed Kalkan — Anyka-Camera-Firmware](https://github.com/mkalkan/Anyka-Camera-Firmware) (MIT)
* [AlexxIT — WebRTC for Home Assistant](https://github.com/AlexxIT/WebRTC)

Licensing and provenance for everything vendored here is in
[reference/README.md](reference/README.md). This repo is GPL-3.0.
