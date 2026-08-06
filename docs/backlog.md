# Improvement backlog

Live queue for this camera. Ordered by value per unit of risk, not by how
interesting the problem is.

**Rules that earned their place** (2026-08-06, the day most of this was found):

- **Read the artifact before measuring the device.** Every conclusion drawn from
  disassembly, source or `/proc` held. Nearly every conclusion drawn from an
  unvalidated measurement was overturned.
- **This firmware narrates itself.** Twice the answer was a log line nobody had
  read — `[ak_drv_ir_set_ircut:229] not inited` and `## ASLC OPEN OK ena:1`.
  Run the binary in the foreground and read its output before inferring anything.
- **Establish what depends on a fault before repairing it.** Three separate bugs
  turned out to be the only reason something worked.
- **Verify the effect, not the invocation.** A `200`, an exit code and a
  `DrwAck` all mean *parsed*, not *honoured*.
- **Prefer the SD card to the squashfs root.** Card edits are recoverable by
  pulling the card. Root edits are not.
- **When you learn something, grep for every place that says otherwise.** A doc
  gets edited where the new fact lands, not where the old one lives — so it ends
  up carrying a claim and its own refutation, paragraphs apart, both reading
  authoritative. Three instances in one day: `troubleshooting.md` stating a
  green-fraction IN band of 1.06–1.39 while `ptz.md` recorded two confirmed IN
  readings that band scores as misses; a `SPK_PA must be high before each run`
  precondition that is 0 before *every* run by design, because the player raises
  it itself; and `usr-sbin/README.md` calling `/sbin/updater` "not yet analysed"
  four paragraphs above the section analysing it. **The stale half is the
  dangerous half**, because it reads like the checked one.

  **A fourth instance closed the distance to two lines**, and that is the part
  worth keeping. `identity.md` claimed *"a raw seed caps at 32 distinct names
  however many cameras you own"* directly beneath a table whose own
  `random MACs | 256 | 229` row disproves it. Nobody spotted it — not the
  author, not two reviewers — until an adversarial read went looking. So
  **proximity is not protection**: a refutation one line away is no more likely
  to be noticed than one in another file, because nobody re-reads the paragraph
  they just wrote. The measured table was right and the sentence summarising it
  was wrong, which is the usual direction — **prose drifts, data doesn't.**
  Trust the table; re-derive the sentence.

  (True version, for the record: the cap is **per aligned 256-wide MAC window**,
  because the noun index is bits 8–12 and those are constant inside one. It is
  not a global ceiling.)

  **The same failure also runs at FILE scale, and that is why the rule above did
  not catch it.** An audit on 2026-08-06 found five live contradictions with one
  shared cause: **today's findings landed in this backlog, and the reference docs
  were never revisited.** The volume ladder, the ASLC result, the OTA analysis and
  the identity rationale were all correct *here* while `ptz.md`, `web-ui.md`,
  `home-assistant.md` and `hardware.md` still said what they said that morning.

  The existing rule says to grep for contradictions when you learn something — and
  it failed because the sweep looks *near* the new fact, and the contradiction was
  in a different file with a different reader. **Nobody greps their own working
  notes.**

  > **The backlog is what we read. The reference docs are what a stranger reads.**
  > A doc set can be **collectively correct and individually misleading**, and the
  > stranger gets the wrong answer every time.

  So: **when a finding lands here, it is not documented — it is queued.** Landing
  it means editing the page a stranger would open.

- **When a file contains both a table and a summary sentence, re-derive the
  sentence.** Three of the four worst rows in that audit were a table refuting its
  own prose — the `identity.md` cap above, `hardware.md` calling `/etc/jffs2` "the
  only writable place that persists to flash" one line above a mount table listing
  `/data` as `jffs2 rw`, and a green-fraction band contradicted by the readings
  beside it. At that frequency it is not bad luck, it is **the dominant mode**.
  Tables are usually dumps — measured. Summaries are usually unsourced and drift.

- **A sweep built from what you expect to find will miss what you didn't expect to
  be there.** A real address survived four separate scrubs on 2026-08-06 because
  every sweep was assembled from a mental model of where addresses live, and the
  file was a new directory added mid-session. It was caught by a mechanical pass
  that **extracted every token of an identifier shape and printed the distinct
  values to classify**, rather than grepping for known-bad ones.
  **Enumerate from the artifact, not from memory.** Second instance the same day:
  "there are two paths to the speaker" when there were eight.

  Corollary that falls out of it: **sort such a list by frequency and read the
  bottom first.** A value appearing once is the one no convention covers.

