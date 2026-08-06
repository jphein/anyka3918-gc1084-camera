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
only writable place that persists to flash, and it has about 8 KB free. Consequences that show
up all over this project:

* `isp_gc1084.conf` is 104 KB and physically cannot be stored there, so it is a **symlink** to a
  copy on the SD card. See [sd-card.md](sd-card.md#the-sensor-problem).
* Setting `rootfs_modified=1` asks `start_web_interface.sh` to copy ~25 KB of CGI into
  `/etc/jffs2/www/`. It does not fit. See [web-ui.md](web-ui.md#how-it-is-served).

## Mount table

```
/dev/root        /            squashfs  ro
/dev/mtdblock5   /usr         squashfs  ro
/dev/mtdblock6   /etc/jffs2   jffs2     rw     <- the only persistent writable flash
/dev/mtdblock7   /data        jffs2     rw
/dev/mmcblk0p1   /mnt         vfat      rw     <- the SD card
tmpfs            /tmp         tmpfs     rw     <- token, PTZ FIFO, extracted sensor conf
tmpfs            /var         tmpfs     rw
tmpfs            /mnt                          (before the card mounts over it)
```

The root filesystem is **read-only squashfs**. Anything you want to survive a reboot goes in
`/etc/jffs2` (tiny) or on the SD card (roomy). Anything in `/tmp` is gone on reboot — including
`/tmp/token.txt` and `/tmp/sensor_ko_and_isp_conf/`.

## GPIO

`/sys/user-gpio/` exposes exactly six pins. Full table, observed values and cautions are in
[ptz.md](ptz.md#gpio-map). Summary: `IR_LED` (6), `SPK_PA` (7), `WHITE_LED` (24), `wifi_en` (34),
`ircut_b` (41), `ircut_a` (42). **There is no microphone pin**, which is why the mic cannot be
muted in hardware.

Pin numbers were decoded from **this camera's own kernel** (`mtd1` dumped from the live device).
They do **not** match upstream's firmware image, which is a different build — `ircut_b` exists
here and not there. Of the six, only `SPK_PA` and `ircut_a` are confirmed to do anything — by
direct observation (audible speech, visibly purple image) rather than by inference. `IR_LED` is
[unverified](ptz.md#-ir-leds--unverified); the rest have no observable effect.

## I2C

`/sys/bus/i2c/devices/` contains **`0-0058`**, which names itself `AW9523B` — a 16-channel I/O
expander. The kernel carries a driver: `aw9523b_read` and `aw9523b_write` appear in
`/proc/kallsyms`, both `EXPORT_SYMBOL`'d.

It was once the leading suspect for the non-working white LEDs. It is no longer: `aw9523b_probe`
configures all 16 channels as plain GPIO rather than constant-current LED sinks, never touches
the DIM registers, and no pin in the expander's range appears anywhere in the image. See
[ptz.md](ptz.md#2-the-aw9523b-expander--possible-but-weaker-than-it-first-looked).

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

The camera has a 32.768 kHz RTC but **no battery**, so it boots to 1969 and depends on NTP.
On the cams VLAN, NTP to the router is blocked, so the clock never syncs. See
[troubleshooting.md](troubleshooting.md#the-cameras-clock-stays-at-1969).

## Serial console

The board has a UART. Upstream's boot logs are vendored in
[`reference/UART_logs/`](../reference/UART_logs/) — factory boot, factory boot with SD, and the
exploit boot with and without SD. They are the fastest way to tell where a non-booting camera is
getting stuck. `getty` runs on `ttySAK0` at **115200 8N1**.

## See also

* [`reference/hardware/`](../reference/hardware/) — board photos, datasheet, flash chip log
* [sd-card.md](sd-card.md) — the sensor files this hardware needs
* [troubleshooting.md](troubleshooting.md) — when it will not boot or will not associate
