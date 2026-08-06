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
| `init_ir` | Initialise the IR-cut driver. **Required before `set_ir_cut`, and *not* run at boot** — [detail](#-retracted-set_ir_cut-through-the-daemon-and-it-worked-for-weeks) |
| `set_ir_cut 1` | IR-cut filter **on** |
| `set_ir_cut 0` | IR-cut filter **off** |
| `q` | Quit the daemon |

> ⚠️ **Two separate initialisation steps, one settings key.** `ptz_init_on_boot=1` runs `init_ptz`
> only. **Nothing runs `init_ir`.** Homed axes do not imply a ready IR driver.

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

> ## 🔑 One write works. Every vendor route is dead, and they die in the same place.
>
> **Writing `/sys/user-gpio/ircut_a` directly is the only thing that moves this filter.** Every
> route the firmware provides fails, and disassembly shows all three failing at **one shared
> cause** — `ak_drv_ir_init` in `libplat_drv.so` stats the **2022** node names `gpio-ircut_a` and
> `gpio-ircut_b`, which do not exist on this 2023 build, so the driver is never initialised.

| Route | Status | Why |
|---|---|---|
| **`echo 1 > /sys/user-gpio/ircut_a`** | ✅ **works** | nothing in between |
| **`/cgi-bin/ctl`** (Home Assistant) | ✅ **works — since 2026-08-06** | rewritten to write the pin directly |
| `set_ir_cut` at the ptz daemon | ❌ dead | `ak_drv_ir_init` → `-1`, `set_ir_cut` bails before writing |
| `libre_anyka_app` day/night | ❌ dead | `ak_drv_ir_get_input_level()` → `-1`, the thread bails |
| `ak_drv_ir_demo -s 1/0` ([upstream's method](#-referenceir_shuttertxt-is-wrong-for-this-camera)) | ❌ dead | same init failure. **Tested live** |

**Six distinct `libplat_drv.so` builds are now known, and every one carries the 2022 `gpio-`
names.** This is not a corrupted file or an odd variant — the vendor shipped a library that cannot
address its own hardware, and nothing reports it, because `camera_set_ircut` is a `sprintf` into
`ak_cmd_exec` that **hard-codes `return 0`**.

*Evidence class: `lucid-camera`'s disassembly of the unstripped binaries, plus one live test of
`ak_drv_ir_demo`.*

### ✅ Route 1: write the pin

```sh
echo 1 > /sys/user-gpio/ircut_a     # 1 = filter IN = normal colour
```

**Polarity, because this project had it inverted for most of a day:** `1` puts the filter **in**,
which is the normal daytime position. `0` takes it out, which is what makes the image purple.

> ⚠️ **Allow ~10 seconds.** The filter takes **4–8 s** to move, so
> [measuring sooner gives a false negative](troubleshooting.md#measuring-the-ir-cut-filter-the-best-instrument-is-your-ears).
> Judge by the image, not by re-reading the pin — the pin read is honest, but the solenoid is
> downstream of it.

### ✅ Route 2: `/cgi-bin/ctl` — what Home Assistant uses, fixed 2026-08-06

`ctl` used to write `set_ir_cut N` into the daemon's FIFO. It now writes the pin itself:

```sh
ircut_on)   echo 1 > /sys/user-gpio/ircut_a ;;
ircut_off)  echo 0 > /sys/user-gpio/ircut_a ;;
```

**Verified through the actual Home Assistant button**, with a 14 s settle and distinct frame
hashes: green fraction **`0.659`** (filter out, magenta) → **`1.019`** (filter in, normal).

This is kernel-agnostic — a direct write to a node this build has — so it needs no detection and
ships on every card.

### ❌ RETRACTED: `set_ir_cut` through the daemon, and "it worked for weeks"

**The FIFO route could never have worked on this kernel.** `ak_drv_ir_init` stats the prefixed
`gpio-ircut_a` and `gpio-ircut_b`, both absent here, so it returns `-1` without setting its
`inited` flag, and `ak_drv_ir_set_ircut` bails with `[ak_drv_ir_set_ircut:229] not inited` before
writing anything.

**Nothing reported it.** `camera_set_ircut` is a `sprintf` into `ak_cmd_exec` that unconditionally
returns `0`. So `ctl` replied `OK`, `command_state` honestly read an unchanged pin, and the whole
thing presented as **a flaky switch rather than a dead code path.**

> #### ❌ And this resolves the open question, by dissolving it
>
> This page asked: *if `init_ir` is required and nothing runs it at boot, how did the switch work
> for weeks?* It listed three candidate explanations and refused to choose between them.
>
> **All three are retired. The answer is that it never worked.** The apparent history of a working
> switch was **never this code path**, so there was no mechanism to find — the question had a false
> premise, and every candidate answer was an attempt to explain something that had not happened.
>
> **Worth keeping as a pattern**, because it has now happened twice on this page: an open question
> that resists three plausible explanations may be
> [pointing at a false premise](#-the-filter-has-been-seen-to-read-back-off--cause-unknown)
> rather than a missing mechanism. When candidate explanations all feel strained, **re-examine the
> observation before inventing a fourth.**
>
> ❔ **What is *not* resolved**, and is deliberately left open: what JP actually experienced as a
> working switch for weeks. The command path was dead throughout, so something else accounts for
> it — the [boot-time mitigation](#the-boot-time-mitigation-is-user-relied-on-behaviour) holding
> the filter in the good position is the obvious candidate, but nobody has established that and it
> is not being asserted here.

> ⚠️ **`init_ir` is still a real requirement — it is just not a sufficient one.** The command
> exists, the daemon accepts it, and `set_ir_cut` genuinely will not work without it. It also
> genuinely does not work *with* it on this build, because `init_ir` is what calls the
> `ak_drv_ir_init` that fails. **Nothing runs it at boot** — `ptz_init_on_boot=1` homes the PTZ
> axes only.
>
> **The earlier reversal of its retraction stands, and the meta-lesson with it:** absent evidence
> of the negative, retract to **"unproven"**, not to **"false"**. Deleting a true statement costs
> as much as asserting a false one and is harder to notice afterwards, because the record no
> longer contains what you removed. This page has now lost a
> [correct prediction](#-the-two-actors-conflict-was-predicted-in-writing-and-then-deleted) that
> way, at real cost.

### 🔴 ROOT CAUSE: the `libplat_drv.so` patch tipped the driver into a mode for other hardware

**The mechanism is now exact, from disassembly.** `ak_drv_ir_init` stats **both** node names and
branches three ways:

| `stat()` results | Log line | Mode |
|---|---|---|
| **both fail** | `Ircut a & b interface can't access` | **driver disabled** — returns `-1`, `inited` never set |
| **exactly one works** | `Only can access:%s` | **1-line** — one write, **value stays asserted** |
| **both work** | `Ircut a & b interface all can access` | **2-line** — a pulse |

And 2-line mode does this:

```c
a = v;  b = !v;  ak_sleep_ms(10);  a = 0;  b = 0;    // for a LATCHING solenoid
```

**This board's filter is hold-to-engage on `ircut_a` alone, with 4–8 s of travel.** A 10 ms pulse
that then *releases* the pin cannot hold it. So in 2-line mode **every command ends with the
filter parked OUT** — magenta — regardless of which direction you asked for.

That is JP's *"it toggles then goes back to the position it was before"*, precisely: the pin is
asserted, then released 10 ms later.

> #### 🎯 The attribution is exact, and it indicts thoroughness
>
> The patch renamed **both** `gpio-ircut_a` **and** `gpio-ircut_b`. That is what tipped `init`
> from the **disabled** branch straight past 1-line into **2-line**.
>
> **Renaming `gpio-ircut_b` alone caused the regression.** Renaming only `ircut_a` would have
> landed in **1-line mode — write-and-hold, which is correct for this hardware** — and would not
> have regressed at all.
>
> **The more thorough fix was the harmful one.** Fixing one wrong string would have worked; fixing
> both broke it. There is no instinct in normal engineering practice that protects against this —
> "I found two instances of the bug, I fixed both" is exactly what a careful person does.
>
> (The third edit, `ir-led` → `IR_LED`, was **dead code**: `ptz_daemon_dyn` imports no
> `ak_drv_irled_*` symbol at all.)

**So the load-bearing failure was the `stat()` failing.** It kept the driver *disabled*, and a
disabled driver was better than a driver running in a mode built for hardware this board does not
have.

#### 🔑 The two-actors conflict was predicted, in writing, and then deleted

**This exact failure was documented as a risk in this file, argued about, and dismissed.** It is
reproduced verbatim, because the reasoning that dismissed it is more instructive than the bug:

> > **Two actors on one pin — a documented risk, deliberately not designed around.** Once
> > `libre_anyka_app` *and* `ptz_daemon` can both reach `ircut_a`, the app's automatic day/night
> > loop and manual `set_ir_cut` (what Home Assistant drives) could contend.
> >
> > **No arbitration has been built, on purpose.** The conflict is hypothetical: the app's
> > automatic loop has **never been observed to move that pin**, patched or not. Building
> > sequencing or locking now would mean designing around behaviour nobody has seen, which is the
> > exact failure mode this project has produced repeatedly today.
> >
> > **Symptom if it does appear:** a manual `set_ir_cut` gets reverted at the app's next
> > evaluation.

**The predicted symptom is, word for word, the symptom that occurred — and the predicted mechanism
is wrong.** The app's day/night loop never woke up. The reverting was the daemon's own 10 ms
pulse.

> ### ⚠️ A matching symptom is not a confirmed mechanism, and this is what that cost
>
> This prediction did real damage **precisely because it looked confirmed.** JP reported "toggles
> then goes back", the deleted paragraph had predicted "gets reverted at the app's next
> evaluation", and the match was close enough that the investigation went straight to
> `libre_anyka_app` — **the wrong binary** — and stayed there through a rollback, a root-cause
> write-up and two commits of mine.
>
> **Two entirely different mechanisms produce that same sentence.** A day/night loop overwriting
> you, and a driver that asserts a pin then releases it 10 ms later, are indistinguishable from
> the outside. JP's description was accurate and it simply did not discriminate.
>
> **When a symptom matches a prediction you already had, that is the moment to demand independent
> confirmation of the mechanism — not the moment to stop looking.** A prediction coming true feels
> like evidence. It is a hypothesis with better PR.

> ### The dismissal reasoning: sound rule, right answer, and still worth keeping
>
> The argument was *don't build for a conflict nobody has observed* — the rule adopted after
> inventing a photoresistor, an H-bridge and an I²C expander that all turned out not to exist.
>
> **The conclusion was correct**: the app's loop genuinely never acts, so arbitration against it
> would indeed have been designing around nothing. But it was right for the wrong reason, and the
> flaw in the reasoning is still worth keeping:
>
> **"Never observed" is only evidence of "will not happen" while the conditions that prevented it
> hold.** The loop had never been seen to act because its path was broken, and the very next
> action was to repair that path. If you are about to change a condition your observational record
> rests on, **that record expires at the moment you change it.** Ask what your evidence is
> conditional on before treating absence as safety.
>
> **And the warning was deleted** in the same commit that moved the investigation to
> `libplat_drv.so` — dropped as stale scaffolding. That is the
> [over-retraction failure mode](#-retracted-set_ir_cut-through-the-daemon-and-it-worked-for-weeks)
> doing real damage: the record no longer contained the paragraph that would at least have kept
> pin-contention on the table.

#### The vendor app's day/night loop is confirmed inert

**Restored — this page was right the first time.** It once said the loop had never been seen to
move the IR-cut pin even with the patch applied. **I retracted that as a false negative. The
retraction was wrong and the original observation was correct**, and there is now a mechanism:

```c
lev = ak_drv_ir_get_input_level();
if (lev == -1) goto sleep;          // photosensitive_switch_th_ex, every loop
```

`ak_drv_ir_get_input_level` resolves into **`libre_anyka_app/lib/libplat_drv.so` (`385740be…`) —
a *different* build that nobody ever patched**, structurally identical: the same two `stat()`s on
the prefixed names, the same `if (!inited) return -1`. The level is always `-1`, so the thread
bails **before reaching any write**.

> 🔑 **The patch fixed the write end of a two-ended chain while the sense end stayed broken in a
> file nobody touched.** That is the cleanest illustration on this page of why string-level
> reasoning fails: both ends were visible, both were wrong in the same way, and correcting one of
> them changed nothing whatsoever.

Still true and unaffected: with the filter out and the scene IR-washed, **the app asserted
`IR_LED` by itself.** The illuminator path and the filter path are separate, and only the filter
path is dead. That answers the older question — the repeated
`IR_LED store:0` / `store:1` in `dmesg` is **the vendor app**, not a mystery writer.

#### 🔴 Automatic day/night is not fixable on this board

**Stop here. This is not a patching problem, and it will consume a day if you treat it as one.**

Even if `ak_drv_ir_init` succeeded, two further gates would bite:

* a **`cfg[0x1c] != 2` mode gate**, and
* `get_input_level`'s sensor is **`gpio-rf_feed`** — which **does not exist on this board** and
  cannot be renamed to anything that does. It falls back to `/sys/kernel/ain/ain0`, **measured
  pinned at a constant `2999`**, which trips the unchanged-since-last-reading guard forever.

**The feature needs a sensor input this hardware does not expose.** No arrangement of binary
patches reaches it. The [boot-time mitigation](#the-boot-time-mitigation-is-user-relied-on-behaviour)
is the only automatic IR-cut action available here — and given
[both LED rings are dark](#lights--neither-ring-lights), there is no working IR illumination for a
night mode to switch *to* anyway. **Nothing is being given up.**

> ❌ **RETRACTED: "you get automatic day/night *or* reliable manual control, not both."** That
> framed it as a trade-off with a wrong default. **There is no trade.** One side of it does not
> exist and cannot be made to.

#### Current state

| File | md5 | State |
|---|---|---|
| `libre_anyka_app` | `3458b8598ca9525a0d5e693ff5fd5d5c` | **ORIGINAL** — reverted |
| `ptz/lib/libplat_drv.so` | `f5769ff013d7a3094e73ee76e312cad0` | **ORIGINAL** — reverted |
| `cgi-bin/header` | `934ce4814d4fc90edec82275769986c5` | **PATCHED — keep**, unrelated |
| `cgi-bin/ctl` | — | **PATCHED — keep.** Writes the pin directly |

Verified alongside: snapshot server returns `200`, RTSP carries h264 + `pcm_alaw`, filter is IN
and the image is normal.

> ✅ **The `cgi-bin/header` RCE fix stays and is not implicated in any of this.** It closes a real
> unauthenticated remote root hole, it was verified by demonstrating the exploit and then its
> absence, and it touches nothing to do with GPIO. **Do not revert it while cleaning up.**

#### The boot-time mitigation is user-relied-on behaviour

```sh
# keep the IR cut filter in the non-pink position on every boot
(sleep 60; echo 1 > /sys/user-gpio/ircut_a) &
```

> ⚠️ **`ctl` handles button presses. `config.sh` handles boot. Neither covers the other.**
>
> Do not read the `ctl` fix as making this line redundant — they address different moments. `ctl`
> only runs when somebody presses something; nothing presses anything at 3 a.m. after a power cut.
> **A camera with the `ctl` fix and no boot line comes up magenta and stays magenta until a human
> notices.**
>
> This is worth stating because the two fixes look interchangeable — both end in
> `echo 1 > /sys/user-gpio/ircut_a`, and it is tempting to conclude one supersedes the other. They
> are the same *write* at different *times*, and the times are what matter.

**This is not a workaround this project invented.** JP has relied on it for a long time — in his
words, *"we used to apply the ircut filter to fix the magenta on startup bug"* — and it is on his
live card at `/Factory/config.sh` with that comment.

> ⚠️ **It was missing from the backup, and therefore from every card this tool has ever written.**
> A fresh camera would boot magenta and stay that way. `tools/write-sd-card.sh` now appends it.
>
> **The 60 s delay is deliberate** — `gergehack.sh` and the module loads must finish before
> `/sys/user-gpio/` exists.
>
> A confirmation worth recording: appending to the backup's 30-line `config.sh` lands this at
> **line 33, exactly where it sits on JP's card.** That checks the placement *and* establishes
> that `gergehack.sh` returns rather than blocking — otherwise JP's own line would never have run.

> ❔ **Why the backup lacks it is unknown, and is being left unknown.** The obvious story — the
> line was added to the live card after the backup was taken — is plausible and **nobody has
> checked it.** Recorded as an open question rather than a tidy explanation, because a
> confident-sounding cause is exactly what this page keeps having to retract.
>
> **The transferable part needs no mechanism:** a working system had a modification its backup did
> not, and the gap was invisible until a fresh install. **Diff the live device against what you
> would deploy**, rather than trusting the backup to be complete.

### ❌ RETRACTED: "IR-cut control through the daemon is broken"

**It was never broken.** This section previously asserted, in bold, that the daemon could not move
the filter. That was wrong, and it was wrong on the strength of a measurement that did not test
what it appeared to test. JP had been driving the filter through the daemon for weeks while this
page said it was impossible.

#### What was actually measured, and what it actually proved

```
ctl?command=ircut_on   ->  'OK'
  baseline    ircut_a=1  mtime=1786031282  Gfrac=1.066  filter IN
  after 16 s  ircut_a=1  mtime=1786031282  Gfrac=1.048  filter IN
```

**Split this into its two halves, because only one of them survives.**

| Half | Verdict |
|---|---|
| **The mtime did not move.** sysfs updates mtime on *any* write, including a same-value one. | ✅ **Stands.** The daemon genuinely never writes `/sys/user-gpio/ircut_a`. |
| **The green fraction did not move**, therefore the filter did not move, therefore the daemon is broken. | ❌ **Void.** |

**The mtime result was read as proving the wrong claim.** It proves *the daemon does not use
sysfs*. It was taken as proving *the daemon cannot move the filter*. Those are different
statements, and everything downstream followed from conflating them.

> ⚠️ **And the green-fraction half was never evidence of anything.** Look at the baseline:
> `ircut_a=1` is **filter already IN**, and the command issued was `ircut_on`. **It commanded the
> filter to the state it was already in**, then read the resulting non-change as proof of
> brokenness.
>
> **That is precisely the fallacy this same page retracts a few paragraphs above** — "nothing
> happened because nothing needed to." The page caught the error, wrote it down, and then
> committed it again in the opposite direction within the same day. Both readings (1.066 and
> 1.048) are inside the **filter-IN band** of
> [1.06–1.39](troubleshooting.md#the-bands-and-the-boundary-that-does-not-exist) anyway, so the
> numbers agree with each other and say nothing about the daemon.

#### The rollback sequence, and a correction to how it was first written up

**2026-08-06, in order:**

1. `libre_anyka_app` was patched (`gpio-ircut_a` → `ircut_a`) and shipped as a day/night fix.
2. `/mnt/anyka_hack/ptz/lib/libplat_drv.so` was patched on the live camera — `gpio-ircut_a`,
   `gpio-ircut_b`, `ir-led` — and the daemon restarted.
3. **JP reported the regression:** the Home Assistant IR-cut switch had worked for weeks and
   stopped — *"it was working before even if it doesn't now"*, and then the decisive detail,
   *"it toggles then goes back to the position it was before."*
4. `libplat_drv.so` was rolled back. JP confirmed by ear that the solenoid *"does actually click
   on and off again."*
5. `libre_anyka_app` was rolled back too. **Harmless but unnecessary** — it is
   [confirmed inert](#the-vendor-apps-daynight-loop-is-confirmed-inert), and it neither caused nor
   fixed anything.
6. `ctl` was rewritten to [write the pin directly](#-route-2-cgi-binctl--what-home-assistant-uses-fixed-2026-08-06).
   **That is what actually made JP's toggle work.**

> ### ❌❌ This attribution flipped twice. Both flips are recorded, because the pattern is the
> ### point.
>
> | Version | Blamed | Verdict |
> |---|---|---|
> | 1st | `libplat_drv.so` | ✅ **correct**, and abandoned without disproof |
> | 2nd | `libre_anyka_app` | ❌ wrong — that binary is inert |
> | 3rd (this) | `libplat_drv.so`, with a disassembled mechanism | ✅ correct, and now *supported* |
>
> **The first answer was right and was given up because a better-sounding story arrived.** The
> second rested on a symptom matching a prediction — which
> [is not confirmation](#-a-matching-symptom-is-not-a-confirmed-mechanism-and-this-is-what-that-cost)
> — and on the ordinary confounder of **two changes in flight**, where reverting one and seeing
> improvement does not identify which one mattered.
>
> **The thing that finally settled it was neither observation nor inference: somebody read the
> code.** Two rounds of careful reasoning over symptoms produced two confident answers, one of
> them wrong. One disassembly produced a mechanism precise enough to name *which single string*
> caused it. On this device that has now been true repeatedly — **when a question survives two
> rounds of symptom-based reasoning, stop reasoning and go read the binary.**

> ### 🔑 The lesson, and it is the sharpest one this project has produced
>
> **A string that looks broken may be a dead path whose failure is load-bearing.**
>
> `gpio-ircut_a` in a binary on a camera with no `gpio-ircut_a` node looks like an unambiguous
> defect. It reads as a bug you can see with `strings` and fix with `dd`. But **a path that
> reliably fails is still a behaviour the rest of the system is built on** — silence from a dead
> branch can be exactly what keeps the live branch in control.
>
> **Before "fixing" a wrong-looking path, establish that it is the path actually being taken.**
> Not that it exists. Not that it is wrong. That it *executes*. The cheapest check is usually to
> break it *further* — or simply to ask whether the feature currently works, which here would
> have cost one question and saved the whole excursion.
>
> **This was the fourth time in one day that a fix targeted something outside the execution
> path**, after the `ptz_daemon` binary that never runs, the AW9523B that is not on the board, and
> the photoresistor that does not exist. The pattern is now the single most reliable predictor of
> wasted effort in this repo: *we keep finding real defects in code that does not run.*

> ### 🔑 The sibling lesson: a prescriptive clause riding on a verified observation
>
> Found by `luna-ha` in `packages/anyka_camera.yaml`, where **all three errors shared one shape**:
> a **correct, verified factual half** with an **unverified "so you should…" half attached** — the
> polarity note, an `init_ir` consequence, and a *"fixable by renaming pins the way the ircut path
> was"* clause.
>
> **The verified half lends its authority to the unverified one.** A reader checks the first
> clause, finds it sound, and carries that confidence across the comma.
>
> **The tell, and it generalises well past this project:** a **"…the way X was"** or **"…so you
> should Y"** clause hanging off a sentence whose factual half you *did* check. Those clauses need
> their own evidence, and they almost never get it — precisely because the sentence already feels
> verified.
>
> **It is the sibling of the lesson above**, one level up: that one says do not trust your account
> of what a thing *does not do*; this one says do not trust the advice you *attach* to something
> you confirmed. Note that this page's own *"fixable by renaming"* framing is the ancestor of the
> regression — the observation (the string is wrong) was right, and the prescription (so rename
> it) was never independently justified.

> ✅ **Consequence for Home Assistant — resolved, and both earlier claims retracted.** This page
> called `switch.anyka_cam_ir_cut_filter` "a no-op switch with a truthful state", then said the
> command half worked and had for weeks. **Neither was right.** The command half was dead the
> whole time; the state half was honest throughout, faithfully reporting a pin nothing was moving.
>
> **Both halves now refer to the same node by construction**, because
> [`ctl` writes `/sys/user-gpio/ircut_a` directly](#-route-2-cgi-binctl--what-home-assistant-uses-fixed-2026-08-06)
> and `command_state` reads it. The open question about whether the state read tracked the filter
> is **gone rather than answered** — the configuration that made it hard no longer exists.

#### ❌ ALSO RETRACTED: "`ptz_daemon` has the same bug"

This page said the 2.1 MB `ptz_daemon` carried the same hard-coded prefixed paths. **The strings
are genuinely in that file — but that file never runs**, so patching it would fix nothing.

```
ps  ->  /mnt/anyka_hack/ptz/ptz_daemon_dyn        <- this is what executes
```

`ptz_daemon_dyn` (122181 B) is the dynamically-linked variant and contains **zero**
`/sys/user-gpio` strings — verified. Its paths come from a shared library. The static
`ptz_daemon` is inert here and is **deliberately left unpatched**; it may still matter on a
variant that launches it, since `gergehack.sh` has a `/usr/bin/ptz_daemon_dyn` preference branch.

#### 🔴 `libplat_drv.so` — where the prefixed strings live. **Do not patch it.**

> ### ⛔ This is the file that caused the regression. Leave it alone.
>
> Everything below is **reference for identifying the file**, not a recipe. The offsets are
> correct, the strings really are wrong, and **applying the patch breaks working IR-cut control**
> — [that experiment has been run](#-retracted-ir-cut-control-through-the-daemon-is-broken).
>
> It is documented rather than deleted for one reason: **this table is exactly what makes the
> patch look obvious and safe.** Someone will rediscover these strings with `strings` and reach
> for `dd`. The warning has to live next to the temptation, not on the front page.
>
> **The live camera runs the original, md5 `f5769ff013d7a3094e73ee76e312cad0`. Verify that before
> anything else if the IR-cut filter stops clicking.**

There are two different builds sharing the filename:

| Copy | Size | md5 | Strings |
|---|---|---|---|
| `ptz/lib/libplat_drv.so` | 33782 | `f5769ff013d7a3094e73ee76e312cad0` | `gpio-rf_feed`, `gpio-ircut_a`, `gpio-ircut_b`, **`ir-led`** |
| `libre_anyka_app/lib/`, `rtsp/lib/` | 26594 | `385740bed22797fb5bb26a996cd3e145` | `gpio-rf_feed`, `gpio-ircut_a`, `gpio-ircut_b` |

> ⚠️ **Identify this file by md5, not by filename.** Three files share the name and there are two
> distinct builds with different offsets. Both repo copies match the card exactly — which is how
> the rollback was verified.

Offsets in the 33782-byte build. **These are the edits that were applied and then reverted** —
listed so the damage can be recognised, not so it can be repeated:

| Offset | Original (**correct — leave it**) | What the patch wrote |
|---|---|---|
| `0x450f` | `/sys/user-gpio/gpio-ircut_a` | `/sys/user-gpio/ircut_a` |
| `0x452b` | `/sys/user-gpio/gpio-ircut_b` | `/sys/user-gpio/ircut_b` |
| `0x466e` | `/sys/user-gpio/ir-led` | `/sys/user-gpio/IR_LED` |
| `0x4457` | `/sys/user-gpio/gpio-rf_feed` | — never touched |

**`ir-led` vs the live `IR_LED` is a genuine fourth naming mismatch** — and it is the clearest
illustration of how these patches sell themselves, because being the same length it was *the
safest and simplest of the four edits*. **Ease of patching says nothing about whether patching is
the right move**, and "it's only a rename, and the lengths even match" is the argument that
carried all four.

> ⚠️ **`gpio-rf_feed` cannot be fixed by renaming, and this reasoning survived the regression
> intact.** The live node list is exactly `IR_LED SPK_PA WHITE_LED ircut_a ircut_b wifi_en` —
> there is no `rf_feed` in any spelling. **Do not point it at another name that also does not
> exist**; that turns a clean `ENOENT` into a silent wrong-pin write, which is strictly worse.
>
> Note that this warning was already arguing, for one string, exactly what the regression proved
> for the others: **a failing path can be the safe one.** It was right, and it was not
> generalised. Worth remembering that the correct instinct was already written down here.

**Status: reverted, and to be left reverted.** Any future attempt needs to start from a
demonstration of *which call actually moves the solenoid*, not from the strings — and any test
must [command a real change and be judged by ear](troubleshooting.md#measuring-the-ir-cut-filter-the-best-instrument-is-your-ears),
since the metric that "confirmed" the patch was the one that had already been shown unreliable.

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

> ### ⚠️ The proposed mechanism has since been **proven real** — and it still does not explain
> ### this observation. Resist merging them.
>
> This section long speculated that `libre_anyka_app` re-asserts the pin from its own day/night
> loop. **That mechanism is now confirmed**: it is exactly
> [what the patch unleashed](#-root-cause-the-libplat_drvso-patch-tipped-the-driver-into-a-mode-for-other-hardware),
> and JP's *"toggles then goes back"* is it operating.
>
> **But it cannot be the cause of the observations above**, and the reason is a date. Those
> readbacks happened while the camera ran the **stock** binary, whose writes fail `ENOENT`. **A
> writer that cannot write cannot revert anything.** The confirmed mechanism only exists in a
> configuration that did not exist yet when the symptom was recorded.
>
> **This is the trap this repo has documented and fallen into repeatedly** — see
> [the pattern note](#-wifi_en--resolved-and-it-needed-no-new-mechanism): a mechanism being real
> is not the same as it being *the* mechanism, and the temptation to close an open question with a
> newly-proven neighbour is strongest right after proving it. The two remaining explanations below
> are unchanged, and the token bug is still the more likely.

If it does turn out to be real **on the stock binary**, the mechanism would have to be something
other than the app's sysfs writes — those demonstrably fail. Circumstantial support for *an*
owning process, which survives:

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
  pin. **This is no longer only circumstantial**: the daemon demonstrably moves the filter
  [without writing sysfs at all](#-retracted-ir-cut-control-through-the-daemon-is-broken),
  so a driver-level owner is not an inference from the API shape — something has to be moving that
  solenoid, and it is not `/sys/user-gpio/ircut_a`.

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
| `IR_LED` | 6 | Infrared illuminator LEDs | ❌ pad toggles, [ring stays dark](#-ir-confirmed-dark). The vendor app *does* write this pin. |
| `SPK_PA` | 7 | **Speaker** power amplifier (output side) | ✅ yes — required for [audio out](#speaker--audio-out-works) |
| `WHITE_LED` | 24 | White LEDs on the ring | ❌ **no — see below** |
| `wifi_en` | 34 | WiFi enable | ❌ no observable effect |
| `ircut_b` | 41 | IR-cut filter — role unknown | ❌ **no observable effect** — measured, not assumed |
| `ircut_a` | 42 | IR-cut filter — **hold to engage** | ✅ yes — moves the filter on its own |
| `motor_switch` | −1 | — | no `/sys` node at all (negative pin) |

**The table corroborates itself on two pins**, and it is worth being precise about which. Both
`SPK_PA` (7) and `ircut_a` (42) do exactly what the table says, and — importantly — both are
confirmed by **direct observation rather than inference**: you *hear* speech come out of the
speaker, and you *see* the image go purple when the filter moves. Neither rests on measuring a
number that could have moved for another reason.

That is meaningful evidence the decode is right rather than a plausible-looking guess, but it is
two pins out of seven, not a validated table. `IR_LED` and `WHITE_LED` toggle their pads and
drive nothing; `ircut_b` and `wifi_en` have no observable effect.

> ⚠️ **Do not quote upstream's GPIO numbers for this camera.** They are a genuinely different
> kernel build: `ircut_b` (41) exists here and is **absent** from the upstream firmware image,
> which instead has a prefixed `gpio-ircut_a` and a `motor_switch`. Numbers from Gerge's images
> do not transfer.

Two notes on the pins themselves:

* **`ircut_a` is hold-to-engage, and it acts alone.** Assert it and the filter moves; release it
  and the filter returns. Holding `ircut_a=1` is the **normal operating state**, not a stress
  condition — both the vendor daemon's `set_ir_cut 0` path and the known-good baseline sit there.
* **`ircut_b` genuinely does nothing, and we do not know why.** See the retraction below.
* **`wifi_en` is a specific anomaly** — see below. It does not generalise.

> ### ⚖️ PARTLY UN-RETRACTED: the "H-bridge pair" idea was half right
>
> This page said 41 and 42 were two halves of a complementary pair, then retracted it outright as
> unsupported. **The retraction went too far, and the disassembly says which half was right.**
>
> ✅ **Right about the code.** `ak_drv_ir_set_ircut` in 2-line mode really does drive them as a
> complementary pair — `a = v; b = !v; sleep 10 ms; a = 0; b = 0`. That is a latching-solenoid
> pulse, and the intuition was **not** baseless.
>
> ❌ **Wrong about the board.** `ircut_b` is not wired to anything here, and the filter is
> hold-to-engage on `ircut_a` alone with 4–8 s of travel. A 10 ms pulse that releases cannot move
> it. **The vendor's code models hardware this unit does not have.**
>
> **This is the third time today that retracting to "false" was itself an error** — after
> `init_ir` and the day/night loop. The honest verdict was always available: *right about the
> driver, wrong about this board.* Retract to **unproven**, and say **which part** is unproven.

The measurement below stands, and is what showed the board does not match the code:
>
> Measured with the filter out: `ircut_b=1` held for 14 s produced a **dead-flat**
> [green fraction](troubleshooting.md#measuring-the-ir-cut-filter-the-best-instrument-is-your-ears)
> (0.450 → 0.451 → 0.451), with a **passing positive control** (releasing `ircut_a` swung the
> filter) and a **passing negative control** (26 s with no spontaneous return). The filter is
> hold-to-engage on `ircut_a` alone.
>
> **This matters structurally, and makes the picture less tidy.** The H-bridge story was what
> explained `ircut_b` away, leaving `WHITE_LED` as the *sole* unexplained failure. Without it,
> **both `ircut_b` and `WHITE_LED` are measured-dead and unexplained.**

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
> shape as [the photoresistor](#lights--neither-ring-lights), the `init` spelling, and the IR-cut
> "drift". **On this camera, the boring explanation has won every time.**

## Lights — neither ring lights

The LED ring holds **4 infrared and 4 white LEDs**. **Neither lights**, and both pins
demonstrably toggle [at the pad](#-readback-works-and-it-reads-the-physical-pad) — so whatever is
wrong is downstream of the GPIO in both cases.

The white ring has a firmware explanation. **The IR ring does not**, and that is left open.

### ❌ White: dark, and the reason is understood

See [below](#-white-leds--the-vendor-firmware-disables-them-on-this-variant). The pad swings,
nothing lights, and the vendor firmware declares this variant unsupported for white LEDs.

### ❌ IR: confirmed dark

IR emitters are invisible to the eye but **plainly visible to a phone camera**, so the question
costs ten seconds:

```sh
echo 1 > /sys/user-gpio/IR_LED     # assert and hold, do not pulse
```

then point a phone at the ring.

**Result: no glow.** And critically, **the same phone demonstrably shows another camera's IR
emitters** — so the instrument is validated and this is a **true negative**, not a phone that
cannot see IR.

That distinction is the whole test, and it took two attempts to get right:

> ⚠️ **The first attempt was recorded as a measured negative and should not have been.** It came
> with a calibration claim — that the phone had been confirmed able to see IR — but **the
> calibration was performed on a *different* camera, and the transfer to this one was assumed
> rather than checked.** It may have been judged by eye, and **940 nm is invisible to the naked
> eye**, so an uncalibrated look proves nothing.
>
> **A phone camera is the right instrument, but only if you verify on the same handset, in the
> same session, that it can see a known-good IR source.** Otherwise a negative is
> indistinguishable from a phone with an IR-cut filter.

Two earlier nulls are **retrospectively vindicated**: optical and supply-current measurements for
IR had both come back negative and were honestly written off at the time as possible instrument
failures. They were **true negatives all along**.

**So both rings are dark, while both pins demonstrably toggle at the pad.**

> ❓ **Why the IR ring is dark remains open**, and is deliberately not folded into the white-LED
> explanation. The vendor's `not support white led` string says nothing about IR. Two dark rings
> may share a cause — an unpopulated LED stage, a missing supply rail — but that is an assumption,
> and this project's record on assumed shared causes is poor.

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

Separately, `dmesg` shows repeated `IR_LED store:0` / `store:1` transitions. **That is answered:
the vendor app is writing them**, from a day/night loop that
[works for the LED and fails for the filter](#-root-cause-the-libplat_drvso-patch-tipped-the-driver-into-a-mode-for-other-hardware).
So assert and hold rather than pulsing when testing — something else is competing with you.

> ### ✅ The day/night sense mechanism is now known — and it is why the feature cannot work
>
> This paragraph used to say "we do not know what it is". **We do.** The driver reads its ambient
> level from **`gpio-rf_feed`**, and when that is absent it falls back to `/sys/kernel/ain/ain0` —
> an ADC channel **measured pinned at a constant `2999`** on this board.
>
> So there is no photoresistor, exactly as suspected, but the reason matters more than the
> absence: **the input the vendor's code wants is a pin this board does not route, and its
> fallback is a dead ADC.** [Automatic day/night is therefore unfixable
> here](#-automatic-daynight-is-not-fixable-on-this-board), at any level of patching.
>
> Upstream's ["automaticly controlled by a photoresistor"](#-referenceir_shuttertxt-is-wrong-for-this-camera)
> is a real quote describing different hardware — **not a fabrication**, which this project once
> recorded it as.

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
* [`reference/IR_shutter.txt`](../reference/IR_shutter.txt) — upstream's IR notes, **and see the
  correction below before following any of it**

## ❌ `reference/IR_shutter.txt` is wrong for this camera

Upstream's IR notes are the obvious place to start and **every method in them fails here.** This
is not a criticism of that file — it describes a different unit — but following it costs an
afternoon.

| Upstream says | On this camera |
|---|---|
| `ak_drv_ir_demo -s 1/0` toggles the filter | ❌ **Tested live. Does nothing.** Prints `Ircut a & b interface can't access`; the pin does not follow `-s` |
| The binary is under `oldcam` | ❌ no such path — it is at `/mnt/ak_drv_ir_demo` |
| Needs `cmd_serverd` / `run_cmd_server=1` | ❌ **neither exists on this build** |
| The LEDs are "automaticly controlled by a photoresistor" | ❌ not on this board — the driver's input is `gpio-rf_feed`, absent here, falling back to `ain0` **pinned at a constant 2999** |

> ⚠️ **The photoresistor line is a real quote from that file, not a fabrication.** This project
> previously logged it as an invented mechanism; it is not. **It is accurately transcribed and
> wrong when applied to this unit** — which is a different failure, and a much more common one.
> Vendored upstream documentation describes the author's hardware, and cheap cameras from one
> contract manufacturer vary underneath a shared firmware.
>
> **Attribute the error to the transfer, not to the source.** Getting that distinction wrong makes
> a useful reference look untrustworthy when it is merely about a different board.

`ak_drv_ir_demo` fails for [the same shared reason as everything else](#-one-write-works-every-vendor-route-is-dead-and-they-die-in-the-same-place):
`ak_drv_ir_init` cannot find the prefixed node names. **All three vendor routes die in one
place.**