- **A fix whose evidence is an *absence* needs a way to observe the behaviour** —
  or the next person re-reports the bug. (Anyka volume, 2026-08-06; cost a false
  *"still broken"* verdict within the hour.) Two halves:

  **(a) Duplicated correct implementations are camouflage for the missing one.**
  Two call sites handled volume and one did not — an asymmetry a reader could
  spot. Centralising removed the bug *and* the only visible clue it had ever
  existed.

  **(b) Ship an observation with it.** `anyka_http.py level` answers *"is it
  wired up?"* in one command, where a code read cannot. **Put the reason in the
  new code's comment**, or someone deletes it as redundant.

  Applies to any invisible-by-design fix: a removed workaround, a defaulted config
  key, an inherited behaviour. **If the diff is mostly deletions, ask what a
  reviewer is meant to point at — and if the answer is "nothing", build the thing
  they can.**

  > **The compounding is the part that generalises.** After centralising, all three
  > call sites look identical, so **the correct state and the defect are
  > byte-identical from a code read** — only behaviour distinguishes them. The
  > false verdict came from checking for the *old shape* and finding none. That is
  > the same failure as ["proximity is not protection"](#improvement-backlog) seen
  > from the reviewer's side: **the reader is looking where the evidence used to
  > be, and a good fix is precisely what moves it.**
- **A uniform result across varied inputs means a broken instrument, not a
  conclusion.** Six different `&level=` values that all report the same thing are
  telling you about your *test*, not the system. Seen four times today: a `ps`
  parse that showed all six volume variants as the same binary; six snapshot
  frames returning luma `130.47` to two decimals because the server was serving
  one cached frame; `ctl` returning `OK` for every command whether honoured or
  not; and `camera_set_ircut` hardcoding `return 0`. **Before believing a null or
  a uniform result, feed the instrument an input you already know differs** — if
  it cannot tell those apart, it cannot tell anything apart.
  **Two of those four are in vendor code, and that is why they survived for
  years**: the reporting layer and the thing being reported were written by the
  same people, so nothing in the system ever disagreed with itself. A firmware
  that always says `OK` is internally consistent and externally useless. Expect
  the vendor's own success signals to be decorative until proven otherwise.
- **A repo copy and the deployed file are two different things.** The repo `ctl`
  had eight comment lines the camera's copy did not. Editing the device copy and
  committing it would have silently deleted them. Diff before you overwrite, and
  make the two hash the same afterwards.
- **`git commit -o` stops you carrying someone else's work. Nothing stops them
  carrying yours.** Everyone guards the first direction and nobody guards the
  second. It happened here on 2026-08-06: a one-line phrasing fix sat
  uncommitted in `write-sd-card.sh` while a sibling committed that same file,
  and the fix shipped under a message about the speaker volume ladder, which
  never mentions it. Nothing broke — the content was correct and landed on
  `main` — but the change is now attributed to work it has nothing to do with,
  and no amount of `-o` discipline on the *author's* side would have prevented
  it. **The only defence available is committing promptly**, which is why "a
  partial commit that unblocks a sibling beats a complete one that holds the
  file" is an engineering rule and not just courtesy. Corollary: git authorship
  cannot distinguish who did what here — every commit is `jp <jp@jphein.com>` —
  so the commit *message* is the only provenance record, and a message that
  silently covers two people's work has lost it.

---

## The goal: this is a platform, not one repaired camera

JP has **a bag of these**. So the unit of work is *a fleet that comes up correct
and stays that way*, not *this camera made to behave*. That reorders everything
below — a fix that only exists on one running device is worth roughly nothing.

**The test for any change: would a camera taken out of the bag today get it?**

Three consequences worth holding onto:

- **Nothing counts until it is in `tools/write-sd-card.sh`.** Two fixes have
  already nearly been lost by living only on the live card — the boot-time IR-cut
  line (which was never in the backup, so no written card ever had it) and the
  `gergesettings` timezone. Both were caught by luck.
- **The card is the deployment mechanism.** Fixes belong on removable media, not
  the squashfs root: recoverable by pulling the card, survivable when wrong, and
  the same artefact for every unit.
- **Per-unit config must be a parameter, not a default.** `--ssid` is now
  required precisely because a wrong default strands a camera with no network and
  no console. Anything else that varies per camera — SSID, `time_source`,
  hostname — needs the same treatment before the fleet grows.

### Platform gaps, in priority order

1. **A camera has no identity — DONE, see [identity.md](identity.md).** Both
   halves of the split now ship in `tools/write-sd-card.sh`:

   | | Unit | Build |
   |---|---|---|
   | Lives in | `/data/unit.json` (`mtd7`) | `/anyka_hack/build.json` (the card) |
   | Written by | `name-unit.sh`, once, at first boot | the writer, at card-write time |
   | Realm | `fleet` (identity) | `forge` (provenance) |
   | On a card swap | stays with the camera | follows the card |

   A camera out of the bag names itself from its own MAC — no registry, no
   configuration, nothing to keep in sync. `--unit-name` overrides it for a
   camera JP wants to name himself. Read it back with
   `/mnt/anyka_hack/identity/whoami.sh`.

   ⚠️ **Do not move the unit marker to `/etc/jffs2`** — an earlier version of
   this item recommended exactly that, and it was wrong. `/etc/jffs2` is `mtd6`,
   slot **`C`** of the stock updater: any firmware update carrying a `usr.jffs2`
   overwrites the whole partition.

   **What softens that failure, and only here:** the name is *derived* from the
   MAC, so it is idempotent — a wiped marker re-derives the **same** name on the
   next boot. A wipe costs a boot, not an identity. That does **not** hold for
   `--unit-name`; an override is not derivable and a wiped one is gone. Which is
   the argument for leaving cameras self-named unless there is a real reason.

   Two limits worth carrying forward rather than rediscovering:

   - It is a strong spread, **not** a uniqueness proof. `Adjective Noun` draws
     from 1024 combinations and can repeat; the full `Adj Noun · <mac6>` does not
     while MACs are unique. **Never use the bare noun as an identifier.**
   - The word tables are **pinned** (`tools/identity/PINNED.md`). Counts are the
     modulus, so a word added upstream renames every camera. `fleet` is
     size-locked at 32 × 32 by design, which is why it was chosen over `fantasy`.

   Nothing here has run on a camera yet — the device was owned by another agent.
   Watch the boot console for `identity:` lines on the first unit to take a card.
2. **No inventory.** Nothing enumerates which cameras exist, what card each is
   running, or which are behind. On one camera that is fine; on ten it is the
   whole problem. Note there are **three** distinct version-ish facts, and an
   inventory reporting one field called "version" will be wrong about two of
   them: the vendor's `fw_version` (what the flash contains), the card build
   stamp (which commit of this repo wrote the SD card), and the unit identity.
3. **An upgrade path exists — it was never missing, just unread.** This item
   previously said a fix meant writing a new card and physically swapping it.
   That was too pessimistic. `/usr/sbin/update.sh` is a complete self-contained
   updater with **two** entry points, no cloud and no account:

   | mode | trigger | version gate |
   |---|---|---|
   | TF (SD card) | `/mnt/update/update.tar` | `tar_ver != dev_ver` — any change, **including downgrade** |
   | OTA (network) | `/tmp/update.tar` | `tar_ver > dev_ver` — newer only, **but see below** |

   So the task is *packaging for the mechanism that is there*, not designing one.
   Be accurate about the risk: in-place, non-atomic, **no A/B slots, no
   rollback**, and the watchdog is deliberately killed before flashing — safe to
   let finish, dangerous to interrupt. Verification is md5 **only when the
   `.md5` is present** (the check is inside an `if [ -e ]`), and the hash ships
   inside the artefact it verifies: integrity against corruption, not
   authenticity.

   ### 🔴 Two rules that are not optional

   **Never put `usr.jffs2` in a tarball aimed at a hacked camera.** Slot `C` is
   `/etc/jffs2`, and `C=` is a whole-partition erase (`erase_info.start = 0`,
   `length = mtd_info.size`). That partition holds **the entire hack**:
   `time_zone.sh` (the exploit entry point that launches telnet),
   `gergehack.sh`, `gergedaemeon.sh`, `shadow`/`passwd` symlinked to `/etc`
   (the root login), `webui.hash`, `gergesettings.txt` — **and `anyka_cfg.ini`,
   which holds the WiFi SSID and password.**

   So one write costs telnet, the hack, both passwords *and the network
   config*. **A remote flash including slot C is a remote strand**, recoverable
   only by pulling the card or attaching UART. A camera that has lost its SSID
   is this project's signature disaster — it is why `--ssid` is a required
   argument — and it presents as a unit that is simply *gone*: no association,
   no auth failure, no console. The tarball format makes including it the easy
   mistake.

   (Related, smaller: `update_ispconfig()` runs `rm -rf /etc/jffs2/isp*.conf`
   unconditionally on **every** update, even a kernel-only one. And
   `update_factory_data.sh`'s `update_audio_file()` runs
   `rm -rf /data/audio_file/*` — so `/data` survives an update but that
   subdirectory does not.)

   **Do not trust the "newer only" gate.** Line 277 is
   `[ "$tar_ver" \> "$dev_ver" ]` — a **string** compare. Tested in `sh`, `dash`
   and `busybox sh` (the real interpreter) against the installed
   `6.0.24.10_202401091113`:

   ```
   6.0.24.9  > 6.0.24.10 : TRUE    <- a downgrade PASSES the newer-only gate
   6.0.24.10 > 6.0.9.1   : FALSE   <- .24 reads as older than .9
   same prefix, later timestamp : TRUE (correct)
   ```

   It sorts correctly within an identical prefix and inverts when a component
   crosses a digit-width boundary — **and the installed version is already past
   one.** A gate that is right most of the time and silently wrong at the
   boundary is worse than no gate, because it reads as a safety net.

   **Consequence: version comparison belongs to us, not to the device.** The
   enumerator deliberately does *not* order vendor versions — it reports them
   verbatim and flags **divergence across the fleet**. "All report X, cam3
   reports Y" is actionable, needs no ordering, and cannot be wrong. Ordering
   only becomes meaningful once a declared target firmware exists, and there
   isn't one; do not invent one to make a column sortable.

   ### What this does to gaps 1 and 2

   A remote update mechanism with no identity and no inventory is how you brick
   a fleet one camera at a time. **Inventory stopped being a report and became a
   safety interlock** — the thing standing between a correct flash and flashing
   the wrong unit.

   Note the direction, because it inverts the usual argument: *"we can fix it
   remotely"* normally justifies **less** ceremony. Here it justifies **more**,
   because the only thing that previously forced you to identify the right
   camera — physically standing in front of it — has been removed. You can now
   strand a camera from your desk, in one command, with nothing in the way.
4. **Kernel-build variance is real and unmapped.** Two builds already seen —
   2022 `zhoujiahui` (prefixed `gpio-ircut_a`) and 2023 `chensheng` (`ircut_a`
   plus `ircut_b`). The writer detects by node name on every boot, which is right,
   but nobody has surveyed what the bag actually contains.

---

## 1. Day/night switching — TABLED, see issue #2

Filed rather than built. The camera genuinely cannot do it (`gpio-rf_feed`
absent, fallback ADC constant at 2999), and the HA-side implementation is
straightforward but not urgent.

## 2. Speaker volume — ✅ SOLVED 2026-08-06, shipped in `df16c66`

**`ctl` now takes an optional `&level=1..6`** (DAC device volume 0–5), default **4**,
falling back to the default binary on absent/malformed/out-of-range input and to the
stock `/usr/bin` player if a card variant is missing. Six one-byte variants live at
`/mnt/anyka_hack/ak_adec_demo/ak_adec_demo.vol1..6`, the original is kept as `.orig`,
and `/usr/bin` is untouched.

**ASLC was never disabled and never needed to be.** The DAC value goes out via ioctl,
which is *downstream* of the compressor — measured: device volume moved 5 → 1 while
every ASLC parameter stayed byte-identical (`ena:1`, `aslc volume 6`), and JP confirmed
the A/B/A/B alternation audibly. That is also why upstream's pre-attenuate-the-file
workaround cannot work: the file is *upstream* of ASLC.

The `strb → NOP` patch that would have disabled ASLC was **never applied** — its proof
chain (demo struct offset +44 → `filterObj[0xa8]`) was never closed, and it turned out
to be unnecessary. Do not apply it.

**Superseded — "only 6, 4 and 2 have been listened to" is out of date.** JP exercised
the HA slider **across its range** on 2026-08-06 — *"all the volumes worked well on the
ha slider then the speak button"* — corroborated by where the entity was found
afterwards: left at 4, discovered at 1, so he moved **down through** the ladder.

**But "verified" is per path, not global**, and `luna-volume`'s record keeps them apart
because they do not all resolve their level the same way:

| Path | Status |
|---|---|
| `media_player` (passes its own level) | ✅ **verified**, slider exercised across range. Unchanged by the centralisation, so the test still applies |
| **Alive** button (`play`, level *resolved*) | ✅ **verified at both ends** — *"alive works at 1 and 6, volume changes"*. This is the path JP reported broken |
| **Chime** button | ⚪ **by construction, not by test** — same script, same `shell_command`, different `clip`. *"Both buttons verified"* would be one press stronger than the evidence |
| **Speak** button (`say`) | ⚠️ **verified *before* its mechanism changed** — it carried a Jinja template when JP tested it; the centralisation deleted that and moved resolution into `ctl_file()`. Re-verified by stub only, **not by ear** |

> ⚠️ **The Speak row is a real open thread, not a formality.** Risk is low — it now uses
> the same resolver Alive proves — but **it is not the same claim**, and *"it follows
> mechanically"* is exactly the reasoning that produced five wrong path counts in one day.
> It is also a textbook case of the rule above: **the centralisation deleted the mechanism
> the verification was performed against**, so the evidence no longer points at the code
> that runs.

**Still not established:** that the ladder is **evenly graded**, or that **adjacent rungs
are distinguishable** — nobody has tried 3 against 4, and the codec's gain table in the
kernel DAC driver is unread. It could be linear, logarithmic, or bunched at one end.

> 🔑 **"All six work" is not "six perceptually distinct steps".** What is established:
> every rung produces audible output — **rung 1 included, so the bottom of the slider is
> quiet rather than silent** — and the paths honour the entity. **Two rungs at opposite
> ends is not a ladder measurement:** 1-vs-6 says the control *moves*, not that it has
> *steps*.
>
> One separate thing the rung-2 pass did settle: *"audible much softer"* rules out an
> **inverted** mapping, which no off-device test can — those prove the slider maps
> consistently, not the right way round.
>
> **That one-clause upgrade — "all six work" → "six distinct steps" — is the same shape as
> every retraction in this file, except it runs on good news.** Good news outruns its
> evidence just as easily as bad news, and **meets far less resistance doing it.**

The original analysis follows, kept because the reasoning is what made the fix findable.

Automatic Sound Level Control is enabled (`## ASLC OPEN OK ena:1`), so a 10.3 dB
difference measured *in the file on the card* is inaudible coming out. Confirmed:
identical text rendered at gain 0.307 and 1.0 measures −26.7 dB and −16.4 dB mean.

`ak_adec_demo` imports `ak_ao_set_aslc_volume`, `ak_ao_set_dac_volume` and
`ak_ao_enable_eq`, and hardcodes them — usage takes only rate, channels, type and
path. In `main` at `0xa484`, both are `mov r1, #6` immediates: DAC volume 6, ASLC
volume 6, against a range of 0–6. **There is a volume control; it is pinned at
maximum and never exposed on the command line.**

Upstream found the symptom and stopped there. The card's own
`anyka_hack/ak_adec_demo/README.md` says *"it is waaayyyy too loud (this is
probably because volume control fails when running) … so I recommend lowering the
volume of the mp3 file"*. That workaround is self-defeating: attenuating the file
just gives ASLC more headroom to normalise back up, which is exactly the effect
measured here (−26.7 dB vs −16.4 dB in the file, inaudible out of the speaker).

