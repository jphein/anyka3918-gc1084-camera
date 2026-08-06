# Home Assistant integration

## Streams

| | |
|---|---|
| Main | `rtsp://192.168.1.20:554/vs0` — h264 **1280×720** @ **15.2 fps**†, PCM A-law 8 kHz |
| Sub | `rtsp://192.168.1.20:554/vs1` — h264 640×360 @ **15.2 fps**†, PCM A-law 8 kHz |
| Still | `http://192.168.1.20:3000/snapshot.jpeg` — ~32 KB JPEG, 640×360 |

> † **15.2 fps is measured, 2026-08-06.** `ffmpeg -rtsp_transport tcp -t 30 -an -f null -`
> against `/vs1`: **455 frames in 29.93 s of stream time = 15.20 fps**, and 455 frames in
> 28.77 s of *wall clock* = 15.82 fps — delivering slightly ahead of its own timestamps, so
> it is keeping up rather than lagging. ffmpeg's independent `tbr` estimate agrees at 15.17.
> ⚠️ **That figure is for `/vs1`. `/vs0`'s *delivered* rate has not been measured.** `/vs0`
> returned a byte-identical frame count — but per the warning below that is guaranteed by the
> method, not observed in the device: `-t` cuts on media time, so two streams stamping at the
> same nominal rate always return the same count. **It establishes that both streams *declare*
> the same rate; it says nothing about what `/vs0` delivers.** 720p is 4× the pixels over
> 2.4 GHz on a printed-circuit antenna, which is exactly where a delivered rate could fall
> behind a declared one.
>
> ⚠️ Count frames; do not read `avg_frame_rate`, and do not divide by ffmpeg's `time=`.
> That field is the **media timestamp**, not wall clock — dividing by it returns the rate the
> camera *stamps* frames at, which is a declared number wearing a measurement's clothes. The
> giveaway was `/vs0` and `/vs1` reporting byte-identical counts: `-t` cuts on media time, so
> both stopped at the same stamp by construction.
>
> **The "20 fps" that stood here until 2026-08-06 was never sourced anywhere.** Searched that
> day: not in `gergesettings.txt`, not in the app's argv (`-w 640 -h 360 -m 0 -i 4 -u`, no
> rate flag), and no anyka/video/encoder entry under `/proc` reports throughput. It was wrong
> by ~24%. The `640×360` half *is* traceable — `image_width`/`image_height` in
> `gergesettings.txt`, passed to the running process, and `ctl?command=stats` reports it from
> the live argv.
>
> **There is no fps counter on this camera and `stats` deliberately returns `"fps":null`** —
> which is precisely why this had to be measured from outside. Use `encoder_cpu_jiffies`
> differentiated across two polls if you need an "is the encoder actually working" signal.

None of these use authentication. `/vs2` returns 404.

