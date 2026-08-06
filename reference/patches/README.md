# Patched binaries

In-place binary patches for this camera's 2023 kernel build. Each is byte-for-byte the vendor
binary with one string rewritten; **sizes are unchanged**, so nothing moves and no relocation is
touched.

> ⛔ **Exactly one of these is installed on a card: `cgi-bin-header.hardened`.** It closes a live
> pre-auth remote root hole and is kernel-agnostic. **Every binary IR-cut patch below is kept for
> documentation only** — one is inert, one is a regression, and
> [`tools/write-sd-card.sh`](../../tools/write-sd-card.sh) ships neither.

## `libre_anyka_app.node-ircut_a` — ⚪ **confirmed inert, not shipped**

Intended to fix automatic day/night IR-cut switching, which has **never worked** on the 2023
build. It does not, and [nothing can](../../docs/ptz.md#-automatic-daynight-is-not-fixable-on-this-board).

> ### ⛔ CONFIRMED INERT. Not shipped, and not worth shipping.
>
> **It repairs the *write* end of a two-ended chain while the *sense* end stays broken in a file
> nobody patched.** The day/night thread `photosensitive_switch_th_ex` calls
> `ak_drv_ir_get_input_level()`, which resolves into a **different** `libplat_drv.so` build
> (`385740be…`) whose init fails the same way. It returns `-1` and the thread bails **before
> reaching any write** — so the corrected string is never executed.
>
> It is also **structurally harmless**: it writes via `camera_set_ir(val,path)` and
> `ak_misc_set_video_day_night` does **one write per pin and leaves it asserted** — write-and-hold,
> correct for this hardware. It cannot park the filter out.
>
> **`tools/write-sd-card.sh` no longer installs it at all.** Shipping an inert patch buys nothing
> and cost the entire per-boot node-name detection scheme that existed only to serve it.
>
> ❌ **RETRACTED: "this patch broke JP's IR-cut toggle."** It did not. That was
> [`libplat_drv.so`](#libplat_drvso---the-regression-never-patch-this), and the misattribution
> survived a rollback and two commits.
>
> [Full story](../../docs/ptz.md#the-vendor-apps-daynight-loop-is-confirmed-inert).

| | |
|---|---|
| Offset | `0x447c` (17532) |
| Old | `/sys/user-gpio/gpio-ircut_a\0` — 28 bytes |
| New | `/sys/user-gpio/ircut_a\0` + 5 slack NULs — 28 bytes |
| Bytes differing | 12 |
| Size | 27552, unchanged |
| md5 before | `3458b8598ca9525a0d5e693ff5fd5d5c` |
| md5 after | `351d54e853ee6774e50e9704986bd6b6` |

The correct path being **shorter** than the wrong one is what makes this a safe in-place edit
rather than a relink.

Reproducible without shipping a binary:

```sh
printf '/sys/user-gpio/ircut_a\0\0\0\0\0\0' \
  | dd of=libre_anyka_app bs=1 seek=17532 count=28 conv=notrunc
```

> ❌ **RETRACTED: "verified applied, effect NOT yet validated."** This said the patch was correct
> and running and merely awaiting its first day/night transition. **That transition never came and
> never will** — the sense end of the chain is broken in a different library.
>
> The wording was careful and still not careful enough. *"The binary is correct and running"* was
> true, and it framed the only open question as **whether** the feature would work. Two better
> questions went unasked: **what else changes when it does**, and **is anything else in this chain
> also broken?** A patch awaiting validation is not a neutral state.

> ⚠️ **It is also kernel-build-specific**, and *wrong* on the 2022 build whose node really is
> `gpio-ircut_a`. That is what the
> [per-boot selection](../../docs/sd-card.md#-the-per-boot-selection-retained-for-reference-no-longer-used)
> existed to handle. **That machinery is now dormant** — with nothing build-specific shipping,
> there is nothing to select between.

> ⚠️ **The patch itself is not wrong, and that is the point worth keeping.** It correctly fixes a
> real bug. It is simply *pointless*, because the feature it repairs is gated behind a second
> failure nobody had looked for. **"This patch is correct" and "this patch does something" are
> different claims**, and only the first was ever established.

## `cgi-bin-header.hardened`

Fixes the **pre-auth remote root RCE** on port 80. Not a binary patch — a rewritten shell
parser.

| | |
|---|---|
| md5 (hardened) | `934ce4814d4fc90edec82275769986c5` |
| md5 (stock) | `997a3c6e65e66d29a47a7c59c8964685` |
| Kernel-specific? | **No.** Applies unconditionally, no detection needed. |

The old parser was `for i in $QUERY_STRING; do eval $i; done`, and because every CGI sources
`header` *before* its token check, that was unauthenticated remote root code execution. It cannot
be fixed by reordering, because `$token` is produced **by** that eval.

The fix accepts **lowercase identifier keys only** and assigns the value **by reference**:

```sh
eval "$key=\$val"
```

`$val` inside the eval is a *variable reference*, so its contents are never re-parsed as shell.
Dynamic keys still work, which `settings_submit.sh` depends on. The lowercase rule is derived
from the device rather than guessed: every legitimate parameter is lowercase (all 17
`gergesettings.txt` keys and all five UI params), while every dangerous shell/loader variable is
uppercase by convention — `PATH`, `IFS`, `LD_*`, `ENV`, `BASH_ENV`, `CDPATH`.

**Verified by demonstrating the hole, then its absence** — not by a harness:

* Before: an unauthenticated `GET` created a **root-owned `/tmp/rce_probe`**.
* After: the identical payloads — backtick, `$()`, embedded, and `?PATH=/tmp/evil&IFS=X` — left
  no file, same URL, same camera.
* Regression-checked: UI login still works; `settings_submit.sh` did **not** corrupt
  `gergesettings.txt` (md5-identical to a pre-test backup); the Home Assistant path is
  structurally independent (`login_validate.sh` and `login` do not source `header` at all, and
  `ctl`'s only match is a comment).

> **Why a harness pass was not accepted as evidence:** an earlier version of this fix passed one
> while still permitting `PATH`/`IFS`/`LD_PRELOAD` hijacking — those are valid *identifiers*, so
> validating identifier-ness alone is insufficient. On this device, proof has to be the exploit
> failing on the real target.

> 📌 **Hardening note for a future revision — not a defect in this one.** The key filter uses the
> glob range `*[!a-z0-9_]*`. Under a non-C locale, bracket ranges follow collation order and
> `[a-z]` can match uppercase, which would let `PATH` through. This camera has no locale
> configured, so it runs in the C locale and the filter is strict ASCII — the fix is sound **as
> deployed**. A future revision could enumerate the characters explicitly to make it
> locale-independent. **Do not change this file to "fix" that without re-running the live exploit
> test**; the md5 here is what was verified.

## ⛔ Deliberately NOT patched — and one of these is a mistake already made

**This section is the most dangerous page in the repo, because every entry below looks like an
obvious unfinished job.** Each one is a real, visible, easily-patched wrong string. None of them
should be patched. Read the reason before reaching for `dd`.

### `libplat_drv.so` — 🔴 **THE REGRESSION. Never patch this.**

This is where `ptz_daemon_dyn` gets `gpio-ircut_a`, `gpio-ircut_b` and `ir-led` from. On
2026-08-06 those three strings were patched on the **live camera**, which **broke the IR-cut
filter**, and were rolled back to md5 `f5769ff013d7a3094e73ee76e312cad0`.

**The mechanism is exact.** `ak_drv_ir_init` stats *both* ircut names and picks a mode:

| `stat()` | Mode | Behaviour |
|---|---|---|
| neither | **disabled** | returns `-1`; `set_ir_cut` writes nothing |
| **one** | **1-line** | one write, **stays asserted** — correct for this board |
| **both** | **2-line** | `a=v; b=!v; sleep 10 ms; a=0; b=0` — a **latching-solenoid pulse** |

This board's filter is **hold-to-engage on `ircut_a` alone with 4–8 s travel**. A 10 ms pulse that
releases cannot hold it, so in 2-line mode **every command parks the filter OUT** — magenta.

> ### 🎯 Renaming `gpio-ircut_b` alone caused it
>
> The patch renamed **both**, which jumped the driver from *disabled* past 1-line into 2-line.
> **Renaming only `ircut_a` would have landed in 1-line mode and worked.**
>
> **The more thorough fix was the harmful one.** "I found two instances of the bug and fixed both"
> is what a careful engineer does. There is no ordinary instinct that guards against a component
> whose behaviour depends on *how many* things it can reach.
>
> The third edit, `ir-led` → `IR_LED`, was **dead code**: `ptz_daemon_dyn` imports no
> `ak_drv_irled_*` symbol at all.

**No patch file for this library exists in this directory, and none should be added.**
[Full story](../../docs/ptz.md#-root-cause-the-libplat_drvso-patch-tipped-the-driver-into-a-mode-for-other-hardware).

### `ptz_daemon` (the static 2.1 MB binary) — inert

It carries the same prefixed strings, but **that file never executes** on this setup —
`ptz_daemon_dyn` does. Patching it would change nothing. Left alone.

### `gpio-rf_feed` — no counterpart exists

There is **no `rf_feed` node** on the 2023 build, prefixed or otherwise. It cannot be fixed by
renaming; the feature is unavailable. **Do not patch it to another name that also does not
exist** — that turns a clean `ENOENT` into a silent wrong-pin write.

---

> ### 🔑 The rule this section exists to enforce
>
> **A string that looks broken may be a dead path whose failure is load-bearing.**
>
> `libre_anyka_app` writing a non-existent sysfs path is unambiguously a bug by inspection.
> Fixing it was obviously correct. **And that silent failure was the only reason manual IR-cut
> control worked at all.**
>
> So the rule has two halves, and the second is the one that was missing:
>
> 1. **Establish that the path is actually taken** — not that it exists, not that it is wrong,
>    that it *executes*. Three of the entries above are real defects in code that does not run.
> 2. **Establish what currently depends on it failing.** A path that reliably fails is a behaviour
>    the rest of the system has been built on top of, whether or not anyone designed it that way.
>
> The cheapest version of both: **ask whether the feature currently works, and what would notice
> if it started.**
