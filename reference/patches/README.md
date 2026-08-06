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

## Not patched

* **`ptz_daemon`** carries the same bug (`gpio-ircut_a`, `gpio-ircut_b`) and is very likely
  broken the same way, but has **not** been patched — separate authorisation, and it needs
  testing. See [ptz.md](../../docs/ptz.md#-ptz_daemons-ir-cut-control-is-probably-broken-too).
* **`gpio-rf_feed`**, also in `ptz_daemon`, has **no counterpart at all** on the 2023 build —
  there is no `rf_feed` node, prefixed or otherwise. It cannot be fixed by renaming; the feature
  is simply unavailable. Do not patch it to another name that also does not exist.
