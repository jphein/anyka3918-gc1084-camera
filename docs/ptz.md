# PTZ, IR-cut filter and lights

Pan/tilt runs through kuhnchris' `ptz_daemon`, started by `gergehack.sh` when
`run_ptz_daemon=1`. It reads newline-delimited commands from the FIFO **`/tmp/ptz.daemon`**.
That FIFO is the only control surface — the web UI, Home Assistant and telnet all end up
writing to it.

There is no zoom. "PTZ" here is pan and tilt only; the lens is fixed.

## Quick start

```sh
echo "init_ptz"   > /tmp/ptz.daemon   # home both axes — REQUIRED first
echo "left"       > /tmp/ptz.daemon   # relative, 10 degrees
echo "t2p 190 95" > /tmp/ptz.daemon   # absolute: pan 190, tilt 95 (0 = top)
```

## ⚠️ The homing command is `init_ptz`, not `init`

The upstream [`anyka_hack/ptz/README.md`](../reference/sd-card-hack/anyka_hack/ptz/README.md)
says to home the axes with `init`. **That is wrong.** The daemon accepts the write, spawns a
worker, and silently does nothing. Every subsequent move then fails with:

```
[ak_drv_ptz_turn_to_pos:1027] not init.
```

`gergehack.sh` has the correct spelling — it sends **`init_ptz`**. With that, the daemon reports
real motor parameters (`angle2step steps: 4209`, `MaxHit=369` for pan; `2161` / `189` for tilt)
and the motors move.

This cost a full debugging cycle, because the failure looks like healthy hardware: the daemon
and `cmd_serverd` are both running, and every command is accepted without error.

`ptz_init_on_boot=1` is set in `gergesettings.txt` on this camera, so `gergehack.sh` homes the
axes ~10 s into every boot and you rarely need to send it by hand.

## Command reference

Written one per line to `/tmp/ptz.daemon`. Nothing is echoed back — the FIFO is write-only from
the caller's perspective, and errors surface in the daemon's own stdout, not to the writer.

| Command | Effect |
|---|---|
| `init_ptz` | Home both axes. Required before any movement. |
| `up` / `down` / `left` / `right` | Relative move, 10° |
| `left_up` / `right_up` / `left_down` / `right_down` | Relative diagonal, 10° |
| `t2p <pan> <tilt>` | Absolute move in degrees. Tilt `0` is the top. |
| `init_ir` | Initialise the IR-cut driver |
| `set_ir_cut 1` | IR-cut filter **on** |
| `set_ir_cut 0` | IR-cut filter **off** |
| `q` | Quit the daemon |

Relative and absolute commands compose, so this ends at pan 290, tilt 40:

```sh
echo "t2p 300 50" > /tmp/ptz.daemon
echo "up"         > /tmp/ptz.daemon    # 300,40
echo "left"       > /tmp/ptz.daemon    # 290,40
```

### Dependencies

`ptz_daemon` needs **`cmd_serverd`** running — it is the stock firmware's local control server,
listening on `127.0.0.1:8782`. It is part of the vendor image and starts on its own. If PTZ
commands are accepted but nothing moves and `init_ptz` does not print motor parameters, check
`cmd_serverd` is alive before suspecting the motors.

`gergehack.sh` prefers `/usr/bin/ptz_daemon_dyn` if the camera has it installed in flash, and
otherwise runs `/mnt/anyka_hack/ptz/run_ptz.sh` from the SD card, which sets
`LD_LIBRARY_PATH=/mnt/anyka_hack/ptz/lib` first. This camera runs the SD-card copy.

### Over HTTP