**Patch the card's copy, not `/usr/bin`.** `/mnt/anyka_hack/ak_adec_demo/ak_adec_demo`
is byte-identical to the squashfs original (`21a59c852dfb7af2fbaebd0994e24570`) and
already ships with the hack, so it is the natural seam: recoverable by pulling the
card, and it belongs in `tools/write-sd-card.sh` rather than on one live device.
Each level is a one-byte change (`e3a01006` → `e3a0100N`); invoke by absolute path.

*Refuted:* PATH shadowing. `ctl` does call `ak_adec_demo` by bare name, but every
directory on `PATH` is squashfs, so there is nowhere to put the shadowing binary.

## 3. Watchdog catches death, not hangs

It greps `top` for the process name. The camera's characteristic failure is
**silence with the process alive** — port 3000 stopped listening while
`libre_anyka_app` was still running and RTSP still answering. A liveness probe
that made a real HTTP request would catch what the name check cannot.

## 4. Post-auth hardening in the web UI

Lower priority *because post-auth on this UI already means root by design* — the
`system` CGI exists to run privileged commands. Still worth doing:

- `del_video.sh` interpolates `$file` unquoted into `mv`; `.h264`/`.mp4` is
  appended, so traversal is constrained to relocating files with those suffixes
- the same `$file` is echoed into HTML unescaped (reflected XSS)
- `settings_submit.sh` still has `eval 'echo $'$parameter`, fed from
  `gergesettings.txt` — trusted-ish, hence the low ranking

