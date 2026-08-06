# Hardware

## Identification

| | |
|---|---|
| Brand | Teruhal |
| Model | TC20 |
| FCC ID | 2BEXJ-TC20 |
| MPU | AK3918EN080 V200 CDSJ09J23 |
| WiFi | ZT9101UV20 |
| Image sensor | **GC1084** |
| Stock app | [Yi IOT](https://play.google.com/store/apps/details?id=com.yunyi.smartcamera) |
| Source | [Temu](https://share.temu.com/A5qeTOEZVbA), roughly $3–$8 |

![camera](https://github.com/user-attachments/assets/c23b2242-16df-46c6-87fc-d2d16095efb9)

It opens with the 3 screws on the main body. **The external antennas are fake** — there is a
small printed-circuit antenna taped inside the main compartment instead. The main chip is the
Anyka AK3918; the sensor is the GC1084.

The AK3918 and the WiFi module are the same parts used in
[Gerge's Anyka_ak3918_hacking_journey](https://gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/),
which is why that project's SD-card exploit works here unmodified. **The image sensor is
different**, and that difference is the whole of the extra work — see
[sd-card.md](sd-card.md#the-sensor-problem).

## SoC and system

Read from the running camera (`/proc/cpuinfo`, `/proc/mtd`, `dmesg`) and cross-checked against
[`reference/hardware/ak3918.pdf`](../reference/hardware/ak3918.pdf).

| | |
|---|---|
| SoC | Anyka **AK3918EN080**, chip ID `0x20150200`, board `Cloud39EV2_AK3918E80PIN_MNBD` |
| CPU | ARM926EJ-S rev 5, ARMv5TEJ, **400 MHz**, 16 KB I-cache + 16 KB D-cache (VIVT), MMU, little-endian only |
| Clocks | `AK39 clocks: CPU 400MHz, MEM 200MHz, ASIC 100MHz` |
| RAM | Embedded DDR2 @200 MHz — 64 MB total, **36.5 MB visible to Linux** (the rest is carved out for ISP/video) |
| Flash | 8 MB SPI NOR |
| Video | H.264 hardware encoder 720p30, MJPEG 720p30, multi-stream; ISP + CCIR601/656 sensor interface with scaling |
| Audio | MP3 / ADPCM / WAV / Speex encoders, 2 ADCs (mic + battery), 2 sigma-delta DACs, headphone driver, I2S slave, I2C master |
| Crypto | AES / DES / 3DES |
| Storage I/O | MMC/SD (MMC 4.2, SD 2.0), SDIO 1.1 |
| Other I/O | 2 UART, USB 2.0 HS host/slave, 2 SPI, 5 PWM, 5 timers, watchdog, 32.768 kHz RTC, 64 GPIO (7 dedicated) |
| Firmware | Linux **3.4.35** (`armv5tejl`), uClibc 0.9.33.2, gcc 4.8.5, Anyka `AKV_2.5.04`, built 2023-09-25 |

BogoMIPS reads 199.06, which is about half the 400 MHz core clock — that is normal for the
ARM926 delay loop, not an underclock.

> ⚠️ The datasheet in `reference/hardware/ak3918.pdf` is v1.0 (July 2014) and describes the
> **152-pin LFBGA** part. This camera uses the **80-pin** variant (`AK3918EN080`, board string
> `...E80PIN...`), so the pinout and some peripherals do not carry over — notably the Ethernet
> MAC, which this board does not wire up since it is WiFi-only. Treat the feature list as
> family-level, not part-exact.

## Flash layout

```
mtd0  8.00 MB  spi0.0     whole device
mtd1  1.50 MB  KERNEL
mtd2  4.00 KB  MAC
mtd3  4.00 KB  ENV
mtd4  1.00 MB  A
mtd5  3.02 MB  B          -> /usr        (squashfs, read-only)
mtd6    64 KB  C          -> /etc/jffs2  (88% full, 8.0 KB free)
mtd7  2.20 MB  D          -> /data
```

**That 64 KB `/etc/jffs2` partition is the constraint that shapes the whole hack.** It is the
writable flash partition *the hack uses*, and it has about 8 KB free. Consequences that show
up all over this project:

* `isp_gc1084.conf` is 104 KB and physically cannot be stored there, so it is a **symlink** to a
  copy on the SD card. See [sd-card.md](sd-card.md#the-sensor-problem).
* Setting `rootfs_modified=1` asks `start_web_interface.sh` to copy ~25 KB of CGI into
  `/etc/jffs2/www/`. It does not fit. See [web-ui.md](web-ui.md#how-it-is-served).

## Mount table

```
/dev/root        /            squashfs  ro
/dev/mtdblock5   /usr         squashfs  ro
/dev/mtdblock6   /etc/jffs2   jffs2     rw     <- 64 KB, ~8 KB free, and slot C of the updater
/dev/mtdblock7   /data        jffs2     rw     <- 2.20 MB, slot D. THE ROOMY ONE.
/dev/mmcblk0p1   /mnt         vfat      rw     <- the SD card
tmpfs            /tmp         tmpfs     rw     <- token, PTZ FIFO, extracted sensor conf
tmpfs            /var         tmpfs     rw
tmpfs            /mnt                          (before the card mounts over it)
```

The root filesystem is **read-only squashfs**. Anything in `/tmp` is gone on reboot — including
`/tmp/token.txt` and `/tmp/sensor_ko_and_isp_conf/`.

### Where persistent state actually goes — three places, not two

| Target | Size | Survives a firmware update? | Use it for |
|---|---|---|---|
| **`/data`** (`mtd7`, slot **D**) | **2.20 MB** | ✅ **yes** — no stock update path writes slot D | **device-local state**, e.g. [the identity marker](identity.md#why-data-and-not-etcjffs2) |
| `/etc/jffs2` (`mtd6`, slot **C**) | 64 KB, ~8 KB free | ❌ **no** — a `usr.jffs2` update overwrites the whole partition, *including the hack* | vendor config the hack must edit in place |
| SD card | GBs | ✅ (it is not flashed at all) | binaries, sounds, sensor conf, anything large |

> ❌ **RETRACTED: "`/etc/jffs2` is the only writable place that persists to flash."** This page
> said that twice — in prose and as an inline comment in the mount table — while **the line
> directly below the comment listed `/data` as `jffs2 rw`.** `/data` is **34× larger** and equally
> persistent.
>
> The consequential half was the guidance that followed: *"anything you want to survive a reboot
> goes in `/etc/jffs2` (tiny) or on the SD card (roomy)"* steered readers toward the two
> constrained options and away from the right one. `/data` is where
> [identity](identity.md) writes, and `/etc/jffs2` is *explicitly wrong* for it.
>
> 🔑 **A table refuting its own prose, one line apart, is now the most common defect in these
> docs.** The mount table is a device dump — measured. The sentence summarising it was unsourced
> and drifted. **Prose drifts, data doesn't: trust the table and re-derive the sentence.**

> ⚠️ **`/data` being safe from updates is not the same as `/data` being unreachable.**
> `updater local D=<file>` *would* flash it — the usage text simply does not advertise `D`. It is
> safe from the **stock update flow**, not armoured. See
> [identity.md](identity.md#why-data-and-not-etcjffs2).

## GPIO

`/sys/user-gpio/` exposes exactly six pins: `IR_LED` (6), `SPK_PA` (7), `WHITE_LED` (24),
`wifi_en` (34), `ircut_b` (41), `ircut_a` (42). Full table and cautions in
[ptz.md](ptz.md#gpio-map). **There is no microphone pin**, which is why the mic cannot be muted
in hardware.

Pin numbers were decoded from **this camera's own kernel** (`mtd1` dumped from the live device).
They do **not** match upstream's firmware image, which is a different build — `ircut_b` exists
here and not there.

**Reads are real hardware reads.** Disassembly shows the two helpers hit different registers:

```
g_ak39_gpio_setpin(pin,val)  ->  WRITES  0xf00a000c + bank*4   (output data)
g_ak39_gpio_getpin(pin)      ->  READS   0xf00a0018 + bank*4   (pin state)
```

So a readback reflects the **physical pad**, not the output latch — which is what makes the LED
results meaningful: [the pads swing and nothing lights](ptz.md#lights--neither-ring-lights),
so whatever is wrong is downstream of the pin.

`SPK_PA` and `ircut_a` are confirmed to drive real hardware by direct observation — audible
speech, visibly purple image. **`WHITE_LED` and `IR_LED` drive nothing**: both pads swing and
neither ring lights.

## I2C

`/sys/bus/i2c/devices/` contains **`0-0058`**, which names itself `AW9523B` — a 16-channel I/O
expander — and the kernel carries a driver, with `aw9523b_read` / `aw9523b_write` `EXPORT_SYMBOL`'d.

> ⚠️ **There is no such chip on this board.** Re-running the probe shows the one discriminating
> register write reading back `0xff` instead of the required `0x10`, while the GC1084 sensor on
> the same bus keeps working — a dead address, not a dead bus. The node exists only because
> platform code declares the device unconditionally and the probe ignores its return values.
> **A populated `/sys/bus/i2c/devices/` entry is not evidence that hardware is present.** Full
> writeup: [ptz.md](ptz.md#2-the-aw9523b-expander--experimentally-refuted).

The real bus client is the sensor. `i2c-ak39` sits at `0x20150000–0x20150100` with **no IRQ** —
`ak39_i2c_xfer` is polled.

## Register map, and why you cannot poke it

Anyone trying to reach hardware registers directly on this box will hit all of these:

| Route | Status |
|---|---|
| `devmem` | **Does not exist.** `/sbin/devmem` is a busybox symlink and `devmem` is not a compiled-in applet — it answers `applet not found`. |
| `/dev/mem` | **Cannot reach register windows.** ARM's `valid_phys_addr_range()` requires `addr ≥ PHYS_OFFSET`, and **`PHYS_OFFSET` here is `0x81800000`** — every register window is below it. Only `mmap()` could reach them, and nothing on the box can mmap. `dd` *can* read System RAM at `0x81800000`+. |
| `/dev/uio0` | Maps **`video-base`** (`0x20020000`, size `0x430`) — not I2C, not GPIO. |
| `/proc/iomem` | `i2c-ak39` at `0x20150000–0x20150100`. **No GPIO block is registered at all.** |

> ⚠️ **`PHYS_OFFSET` is `0x81800000`, not the conventional `0x80000000`.** An analysis pass that
> assumed the usual value had every physical address off by `0x1800000` — enough that a proposed
> target would have fallen *below* `PHYS_OFFSET` and been rejected outright. Validate translated
> addresses against `/proc/iomem` before trusting them. Worked example:
> `VA 0xC03CA61C → PA 0x81BCA61C`.

## Motors

The kernel declares two steppers, which is what makes this a "shaking-head" (PTZ) unit:

| Motor | GPIOs |
|---|---|
| `ak-motor0` | 19, 20, 10, 11 |
| `ak-motor1` | 15, 14, 13, 23 |

That classification matters beyond pan/tilt — the vendor firmware disables the white LEDs on
shaking-head units, which is [the leading explanation for why they do not
work](ptz.md#1-this-ptz-variant-was-never-wired-for-white-leds--best-supported).

## Clock

The camera has a 32.768 kHz RTC but **no battery**, so it boots to 1969 and depends entirely on
NTP. NTP does work — `ntpd` runs from `gergehack.sh` against `time_source`, and the clock has
been verified correct after ~12 hours of uptime.

The timezone is a different story: `gergehack.sh` passes `time_zone` straight to `export TZ=`,
POSIX `TZ` counts hours *west* of Greenwich, and the configured value has the sign backwards. See
[troubleshooting.md](troubleshooting.md#the-clock--ntp-works-the-timezone-was-15-hours-wrong-on-every-service).

## Serial console

The board has a UART. Boot logs are vendored in
[`reference/UART_logs/`](../reference/UART_logs/) — factory boot, factory boot with SD, and the
exploit boot with and without SD. They are the fastest way to tell where a non-booting camera is
getting stuck. `getty` runs on `ttySAK0` at **115200 8N1**.

> ⚠️ **Those logs are not this camera's firmware.** They are `#1 Nov 14 2022
> zhoujiahui@szfirsvr`; the kernel running here is `#2 Sep 25 2023 chensheng@ants-szfir`. The
> node naming confirms it independently — the logs show a prefixed `gpio-ircut_a`, while this
> camera has unprefixed `ircut_a` / `ircut_b` plus a `motor_switch`.
>
> They remain useful as **family-level** evidence (for instance, that the AW9523B is unpopulated
> across these boards), but **do not cite them as evidence about this camera's own factory
> firmware.** Two different builds.

## See also

* [`reference/hardware/`](../reference/hardware/) — board photos, datasheet, flash chip log
* [sd-card.md](sd-card.md) — the sensor files this hardware needs
* [troubleshooting.md](troubleshooting.md) — when it will not boot or will not associate
