# `/usr/sbin` update & OTA tooling — faithful device dump

Dumped read-only from the live camera (`10.0.10.20`) on 2026-08-06 by `lucid-camera`.
**Nothing here was executed.** These scripts write flash; see the warning at the bottom.

These files live on the **read-only squashfs root**, not the SD card, and were absent from
this repo entirely (there was no `reference/usr-sbin/` before this commit). Transferred via
`base64` over telnet; each md5 below was verified against the device *after* transfer, and
every size matches the device's own `ls -la`.

| file | size | md5 (device == this copy) |
|---|---|---|
| `update.sh` | 9022 | `c481a9cecd2ddaf73198ecb732d49af8` |
| `update_factory_data.sh` | 3971 | `34adf94a62925e338ef5783190e998c3` |
| `update_audio_ota_packet.sh` | 1227 | `4aa5d75b6a5b9e99eb1f9c53369a36ce` |
| `update_play_aac.sh` | 449 | `8ae234d104d20cff8ecfa8808aa3e8d3` |

Device firmware version (`/usr/fw_version`): **`6.0.24.10_202401091113`**

---

## The headline: there IS a working SD-card firmware update path

`update.sh` is a complete, self-contained updater with **two entry points**:

| mode | trigger | version gate |
|---|---|---|
| **TF (SD card)** — `UPDATE_WAY=0` | `/mnt/update/update.tar` exists | `tar_ver != dev_ver` — **any different version installs, including a DOWNGRADE** |
| **OTA (network)** — `UPDATE_WAY=1` | `/tmp/update.tar` exists | `tar_ver > dev_ver` (shell string compare) — newer only |

The TF path is the interesting one for us: it needs no cloud, no account, and its gate is
merely *different*, not *newer*.

`update.tar` is expected to contain any of:

```
uImage  root.sqsh4  usr.sqsh4  usr.jffs2  audio_update.tgz
  + optional  <name>.md5  for each
  + optional  fw_version   (REQUIRED — read unconditionally at line 271)
  + optional  special.sh   (executed if present, only when /data exists)
  + optional  9.aac        (the "starting update" voice prompt)
```

## Slot → mtd mapping — the partition question, answered exactly

`update.sh` never names an mtd device; it calls `updater local <SLOT>=<file>`. **The slots
are the partition *names*,** so `/proc/mtd` resolves it with no disassembly needed:

```
dev:    size     erasesize  name
mtd0: 00800000  00001000  "spi0.0"   8.00 MB  whole flash
mtd1: 00180000  00001000  "KERNEL"   1.50 MB  <- updater local KERNEL=uImage
mtd2: 00001000  00001000  "MAC"      4 KB
mtd3: 00001000  00001000  "ENV"      4 KB
mtd4: 00100000  00001000  "A"        1.00 MB  <- updater local A=root.sqsh4
mtd5: 002f5000  00001000  "B"        3.02 MB  <- updater local B=usr.sqsh4
mtd6: 00010000  00001000  "C"        64 KB    <- updater local C=usr.jffs2   (= /etc/jffs2)
mtd7: 0022a000  00001000  "D"        2.16 MB  (= /data — NOT written by update.sh)
```

**This cross-validates against everything already known**, which is why it can be trusted:
root is mounted from `mtdblock4` squashfs (= "A"), `/etc/jffs2` is `mtdblock6` (= "C", 64 KB,
matching the recorded "64 KB, 88 % full"), and `/data` is `mtdblock7` (= "D", 2.16 MB ≈ the
recorded 2.2 MB). Four independent facts agree.

The actual flasher is **`/sbin/updater`**, since disassembled — see the section at the end of
this file. It confirms the mapping above is a **runtime sysfs lookup**, not a hardcoded table,
and that **`D` (mtd7, `/data`) is reachable** even though `update.sh` never uses it.

## ⚠️ Verification: md5 only, NO signature — and the check is SKIPPED IF THE `.md5` IS ABSENT

Every one of the five update functions has this identical shape:

```sh
if [ -e ${DIR1}/${VAR1} ]; then
    if [ -e ${DIR1}/${ZMD5} ]; then          # <-- CONDITIONAL
        result=`md5sum -c ${DIR1}/${ZMD5} | grep OK`
        if [ -z "$result" ]; then return; fi  # bail only if the file EXISTED and failed
    fi
    updater local KERNEL=${DIR1}/${VAR1}      # <-- flashes regardless
fi
```

Two consequences, both important:

1. **Omit the `.md5` and no verification happens at all.** The check is opt-in *by whoever
   built the tar*. This is not a bypass to be found — it is the documented behaviour of the
   `if`.
2. **Even when present, the md5 ships inside the same `update.tar`.** That is an integrity
   check against corruption, **not** an authenticity check. Anyone who can supply the tar
   supplies the expected hash with it. There is no signature, no public key, no chain of
   trust anywhere in this pipeline.

