# Patched binaries

In-place binary patches for this camera's 2023 kernel build. Each is byte-for-byte the vendor
binary with one string rewritten; **sizes are unchanged**, so nothing moves and no relocation is
touched.

Installed onto a card by [`tools/write-sd-card.sh`](../../tools/write-sd-card.sh), which
**verifies the md5 before installing** and refuses on a mismatch.

## `libre_anyka_app.node-ircut_a` — 🔴 **shipped, regressed, now off by default**

Fixes automatic day/night IR-cut switching, which has **never worked** on the 2023 build.

> ### ⛔ It works. That is the problem.
>
> Making the app's day/night writes land means **the app's day/night loop starts reverting every
> manual IR-cut toggle** — JP's Home Assistant switch went from working-for-weeks to *"toggles
> then goes back to the position it was before."* Rolled back on the live camera; manual control
> restored.
>
> `tools/write-sd-card.sh` **no longer installs this by default.** `--ir-cut-daynight` opts in.
> There is no arbitration in this firmware: on a 2023 build you get automatic day/night **or**
> reliable manual control. Given both LED rings are dark, automatic night mode has nothing to
> switch to, so manual wins.
>
> [Full story](../../docs/ptz.md#-root-cause-patching-libre_anyka_app-is-what-broke-manual-ir-cut-control).

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
> and running and merely awaiting its first day/night transition. **The transition came, and it
> broke manual IR-cut control.** The effect is validated now, and it is not the wanted one.
>
> The wording was careful and still not careful enough: *"the binary is correct and running"* was
> true, and it framed the only open question as **whether** the feature would work — when the live
> question was **what else changes when it does.** A patch awaiting validation is not a neutral
> state; it is a change whose consequences have not arrived yet.

> ⚠️ **This patch is kernel-build-specific.** It is *wrong* on the 2022 build, whose node really
> is `gpio-ircut_a`. That is why the card ships both binaries and
> [selects one per boot](../../docs/sd-card.md#-the-per-boot-selection-one-card-works-in-any-of-these-cameras) rather
> than baking a choice in at write time.

> ⚠️ **The file is kept, correct, and verified — the question was never whether the patch is
> right.** It is a valid fix to a real bug. It is off by default because *repairing that bug has a
> consequence nobody wanted.* Keep the distinction: this is not a bad patch, it is a patch whose
> side effect costs more than its benefit on this deployment.

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

### `libplat_drv.so` — 🔴 **tried, rolled back, never validated**

This is where `ptz_daemon_dyn` gets `gpio-ircut_a`, `gpio-ircut_b` and `ir-led` from. On
2026-08-06 those three strings were patched on the **live camera**, then rolled back to md5
`f5769ff013d7a3094e73ee76e312cad0` during the regression hunt.

**It was not the culprit** — that was `libre_anyka_app` — but it was never shown to *help* either.
The daemon does not reach the filter through sysfs at all: `set_ir_cut` moves the filter while
`/sys/user-gpio/ircut_a`'s mtime never changes, which is measured. So correcting those strings
repairs a path nothing uses.

> **Leading hypothesis, untested and staying that way:** the daemon reaches the filter through
> `ak_drv_ir_set_ircut`, and the sysfs strings are a legacy path failing silently and harmlessly.

**No patch file for this library exists in this directory, and none should be added.**
[Full story](../../docs/ptz.md#-retracted-ir-cut-control-through-the-daemon-is-broken).

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