The pre-auth RCE in `cgi-bin/header` is **already fixed** — do not reopen it, and
do not "tidy" the lowercase-only key filter without re-running the live exploit
payloads. The md5 recorded in the writer is what was actually verified.

## 5. A stop command for audio

Playback is `setsid ak_adec_demo`, fire-and-forget. Nothing can interrupt a clip,
which blocks a real media_player `stop`, and makes streaming seams unfixable.
A `ctl` verb that kills the decoder would close several things at once.

## 6. Streaming / radio

Groundwork exists in `anyka_http.py radio` — chunked fetch, transcode, upload,
play, repeat, with alternating filenames so a playing file is never overwritten.
The seam is the upload (~1 s per chunk). Blocked on (5) for clean stopping.

## 7. The two-timezone wart

`/etc/jffs2/time_zone.sh` exports its own `TZ` for the vendor app's process tree
while `gergehack.sh` exports `$time_zone` for everything it launches. Left alone
deliberately: that file is what the telnet exploit hooks. After November's DST
change expect up to an hour's disagreement between the web UI and the ptz daemon.
Cosmetic; documented so nobody hunts it.

---

## 8. Repo and device can drift, and `write-sd-card.sh` assumes they don't

**Observed, not hypothetical.** The repo's `reference/sd-card-original/web_interface/ctl`
(`17810bd0…`) carried eight comment lines about the ircut direct-write that the
*deployed* copy on the camera (`2b85f044…`) did not. Editing the device copy and
committing it would have silently deleted that comment block — a documentation loss
with no diff conflict to warn anyone. Caught by diffing before overwriting; the change
was merged onto the repo version instead and the device re-flashed from it, so both now
hash `81237ee7…`.