Every web UI `command=` value maps onto exactly one FIFO write. The full table is in
[web-ui.md](web-ui.md#camera-control--cgi-binwebui). Note that `ptz_invert` in
`gergesettings.txt` only swaps which arrow **button** sends which command — it does not change
what `ptzl` means at the daemon.

The web UI exposes no absolute-position control. `t2p` is telnet-only.

## IR-cut filter

The IR-cut filter is the mechanical shutter that makes the audible **click**. It is not the IR
LEDs. With it in the wrong position the image has a heavy pink/purple cast.

There are two ways to drive it, and they are not equivalent.

### The intended way — through the daemon

```sh
echo "set_ir_cut 1" > /tmp/ptz.daemon    # or 0
```

or over HTTP, `command=iron` / `command=iroff`. This goes through the vendor's IR driver, the
same path `libre_anyka_app` uses.

### The direct way — GPIO

```sh
echo 1 > /sys/user-gpio/ircut_a
```

This works immediately but bypasses the driver.

### ⚠️ The filter drifts back on its own — hypothesis, not established fact

`echo 1 > /sys/user-gpio/ircut_a` clears the purple cast, but the setting **re-engages by
itself** — observed reverting three times in a single session, which matches an older note that
it was "stuck on the next day".

The current working theory is that **`libre_anyka_app` runs its own day/night state machine and
re-asserts the IR-cut position**, so a raw GPIO write is a change the owning process does not
know about and overwrites at the next transition. Driving it through `set_ir_cut` instead should
let the driver and the app agree.

Supporting evidence — but **this has not been confirmed**:

* `libre_anyka_app`'s `-i` argument selects exactly this behaviour. The Settings page folds two
  checkboxes into it, and the mapping is:

  | `extra_args` | Day/Night invert | IR filter invert |
  |---|---|---|
  | `-i 1` | off | off |
  | `-i 2` | off | **on** |
  | `-i 3` | **on** | **on** |
  | `-i 4` | **on** | off |

  So the app definitely has an opinion about IR state. This camera runs `-i 4 -u`.
* The daemon exposes `init_ir` / `set_ir_cut`, implying a driver-level owner rather than a bare
  pin.

**What has not been tested:** whether `set_ir_cut` actually holds where the GPIO write does not,
and whether flipping `-i` between 3 and 4 fixes the drift at the source. Both are cheap
experiments for the next session with the camera. Until then, treat the GPIO-versus-daemon
interaction as unproven.

The current mitigation is a boot-time GPIO write from `/Factory/config.sh` on the SD card:

```sh
# keep the IR cut filter in the non-pink position on every boot
(sleep 60; echo 1 > /sys/user-gpio/ircut_a) &
```

The 60-second delay lets the video pipeline come up first. For drift while running,
`switch.anyka_cam_ir_cut_filter` in Home Assistant toggles it live.

> ⚠️ This pins the filter in its **daytime** position, which may cost night-time IR sensitivity.
> Drop the boot line if nights look worse. If the `set_ir_cut` theory holds, the better fix is
> to stop writing the GPIO at all and correct `-i` instead.

## GPIO map

`/sys/user-gpio/` exposes exactly six pins — verified by directory listing, not inferred:

| Pin | Meaning | Observed value |
|---|---|---|
| `IR_LED` | Infrared illuminator LEDs | `1` |
| `SPK_PA` | **Speaker** power amplifier (output side) | `0` |
| `WHITE_LED` | White floodlight LED | `0` |
| `ircut_a` | IR-cut filter, coil A | `1` |
| `ircut_b` | IR-cut filter, coil B | `0` |
| `wifi_en` | WiFi enable | `0` |

Two cautions:

* **`wifi_en` reads `0` on a camera whose WiFi is working.** Do not assume it is a live enable
  line, and do not write to it hoping to reset the radio.
* `ircut_a` and `ircut_b` are the two coils of a latching solenoid. Driving them incoherently is
  not obviously safe; prefer `set_ir_cut`.

## Lights

The white LED and the IR LEDs have not been made to work by writing GPIO:

```sh
echo "1" > /sys/user-gpio/WHITE_LED
echo "1" > /sys/user-gpio/IR_LED
```

`IR_LED` already reads `1` while the illuminator is not obviously on, which suggests the LEDs
are gated by something else — most likely the photoresistor-driven day/night circuit rather than
the pin alone. Unresolved.

## Speaker

`SPK_PA` is the speaker power amplifier and reads `0`. Nothing in this project has driven audio
**out** of the camera yet; upstream's
[`ak_adec_demo`](../reference/sd-card-hack/anyka_hack/ak_adec_demo/) is the starting point, and
`SPK_PA` would be the enable to raise first.

## ⚠️ The microphone cannot be muted

The camera's audio is always on, and there is no way to mute it at the source:

* `libre_anyka_app`'s option string is `w:h:m:i:u` — width, height, motion-record seconds,
  `-i <n>`, and a boolean `-u`. **There is no audio flag**, so restarting the app cannot disable
  the mic either.
* `/sys/user-gpio/` has no microphone pin. `SPK_PA` is the *speaker* amp, i.e. output.
* There is no `amixer` and no `/proc/asound`, so there is no ALSA mixer to mute.

The mic is hardwired on and always encoded into the RTSP stream as PCM A-law. The only "mute"
available is on the consuming side — dropping the audio track in go2rtc, or muting in the
player. That is a playback choice, not a hardware mute. Anyone who needs a genuine guarantee
should treat this camera as an always-live microphone and place it accordingly, or desolder the
mic.

## See also

* [web-ui.md](web-ui.md) — the HTTP wrapper over this FIFO
* [home-assistant.md](home-assistant.md) — the `shell_command` services that drive it
* [`reference/IR_shutter.txt`](../reference/IR_shutter.txt) — upstream's IR notes
