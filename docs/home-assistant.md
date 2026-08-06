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

## ⚠️ Go easy on the polling

**This camera has no CPU headroom.** Three HA switches polling every 60 s, plus a live video
stream, plus anything else touching it, is enough to push it to load 4.95 and knock the snapshot
server off port 3000 — which then breaks HA config saves, because HA validates `still_image_url`
before writing.

Practical limits:

* Poll camera state at **5 minutes or slower**, not 60 seconds.
* Let **go2rtc hold the single RTSP connection** and have everything else consume it from there,
  rather than pointing several clients at port 554.
* Point automation at [`/cgi-bin/ctl`](web-ui.md#cgi-binctl--our-fast-control-endpoint), not
  `/cgi-bin/webui` — the stock page costs 0.2–1.0 s of camera CPU per request.

Full incident write-up and budget guidance: [troubleshooting.md](troubleshooting.md#-this-camera-is-trivially-overloaded).

## PTZ

PTZ is wired as five `shell_command` services — `anyka_ptz_left`, `_right`, `_up`, `_down`,
`_home` — surfaced as buttons in the Anyka section of the Cameras view. They live in
`packages/anyka_camera.yaml` in the `ha` repo and call a helper deployed to
`/config/scripts/anyka_ptz.py`, which writes to the camera's `/tmp/ptz.daemon` FIFO over telnet.

`switch.anyka_cam_ir_cut_filter` toggles the IR-cut filter live, for when it drifts back mid-session.

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
