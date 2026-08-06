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

**Everything beyond that is unresolved.** This was originally written up as the filter physically
drifting because raw GPIO writes fight the owning process. Two explanations remain:

* **The Home Assistant integration mis-reported it.** During the same period it had a live fault:
  the camera keeps [a single session token](web-ui.md#the-token) in `/tmp/token.txt`, overwritten
  by every login, so concurrent polls invalidated each other, the helper exited non-zero, and the
  switch read `off`. **This is intermittent by nature**, which fits an intermittent symptom.
* **The filter really is reverting** — something re-asserts the position and overwrites the
  write.

The first needs no hardware behaviour, so **treat "the filter drifts" as unsupported** until the
readback path is known healthy.

> **A gap that closed, and how.** A third explanation sat here for a while: that
> `user_gpio_show` could not read an output pin and always returned `0`. Alongside it was a
> flagged inconsistency — *if reads always return `0`, the switch should have read `off` every
> time, not three times in a session.*
>
> That inconsistency was pointing at a false premise, not a missing mechanism.
> [Readback was measured and works](#-readback-works-and-it-reads-the-physical-pad), so the explanation is gone and the gap
> closed with it. Worth recording as a small vindication of logging things that do not fit:
> the anomaly was the signal.
>
> The comparable open one — the changed PID in the
> [snapshot-server story](troubleshooting.md#recovering-from-a-dead-snapshot-server) — is still
> unexplained.

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

**What has not been tested:** whether the filter physically moves at all when you think it does.
Judge that **by looking at the image**, not by reading the pin. The pin read is trustworthy — it
[reflects the physical pad](#-readback-works-and-it-reads-the-physical-pad) — but the solenoid is
*downstream* of the pad, exactly as the LEDs are, and a swinging pad does not prove the mechanism
moved. Then whether `set_ir_cut` behaves differently from a raw write, and only then whether `-i`
matters. Do them in that order; the first may dissolve the other two.

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
| `IR_LED` | 6 | Infrared illuminator LEDs | ❔ **unverified** — accepts writes, [illumination not shown](#lights--white-confirmed-dark-ir-unresolved) |
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
* **`wifi_en` is a specific anomaly** — see below. It does not generalise.

### ✅ Readback works, and it reads the physical pad

`user_gpio_show` returns `ak_gpio_getpin(pin)`, the value tracks what you write, and
disassembly confirms **why**:

```
g_ak39_gpio_setpin(pin,val)  @ c0012f48   ->  WRITES  0xf00a000c + bank*4   (output data reg)
g_ak39_gpio_getpin(pin)      @ c00130c0   ->  READS   0xf00a0018 + bank*4   (pin-state reg)
```

**Two different registers, twelve bytes apart.** `getpin` reads the **pad**, not the output
latch — so a readback tells you the physical pin state, not merely that a write landed in a
register.

Measured, before the disassembly agreed:

```
WHITE_LED: wrote 0 -> reads 0,  wrote 1 -> reads 1,  wrote 0 -> reads 0,  wrote 1 -> reads 1
IR_LED   : wrote 0 -> reads 0,  wrote 1 -> reads 1,  wrote 0 -> reads 0     (control)
```

> **This page briefly claimed the opposite** — that `user_gpio_show` did an input read on an
> output pad and therefore always returned `0`. That was wrong, was propagated into four other
> places, and is now doubly refuted: empirically, then by disassembly. `ctl`'s
> [`status` command](web-ui.md#the-status-command-works) is a real capability, and a Home
> Assistant switch may read its state back from this interface.

**This makes the [white-LED conclusion](#-white-leds--the-vendor-firmware-disables-them-on-this-variant)
stronger, not weaker.** GPIO 24's *pad* demonstrably swings 0↔1, and there is still no light and
no measurable supply current. The pin is doing its job; there is nothing downstream of it.

#### ✅ `wifi_en` — resolved, and it needed no new mechanism

`wifi_en` reads `0` on a camera whose WiFi is working, while the kernel table shows `val=1`.
This was logged here as an unexplained anomaly. It is now explained, and mundanely:

* **`getpin` reads the pad.** The table's `val=1` set the **latch**. A pad reading `0` while the
  latch is `1` is therefore **not a contradiction** — it means something external is holding pin
  34 low. The `ZT9101UV20` WiFi module is loaded and WiFi works, so its driver owns that pin and
  overrode `user_gpio`'s probe-time value.
* Independently: `/sys/user-gpio/wifi_en` has **mtime epoch 0** — never written via sysfs this
  boot — **and WiFi is up anyway.** So `wifi_en` is not required for WiFi in the first place.

Still: do not write to it hoping to reset the radio. Something else owns it.

> **Worth noting the pattern, because this is the fourth instance.** A sweeping theory — "all
> readbacks are broken" — was invented to explain an observation that had a boring cause. Same
> shape as [the photoresistor](#lights--white-confirmed-dark-ir-unresolved), the `init` spelling, and the IR-cut
> "drift". **On this camera, the boring explanation has won every time.**

## Lights — white confirmed dark, IR unresolved

The LED ring holds **4 infrared and 4 white LEDs**. The white ones are confirmed dark. **The IR
ones are an open question.**

### ❌ White: dark, and the reason is understood

See [below](#-white-leds--the-vendor-firmware-disables-them-on-this-variant). The pad swings,
nothing lights, and the vendor firmware declares this variant unsupported for white LEDs.

### ❔ IR: unresolved — the test that looked decisive was not

IR emitters are invisible to the eye but **plainly visible to a phone camera**, so the question
should cost ten seconds:

```sh
echo 1 > /sys/user-gpio/IR_LED     # assert and hold, do not pulse
```

then point a phone at the ring.

> ⚠️ **This was briefly recorded here as a measured negative. It should not have been.**
>
> The reading was reported alongside a calibration claim — that the same phone had been confirmed
> able to see IR, by looking at a different camera's ring. **The calibration was performed on the
> other camera, and it was assumed rather than checked that the phone was then pointed at this
> one.** It may have been judged by eye here, and **940 nm is invisible to the naked eye**, so an
> uncalibrated look proves nothing.
>
> A properly calibrated re-test is pending. Until it lands, **IR is unresolved — neither working
> nor confirmed dark.**

The general point stands regardless of how this resolves: **a phone camera is the right
instrument, but only if you verify on the same handset, in the same session, that it can see
a known-good IR source.** Otherwise a negative result is indistinguishable from a phone with an
IR-cut filter.

> **If the IR ring does light**, then "both rings dark" collapses to "white only" — which the
> vendor's `not support white led` string already explains — and the remaining fault is the
> day/night switching rather than the emitters.

> ⚠️ **Do not try to settle this with frame luma.** An earlier attempt measured average luma
> rising across on/off pairs (119→124, then 101→119) and briefly recorded it here as proof that
> the IR LEDs worked. It was not proof, and the reasons generalise to any invisible emitter:
>
> * **The ambient baseline moved between samples** — one pair opened at 119, the other at 101.
>   The scene was getting darker on its own.
> * **Sensor AGC responds to that independently**, settling over seconds.
> * **The IR-cut filter shifts luma far more than illumination does**, and `ircut_a` is confirmed
>   working, so that mechanism was live throughout.
>
> No A/B/A/B control was run, so nothing showed luma tracking the *command* rather than the
> *clock*. Two deltas of different magnitude on a drifting baseline is not a signal. A human
> eyeball and a phone settled in ten seconds what the arithmetic could not.

### What this leaves

`IR_LED` (6) and `WHITE_LED` (24) both accept writes and read back correctly, and no light has
been confirmed from either. Since [`getpin` reads the physical pad](#-readback-works-and-it-reads-the-physical-pad),
that readback is meaningful: **the pins really are swinging.** Whatever is wrong is downstream of
the pin, not in the driver.

For the white LEDs there is a firmware-level explanation — see below. **For the IR LEDs there is
not one yet.** The vendor's "not support white led" string says nothing about IR, so the two
rings being dark for the same reason is an assumption, not a finding.

> **Unexplained, and worth keeping visible:** why the IR ring is dark. Candidates nobody has
> ruled out: the pin is right but the LEDs are unpopulated or have no supply rail; the pad is
> muxed elsewhere; or a driver stage is missing. All look identical from software, exactly as
> with the white ring.

Separately, `dmesg` shows repeated `IR_LED store:0` / `store:1` transitions, so something else
may also be writing the node — a night-mode loop would overwrite whatever you set. Assert and
hold rather than pulsing when testing.

> **On the day/night mechanism: we do not know what it is.** Upstream's
> [`IR_shutter.txt`](../reference/IR_shutter.txt) says the LEDs are "automaticly controlled by a
> photoresistor", and **nothing we have examined corroborates it** — not the decoded pin table,
> not the vendor binaries. Cheap SoC cameras commonly do day/night in software from the ISP's
> luma and gain registers rather than fitting a CdS cell, so treat any ambient-light sensor as an
> open question.

### ❌ White LEDs — the vendor firmware disables them on this variant

The hardware is there — 4 white LEDs on the ring — but nothing lights them from
`/sys/user-gpio/`:

```sh
echo 1 > /sys/user-gpio/WHITE_LED    # write succeeds, dmesg logs "WHITE_LED store:1", no light
```

Confirmed by eye with a phone camera. A flat frame-luma reading (**159 / 157 / 157** across
on / off / on) was also recorded, but **treat that as weak corroboration only** — the snapshot
server [returns cached frames when polled quickly](troubleshooting.md#the-snapshot-server-returns-cached-frames),
so a flat series may be one frame fetched three times. The conclusion rests on the pad read, the
absent supply current and the vendor string, not on the luma.

**Three candidates were investigated. Two are now dead, and the survivor is the one this page
listed first from the beginning.**

> **Two corrections this section has been through**, kept visible because both were stated
> confidently:
>
> * It once concluded the cause was "a driver/I2C matter, **not** a pin-number problem." That
>   rested on the AW9523B theory and is wrong.
> * It then said the pin number was "back on the table." That is also now wrong — the pin has
>   been checked and is correct.

**There is no software fix, and no vendor code path to copy.**

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

#### 2. The AW9523B expander — experimentally refuted

❌ **There is no working chip at 0x58 on this board.** This was once the leading theory here; it
is now dead, and the way it died is instructive enough to keep.

The driver's probe was safely re-run — `echo 0-0058 > .../AW9523B/unbind` then `bind`, which is
zero-risk because `remove` is a `return 0` stub — and `aw9523b_write` conveniently `printk`s its
own read-back after every write:

```
aw9523b_write data=0xff, dummy=0xff
aw9523b_write data=0xff, dummy=0xff
aw9523b_write data=0x10, dummy=0xff      <-- wrote 0x10 to GCR 0x11, read back 0xff
aw9523b_write fail!! dummy!=data
aw9523b_write data=0xff, dummy=0xff
aw9523b_write data=0xff, dummy=0xff
aw9523b_probe successed
```

The `0xff` writes appear to succeed only because **`0xff` is also what an idle or absent bus
returns.** The single discriminating write gives it away: `0x10` into GCR `0x11` reads back
`0xff`, where a real AW9523B must return `0x10` — its reserved bits read as 0. Either the reads
are NAKing (the driver returns −1, and its `and r0,r0,#255` masks that to exactly `0xff`) or SDA
is simply floating high.

**The control that makes this conclusive:** the GC1084 sensor is a client on the same `i2c-0`,
and video kept working throughout. So this is not a dead bus — it is a dead address.

> ⚠️ **Why the sysfs node fooled us, which generalises well beyond this camera.**
> `aw9523b_init` calls `i2c_new_device(0x58)` **unconditionally**, and `aw9523b_probe` **ignores
> every return value** — so it prints `probe successed` whether or not any chip answers.
>
> **A `/sys/bus/i2c/devices/0-0058` node naming itself `AW9523B`, and a bound driver, prove only
> that platform code *declared* the device.** They are not evidence that the hardware exists.
> This was a directly observed fact supporting a conclusion it could not carry — the same error
> family as the confounded luma measurement, one level deeper.

The `EXPORT_SYMBOL`'d `aw9523b_read` / `aw9523b_write` are therefore a **red herring**: exported
for a board variant that does have the chip. This one does not.

**And it could never have mattered anyway.** `aw9523b_write` is reachable from `user_gpio_store`
only for **virtual pins 79–82**, and no entry in this camera's pin table uses those. So even a
populated expander could not have been reached through `/sys/user-gpio/`. `ch422_is_exist:0`
as well — both expanders are absent.

#### 3. Wrong pin, or muxed elsewhere — ❌ also refuted

The live kernel table, read out of running memory, confirms **`WHITE_LED` is pin 24 with
`dir=1`** — *identical in configuration to `IR_LED`* — and the pin reads back what is written.
The configuration is not the problem.

Every alternative software route was checked and is closed: no `akgpio` in `/proc/misc`, no
`/dev/ak_pwm`, no `/sys/class/pwm`, no i2c-dev.

#### So: candidate 1, and nothing else

The vendor firmware declares this variant unsupported for white LEDs, the pin is configured
correctly, and there is no other software path to the hardware. **A software fix does not exist,
and there is no vendor code path to copy** — which also means no amount of further poking from
the OS side will help. The remaining question is a hardware one: whether the white LEDs are
populated and supplied at all on a shaking-head board. Continuity or a scope would answer it.

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