For *our* purposes (JP building his own images) this is convenient. It is worth being clear
that it is convenient because the security model is absent, not because it is permissive.

## The cloud OTA path is plain HTTP

`update_audio_ota_packet.sh` fetches over **unencrypted HTTP**:

```
http://yihome-publicfiles-us.oss-us-west-1.aliyuncs.com/fw615/audio_update.tar
```

via `/usr/bin/cloudAPI`, then md5-checks it against `audio_update.tgz.md5` — **extracted
from that same download**. So the transport is unauthenticated and the integrity check is
self-referential: anyone able to MITM that request supplies both payload and hash. It runs
as root and unpacks into `/data/audio_file`.

Gated by `/etc/jffs2/already_update_audio_flag`, so it runs at most once. **Whether anything
still invokes it is not established** — and the vendor cloud may well be dead. Recorded as a
property of the script, not an active exposure.

## `/mnt/v200_update/` — an SD-card drop point with NO integrity check at all

`update_factory_data.sh` reads from `/mnt/v200_update/` on the SD card:

| file | destination | check |
|---|---|---|
| `audio_update.tgz` | `rm -rf /data/audio_file/*` then untar into it | **none** |
| `wifi_driver.sh` | `/data/` | "differs from current" only |
| `wifi_station.sh` | `/data/` | "differs from current" only |
| `wifi_driver.tgz`, `wifi_tool.tgz` | `/data/` | "differs from current" only |
| `sensor.tgz` | `/etc/jffs2/` then **`reboot`** | "differs from current" only |

The md5 comparison in `copy_file()` asks *"is the new file different from the installed
one?"* — it is a change detector, not a validator. And `wifi_driver.sh` / `wifi_station.sh`
are **shell scripts that get executed later**, so this directory is a root-code-execution
drop point for anyone who can write to the card.

That is not a *remote* hole on its own (writing to the card needs physical access or root),
but it is worth knowing the path exists, especially given the web UI can already place files
on the card over FTP.

## Practical constraints for building an image

- **`/tmp` is tmpfs and the box is `mem=64M`.** `update.sh` copies every image from `/mnt`
  into `/tmp` before flashing (lines 336–347) and then `umount /mnt -l`. So the whole update
  payload must fit in RAM alongside a running system. `usr.sqsh4` could be up to 3 MB.
- **`fw_version` is mandatory.** Line 271 reads `/tmp/fw_version` unconditionally; without it
  the comparison degenerates and the TF path's `!=` test will match an empty string.
- **The watchdog is deliberately killed** before flashing (`killall -12 daemon`, sleep 3,
  `killall -9 daemon`), so a slow flash will not trigger a watchdog reboot. That is why the
  script is safe to run *to completion* and dangerous to interrupt.
- **busybox is copied to `/tmp` first** (line 329) so the tail of the script still works after
  the rootfs partition has been overwritten. Any custom `special.sh` should assume the same.

## Incidental finding: the update LED feedback is dead on this build

`update_play_aac.sh` blinks `/sys/user-gpio/AP_LED` and `/sys/user-gpio/PWR_LED`. **Neither
node exists on this kernel** — the live set is exactly `IR_LED SPK_PA WHITE_LED ircut_a
ircut_b wifi_en`. Both writes ENOENT silently, so during an update there is **no LED
indication**, only the repeating `didi.aac` beep. Same 2022-vs-2023 node-naming skew that
broke the IR-cut path; see `docs/ptz.md`.

Plan for audio-only progress feedback, and do not read a dark LED as a failed update.

---

## ⛔ DO NOT RUN ANY OF THESE

`update.sh` kills the watchdog, unmounts `/mnt`, and overwrites kernel and rootfs partitions.
The only writable regions with meaningful free space are `mtd6` (~8 KB free) and `mtd7`
(~760 KB free); a partial write to `KERNEL`/`A`/`B` has nowhere good to land and there is no
A/B slot scheme or rollback here — **the update is in-place and non-atomic.**

These files are checked in as **reference for designing an update path**, not as tooling.
Recovery from a bad flash means the UART console and a full reflash, not a reboot.

---

# `/sbin/updater` — disassembled 2026-08-06. The flasher, read rather than inferred.

`updater` (26348 B, md5 `98c425be815862aa30b92cc2717694ed`, Jan 2024) was the one component
above whose behaviour was *inferred*. It has now been read. **Static analysis only — it was
never executed.** Stripped, no symbols; addresses below are from the disassembly.

## Slot names are a RUNTIME sysfs lookup, not a hardcoded list

`updater` does not contain a partition table. It builds a path from whatever name it is given:

```
sprintf("/sys/kernel/partition_table/%s", NAME)        -> must exist, else
                                     "err:no this partition directory, partname: %s"
sprintf("/sys/kernel/partition_table/%s/%s", NAME, "mtd_index")   -> read index
open("/dev/mtd%d", index)
```

The live table:

