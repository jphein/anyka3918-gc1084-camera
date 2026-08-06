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
| ✅ Video | h264, 720p or 640×360, ~20 fps, RTSP with no auth |
| ✅ Audio | PCM A-law, always on — [and it cannot be muted](docs/ptz.md#-the-microphone-cannot-be-muted) |
| ✅ Pan / tilt | 10° relative steps and absolute positioning. No zoom — the lens is fixed. |
| ✅ Snapshots | JPEG on port 3000, no auth |
| ✅ WiFi | 2.4 GHz only |
| ✅ Web UI | Port 80, PTZ pad and live preview — [but see the security warning](#-security) |
| ✅ Home Assistant | Generic Camera + go2rtc, PTZ buttons |
| ✅ IR-cut filter | Controllable. Has been [seen to read back `off` after being set](docs/ptz.md#-the-filter-has-been-seen-to-read-back-off--cause-unknown) — cause unresolved, and possibly a readback bug rather than the hardware |
| ❔ IR LEDs | GPIO 6 accepts writes, but illumination is **not yet demonstrated** — [why the obvious test is confounded](docs/ptz.md#-ir-leds--unverified) |
| ❌ White LEDs | Present in hardware (4 on the ring) but **not driveable from the hacked kernel's GPIO interface** — [likely an I2C expander, not a pin](docs/ptz.md#-white-leds-do-not-light-and-the-pin-is-not-the-problem) |
| ✅ Speaker | MP3 playback out of the built-in speaker — [raise `SPK_PA` first](docs/ptz.md#speaker--audio-out-works) |
| ❌ Clock | No RTC battery, and NTP is firewalled — [stays at 1969](docs/troubleshooting.md#the-cameras-clock-stays-at-1969) |

## Working configuration

Verified against a live camera on **2026-08-05**.

| | |
|---|---|
| Address | `192.168.1.20` — the camera VLAN, alongside the other cameras |
| DHCP | Static reservation `anyka-cam1`, so the address cannot be recycled |
| SSID | `my-iot-ssid` (2.4 GHz only) |
| Main stream | `rtsp://192.168.1.20:554/vs0` — h264 **1280×720** @20 fps + PCM A-law |
| Sub stream | `rtsp://192.168.1.20:554/vs1` — h264 640×360 @20 fps + PCM A-law |
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

> ⚠️ **Go easy on it.** This is a 400 MHz single-core ARM926 with ~36 MB of RAM doing H.264
> encode, RTSP, snapshots and a CGI web server at once. We pushed one to load 4.95 with a
> handful of 60-second pollers and an endpoint sweep, and `libre_anyka_app` came back without
> its snapshot server. Poll in minutes, not seconds, and point automation at
> [`/cgi-bin/ctl`](docs/web-ui.md#cgi-binctl--our-fast-control-endpoint) rather than the stock
> web UI, which costs 0.2–1.0 s of camera CPU per request.
> [→ budget guidance](docs/troubleshooting.md#-this-camera-is-trivially-overloaded)

## ⚠️ Security

**These cameras must live on an isolated, cloud-blocked VLAN.** That is not generic caution —
the hacked firmware has specific, verified problems:

* **Unauthenticated remote root command execution on port 80.** `cgi-bin/header` `eval`s the
  query string as root *before* the token check. One GET is enough:
  `GET /cgi-bin/webui?a=1;id` → `uid=0(root)`. The login token is real but readable pre-auth,
  so the authentication is **cosmetic**. [Full detail and proof](docs/web-ui.md#security-the-auth-is-cosmetic).
* **RTSP and the snapshot server have no authentication at all**, on any port.
* **FTP is enabled by default**, writable, rooted at `/`, and serves the file containing your
  WiFi PSK in cleartext.
* **Telnet is plaintext** with a root shell.
* No TLS anywhere on the device.

On a segregated camera VLAN with no untrusted clients, this is an acceptable trade for a $5
camera. Anywhere else it is not. Do not port-forward it. If you cannot segregate it, set
`run_web_interface=0` and `run_ftp=0` and drive PTZ over telnet.

## Documentation

| | |
|---|---|
| [docs/web-ui.md](docs/web-ui.md) | **Complete HTTP API reference** — every endpoint, the auth scheme, and the security analysis |
| [docs/ptz.md](docs/ptz.md) | PTZ daemon commands, the `init_ptz` trap, IR-cut filter, GPIO map |
| [docs/sd-card.md](docs/sd-card.md) | Writing and cloning cards, settings precedence, the GC1084 sensor files |
| [docs/hardware.md](docs/hardware.md) | SoC, flash layout, mounts, serial console |
| [docs/home-assistant.md](docs/home-assistant.md) | Streams, entities, WebRTC card, PTZ services |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Decision tree, the 2026 outage post-mortem, network debugging |
| [reference/](reference/) | Vendored upstream material, provenance and licensing |
| [reference/sd-card-original/](reference/sd-card-original/) | **This camera's real working config**, including `isp_gc1084.conf` |

## Three things that cost the most time

Recorded up front because each one looks like dead hardware:

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

## Credits

* [Gerge — Anyka_ak3918_hacking_journey](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/)
  (GPL-3.0) — the SD-card exploit, `gergehack.sh`, and the web interface this repo documents
* [kuhnchris — IOT-ANYKA-PTZdaemon](https://github.com/kuhnchris/IOT-ANYKA-PTZdaemon) — the PTZ daemon
* `libre_anyka_app` — RTSP and snapshot server
* [Muhammed Kalkan — Anyka-Camera-Firmware](https://github.com/mkalkan/Anyka-Camera-Firmware) (MIT)
* [AlexxIT — WebRTC for Home Assistant](https://github.com/AlexxIT/WebRTC)

Licensing and provenance for everything vendored here is in
[reference/README.md](reference/README.md). This repo is GPL-3.0.
