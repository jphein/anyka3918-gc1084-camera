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

## ⚠️ Measuring anything on this camera

Two gotchas that **invalidate measurements silently**, and which have already produced a fiction
in this project's own notes. Read these before trusting any number derived from snapshots.

### The snapshot server returns cached frames

**Polled faster than its encoder updates, port 3000 hands back the *same frame* — byte-identical,
not merely similar.** Six consecutive fetches of an unchanging scene came back at luma
`130.47` **six times to two decimal places**.

> ⚠️ **A "noise floor" measured that way is fiction — it is a frame compared against itself.**
> The real frame-to-frame noise on this camera is **±10–14**, not the ~3 that unpaced sampling
> suggests.
>
> This retroactively weakens any earlier conclusion of the form "the difference was tiny, so
> nothing happened", because a tiny difference may just mean you fetched one frame twice.

**Pace your requests**, and **verify frames are actually distinct** — compare bytes or hashes,
do not assume two fetches are two frames.

### The IR-cut filter in one table

Everything you need before touching it, because getting any of these wrong has cost time:

| | |
|---|---|
| `ircut_a=1` | filter **IN** → **normal colour** (daytime position) |
| `ircut_a=0` | filter **OUT** → **magenta / pink cast** (IR-pass) |
| Transition time | **4–8 s.** Allow **≥10 s** before measuring — sampling at 2–4 s guarantees a false negative |
| Green fraction, filter IN | **≥ 1.00** (observed 1.019 – 1.39) |
| Green fraction, filter OUT | **≤ 0.90** (observed 0.45 – 0.90) |
| Best instrument | **A human hearing the solenoid click.** Beats every image metric |
| Chromatic test is blind when | **the scene has little IR** — under blue-dominant indoor light the filter can swing with almost no colour change |
| Symptom: *toggles then reverts* | Somebody patched `libplat_drv.so` — the driver is in 2-line pulse mode and releases the pin 10 ms after asserting it. Restore md5 `f5769ff013d7a3094e73ee76e312cad0` — [see ptz.md](ptz.md#-root-cause-the-libplat_drvso-patch-tipped-the-driver-into-a-mode-for-other-hardware) |
| Symptom: *`OK` but nothing moves, ever* | You are on a vendor route. **All three are dead** — write `/sys/user-gpio/ircut_a` directly, which is what `ctl` now does |

### Measuring the IR-cut filter: the best instrument is your ears

> 🔑 **Before reaching for any image metric: go and listen.** The filter is a solenoid and it
> **clicks, audibly**, on every transition. A human standing next to the camera hearing it click
> on and off is **a more reliable instrument than any number computed from a frame** — it has no
> threshold to mis-set, no scene dependency, and no cached-frame failure mode. The two hardest
> IR-cut questions of 2026-08-06 were both settled by ear after image metrics had produced
> confident, wrong answers in *both* directions.
>
> Use the chromatic test when nobody can be at the camera. Do not use it when somebody can.

#### The chromatic test: green fraction, not R/B

If you must judge from a frame, **measure the green fraction**:

```
G / ((R + B) / 2)
```

**Not R/B.** IR floods red and blue roughly equally, so R/B barely moves and a real filter swap
looks like noise. Measured across the same transition:

| Metric | Filter in → out | Separation |
|---|---|---|
| R/B | 0.875 → 0.970 | **1.1×** — dismissible as noise |
| **Green fraction** | 1.06 → 0.445 | **2.4× — unmissable** |

Any earlier "chromatic" measurement in this project that used R/B was therefore **weak evidence
at best**, and a null from it means very little.

#### The bands, and the boundary that does not exist

Measured across several runs on 2026-08-06 (**JP's and the orchestrator's readings, not a single
sample**):

| Filter | Green fraction | Look |
|---|---|---|
| **IN** (normal colour) | **≥ 1.00** (observed 1.019 – 1.39) | normal |
| **OUT** (IR-pass) | **≤ 0.90** (observed 0.45 – 0.90) | magenta / pink cast |

> ⚠️ **Do not classify against a single boundary value, and specifically not `0.8`.** A run was
> judged with `0.8` as the in/out cut-off and **an entire test run was mislabelled** as a result —
> the reported bands do not sit either side of it, they sit either side of a **gap between 0.90
> and 1.00 that is itself narrower than the within-band spread.**
>
> ⚠️ **The IN band was published as 1.06–1.39 and was WRONG.** A *confirmed* filter-IN
> transition, cross-checked by eye, measured **1.019** — which that band would have scored as a
> MISS. That is the third false threshold this metric has produced (0.8 mislabelled a whole run;
> 1.06 would have rejected a correct result), and all three were set by picking a number from a
> previous session's scene rather than from a pair. **Judge direction from a pair, never altitude
> from a constant.** Compare a reading against the
> *bands*, and if it lands between them, the honest answer is **"this measurement does not say"**,
> not a coin flip.
>
> The safe form of the test is a **paired** one: take a reading, command the change, take another,
> and require the two to land in *different* bands. An absolute reading judged against a
> remembered number is how the mislabelling happened.

#### ⚠️ The chromatic test only works if the scene contains IR

**This is the failure mode that makes the metric untrustworthy indoors, and it is not a precision
problem — the signal is simply absent.** The green fraction moves because removing the filter lets
infrared reach the sensor. **Under blue-dominant indoor lighting there may be almost no IR in the
scene to admit**, so the filter can swing its full travel and produce **almost no colour change at
all**.

So a flat green fraction has **two** explanations, and the metric cannot separate them:

* the filter did not move, or
* the filter moved and there was no IR for it to gate.

**A null from this test is therefore not evidence of a null result** unless you have independently
established that the scene has IR in it — daylight, or an IR illuminator you can confirm is
actually emitting (**not this camera's**, whose [ring is dark](ptz.md#-ir-confirmed-dark)).

That is the whole reason the ear beats the eye here: **the click is unconditional.** It does not
care what is lighting the room.

> ⚠️ **Allow at least 10 seconds.** The filter transition takes **4–8 s** — nothing has happened
> at 4 s, and it is complete by 8 s. **Sampling at 2–4 s guarantees a false negative.** Ten
> seconds is the right rule, with margin.

> ⚠️ **Command a change, not a no-op.** Read the current state first. Commanding the filter *on*
> when it is already *on* and then measuring no change proves **nothing** — and this project has
> made that exact error twice, in both directions: once to conclude a working path was broken, and
> once to conclude a broken path worked. See
> [the daemon's IR-cut path](ptz.md#-retracted-ir-cut-control-through-the-daemon-is-broken).

Judge by the image, not the pin: the pin read is trustworthy, but the solenoid is downstream of
the pad, so a swinging pad does not prove the mechanism moved.

### Use `curl`, not `urllib`

The same server returns a **deterministic 502 to Python's `urllib`** while `curl` gets 200 every
time — verified curl → urllib → curl back to back on the same endpoint.

It also **truncates JPEGs mid-stream**. Validate the `FFD9` end-of-image marker before treating a
downloaded frame as complete; a truncated frame will still decode to *something* and quietly skew
whatever you measure from it.

### "Is this service up?" — the listener is authoritative, the process table is not

**Three people asked that question in one night and the process table lied to two of them,
in the same way, independently.**

The probe looks safe:

```sh
ps | grep -c "[t]elnetd"        # -> 2, on a camera with NO telnetd running
```

The `[t]` bracket trick stops `grep` matching its own `grep`. **It does nothing about the
shell whose command line contains the word.** Run over SSH, dropbear's `sh -c` appears in
the process table carrying your entire command string — so an `echo "telnetd procs: …"`
anywhere in the same command makes the probe count itself.

> 🔑 **The deeper reason it fooled people is `-c`. A count is a number with no way to show
> you it is wrong.** Printing the matching *lines* exposes the fault instantly — you see
> your own command staring back. The same parse printing lines instead of a count would
> have been self-diagnosing.

**Use the thing that cannot be fooled by the question you are asking:**

```sh
/sbin/netstat -ltn | grep ':23 '        # on the camera  (note: /sbin is NOT on ssh's PATH)
# or, better, from another host entirely:
timeout 3 bash -c 'exec 3<>/dev/tcp/<camera>/23'
```

An external port scan is authoritative because nothing about *how you asked* can appear in
the answer. This is the same family as the `ps` parse that
[counted regex matches rather than lines](backlog.md#improvement-backlog) — and it is worth
noticing that the fix is identical: **stop counting, start looking.**

> 🔑 **The general form, and the reason care does not fix it: the probe enters the
> population it is measuring.** `ps` enumerates processes, and asking the question *creates
> a process carrying the question's text*. No amount of attention prevents that — it is a
> property of the instrument, not a lapse by the operator. **Two people hit it
> independently within one hour on this camera**, one reading `2` and one reading `1`,
> neither warned by the other, both on a camera with zero matching processes.
>
> So prefer an instrument the question cannot contaminate. **An external port scan is the
> only one here that qualifies**: it runs on a different machine, so nothing about how you
> asked can reach the answer. Where you must ask on-box, print lines rather than counts —
> a contaminated line is visibly your own command; a contaminated count is just a number.
>
> The same shape shows up wherever the observer shares a namespace with the observed:
> `grep`-ing a log you are writing to, counting connections from the host making them,
> `ls`-ing a directory your own tooling populates.

### On a watchdog box, `dmesg` is volatile evidence

A GPIO sweep wedged the camera, and the **watchdog rebooted it — destroying the pre-hang `dmesg`
that would have contained the diagnostic printk.** The recovery erased the evidence for the
failure.

**Stream kernel output somewhere non-volatile before doing anything that might hang the box** —
to the SD card, or captured over [UART](hardware.md#serial-console).

### ⚠️ OPEN: unexplained reboots on cam2 — and why attribution comes before mechanism

On 2026-08-06/07, three unprompted reboots were reported on cam2 by two people: uptime
`1403 s` then `109 s` about thirteen minutes later, and separately a camera seen at `up 3 min`
going unreachable and returning at `up 0 min`. Nobody has explained them, and that is
recorded here rather than left in a chat log.

> 🔴 **Before hunting a mechanism, rule out each other.** In the same window, **one agent
> rebooted cam2 nine times** — eight deliberately, plus one automatic reboot from
> `gergehack.sh`'s card→flash sync — while testing boot persistence. Any observer scanning
> during that window would have recorded reboots that were entirely accounted for.
>
> This is *"verifying that a state changed is not verifying who changed it"* in its most
> expensive form: **a phantom hardware bug is the most costly kind of finding**, because it
> has no owner, no reproduction, and no way to be closed. **Correlate timestamps against
> everyone's command log first.** At least one of the three reports falls inside a known
> deliberate-reboot window.

**If reboots survive that check, the mechanism list is short but the evidence is hostile:**

- **There is an 8-second hardware watchdog** — `[watchdog_enable:228] watchdog timeout = 8(s)`
  in the UART logs. **Any hang longer than 8 s reboots the box**, so "unexplained reboot" has
  a very large suspect set and tells you almost nothing on its own.
- **`gergehack.sh` reboots deliberately, twice** (lines 62 and 70), whenever the card's
  `gergesettings.txt` or `gergehack.sh` differs from the flash copy. **Anything that makes
  those differ on every boot is a reboot on every boot.** Editing either file is therefore
  expected to cost one extra reboot — that one is not a fault.
- **`update_factory_data.sh` reboots** when the sensor file "differs from current".

**And the reboot destroys the evidence**, per the section above. So the first useful step is
not a theory, it is **making the next reboot leave a trace**: a boot counter and timestamp
appended to a file on `/data` (which survives reboots and card swaps) on every boot, so the
*next* occurrence arrives with a before-and-after instead of a shrug.

> **The cause of that wedge is undetermined.** It was initially attributed to a pin being a
> reserved SPI/SD line; **that attribution has been withdrawn** — the disassembly shows a
> `cmp r0, #49` guarding a printk, but the string it loads is
> `"Error, gpio %d isn't config outpu level"`, which is about the *value*, not the pin. The two
> cannot be reconciled, and no theory is being built on it. Logged as unexplained.

## Working *on* the camera: five silent no-ops

These are traps in the tooling rather than the device — hit while patching binaries over telnet.
**All five fail silently**, which is this camera's signature.

> **The rule that covers all of them: re-verify by md5. Never trust an exit code.** On this
> device an exit code, an HTTP 200 and a `DrwAck` all mean *the request was parsed*, not that it
> was honoured.

| Trap | What happens | Do this instead |
|---|---|---|
| **`dd: Text file busy`** | You cannot write a running binary. | Patch a **copy** and swap it in, so the risky write never touches a live file. |
| **~255-byte input truncation** | A tty in canonical mode (`N_TTY MAX_CANON`) **silently truncates** long lines. Joining commands with `"; "` into one line hits this fast. | Chunk long transfers — one patch was moved as **15 base64 chunks**. |
| **Trailing `&` in a `;`-joined list** | A syntax error, not a background job. | Wrap it: `( … & )`. |
| **busybox `mv` prompts on overwrite** | And **the prompt eats the *next* command** as its answer — so the `mv` silently declines *and* the following `sync` vanishes. | `mv -f`. |
| **`cp -f` still prompts** | Even though `mv -f` does not. | `cat src > dest`, which cannot prompt. |

The middle three compound: a long `;`-joined line gets truncated, the truncation lands mid-`mv`,
the prompt swallows the next command, and nothing reports an error.

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

### ✅ Resolved: the mirror SSID is permanent, and this camera moved off it

This section used to leave a choice open — keep the mirror SSID, or point `gergesettings.txt` at
the main network and drop it. **Both, as it turns out, and the split is deliberate:**

* **This camera was migrated to its own SSID.** One edit to `gergesettings.txt` on the **card**,
  and [the self-heal](sd-card.md#the-wifi-credentials-self-heal-from-gergesettingstxt-on-every-boot)
  propagates it into the vendor config at the next boot. Verified back on the network in ~40 s.
* **The mirror SSID stays broadcasting indefinitely**, because *other* cameras on that VLAN
  depend on it and cannot be moved as cheaply.

> ⚠️ **Do not "finish the migration" by retiring the mirror SSID.** That is the tidy-looking action
> and it is the wrong one. Cameras of other makes on that VLAN join by that SSID, and at least one
> family of them can only be re-provisioned from **its own setup access point** — meaning a
> physical visit per unit, not a config change.
>
> **The cost of an SSID retirement is not paid by the device you are thinking about.** Enumerate
> what joins by a name before removing the name; a leftover-looking SSID is often load-bearing for
> something you are not currently working on.

> 🔑 **Why the migration was one edit rather than a fleet operation, and why that is not general.**
> This camera's credentials live in a plain-text file on removable media, so changing them is a
> file edit on a card you are already holding. Devices whose provisioning is a *protocol* rather
> than a *file* are far more expensive to move — and on some of them the only mechanism to apply
> a change is also the only mechanism that reveals it failed. **Cheap to re-provision is a
> property of the device, not of the network change.**

### 🔑 Name the VLAN by its tag, never by a nickname

**One VLAN answers to a different name at every layer**, and using any of those names in prose
produces ambiguity that has already cost time here:

| Layer | What it is called |
|---|---|
| Router interface | e.g. `network.lan` (`br-lan.20`) — **often *not* named after its purpose** |
| Router firewall zone | e.g. `cameras` |
| Access-point interface | e.g. `network.cams` |
| SSID the devices join by | e.g. `my-iot-ssid` |

Four names, one broadcast domain, and **none of them is reliably the one your colleague means.**

> ⚠️ **The specific trap: an SSID named after IoT, on a VLAN that is not the IoT VLAN.** "The IoT
> network" then means either the actual IoT VLAN or the camera VLAN reached through that SSID —
> and they are different networks with different security postures. **Say "VLAN 20" and the
> ambiguity disappears**; say "the IoT network" and a reader has to guess.
>
> Note also that a router interface called `lan` may carry an isolated camera VLAN. **Renaming it
> is riskier than living with it** — repointing a firewall zone can silently stop a default-deny
> rule applying, which fails open and is invisible until something reaches the internet. Document
> the mismatch; do not "tidy" it.

**Convention in these docs: refer to the VLAN by tag.** "The camera VLAN" is acceptable where the
security property is the point; a bare nickname like "the cams VLAN" is not, because it matches
nothing you could grep for in any config.

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

Observed three times in one session. **Suspect the integration before the hardware** — a
single-session-token bug in HA produced exactly this symptom at the same time, and being
intermittent it fits an intermittent report, so the filter may never have moved. Both
explanations are in [ptz.md](ptz.md#-the-filter-has-been-seen-to-read-back-off--cause-unknown).

### The clock — NTP works; the timezone was 15 hours wrong on every service

**The clock syncs.** This page previously said it was stuck at 1969 with NTP firewalled; that was
true only while `time_source` still pointed at the *old* IoT VLAN router, unreachable after the
camera moved. It was fixed during the move and these docs did not catch up.

Verified on the running camera: `ntpd -n -N -p <router>` is alive, both copies of
`gergesettings.txt` point at the camera-VLAN router, and after ~12 hours of uptime on a box with
**no RTC battery** the clock matched the workstation to the second. It could only be right by
having synced.

The hardware fact still holds and is why `time_source` matters at all: there is a 32.768 kHz RTC
but **no battery**, so every boot starts at the epoch and the camera depends entirely on NTP.

#### ⚠️ The `time_zone` setting was wrong by 15 hours, and `date` in a shell hid it

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

**And `date` at a telnet prompt showed the correct time throughout**, which is the part worth
dwelling on. Reading `TZ` out of `/proc/<pid>/environ` for every running process:

```
  457  ptz_daemon_dyn     TZ=GMT-08:00      <-- 15 hours wrong
  496  app_restarter.s    TZ=GMT-08:00      <-- 15 hours wrong
 6847  run_libre_anyka    TZ=GMT-08:00      <-- 15 hours wrong
 6852  libre_anyka_app    TZ=GMT-08:00      <-- the RTSP server. 15 hours wrong.
       telnet shell       TZ=GMT+07:00      <-- correct, and the only one
```

> ⚠️ **Every process that does real work was 15 hours out. The single process holding the
> correct value was the login shell — exactly where a human checks the clock and concludes
> everything is fine.**
>
> Anyone debugging timestamps on recorded video, on files written by `libre_anyka_app`, or in
> ptz-daemon logs would have been chasing a phantom, with `date` cheerfully confirming the clock
> was right. If you take one thing from this section: **on this camera, `date` in your shell is
> not evidence about any other process.** Check `/proc/<pid>/environ`.

#### Two process trees, not two competing values

The obvious worry is that `/etc/jffs2/time_zone.sh` (which holds `export TZ=GMT+07:00`) fights
`gergehack.sh`'s `export TZ=$time_zone`, and that one of them "wins" at boot. **It does not work
that way, and the `/proc` readout above settles it without a reboot.**

`TZ` is inherited per process. `gergehack.sh` exports it into everything *it* launches —
`ptz_daemon`, `libre_anyka_app`, `app_restarter`. `time_zone.sh` reaches only its own tree, which
is `telnetd`, and therefore your shell. **Neither overrides the other; which value a process sees
depends only on which tree started it.**

So `time_zone.sh` never protected anything that mattered. The "correct value frozen in place by
the firewall" was only ever freezing it for interactive logins.

That file is still left alone deliberately — it is the file the telnet exploit hooks, and
breaking it would risk the hack's entry path for no real gain. Per upstream's
[`hack-process.md`](../reference/hack-process.md), it is also overwritten whenever the vendor app
syncs time with the cloud, which this camera cannot reach.

> **Evidence classes, since they differ here.** The per-process `TZ` values, both
> `gergesettings.txt` copies, the running `ntpd`, the matching clocks, and the test output below
> are **directly observed**. That `anyka_ipc.sh` sources `time_zone.sh`, and that the vendor app
> rewrites it, come from **upstream's write-up** — though the shell being the one process holding
> `GMT+07:00` is consistent with it.

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

> ⚠️ **Applied, but not yet active.** `gergehack.sh` reads `gergesettings.txt` only at boot, so
> the running processes still carry `TZ=GMT-08:00` and will until the camera restarts. The `date`
> output above was produced by setting `TZ` inline in a shell — it proves the *string* works on
> this libc, not that the services have picked it up. Confirm with `/proc/<pid>/environ` after
> the next reboot, not with `date`.

#### What is left over, once the fix is active

The two trees still disagree, but the disagreement inverts and shrinks dramatically:

| | Before | After next boot |
|---|---|---|
| Services (`libre_anyka_app`, `ptz_daemon`, …) | `GMT-08:00` — **15 h wrong** | `PST8PDT,M3.2.0,M11.1.0` — correct, DST-aware |
| Telnet shell | `GMT+07:00` — correct | `GMT+07:00` — correct until November, then 1 h out |

So the residual error moves off the services and onto the interactive shell, and shrinks from 15
hours to at most one. If you notice `date` disagreeing with a service timestamp by an hour after
the November transition, that is this — not a fault. Do not go hunting.

None of this affects Home Assistant, which timestamps its own frames. It affects the camera's own
logs and any filename it generates.

### The WebRTC integration is disabled

`custom:webrtc-camera` cards render as "Custom element doesn't exist". `go2rtc` is still
enabled. See [home-assistant.md](home-assistant.md).

### The microphone cannot be muted

Not a bug, a hardware fact. [ptz.md](ptz.md#-the-microphone-cannot-be-muted).

### FTP is on by default and is writable

**`run_ftp=1` does not start FTP — the stock `rc.local` does, on every boot, hacked or not.**
`run_ftp=0` **kills** it (`gergehack.sh:89`), and **only at the next boot**, since `gergehack.sh`
runs once — so set it and reboot; checking immediately looks like the setting is broken.
Anonymous is rejected, but root with the root
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