```
/sys/kernel/partition_table/KERNEL/mtd_index : 1
/sys/kernel/partition_table/MAC/mtd_index    : 2
/sys/kernel/partition_table/ENV/mtd_index    : 3
/sys/kernel/partition_table/A/mtd_index      : 4
/sys/kernel/partition_table/B/mtd_index      : 5
/sys/kernel/partition_table/C/mtd_index      : 6
/sys/kernel/partition_table/D/mtd_index      : 7
```

### ⚠️ `D` IS reachable — `update.sh` merely never uses it

The usage text documents only `KERNEL`, `A`, `B`, `C`. **That is documentation, not
enforcement.** The lookup is generic and `D` is present with `mtd_index 7`, so
`updater local D=<file>` would resolve and flash **`/data`**. No name whitelist was found.

The correct, narrow statement — and the one to build on — is:

> **`update.sh` never invokes `D=`.** That is a property of the *script*, verified by reading
> all five of its update functions. It is **not** a guarantee that `mtd7` is unwritable, and
> **not** a guarantee that some other caller cannot target it.

**Second caveat for anything storing identity in `/data`:** `update_factory_data.sh`'s
`update_audio_file()` runs **`rm -rf /data/audio_file/*`** before untarring an audio package.
So `/data` survives a firmware update, but **`/data/audio_file/` does not** — do not put a
unit marker under that subdirectory.

## Q: whole-partition erase or in-place? — **WHOLE PARTITION, from offset 0**

```
b778:  ldr r3, [sp,#48]     ; mtd_info.size   <- FULL PARTITION SIZE
b784:  str r3, [sp,#12]     ; erase_info.length = size
b798:  str r1, [sp,#8]      ; erase_info.start  = 0
b7a0:  pthread_create(...)  ; -> thread prctl(PR_SET_NAME,"erase_mtd")
b09c:      ioctl(fd, MEMERASE 0x40084d02, &erase_info)
```

`erase_info = { start: 0, length: mtd_info.size }`. The **entire** partition is erased in a
single `MEMERASE`, on a worker thread, before any write.

Consequences:

- **`C=usr.jffs2` IS a whole-partition replace.** mtd6 is erased `start=0 length=0x10000`
  (all 64 KB), so **everything in `/etc/jffs2` is destroyed** by a `C=` update. Any per-unit
  state kept there does not survive a firmware update.
- An **undersized** image leaves the remainder **erased (0xFF)**, not stale data — which is
  the clean state for both squashfs (defined by its own length) and jffs2.
- The erase is why the script kills the watchdog first, and why interrupting it is fatal:
  between `MEMERASE` and the end of the write the partition is blank.

## Q: bounds check against mtd size? — **YES, and it is sound**

```
b72c:  fstat(fd, &st)
b744:  ldr sl, [sp,#116]    ; st.st_size
b748:  ldr r3, [sp,#48]     ; mtd_info.size
b74c:  cmp sl, r3
b750:  bls b76c             ; size <= partition -> proceed
b754:  fputs("image file large than mtd partition", stderr)
b764:  mvn r4, #0           ; return -1
```

Unsigned compare (`bls`), checked **before** the erase. **An oversized image is rejected and
nothing is touched.** This is the one safety property in the whole pipeline that actually works.

## Q: short/corrupt image behaviour? — **NO FORMAT VALIDATION AT ALL**

`updater` performs exactly two checks on a local image: it must **open**, and it must not be
**larger than the partition**. There is:

- **no squashfs superblock / magic check** — no `hsqs` or equivalent constant anywhere
- **no length-vs-header consistency check**
- **no md5 on the `local` path** — the `md5 check success/failure` strings belong to the
  `http`/`ftp` download paths only

So a truncated or garbage file that is merely *small enough* will be **erased-in and written
verbatim**. Combined with `update.sh` skipping md5 whenever the `.md5` is absent, the
end-to-end path from `update.tar` to flashed rootfs can contain **zero** integrity checking.

A short `A=root.sqsh4` therefore yields a partition whose head is a valid-looking mount
target and whose tail is 0xFF — i.e. **a device that fails at first read of the missing
region, after the update reports success and reboots.**

## Also present, not exercised

`updater` links `socket`/`bind`/`listen`/`accept`/`connect`/`getaddrinfo` and carries `http`
and `ftp` source options (`updater ftp K=/path/file1 A=a.b.c.d P=port U=aaa C=xxx`). So the
same flasher can pull an image straight from the network. Not analysed; flagged because it
widens the OTA surface beyond the SD card.

`/dev/akfha_char` also appears alongside `/dev/mtd%d` — a second, Anyka-specific flash device
used on at least one path. Which path takes it is **not established.**

## Net assessment for building an update image

Safe, in this order: the size check is real, the erase is complete and atomic-ish per
partition, and an undersized image leaves clean 0xFF. Unsafe: **nothing validates that the
bytes you supply are the filesystem you think they are** — not the script, not the flasher.
Build the `.md5` files and include them; they are the only integrity mechanism available, and
they only run because *you* chose to ship them.
