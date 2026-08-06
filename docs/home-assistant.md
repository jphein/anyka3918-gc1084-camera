# Home Assistant integration

## Streams

| | |
|---|---|
| Main | `rtsp://192.168.1.20:554/vs0` — h264 **1280×720** @20 fps, PCM A-law 8 kHz |
| Sub | `rtsp://192.168.1.20:554/vs1` — h264 640×360 @20 fps, PCM A-law 8 kHz |
| Still | `http://192.168.1.20:3000/snapshot.jpeg` — ~32 KB JPEG, 640×360 |

None of these use authentication. `/vs2` returns 404.

The camera is configured in HA as a **Generic Camera** entry with `rtsp_transport: tcp`. The
entity ID is still the legacy `camera.10_0_8_106` from when the camera lived on the IoT VLAN —
the name is cosmetic, the URLs inside it are current.

> **`/vs0` is available and is 720p.** The integration currently points at `/vs1` (640×360),
> because `image_width`/`image_height` in `gergesettings.txt` were mistaken for the only
> published resolution. They set the **sub** channel only. Switching to `/vs0` is a free
> resolution upgrade if the extra bitrate is acceptable over 2.4 GHz WiFi — worth testing before
> committing, since this is a $5 camera on a printed-circuit antenna.

Quality is decent but latency is high, at roughly 5–15 fps effective.

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

`switch.anyka_cam_ir_cut_filter` toggles the IR-cut filter live, and **it works** — `command_on`
runs `anyka_http.py ircut on` → `ctl?command=ircut_on` → `set_ir_cut 1` at the daemon. JP has
driven it this way for weeks; the solenoid audibly clicks.

> ⛔ **If this switch stops working, the first thing to check is whether somebody patched
> `libplat_drv.so` on the camera.** Rewriting its `gpio-ircut_a` / `gpio-ircut_b` / `ir-led`
> strings to match the real node names **breaks this switch** — it looks like an obvious bug fix
> and it is a regression. The good library is md5 `f5769ff013d7a3094e73ee76e312cad0`. Restore it
> and restart the daemon.
> [Why](ptz.md#-the-daemon-path-was-never-broken-a-regression-and-its-rollback).

> ⚠️ **After a power cycle, send `init_ir` before expecting the switch to work.** Nothing runs it
> at boot — `ptz_init_on_boot=1` homes the *PTZ axes* only.
> [Detail](ptz.md#-init_ir-is-required-first--and-nothing-runs-it-at-boot).

> ⚠️ **If that switch reads `off` when you set it `on`, suspect the integration before the
> hardware.** The camera holds [one session token at a time](web-ui.md#the-token), so concurrent
> polls invalidate each other and the helper exits non-zero — which surfaces as a switch flipping
> itself off. That bug was live here and produced exactly this symptom.
>
> Reading GPIO state back from the camera **does** work, so a stateful switch is fine; an earlier
> version of this page wrongly said otherwise. ❔ **But note an open question:** `command_state`
> reads `/sys/user-gpio/ircut_a`, and the daemon moves the filter *without writing sysfs*. Whether
> that read still tracks the filter when the daemon drives it is **not established**. See
> [ptz.md](ptz.md#-the-filter-has-been-seen-to-read-back-off--cause-unknown).

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

Clips live in `/mnt/sounds/` on the SD card and must be **16 kHz mono, pre-attenuated** — the
decoder ignores the file's own sample rate and has no working volume control. Both traps, and
the `ffmpeg` one-liner that avoids them, are in
[ptz.md](ptz.md#speaker--audio-out-works). `command=sounds` lists what is available.

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
