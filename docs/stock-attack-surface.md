# What a stock, un-hacked Anyka exposes

**Question asked (2026-08-06):** can a stock camera — never hacked, no SD card inserted — be
rooted over the network?

**Answer: no, and not for the reason anyone expected.** The blocker is not a password. **A
stock camera cannot join a network at all without the vendor's QR provisioning flow**, so
there is nothing to attack until someone has already used the app.

Everything below is from **static analysis of the vendor squashfs** (`/` = mtd4, `/usr` =
mtd5, both `ro` — the hack lives entirely on the SD card, so a hacked unit still carries an
untouched stock rootfs to read), plus two live checks. Claims are labelled, and **capability
is stated separately from reachability** throughout — they are different facts and only the
second one decides anything.

> ⚠️ **The pre-auth RCE in `cgi-bin/header` does NOT apply here.** That is a consequence of
> the hack, not a route into it: `gergehack` installs the web UI that contains it. On a stock
> unit there is nothing at that address. Do not cite it as a stock-firmware finding.

---

## 1. 🔴 The finding that stands regardless of everything else

**`rc.local` line 12, stock, on every boot:**

```sh
/usr/bin/tcpsvd 0 21 ftpd -w / -t 600 &
```

| | |
|---|---|
| `0` | **all interfaces** |
| `21` | FTP |
| `-w` | **writes enabled** |
| `/` | **served from the filesystem root**, not a subdirectory |
| started by | `rc.local`, as **root** |

**A stock camera runs a permanently-enabled, network-facing, writable file service rooted at
`/`, as root.** Anyone who can authenticate to it can write anywhere — including
`/tmp/update.tar`, which per [firmware-update.md](firmware-update.md) `update.sh` will flash
**with no signature check at all**. That is a complete root chain built entirely from vendor
components, gated only by the FTP credential.

**This is the defensive finding, and it does not depend on resolving anything else on this
page.** It is an argument for VLAN isolation on its own.

**MEASURED: it is not anonymous.**

```
banner: 220 Operation successful
anonymous login -> error_perm 530 Login failed
```

### ⚠️ The BusyBox help text lies, and it nearly produced the opposite finding

This build's own `--help` says:

```
Usage: ftpd [-wvS] [-t N] [-T N] [DIR]
Anonymous FTP server
```

No auth flag listed; it calls itself anonymous. **It is not** — authentication is compiled
in, and only the probe revealed it. Reported as-is, this would have become *"every stock
camera on the VLAN offers unauthenticated root file-write"*, which is false.

**A binary's usage string is documentation, and documentation lies.** BusyBox prints a
generic banner that does not reflect compile-time feature flags. Feature-gated behaviour must
be read from the code or probed — never from the string the tool prints about itself. Same
failure as every stale doc, wearing an executable's authority.

## 2. `cmd_serverd` — total capability, zero reachability

**Written up precisely because someone will find this binary later and get excited.**

**MEASURED (strings + disassembly):** `/usr/bin/cmd_serverd`, started unconditionally by
`service.sh start_service`, is a TCP server that receives a framed request and **`popen()`s
the command inside it**, returning the output:

```
[%s:%d] header: seq=%u, flag=%d, recvsz=%d, header_len=%d
[%s:%d] popen %s, cmd: %s
[%s:%d] send result, len: %d
```

Imports `system`, `popen`, `fork`, `setsid`, `chdir("/mnt")`. **There is no password, token,
key, challenge or "denied" string anywhere in the binary.** It is unauthenticated remote
command execution *by design* — it is the vendor's own IPC mechanism, not a bug.

**And it binds loopback.** From `main` at `0x96ec`–`0x970c`:

```
strh <0x224e>, [sp,#14]        ; sin_port, network order = 8782
ldr  r0, "127.0.0.1"
bl   inet_addr                 ; sin_addr
bl   bind
```

> **Capability: arbitrary command execution as root, no authentication.
> Reachability: `127.0.0.1:8782`. Zero.**

Anyone reporting "unauthenticated RCE in the stock firmware" will be describing the
capability and omitting the fact that decides it.

## 3. Stock telnet is a boot-window race, not a service

**MEASURED (source):** `rcS` line 6 runs `telnetd &` unconditionally — that is the vendor,
not the hack. But `service.sh`'s `start_service()` contains **`killall telnetd`**, and
`rc.local:34` invokes it on every boot.

**INFERRED:** stock telnet therefore lives only between `rcS` and `service.sh` reaching that
line. Consistent with the hack needing to re-enable telnet at all, which would be pointless
otherwise. **Window length not measured** — that needs a stock unit.

## 4. There is no setup AP. Provisioning is QR-only.

**This closes the question permanently; do not re-derive it.**

| evidence | verdict |
|---|---|
| `/usr/sbin/wifi_ap.sh` exists but **nothing calls it** — not the init chain, not `wifi_manage.sh`, no binary | orphan |
| it requires `hostapd /etc/jffs2/hostapd.conf -B`, and **`hostapd` is not on the filesystem** | cannot run |
| `anyka_cfg.ini` `[softap]`: `s_ssid` and `s_password` both **empty** | never configured |
| `anyka_ipc` does contain `yi_ap_listen_start` / `ap_listen_restart` | could not rule out statically |
| **LIVE: 90-second scan from katana after power-on — no new SSID, nothing camera-shaped** | **no AP** |
| **JP, new unit out of the box: the Yi IoT app is QR-based** | **confirmed** |

For reference if the orphan path ever matters: it would have used SSID `AKIPC_XXX` (the
literal fallback when `s_ssid` is empty), open, camera at **`192.168.0.1`** on `wlan1` with
`udhcpd`.

## 5. The credential — UNRESOLVED, and named as such

The remaining unknown is the vendor's default root password. **It cannot be read from a
hacked unit**: `Factory/config.sh:19` runs `passwd`, and `/etc/passwd` and `/etc/shadow` are
symlinks into `/etc/jffs2`, which the hack rewrote.

Confirmed separately: **no stock init script writes `passwd` or `shadow`** (`rcS`,
`rc.local`, `service.sh`, `camera.sh`), so whatever is there is factory-provisioned and does
not change on boot.

**The repo contains two conflicting unverified claims. Neither is endorsed:**

- `reference/hack-process.md:35`, `:214` — *"root, no password"*
- `docs/sd-card.md:390` — *"Set the root password, so telnet is usable"*, implying an empty
  password **blocks** login

No factory flash dump exists in the repo to settle it (searched). The UART logs show a
factory boot dropping to `[root@anyka ~]$` — but that is the **serial console** via
`inittab`'s getty, i.e. physical access, and says nothing about telnet or FTP credentials.

**The test that settles it**, unspent as of writing:

```
serial console, 115200 8N1  ->  grep root /etc/jffs2/passwd /etc/jffs2/shadow
```

Three distinguishable outcomes, and they are **not** interchangeable:
`root::` = empty · `root:!:` or `root:*:` = locked · `root:$1$…` = a real hash.

---

## What this actually reframes

**The SD card was never the route to root — it is the route to avoiding the vendor app.**

A stock camera cannot reach a network without QR provisioning, so "root it over the network
with no card" is impossible at step zero, regardless of any credential.

That leaves a middle path worth naming:

> **QR-provision with the vendor app, then root over the network — no card ever inserted.**

This depends entirely on the unresolved credential in §5, and on whether JP accepts one app
pairing per unit. If both hold, the fleet story changes from *write a card per unit* to *one
pairing per unit, then everything remotely*. **Not pursued** — it needs the §5 test first.
