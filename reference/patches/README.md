# Patched binaries

In-place binary patches for this camera's 2023 kernel build. Each is byte-for-byte the vendor
binary with one string rewritten; **sizes are unchanged**, so nothing moves and no relocation is
touched.

Installed onto a card by [`tools/write-sd-card.sh`](../../tools/write-sd-card.sh), which
**verifies the md5 before installing** and refuses on a mismatch.

## `libre_anyka_app.node-ircut_a`

Fixes automatic day/night IR-cut switching, which has **never worked** on the 2023 build.

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

> ⚠️ **Status: verified applied, effect NOT yet validated.** On the live camera the patched
> binary is running, its md5 matches, and `strings` confirms the corrected path with `IR_LED`
> untouched. **But the day/night code path has not been exercised** — it was applied at 09:00 in
> stable daylight, when the app has no reason to switch. A watcher is capturing the first real
> transition. Do not read this as "day/night switching is fixed"; read it as "the binary is
> correct and running".

> ⚠️ **This patch is kernel-build-specific.** It is *wrong* on the 2022 build, whose node really
> is `gpio-ircut_a`. That is why the card ships both binaries and
> [selects one per boot](../../docs/sd-card.md#-one-card-works-in-any-of-these-cameras) rather
> than baking a choice in at write time.

> ⚠️ **Same reasoning as the regression below — read that first.** This patch was justified by
> "the string is wrong, so correct the string", which is exactly the argument that broke IR-cut
> control when applied to `libplat_drv.so`. **It is kept because nothing regressed from it**: the
> day/night loop did not work before and does not work after, so at worst it is inert. **Do not
> extend it, and do not build a new patch on string evidence alone.**
> [Detail](../../docs/ptz.md#-this-reasoning-is-now-under-suspicion--and-it-is-the-patch-we-ship).

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

### `libplat_drv.so` — 🔴 **tried, regressed, rolled back**

This is where `ptz_daemon_dyn` gets `gpio-ircut_a`, `gpio-ircut_b` and `ir-led` from. On
2026-08-06 those three strings were patched on the **live camera** and the result was measured as
a fix.

**It was not a fix.** JP reported that the Home Assistant IR-cut switch — which had been working
for weeks — stopped working after the patch. The library was restored to md5
`f5769ff013d7a3094e73ee76e312cad0`, the daemon restarted, and the solenoid **audibly clicks
again**.

> **Leading hypothesis, untested:** the daemon reaches the filter through a driver call
> (`ak_drv_ir_set_ircut` is the likely candidate), and the sysfs strings are a **legacy path that
> was failing silently and harmlessly**. Correcting them woke up a writer that then interfered
> with the route that worked.

**No patch file for this library exists in this directory, and none should be added.**
[Full story](../../docs/ptz.md#-the-daemon-path-was-never-broken-a-regression-and-its-rollback).

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
> Before patching a wrong-looking path, establish that it is **the path actually being taken** —
> not that it exists, not that it is wrong, that it *executes*. The cheapest test is usually to
> ask whether the feature currently works.
>
> Three of the four entries above are real defects in code that **does not run**, and the fourth
> was a real defect whose **failure was holding the system together**. This project has now spent
> four separate efforts patching things outside the execution path in a single day. Assume you are
> about to be the fifth.
