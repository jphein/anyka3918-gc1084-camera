# Troubleshooting

## Finding the camera

The **port-3000 snapshot server plus the `/vs1` path is the `libre_anyka_app` signature**, and
is the most reliable way to find one of these on a network:

```sh
nmap -n -Pn -p 3000,554 --open 192.168.1.0/24
```

Port 3000 is the better fingerprint of the two — plenty of things speak RTSP, almost nothing
else serves JPEGs on 3000.

Once found, give it a **DHCP reservation**. These cameras have no UI for a static address and
nothing to tell you the address changed.

## Decision tree for a camera that has gone dark

| Symptom | Likely cause |
|---|---|
| Nothing on 3000/554, nothing in any AP's association list | **Wrong/absent SSID.** See below. |
| Associated, has a lease, but no ports open | Card missing or hack not running — check UART or reseat the card |
| Ports open, RTSP 404 on every path | `libre_anyka_app` not started; check `run_libre_anyka=1` |
| Video works, PTZ accepted but nothing moves | You sent `init`, not **`init_ptz`**. See [ptz.md](ptz.md) |
| RTSP works but port 3000 is dead | `libre_anyka_app` restarted under load and failed to rebind. [Overload](#-this-camera-is-trivially-overloaded) — reboot it |
| Everything slow, timeouts, HA dropping frames | You are asking too much of a 400 MHz core. [Overload](#-this-camera-is-trivially-overloaded) |
| Web UI redirects to login forever | Token invalid — [web-ui.md](web-ui.md#the-token) |
| Pink/purple image | IR-cut filter position — [ptz.md](ptz.md#ir-cut-filter) |
| A setting keeps reverting after reboot | The SD card is overwriting flash — [sd-card.md](sd-card.md#settings-precedence) |
| Video dead after saving web UI settings | The sensor dropdown reset `sensor_kern_module` — [sd-card.md](sd-card.md#the-sensor-problem) |

## The 2026 outage: a renamed SSID

The camera was offline from **2026-04-28** to **2026-08-05**. It hardcodes `wifi_ssid=iot` in
`gergesettings.txt`, and on that date an "iot prefix delete" change removed the `iot` and
`iot-office` SSIDs, consolidating onto `my-home-ssid` (same VLAN, **same PSK** — only the name
changed). The camera was hunting for a network that no longer existed.

> ⚠️ **This failure mode is nearly invisible, and that is the lesson worth keeping.** A station
> configured for an absent SSID never sends auth frames, so it appears in **no** association
> list and produces **no** failed-auth log line anywhere. Absence of evidence looked exactly like
> dead hardware.

The give-away was **reading `gergesettings.txt` off the SD card** rather than inferring from the
network. When a device is invisible, go read its configuration; do not keep interrogating the
infrastructure.

Pinned to the exact date because the AP still had its pre-change backups:
`/etc/config/wireless.pre-iot-prefix-delete-2026-04-28` contained `option ssid 'iot'` and
`option ssid 'iot-office'`.

Fixed by adding an `iot` SSID on one **access point** (`192.168.1.2`) mirroring `my-home-ssid` —
`radio0` (2.4 GHz channel 6; the camera is 2.4 GHz only), `psk2`, same key — bridged to a new
`network.cams` interface on `br-lan.CAMVLAN`, the **camera VLAN**. That VLAN was already tagged on that
AP's trunk, so only the interface definition was missing. Configs were backed up on the AP at
`/root/backups/`.

The longer-term choice is either to keep that mirror SSID, or to edit `gergesettings.txt` to say
`wifi_ssid=my-home-ssid` and drop the mirror. Note that editing it means editing the **card** —
see [sd-card.md](sd-card.md#settings-precedence).

### ⚠️ Moving VLANs requires a camera reboot

Re-pointing the SSID to a different VLAN leaves the camera associated but still holding its old
lease, which strands it — its `udhcpc` will not re-request until the lease renews, which can be
hours. **Reboot it over telnet while it is still reachable on the old VLAN, and flip the SSID
during the boot.**

## ⚠️ This camera is trivially overloaded

**A 400 MHz single-core ARM926 with ~36.5 MB of usable RAM is doing H.264 encode, RTSP serving,
JPEG snapshots, a CGI web server and motion detection at the same time.** It has no headroom.
Treat every request to it as expensive.

### It has already happened here

On 2026-08-05 the camera hit **load average 4.95 with 3.6 MB RAM free**. `libre_anyka_app` died
and was restarted, and **came back without binding port 3000** — so snapshots were dead while
RTSP on 554 and the web UI on 80 kept working. That in turn broke a Home Assistant config save,
because HA validates `still_image_url` before writing and got a connection failure.

No single thing caused it. Four things landed on the same tiny CPU at once:

* an endpoint sweep probing every port and path,
* three HA switches polling on a 60-second timer,
* HA pulling the video stream continuously,
* and an `ffprobe` negotiating both RTSP streams, which is much heavier than grabbing one frame.

Any one of these is fine. Together they were not.

### Budget guidance

| Do | Don't |
|---|---|
| Pull one frame with `curl` when you need a still | Run `ffprobe`/`ffmpeg` against the RTSP streams casually — stream negotiation is expensive |
| Poll GPIO/state at 5 minutes or slower | Poll several HA switches at 60 s each |
| Use [`/cgi-bin/ctl`](web-ui.md#cgi-binctl--our-fast-control-endpoint) for automation | Drive automation through `/cgi-bin/webui`, which costs **0.2–1.0 s of CPU per request** |
| Hold one RTSP consumer (go2rtc) and fan out from there | Point several clients straight at the camera |
| Space out bulk investigation | Sweep endpoints while video is streaming |

The stock web UI's cost is not incidental: `header` URL-decodes the query string with a
per-character shell loop that spawns subshells, then the page is rendered in full even when the
request is only writing one line to a FIFO. That is the whole reason `ctl` exists.

### Recovering from an overload

Restarting `libre_anyka_app` is the obvious move, but **a full reboot is the more reliable
one** — it clears sockets stuck in `TIME_WAIT` and the memory fragmentation that a restart under
pressure inherits.

Why the snapshot server specifically fails to come back is **not confirmed**. Two plausible
explanations, neither tested:

* **Bind failure.** If port 3000 was still held from the previous process and the binary does not
  set `SO_REUSEADDR`, the bind fails while the app carries on and still serves RTSP. This fits
  the observed "554 yes, 3000 no" shape.
* **Memory.** At 3.6 MB free, a JPEG encode buffer allocated at snapshot-server startup could
  simply fail, with the app continuing without that listener.

> The process that restarts the app is `/mnt/anyka_hack/ffmpeg/app_restarter.sh`, and it runs
> continuously (started by `start_web_interface.sh`). **It is in the `ffmpeg/` directory, which
> this repo excludes**, so its restart policy is undocumented here and cannot be read from the
> repo — which is a good argument for vendoring at least the small shell scripts out of that
> directory even if the 37 MB `ffmpeg` binary stays out. See
> [`reference/README.md`](../reference/README.md).

## Known rough edges

### The IR-cut filter drifts back on its own

Observed reverting three times in one session. Mitigation, the GPIO-versus-daemon hypothesis,
and what has *not* been tested are all in [ptz.md](ptz.md#-the-filter-drifts-back-on-its-own--hypothesis-not-established-fact).

### The camera's clock stays at 1969

Cloud access is firewalled on the cams VLAN, and NTP to `192.168.1.1` also fails
(`ntpd -q -p 192.168.1.1` times out), so `time_source` never syncs. There is no RTC battery, so
every boot starts at the epoch.

Only affects the camera's own timestamps; Home Assistant supplies its own. Allow UDP 123 from
the cams zone to the router if you want it fixed.

Note the camera's `time_source` currently reads `192.168.8.1` — the *old* IoT VLAN router — on both
the card and in flash, because a flash-only edit was reverted by the card. Fixing it means
editing the card.

### The WebRTC integration is disabled

`custom:webrtc-camera` cards render as "Custom element doesn't exist". `go2rtc` is still
enabled. See [home-assistant.md](home-assistant.md).

### The microphone cannot be muted

Not a bug, a hardware fact. [ptz.md](ptz.md#-the-microphone-cannot-be-muted).

### FTP is on by default and is writable

`run_ftp=1` starts `tcpsvd 0 21 ftpd -w /`. Anonymous is rejected, but root with the root
password gets plaintext write access to the whole filesystem, and `gergesettings.txt` served
over it contains the WiFi PSK in cleartext. Set `run_ftp=0`.

### The web UI has a pre-auth root RCE

Anything that can reach port 80 owns the camera. Keep it on an isolated VLAN or turn it off.
Full detail: [web-ui.md](web-ui.md#security-the-auth-is-cosmetic).

## Network debugging notes worth keeping

These are general homelab lessons that came out of this hunt, not camera-specific.

* **`logread` on the router holds only ~3 minutes**, because dnsmasq logs every DNS query and
  floods the ring buffer. For longer lookbacks use **lease arithmetic** — leases are a uniform
  12 h, so `issued_at = expiry - 43200` dates every lease granted in the last 12 hours.
* **Port scans cannot tell a dead device from a cloud-only one** — both show nothing open. Read
  `/proc/net/nf_conntrack` on the router instead: the outbound destination port identifies the
  protocol (8883/8886 = MQTT/TLS = smart-plug class) and the byte counters separate telemetry
  (~3 KB) from video (megabytes).
* **Do not trust an unregistered MAC OUI as a device fingerprint.** `18:DE:50` looked like a
  camera marker but turned out to be shared with smart bulbs. The real camera is
  `C0:4B:24:6D:9F:FD`.

## Serial console

When the camera will not boot far enough to reach the network, the UART is the only way in —
`ttySAK0`, **115200 8N1**. Compare against the vendored boot logs in
[`reference/UART_logs/`](../reference/UART_logs/), which cover factory boot, factory boot with
SD, and exploit boot with and without SD.

## See also

* [sd-card.md](sd-card.md) — settings precedence, the sensor files, the `config.sh` bug
* [web-ui.md](web-ui.md) — every endpoint, and the security posture
* [ptz.md](ptz.md) — the `init_ptz` trap
* [hardware.md](hardware.md) — flash layout and why `/etc/jffs2` is always nearly full
