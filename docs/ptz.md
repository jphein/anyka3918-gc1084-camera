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

### ❔ The filter has been seen to read back `off` — cause unknown

**Observation, which is solid:** after setting the filter on, the state has been seen to read
back as `off` — three times in one session — matching an older note that it was "stuck on the
next day".

**Everything beyond that is unresolved, and the filter is now the *least* likely part of it.**
This was previously written up as the filter physically drifting because raw GPIO writes fight
the owning process. Three explanations, worst-supported last:

* **The readback is simply broken.**
  [`user_gpio_show` cannot read an output pin](#-you-cannot-read-gpio-state-back-every-readback-is-meaningless)
  — it returns `0` regardless of what is driven. A control that reads its own state back from
  this interface will report `off` whatever you set, with no hardware involvement at all.
* **A readback bug of a different kind.** During the same period the HA integration had a live
  fault: the camera keeps [a single session token](web-ui.md#the-token) in `/tmp/token.txt`,
  overwritten by every login, so concurrent polls invalidated each other, the helper exited
  non-zero, and the switch read `off`.
* **The filter really is reverting** — something re-asserts the position and overwrites the
  write.

The first explanation needs no hardware behaviour and no timing coincidence, so **treat "the
filter drifts" as unsupported.** The physical claim is now third in line behind two ways of
mis-reading state.

> **One honest gap.** If output reads always return `0`, the switch should have read `off`
> *every* time, not three times. So either the state was being derived some other way, or more
> than one of these was in play. Nobody has reconciled that, and it is worth doing before
> declaring the question closed — it is the same shape of loose end as the changed PID in the
> [snapshot-server story](troubleshooting.md#recovering-from-a-dead-snapshot-server).

If it does turn out to be real, the leading mechanism would be that `libre_anyka_app` runs its
own day/night state machine and re-asserts the position — a raw GPIO write being a change the
owning process does not know about. Circumstantial support:

* `libre_anyka_app`'s `-i` argument selects exactly this behaviour. The Settings page folds two
  checkboxes into it, and the mapping is:

  | `extra_args` | Day/Night invert | IR filter invert |
  |---|---|---|
  | `-i 1` | off | off |
  | `-i 2` | off | **on** |
  | `-i 3` | **on** | **on** |
  | `-i 4` | **on** | off |

  So the app has an opinion about IR state. This camera runs `-i 4 -u`.
* The daemon exposes `init_ir` / `set_ir_cut`, implying a driver-level owner rather than a bare
  pin.

**What has not been tested:** whether the filter physically moves at all when you think it does
— which now has to be judged **by looking at the image**, since the pin cannot be read. Then
whether `set_ir_cut` behaves differently from a raw write, and only then whether `-i` matters.
Do them in that order; the first may dissolve the other two.

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

`/sys/user-gpio/` exposes exactly six pins. The names come from a directory listing; the pin
numbers were decoded from the **kernel image on this camera** (`mtd1` dumped from the live
device), not from upstream:

| Pin | GPIO | Meaning | Writing it does something? |
|---|---|---|---|
| `IR_LED` | 6 | Infrared illuminator LEDs | ❔ **unverified** — accepts writes, [illumination not shown](#-ir-leds--unverified) |
| `SPK_PA` | 7 | **Speaker** power amplifier (output side) | ✅ yes — required for [audio out](#speaker--audio-out-works) |
| `WHITE_LED` | 24 | White LEDs on the ring | ❌ **no — see below** |
| `wifi_en` | 34 | WiFi enable | ❌ no observable effect |
| `ircut_b` | 41 | IR-cut filter, coil B | ❌ no observable effect |
| `ircut_a` | 42 | IR-cut filter, coil A | ✅ yes — flips the filter |
| `motor_switch` | −1 | — | no `/sys` node at all (negative pin) |

**The table corroborates itself on two pins**, and it is worth being precise about which. Both
`SPK_PA` (7) and `ircut_a` (42) do exactly what the table says, and — importantly — both are
confirmed by **direct observation rather than inference**: you *hear* speech come out of the
speaker, and you *see* the image go purple when the filter moves. Neither rests on measuring a
number that could have moved for another reason.

That is meaningful evidence the decode is right rather than a plausible-looking guess, but it is
two pins out of seven, not a validated table. `IR_LED` is untested and the rest have no
observable effect.

> ⚠️ **Do not quote upstream's GPIO numbers for this camera.** They are a genuinely different
> kernel build: `ircut_b` (41) exists here and is **absent** from the upstream firmware image,
> which instead has a prefixed `gpio-ircut_a` and a `motor_switch`. Numbers from Gerge's images
> do not transfer.

Two notes on the pins themselves:

* **`ircut_b` doing nothing is expected, not broken.** 41 and 42 are an **H-bridge pair** driving
  the IR-cut solenoid. Energising the half that pushes the filter toward where it already rests
  produces no visible change. Prefer `set_ir_cut` over touching either directly.
* **`wifi_en` reading `0` on a working camera means nothing** — see the readback warning
  immediately below, which applies to every pin here.

### ⚠️⚠️ You cannot read GPIO state back. Every readback is meaningless.

**`user_gpio_show` performs a GPIO *input* read. On a pin configured as an output, the pad's
input buffer is off, so it returns `0` regardless of the level actually being driven.**

Consequences, and they are broad:

* `cat /sys/user-gpio/anything` tells you **nothing** about that pin's state.
* `wifi_en` reading `0` on a camera with working WiFi is not a puzzle — it is the expected
  output of a read that cannot see anything.
* **Do not build a Home Assistant switch, or any stateful control, that reads state back from
  this interface.** It will report `off` no matter what you set. Track desired state in the
  consumer instead, or drive the pin write-only and accept it is fire-and-forget.
* [`ctl`'s `status` command](web-ui.md#-the-status-command-cannot-be-trusted) inherits this. Its
  output is not a reading.

This retires a premise several earlier conclusions leaned on. Anywhere this project previously
reasoned from "the pin reads N", the correct reading is "we learned nothing".

## Lights

The LED ring holds **4 infrared and 4 white LEDs**. They behave completely differently.

### ❔ IR LEDs — unverified

```sh
echo 1 > /sys/user-gpio/IR_LED
```

**GPIO 6 accepts the write. Whether it actually lights the LEDs has not been demonstrated.**

An earlier attempt measured average frame luma rising across on/off pairs (119→124, then
101→119) and was briefly recorded here as proof. It is not, and the reasons are worth keeping,
because anyone testing an invisible emitter will be tempted by the same shortcut:

* **The ambient baseline moved between samples.** One pair started at luma 119, the other at
  101 — the scene itself was getting darker, which is a luma change with no help from the pin.
* **Sensor AGC responds to that independently**, and settles over seconds.
* **Whatever drives day/night on this camera was live throughout**, including the IR-cut filter,
  which shifts luma far more than illumination does. `ircut_a` is confirmed working, so that
  mechanism was definitely in play.

No A/B/A/B control was run, so nothing showed luma tracking the *command* rather than the
*clock*. Two deltas of different magnitude (5 and 18) on a moving baseline is not a signal.

> **On the day/night mechanism itself: we do not know what it is.** Upstream's
> [`IR_shutter.txt`](../reference/IR_shutter.txt) says the LEDs are "automaticly controlled by a
> photoresistor", and that is worth reading — but **nothing we have examined corroborates it.**
> Not the decoded pin table, not `hw.conf`, not the vendor binaries. Cheap SoC cameras commonly
> do day/night purely in software from the ISP's luma and gain registers rather than fitting a
> CdS cell, so treat the presence of any ambient-light sensor as an open question rather than a
> given.

There is also an open question about whether the value even persists: `dmesg` shows repeated
`IR_LED store:0` / `store:1` transitions, so something else may be writing the node — a vendor
or ptz-daemon night-mode loop would overwrite whatever you set.

> **The decisive test is trivial and costs ten seconds: IR LEDs are visible to a phone camera.**
> Point a phone at the ring and toggle the pin. Do that before believing any luma argument,
> including this one.

### ❌ White LEDs do not light, and the pin is not the problem

The hardware is there — 4 white LEDs on the ring — but nothing lights them from
`/sys/user-gpio/`:

```sh
echo 1 > /sys/user-gpio/WHITE_LED    # write succeeds, dmesg logs "WHITE_LED store:1", no light
```

Measured dead: frame luma **159 / 157 / 157** across on / off / on. (This is a luma measurement,
with all the caveats above — but here it is being used to show *nothing happened*, and a flat
reading across a stable baseline is a much weaker claim than inferring that something did.)

Whatever the cause, **it is a driver/table problem, not a pin-number problem.** Hunting for the
"correct" GPIO is not the fix. Three candidates, best-supported first.

#### 1. This PTZ variant was never wired for white LEDs — best supported

`anyka_ipc` carries the config key `cfg_onf_shaking_head_cam` and this log string:

```
onf_shaking_head_cam not support white led
```

**This camera is a shaking-head (PTZ) unit**, confirmed two independent ways: the kernel
declares two steppers (`ak-motor0` on GPIO 19/20/10/11, `ak-motor1` on 15/14/13/23), and the app
exposes `ptz_h_range`, `ptz_v_range` and `trace_direction`.

So **the stock firmware never lit these LEDs either** — on a PTZ unit it takes the "not support"
branch. `WHITE_LED = 24` looks **vestigial**, inherited from the non-PTZ sibling that shares this
kernel config, and both the 2022 and 2023 vendor builds left it on 24.

This also closes the "read the vendor app" idea properly, and for a better reason than before:
it is not merely that the vendor uses the same sysfs node, it is that **there is no working code
path to trace on this variant.** There is nothing to copy.

#### 2. The AW9523B expander — possible, but weaker than it first looked

`/sys/bus/i2c/devices/` contains **`0-0058`**, which names itself `AW9523B`, and `/proc/kallsyms`
shows **`aw9523b_read` / `aw9523b_write`, both `EXPORT_SYMBOL`'d**. Those are directly observed.

This was originally written up here as *strong* on the theory that the expander's
constant-current LED sinks drive the ring. **That mechanism is wrong**, and the disproof is worth
recording:

* `aw9523b_probe` writes `0x12=0xFF` and `0x13=0xFF`. Those are the LED-mode switches, where
  **1 = plain GPIO mode and 0 = constant-current LED mode** — so all 16 channels are configured
  as GPIO, and the DIM registers `0x20–0x2F` are **never touched**. The vendor never uses the
  chip's LED-driver capability at all.
* **No pin in the 79–82 expander range appears anywhere in the image.** The highest pin used is
  42. The expander branch in `store` is real code that nothing routes to.
* `anyka_ipc` contains **zero** occurrences of `aw9523`, `ch422`, `i2c` or `/dev/i2c`.

What survives is the weaker form: an expander GPIO feeding a MOSFET. Possible, unevidenced.

#### 3. GPIO 24's pad muxed to another peripheral — unresolved

A pad assigned to a different function would produce exactly this symptom: the write lands, the
driver logs it, the pin toggles in software, and nothing reaches the LEDs. Nobody has checked the
pinmux. **This is a perfect symptom match and the least investigated of the three.**

> **A dead end already closed off.** `write_gpio` / `read_gpio` look promising and are not: they
> only store a hardware-ID string in `gpio.conf` and configure nothing.

## Speaker — audio out works

The camera can play audio out of its built-in speaker using the stock
`/usr/bin/ak_adec_demo` decoder. Two things have to be right:

```sh
echo 1 > /sys/user-gpio/SPK_PA                       # 1. enable the amplifier
ak_adec_demo 16000 1 mp3 /mnt/sounds/doorbell.mp3    # 2. decode and play
```

**`SPK_PA` is the speaker power amplifier and sits at `0` on a cold boot.** Without raising it
the decoder runs happily, reports no error, and you hear nothing. This is the single most
confusing part of getting audio out.

Over HTTP this is `command=play&file=<name>`, which does both steps for you — see
[web-ui.md](web-ui.md#sound-playback).

### ⚠️ The sample rate is an argument, not a property of the file

```
usage: ak_adec_demo [sample rate] [channel num] [type] [audio file path]
support type: [mp3/amr/aac/g711a/g711u/pcm]
```

**`ak_adec_demo` does not read the sample rate out of the file — it uses the number you pass.**
Get it wrong and the clip plays at the wrong speed and pitch, with no error.

Upstream's README suggests `ak_adec_demo 41100 1 mp3 ...`, and that value is wrong twice over:
`41100` is a typo for `44100`, and it is the wrong rate for a 16 kHz file regardless. Feeding a
16 kHz clip to a `41100` decoder plays it roughly **2.5× too fast**, which makes speech
unintelligible and sounds exactly like a corrupt file.

The convention in this project is therefore to **standardise every clip to 16 kHz mono MP3** and
hard-code `16000 1` at the call site, so there is no per-file rate to get wrong:

```sh
ffmpeg -i input.mp3 -ac 1 -ar 16000 -af "volume=0.3" /mnt/sounds/output.mp3
```

### ⚠️ There is no working volume control

`ak_adec_demo`'s volume control does not work, and the speaker is **far too loud** at default —
loud enough to make the plastic casing resonate. There is no runtime fix.

**Attenuate the file before you upload it.** `volume=0.3` is a reasonable starting point and
upstream went as low as `volume=0.1` for indoor use.

### Practical notes

* **Background it, and detach it.** A clip played from a CGI request must outlive the request,
  or it is killed when the CGI process exits. `setsid ... </dev/null >/dev/null 2>&1 &` is what
  `ctl` uses.
* **Keep clips on the SD card**, in `/mnt/sounds/`. They will technically fit in `/etc/jffs2`,
  but that partition has [about 8 KB free](hardware.md#flash-layout).
* The decoder also handles `amr`, `aac`, `g711a`, `g711u` and `pcm`.
* Playback is one-way. There is no intercom path, because [the microphone is a separate,
  always-on capture](#-the-microphone-cannot-be-muted) with no mixing.

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
