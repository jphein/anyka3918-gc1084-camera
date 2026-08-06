# Troubleshooting

## Finding the camera

The **port-3000 snapshot server plus the `/vs1` path is the `libre_anyka_app` signature**, and
is the most reliable way to find one of these on a network:

```sh
nmap -n -Pn -p 3000,554 --open 192.168.1.0/24
```

Port 3000 is the better fingerprint of the two — plenty of things speak RTSP, almost nothing
else serves JPEGs on 3000.

> ⚠️ **A bare TCP connect kills the port-3000 server.** Opening a socket and closing it without
> sending a valid HTTP request takes the snapshot server down until `libre_anyka_app` restarts —
> RTSP on 554 keeps working, which makes it look like a partial failure rather than something
> you did.
>
> That is exactly what a port scan does, so **scan once to find the camera and then stop**. Never
> put port 3000 in a recurring scan, an availability monitor, or an uptime checker. To test
> liveness, issue a **real HTTP GET** instead — it is also a better test, because it proves the
> encoder is producing frames rather than just that something is listening:
>
> ```sh
> curl -fsS -o /dev/null http://192.168.1.20:3000/snapshot.jpeg && echo alive
> ```
>
> This has already bitten us: an early version of the Home Assistant health check was doing a
> bare TCP connect to port 3000 and killing the server it was supposed to be monitoring. See
> [home-assistant.md](home-assistant.md#health-sensors).

Once found, give it a **DHCP reservation**. These cameras have no UI for a static address and
nothing to tell you the address changed.

## Decision tree for a camera that has gone dark

| Symptom | Likely cause |
|---|---|
| Nothing on 3000/554, nothing in any AP's association list | **Wrong/absent SSID.** See below. |
| Associated, has a lease, but no ports open | Card missing or hack not running — check UART or reseat the card |
| Ports open, RTSP 404 on every path | `libre_anyka_app` not started; check `run_libre_anyka=1` |
| Video works, PTZ accepted but nothing moves | You sent `init`, not **`init_ptz`**. See [ptz.md](ptz.md) |
| RTSP works but port 3000 is dead | Something opened a bare TCP connection to it. [Confirmed cause](#recovering-from-a-dead-snapshot-server) — reboot it, then stop probing port 3000 |
| Everything slow, timeouts, HA dropping frames | Possibly request volume on a 400 MHz core — but check your own network path first. [Budget guidance](#be-economical-with-requests) |
| Web UI redirects to login forever | Token invalid — [web-ui.md](web-ui.md#the-token) |
| Pink/purple image | IR-cut filter position — [ptz.md](ptz.md#ir-cut-filter) |
| A setting keeps reverting after reboot | The SD card is overwriting flash — [sd-card.md](sd-card.md#settings-precedence) |
| Video dead after saving web UI settings | The sensor dropdown reset `sensor_kern_module` — [sd-card.md](sd-card.md#the-sensor-problem) |

## The 2026 outage: a renamed SSID

The camera was offline from **2026-04-28** to **2026-08-05**. It hardcodes `wifi_ssid=my-iot-ssid` in
`gergesettings.txt`, and on that date an SSID consolidation removed the `my-iot-ssid` and
`my-iot-ssid-office` SSIDs, consolidating onto `my-home-ssid` (same VLAN, **same PSK** — only the name
changed). The camera was hunting for a network that no longer existed.

> ⚠️ **This failure mode is nearly invisible, and that is the lesson worth keeping.** A station
> configured for an absent SSID never sends auth frames, so it appears in **no** association
> list and produces **no** failed-auth log line anywhere. Absence of evidence looked exactly like
> dead hardware.

The give-away was **reading `gergesettings.txt` off the SD card** rather than inferring from the
network. When a device is invisible, go read its configuration; do not keep interrogating the
infrastructure.

Pinned to the exact date because the AP still had its pre-change backups:
`/etc/config/wireless.pre-ssid-change-2026-04-28` contained `option ssid 'my-iot-ssid'` and
`option ssid 'my-iot-ssid-office'`.

Fixed by adding a `my-iot-ssid` SSID on one **access point** (`192.168.1.2`) mirroring `my-home-ssid` —
`radio0` (2.4 GHz channel 6; the camera is 2.4 GHz only), `psk2`, same key — bridged to a new
`network.cams` interface on `br-lan.20`, the **camera VLAN**. That VLAN was already tagged on that
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

## Be economical with requests

**A 400 MHz single-core ARM926 with ~36.5 MB of usable RAM is doing H.264 encode, RTSP serving,
JPEG snapshots, a CGI web server and motion detection at the same time.** There is not much
headroom, so the guidance below is cheap insurance.

> **What this section does *not* claim.** An earlier version asserted the camera is "trivially
> overloaded" and blamed a specific incident on combined load. **That was never demonstrated, and
> two of its supports have since collapsed:** the port-3000 death turned out to have a
> [confirmed non-load cause](#recovering-from-a-dead-snapshot-server) — a bare TCP connect — and a
> separate apparent HA-side overload was traced to broken routing on the workstation, not to the
> camera or to Home Assistant.
>
> On 2026-08-05 the camera did read **load average 4.95 with 3.6 MB free**, and `libre_anyka_app`
> did restart without rebinding port 3000. Those readings stand. What was never established is
> that request volume *caused* any of it. Being frugal on a 400 MHz core is still sensible — just
> don't reason from an overload nobody measured.

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

### Recovering from a dead snapshot server

Restarting `libre_anyka_app` is the obvious move, but **a full reboot is the more reliable
one** — it clears sockets stuck in `TIME_WAIT` and any memory fragmentation a restart inherits.

Why the snapshot server specifically ends up dead has **one confirmed cause and two unproven
hypotheses.** Take the confirmed one first, because it is the one you are most likely to be
doing to yourself:

* **✅ Confirmed — a bare TCP connect kills it.** Opening a socket to port 3000 and closing it
  without a valid HTTP request takes the server down, while RTSP on 554 survives. Port scans,
  TCP-only health checks and uptime monitors all do exactly this. See
  [Finding the camera](#finding-the-camera).

The two hypotheses below were written to explain the "554 yes, 3000 no" shape *before* the
bare-connect behaviour was known. **Both are now less load-bearing** — a plain TCP probe explains
the same shape without invoking either — but neither is ruled out, and neither fully explains the
observed incident, where the whole process restarted (its PID changed) rather than just losing a
listener:

* **Bind failure (untested).** If port 3000 was still held from the previous process and the
  binary does not set `SO_REUSEADDR`, the bind fails while the app carries on serving RTSP. The
  watchdog's 20-second poll restarts well inside the usual 60-second `TIME_WAIT` window, which
  would make this reachable.
* **Memory (untested).** At 3.6 MB free, a JPEG encode buffer allocated at snapshot-server
  startup could fail, with the app continuing without that listener.

If you only remember one thing: **stop probing port 3000 with anything that is not an HTTP GET**,
then see whether the problem recurs at all.

### The watchdog only catches death, not hangs

What restarts the app is `/mnt/anyka_hack/ffmpeg/app_restarter.sh`, started by
`start_web_interface.sh` and now vendored at
[`reference/sd-card-hack/anyka_hack/ffmpeg/`](../reference/sd-card-hack/anyka_hack/ffmpeg/).
It is short enough to quote in full behaviour:

```sh
while [ 1 ]; do check_app; sleep 20; done
```

`check_app` restarts `libre_anyka_app` only when **neither** it **nor** `wrap_mp4.sh` is
running. That second condition is a deliberate mutex: `video?scan=true` intentionally stops the
app to free memory while wrapping clips, and the watchdog must not fight it.

Two consequences worth knowing before you rely on it:

* **It detects death, not hangs.** `check_app` greps `top` for the process name, so an app that
  is wedged but still resident is never restarted. That is precisely the silent-failure shape
  described above — the process is alive, RTSP answers, and port 3000 is simply gone. The
  watchdog will not save you from it.
* **It polls every 20 seconds**, which is well inside the usual 60-second `TIME_WAIT` window. So
  a restart it triggers is very likely to land while the old listening socket is still held —
  which strengthens the `SO_REUSEADDR` hypothesis above for why 3000 fails to rebind while 554
  comes back. Still a hypothesis; it has not been tested against the binary.

## Known rough edges

### The IR-cut filter has been seen to read back `off`

Observed three times in one session. **Check the readback path before the hardware** — a
single-session-token bug in the HA integration produced exactly this symptom at the same time,
so the filter may never have moved. Both explanations, and the order to test them in, are in
[ptz.md](ptz.md#-the-filter-has-been-seen-to-read-back-off--cause-unknown).

### The clock — NTP works, but the timezone config is wrong and only accidentally harmless

**The clock syncs.** This page previously said it was stuck at 1969 with NTP firewalled; that was
true only while `time_source` still pointed at the *old* IoT VLAN router, unreachable after the
camera moved. It was fixed during the move and these docs did not catch up.

Verified on the running camera: `ntpd -n -N -p <router>` is alive, both copies of
`gergesettings.txt` point at the camera-VLAN router, and after ~12 hours of uptime on a box with
**no RTC battery** the clock matched the workstation to the second. It could only be right by
having synced.

The hardware fact still holds and is why `time_source` matters at all: there is a 32.768 kHz RTC
but **no battery**, so every boot starts at the epoch and the camera depends entirely on NTP.

#### ⚠️ The `time_zone` setting is wrong by 15 hours, and something else is saving you

`gergehack.sh` line 87 is a raw pass-through:

```sh
export TZ=$time_zone
```

No transformation. So `time_zone` must be a **POSIX** `TZ` string — and **POSIX counts hours west
of Greenwich**, which is the opposite of the ISO-style sign most people expect:

| String | POSIX meaning | Commonly misread as |
|---|---|---|
| `GMT+07:00` | **UTC−7** (US Pacific, daylight) | UTC+7 |
| `GMT-08:00` | **UTC+8** (China) | UTC−8 |

`gergesettings.txt` carries `time_zone=GMT-08:00` on **both** the card and flash — written by
someone reading it the ISO way. Taken literally that is UTC+8, i.e. **15 hours off**.

**The clock nonetheless displays correctly, by accident.** `/etc/jffs2/time_zone.sh` contains
`export TZ=GMT+07:00` — the correct POSIX form — and `anyka_ipc.sh` sources that file before
launching the app. That is the same file the telnet exploit hooks.

Per upstream's [`hack-process.md`](../reference/hack-process.md), **`time_zone.sh` is overwritten
by the vendor app every time it syncs time with the cloud server.** This camera can no longer
reach that server, because the camera VLAN is default-deny to the WAN. So a correct value is
being **frozen in place by the firewall**. Restore cloud access, or reset flash, and
`gergesettings` takes over and the clock jumps 15 hours.

> **Evidence classes, since they differ here.** The running `ntpd`, the matching clocks, and both
> `gergesettings.txt` copies are **directly observed**. That the vendor app rewrites
> `time_zone.sh` comes from **upstream's write-up**, not from anyone watching it happen.

#### ✅ Fixed — use a DST-aware POSIX string

Neither `GMT-08:00` nor `GMT+07:00` carries a DST rule, so the displayed time would drift an hour
off at every transition. Both problems are solved by giving `time_zone` a full POSIX string
instead of a bare offset:

```ini
time_zone=PST8PDT,M3.2.0,M11.1.0
```

**Applied and tested on the hardware**, in both copies of `gergesettings.txt`:

```console
camera$ TZ="PST8PDT,M3.2.0,M11.1.0" date
Thu Aug  6 07:51:23 PDT 2026
camera$ TZ=UTC date
Thu Aug  6 14:51:23 UTC 2026
```

Exactly −7 — and note it prints **`PDT`, not `GMT`**. That is the real confirmation: uClibc
0.9.33 is applying the DST *rule* rather than treating the string as a fixed offset, so the
November transition is handled automatically. The old `GMT+07:00` printed `GMT`.

`source` tolerates the commas — `gergehack.sh` sources `gergesettings.txt`, so the value is a
shell assignment, and there are no spaces to word-split on.

> ⚠️ [Settings precedence](sd-card.md#settings-precedence) applies. It was changed in **both**
> `/etc/jffs2/gergesettings.txt` and `/mnt/anyka_hack/gergesettings.txt` and verified
> byte-identical with `diff` afterwards — because `gergehack.sh` diffs the two on every boot and,
> on any difference, copies card→flash **and reboots**.

#### ⚠️ Two timezones are in play, deliberately

The fix above does **not** make the whole camera agree with itself.

`/etc/jffs2/time_zone.sh` still contains `export TZ=GMT+07:00`, and `anyka_ipc.sh` sources it, so
the **vendor app's process tree keeps the old value** while `gergehack.sh`'s tree gets the
DST-aware one. That file was left alone on purpose: it is the file the telnet exploit hooks, and
breaking it would risk the hack's entry path for a cosmetic gain.

Net effect is strictly better than before — a 15-hour error became at most a 1-hour one, confined
to the vendor app's tree, and only after the November transition. But it is **not uniform**, so
if you compare timestamps between the web UI and the ptz daemon and see an hour's difference,
this is why. Do not go hunting.

None of this affects Home Assistant, which timestamps its own frames. It affects the camera's own
logs and any filename it generates.

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
* **Do not trust an unregistered MAC OUI as a device fingerprint.** One OUI (`11:22:33`) looked
  like a camera marker but turned out to be shared with smart bulbs, while the camera we were
  actually hunting was on an entirely different one (`AA:BB:CC:DD:EE:FF`). Cheap devices from
  the same contract manufacturer scatter across OUIs, and the same OUI shows up in unrelated
  product categories — so an OUI is a hint, never an identification.

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
