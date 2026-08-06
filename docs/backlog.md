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

1. **A camera has no identity.** Every card is the same card. There is no
   per-unit name, no way to tell from the device which build it is running, and
   the DHCP reservation is the only thing distinguishing them.

   ⚠️ **Do not put the unit marker in `/etc/jffs2`** — an earlier version of this
   item recommended exactly that, and it was wrong. `/etc/jffs2` is `mtd6`, which
   is slot **`C`** of the stock updater: any firmware update carrying a
   `usr.jffs2` overwrites the whole partition. Every camera would lose its
   identity and silently re-derive a *new* one — no error, no fault, just a fleet
   of strangers. Use **`/data`** (`mtd7`), which `update.sh` does not write.

   The durable split: **unit identity belongs to the camera** (`/data`, survives
   updates and card swaps); **build identity belongs to the card** (written at
   card-write time, travels with the artefact).
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
   | OTA (network) | `/tmp/update.tar` | `tar_ver > dev_ver` — newer only |

   So the task is *packaging for the mechanism that is there*, not designing one.
   Be accurate about the risk: in-place, non-atomic, **no A/B slots, no
   rollback**, and the watchdog is deliberately killed before flashing — safe to
   let finish, dangerous to interrupt. Verification is md5 **only when the
   `.md5` is present** (the check is inside an `if [ -e ]`), and the hash ships
   inside the artefact it verifies: integrity against corruption, not
   authenticity.

   This is what makes gaps 1 and 2 urgent rather than tidy. A remote update
   mechanism with no identity and no inventory is how you brick a fleet one
   camera at a time.
4. **Kernel-build variance is real and unmapped.** Two builds already seen —
   2022 `zhoujiahui` (prefixed `gpio-ircut_a`) and 2023 `chensheng` (`ircut_a`
   plus `ircut_b`). The writer detects by node name on every boot, which is right,
   but nobody has surveyed what the bag actually contains.

---

## 1. Day/night switching — TABLED, see issue #2

Filed rather than built. The camera genuinely cannot do it (`gpio-rf_feed`
absent, fallback ADC constant at 2999), and the HA-side implementation is
straightforward but not urgent.

## 2. Speaker volume — ASLC is levelling everything

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

## Closed — do not reopen

| | |
|---|---|
| White LEDs | Not wired on this PTZ board variant. Vendor firmware says so itself: `onf_shaking_head_cam not support white led`. Expander refuted (nothing answers at 0x58), pin config refuted, share-pin mux refuted with a control. |
| IR LED ring | Dark. Confirmed by JP with a phone whose IR sensitivity is independently established. |
| `gpio-rf_feed` | No counterpart exists. **Do not point it at another name** — that converts a clean `ENOENT` into a silent wrong-pin write, which is strictly worse. |
| Daemon IR-cut path | Every route dies at the same `ak_drv_ir_init` check: `ptz_daemon`, `libre_anyka_app`, and the vendor's own `ak_drv_ir_demo`. One bug, three binaries, six library builds. `ctl` bypasses it with a direct pin write. |
| `libplat_drv.so` rename | **Regression.** Renaming `gpio-ircut_b` flips init into two-line mode, which pulses 10 ms and releases both pins — parking the filter out permanently. Renaming `ircut_a` alone would land in write-and-hold, but the direct write in `ctl` is simpler and already proven. |