The camera is configured in HA as a **Generic Camera** entry with `rtsp_transport: tcp`. The
entity ID is still the legacy `camera.10_0_8_106` from when the camera lived on a different
VLAN — the name is cosmetic, the URLs inside it are current. (Not "the IoT VLAN": that phrase is
[ambiguous here](troubleshooting.md#-name-the-vlan-by-its-tag-never-by-a-nickname), because the
SSID the cameras join is *named* after IoT while sitting on the camera VLAN.)

> **`/vs0` is available and is 720p.** The integration currently points at `/vs1` (640×360),
> because `image_width`/`image_height` in `gergesettings.txt` were mistaken for the only
> published resolution. They set the **sub** channel only. Switching to `/vs0` is a free
> resolution upgrade if the extra bitrate is acceptable over 2.4 GHz WiFi — worth testing before
> committing, since this is a $5 camera on a printed-circuit antenna.

Quality is decent. Throughput is **15.2 fps measured** (2026-08-06) — an earlier note here
estimated "roughly 5–15 fps effective", which was directionally right and slightly
pessimistic, and closer to the truth than the confident "20" that sat in the table beside
it. **Latency has never been measured**; it is reported as high by observation only.

## Liveness testing

> ⚠️ **A camera entity reports `idle` whether or not it works.** The state is not a health
> signal. The only real liveness test is fetching a frame:
>
> ```
> /api/camera_proxy/camera.<entity_id>
> ```
>
> HTTP 200 with a real frame means it works. Anything else means it does not.

## Video and audio — WebRTC card

Home Assistant with the [WebRTC custom card](https://github.com/AlexxIT/WebRTC) works well:

* Fullscreen
* Picture in Picture
* Digital zoom with scroll wheel
* Download a snapshot
* One-way audio

> ⚠️ **The WebRTC integration is currently disabled**, so `custom:webrtc-camera` cards render as
> "Custom element doesn't exist". `go2rtc` is still enabled. Re-enable WebRTC before re-adding
> the card.

## Go easy on the polling

There is not much CPU headroom on a 400 MHz single core, so keep the request rate modest. This
is precaution rather than a fix for a measured problem — an earlier version of this page blamed
a specific incident on HA polling, and [that was never
demonstrated](troubleshooting.md#be-economical-with-requests).

Practical limits:

* Poll camera state at **5 minutes or slower**, not 60 seconds.
* Let **go2rtc hold the single RTSP connection** and have everything else consume it from there,
  rather than pointing several clients at port 554.
* Point automation at [`/cgi-bin/ctl`](web-ui.md#cgi-binctl--our-fast-control-endpoint), not
  `/cgi-bin/webui` — the stock page costs 0.2–1.0 s of camera CPU per request.

Budget guidance, and an honest note on what the "overload" evidence does and does not support: [troubleshooting.md](troubleshooting.md#be-economical-with-requests).

## PTZ

PTZ is wired as five `shell_command` services — `anyka_ptz_left`, `_right`, `_up`, `_down`,
`_home` — surfaced as buttons in the Anyka section of the Cameras view. They live in
`packages/anyka_camera.yaml` in the `ha` repo and call a helper deployed to
`/config/scripts/anyka_ptz.py`, which writes to the camera's `/tmp/ptz.daemon` FIFO over telnet.

`switch.anyka_cam_ir_cut_filter` toggles the IR-cut filter live, and **it works — since
2026-08-06.** `command_on` runs `anyka_http.py ircut on` → `ctl?command=ircut_on`, and `ctl` now
**writes `/sys/user-gpio/ircut_a` directly.**

Verified through the button itself, 14 s settle, distinct frame hashes: green fraction `0.659`
(magenta) → `1.019` (normal).

> #### ❌ RETRACTED: "it has worked for weeks"
>
> An earlier version of this page said this switch had worked reliably for weeks through the ptz
> daemon. **It never worked through that route at all.** `ctl` used to write `set_ir_cut` into the
> daemon's FIFO, and the daemon's `ak_drv_ir_init` stats the *prefixed* `gpio-ircut_*` names,
> which do not exist on this build — so it returned `-1` and `set_ir_cut` bailed before writing.
>
> **Nothing reported it**, because `camera_set_ircut` unconditionally returns `0`. `ctl` said
> `OK`, `command_state` honestly read an unchanged pin, and it presented as **a flaky switch
> rather than a dead code path.** That is the single most expensive shape of bug on this device.

> ⛔ **If this switch stops working, check for a patched `libplat_drv.so` first.** Renaming its
> `gpio-ircut_a` **and** `gpio-ircut_b` strings tips the driver into a 10 ms pulse mode built for
> a latching solenoid, and this filter is hold-to-engage — so every command **parks it in
> magenta**. Known-good binaries:
>
> | File | Good md5 |
> |---|---|
> | `libre_anyka_app` | `3458b8598ca9525a0d5e693ff5fd5d5c` (**stock** — yes, stock) |
> | `ptz/lib/libplat_drv.so` | `f5769ff013d7a3094e73ee76e312cad0` (**original**) |
>
> Restore and restart. **Leave `cgi-bin/header` patched** (`934ce4814d4fc90edec82275769986c5`) —
> it is the RCE fix, and it is unrelated to any of this.
> [Why](ptz.md#-root-cause-the-libplat_drvso-patch-tipped-the-driver-into-a-mode-for-other-hardware).

> ⚠️ **`init_ir` is not the fix, and a previous version of this page said it was.** It is required
> before `set_ir_cut` and it does not help, because `init_ir` is what calls the initialisation
> that fails. **Nothing runs it at boot either** — `ptz_init_on_boot=1` homes the *PTZ axes* only.
> The working answer is the direct write `ctl` now does.

> ⚠️ **If that switch reads `off` when you set it `on`, suspect the integration before the
> hardware.** The camera holds [one session token at a time](web-ui.md#the-token), so concurrent
> polls invalidate each other and the helper exits non-zero — which surfaces as a switch flipping
> itself off. That bug was live here and produced exactly this symptom.
>
> ✅ **The state read is now unambiguously meaningful, and an open question closes with it.** This
> page wondered whether `command_state`'s read of `/sys/user-gpio/ircut_a` still tracked the
> filter when something else drove it. **`ctl` now writes that exact node**, so command and state
> refer to the same pin by construction. The question is gone rather than answered — the
> configuration that made it hard no longer exists.

Command semantics, the mandatory `init_ptz` homing step, and the IR-cut caveats are in
[ptz.md](ptz.md).

### Alternative: HTTP instead of telnet

Now that the [web UI's API](web-ui.md) is documented, PTZ can also be driven over HTTP with
`rest_command`, which avoids shelling out to telnet:

```yaml
rest_command:
  anyka_ptz:
    url: "http://192.168.1.20/cgi-bin/webui?token={{ token }}&command={{ command }}"
    method: get
```

> ⚠️ This is **not** obviously the better option. The token changes on every login, has no
> expiry, and there is only one session slot — so a `rest_command` that logs in each time will
> silently invalidate any browser session, and a cached token dies at the next camera reboot.
> The telnet helper has no such state. Documented as a possibility, not a recommendation.

### WebRTC card PTZ config

If the WebRTC card is re-enabled, its PTZ overlay wires to a script like this
(from [AlexxIT's examples](https://github.com/AlexxIT/WebRTC/wiki/PTZ-Config-Examples)):

```yaml
# configuration.yaml
script:
  camera_ptz:
    sequence:
      - service: rest_command.camera_ptz_start
        data:
          param: "{{ direction }}"
      - service: rest_command.camera_ptz_stop
        data:
          param: "{{ direction }}"
```

```yaml
# card
type: 'custom:webrtc-camera'
entity: ...
ptz:
  service: script.camera_ptz
  data_left:  { direction: directionleft }
  data_right: { direction: directionright }
  data_up:    { direction: directionup }
  data_down:  { direction: directiondown }
```

Note the camera has **no zoom** and no continuous-motion start/stop — moves are discrete 10°
steps — so the start/stop pattern above collapses to a single call per press.

## Health sensors

`sensor.anyka_cam_health` and `binary_sensor.anyka_cam_online` track whether the camera is
actually serving, rather than trusting the camera entity's state (which reads `idle` either way).

> ⚠️ **The port-3000 probe must be a real HTTP GET.** A bare TCP connect **kills the snapshot
> server** — an early version of this check was taking down the very thing it was monitoring, and
> the symptom (RTSP fine, snapshots dead) looks like a camera fault rather than a monitoring
> fault.
>
> ```sh
> curl -fsS -o /dev/null http://192.168.1.20:3000/snapshot.jpeg
> ```
>
> A GET is also the better check: it proves the encoder is producing frames, not merely that
> something is listening. Same rule applies to uptime monitors and recurring port scans — see
> [troubleshooting.md](troubleshooting.md#finding-the-camera).

Keep the poll interval slow — these sensors are part of the load budget too.

## Speech to text — the mic feeds Whisper

The camera's always-on microphone works end to end into Home Assistant's speech-to-text
pipeline, so the audio track is usable for voice events and not just monitoring.

> ⚠️ **HA's STT API needs raw PCM, not a WAV file** — despite the API advertising `format=wav`.
> Posting a WAV container returns **HTTP 415**. Strip the header and send the raw samples.

Given [the mic cannot be muted](ptz.md#-the-microphone-cannot-be-muted), treat this as a
capability the camera has whether or not you use it, and site the camera accordingly.

## Playing sounds through the camera

The camera can play MP3s out of its built-in speaker, which makes it usable as an announcement
or deterrent endpoint from HA — a `rest_command` per clip, or one parameterised by name:

```yaml
rest_command:
  anyka_play:
    url: "http://192.168.1.20/cgi-bin/ctl?token={{ token }}&command=play&file={{ clip }}"
    method: get
```

Clips live in `/mnt/sounds/` on the SD card and must be **16 kHz mono** — the decoder ignores the
file's own sample rate and uses the number it is given. That trap, and the `ffmpeg` one-liner that
avoids it, are in [ptz.md](ptz.md#speaker--audio-out-works). `command=sounds` lists what is
available.

> ⚠️ **Do not pre-attenuate clips, and set the volume on the camera instead.** An earlier version
> of this page said clips must be *"pre-attenuated"* because the decoder had no working volume
> control. **Both halves are retracted.** There is a
> [six-rung volume ladder](ptz.md#-volume-a-six-rung-ladder-shipped-on-the-card) on the card, and
> attenuating the file is undone by a compressor downstream of it — measured at 10.3 dB into the
> camera and inaudible coming out.

The same token caveat as PTZ applies — see [above](#alternative-http-instead-of-telnet).

## ⚠️ Audio is always live

The microphone cannot be muted at the camera. Muting in the HA player or dropping the audio
track in go2rtc is a playback choice, not a hardware mute — the stream still carries audio.
Details and the evidence are in [ptz.md](ptz.md#-the-microphone-cannot-be-muted).

## Scope

Of the ~3 cameras originally set up, **only this one** was ever in Home Assistant. The other HA
cameras are unrelated: two Hikvision cameras on the camera VLAN, three `video.cgi` MJPEG cams, and an
iCam365 over ONVIF.

## See also

* [web-ui.md](web-ui.md) — HTTP API, and why port 80 must stay on an isolated VLAN
* [troubleshooting.md](troubleshooting.md) — when the entity goes dark

## ⚠️ This camera's load average has a permanent +3 offset — do not alert on it

`ctl?command=stats` reports `load1/5/15`, and the raw number is **misleading on this
hardware**. Measured 2026-08-06:

```
load1 median 4.26        but    cpu_used median 30.6 %   (~69 % idle)
```

**MEASURED — three kernel threads sit permanently in `D` (uninterruptible sleep):**

```
D 796 (wlan_mgmt_00)
D 797 (ap_00)
D 798 (mlme_00)
```

Those are the `ZT9101UV20` WiFi driver's threads, and they are parked in D state from boot
regardless of activity. `top` agrees with the CPU figure independently: `46.6% idle`.

**INFERRED, from standard Linux load semantics** (load average counts uninterruptible-sleep
tasks, not just runnable ones): those three threads contribute a constant **≈ +3.0** to every
load reading. So the camera's *real* load is roughly `load1 − 3`, i.e. **~1.2, not ~4.3**.

Consequences:

- **Never treat this camera's load average as CPU pressure.** Use `cpu_total_jiffies` /
  `cpu_idle_jiffies` differentiated across two polls; that is the honest number.
- **Any alerting threshold must account for the +3 baseline**, or it fires permanently.
- It is **not** caused by anything this project did — these are driver threads present from
  boot, on a stock WiFi module.

This was mis-stated twice on 2026-08-06 (including by the agent who then measured it), which
is why it is written down: the load figure is the single most quotable and most misleading
number the camera reports about itself. Same trap as `uptime` 7.14 vs `vmstat` 80 % idle on
another host the same day.

`hz` in the bundle is **100** — that is `USER_HZ`, the fixed Linux ABI unit for
`/proc/stat` and `/proc/<pid>/stat`, confirmed on-device with `getconf CLK_TCK`. An earlier
sanity check computed 96.6 from `total_jiffies / uptime`; that shortfall is unaccounted boot
ticks, **not** evidence that `hz` is 96.6. Do not "correct" it.

## What a sustained RTSP consumer actually costs — MEASURED 2026-08-06

Captured through `ctl?command=stats` while `nebula-inventory` held short streams. Phases
self-labelled by the bundle's own `rtsp_clients` field, so no clock sync was needed:

```
no client (idle)     n=8   cpu 32.9 %   app-cpu 25.0 %   mem_free 4442 kB
client attached      n=8   cpu 42.3 %   app-cpu 32.1 %   mem_free 4012 kB
```

**One sustained consumer costs roughly +9 pp CPU and +7 pp app-CPU**, on a camera that idles
around 67 % free. An independent 8-sample baseline an hour earlier read 30.6 % / 24.1 %,
matching the idle rows here — the instrument is consistent across runs.

**So this camera can comfortably sustain a continuous RTSP consumer.** That question had been
open, with the repo's existing caution recorded as *"precaution rather than a fix for a
measured problem"*. It is now measured. Note this is the opposite of what the raw load
average suggests — see the +3 offset section above.

**Memory is the tighter resource, not CPU.** `mem_free_kb` fell to a low of 3456 kB with a
client attached. That is the number to watch under a permanent consumer.

### Two things deliberately NOT concluded

**Per-stream cost.** The point estimates came out with the 720p main *cheaper* than the 360p
substream (37.3 % vs 43.6 %), which is backwards. With n=3 against n=5 and 10 s samples
straddling the start/stop boundaries, that is most likely dilution — but a real mechanism
exists too (if the ISP encodes 720p natively and `/vs1` is a downscale, the substream costs
an extra scale+encode). **Not established either way; do not quote the split.** The test
would be a longer single-stream hold on each, timed to sample boundaries.

**What `encoder_cpu_jiffies` measures.** It is `libre_anyka_app`'s *total* CPU — encode plus
RTSP packetisation and network I/O. A rise proves the app is working harder, **not** that the
extra work is encoding.

> ⚠️ **RETRACTED 2026-08-06, and the retraction is the instructive part.** This section
> originally continued: *"It does cleanly refute 'both streams are always encoded, so the main
> is free': app CPU did not stay flat when a client attached."* **That inference does not
> survive the sentence immediately before it**, as `nebula-inventory` pointed out.
>
> The test was "if app CPU stays flat while a client pulls `/vs0`, both streams were already
> being encoded". But if the counter also includes packetisation and network I/O, attaching a
> client raises it **whether or not encoding was already running**. The flat reading was never
> achievable, so the observation cannot separate the hypotheses — **a test that can only
> return one answer.** That is this repo's own rule (a uniform result means a broken
> instrument) applied to a test designed by the person who wrote the rule down.
>
> **Whether both streams are encoded continuously is UNKNOWN.** `nebula-inventory`'s frame
> counts do not settle it either — both streams delivered identical counts at identical
> cadence, which is equally consistent with one pipeline and with two independent encoders
> sharing a sensor clock. Do not cite either measurement as evidence.
>
> The discriminating test is **pulling both streams simultaneously**: if both are always
> encoded, the second consumer adds only packetisation; if encoded on demand, it adds roughly
> a whole encode. `rtsp_clients` reads 2 during that phase, so it self-labels.

Observer overhead: the sampler ran at 10 s intervals, ~0.5 s each, ≈5 % duty present in
every phase equally. Absolute figures include it; the deltas do not.

## ⚠️ `ERR auth` means CONTENTION, not a dead camera

The camera holds **exactly one** token, in `/tmp/token.txt`. Any successful login overwrites
it, instantly invalidating everyone else's. This is not theoretical and not confined to HA:
while taking the baseline above, two calls came back `ERR auth` **because JP was pressing
buttons in the dashboard at the same time.** It happens on plain reads, under entirely normal
use.

So any poller must treat `ERR auth` as **"re-read the token and retry"**, never as a camera
fault:

```python
if body.strip() == 'ERR auth':
    token = reread_token()      # someone else logged in
    retry()
```

**Getting this wrong is worse than it sounds.** A tile that renders "camera offline" because
another poller logged in points whoever debugs it at the network, the camera, or the SD card
— none of which are the problem. The camera is fine and answering in 0.1 s.

Two ways to avoid it entirely:

- **Go through `anyka_http.py`**, which holds a `flock` for the whole login+command sequence
  so callers queue instead of racing. **Any new HA polling should use this rather than
  opening its own HTTP path.**
- **Don't mint a token at all** where the data allows it. The snapshot endpoint on port 3000
  and RTSP need no login, so health and stream measurements can sidestep the contention
  completely — `nebula-inventory`'s stream measurement was built this way deliberately.

Note the interaction with polling frequency: **more pollers means more logins means more
contention**, so this is a second argument for the conservative interval, independent of CPU
cost. Four pollers at 60 s is four token overwrites a minute.