Best guess is the repo copy was edited for comments after the device was last flashed
and never re-deployed — **a guess, not established.** Worth one look, low priority.

**The generalisation is the part that matters:** `tools/write-sd-card.sh` carries md5
constants that assume repo and device agree. If they can drift for `ctl` they can drift
elsewhere, and the writer's gates would then be checking against a stale expectation —
passing while installing something nobody reviewed. Worth an audit of every hardcoded
md5 in that script once the card work settles.

Cheap mitigation if an audit is too much: have the writer *report* the md5 of what it
installed rather than only asserting a constant, so a drift shows up in the output
instead of being silently absorbed.

## Closed — do not reopen

| | |
|---|---|
| White LEDs | Not wired on this PTZ board variant. Vendor firmware says so itself: `onf_shaking_head_cam not support white led`. Expander refuted (nothing answers at 0x58), pin config refuted, share-pin mux refuted with a control. |
| IR LED ring | Dark. Confirmed by JP with a phone whose IR sensitivity is independently established. |
| `gpio-rf_feed` | No counterpart exists. **Do not point it at another name** — that converts a clean `ENOENT` into a silent wrong-pin write, which is strictly worse. |
| Daemon IR-cut path | Every route dies at the same `ak_drv_ir_init` check: `ptz_daemon`, `libre_anyka_app`, and the vendor's own `ak_drv_ir_demo`. One bug, three binaries, six library builds. `ctl` bypasses it with a direct pin write. |
| `libplat_drv.so` rename | **Regression.** Renaming `gpio-ircut_b` flips init into two-line mode, which pulses 10 ms and releases both pins — parking the filter out permanently. Renaming `ircut_a` alone would land in write-and-hold, but the direct write in `ctl` is simpler and already proven. |
