# SSH

**Status: working, and proven on hardware by an actual login — not by a config read.**
Key-only, password login disabled, and every card carries a host key generated for it.

Everything on this page is marked **measured** or **inferred**. The measurements were taken
on 2026-08-06 against a camera running the `chensheng` 2023 kernel.

---

## 🔴 The host key that ships with the hack is published

This is the reason the page exists, and it is worth stating before anything else.

The hack has shipped `anyka_hack/dropbear/dropbear_ecdsa_host_key` since 2024. **Measured**:

| | |
|---|---|
| upstream public repo, fetched over plain HTTP | `HTTP 200`, 243 bytes |
| its md5 | `d643a89f07f51cb32412d66fd34ef34b` |
| the copy in the backup every card is built from | **identical** |
| the copy on both of JP's cameras | **identical** |

```
gitea.raspiweb.com/Gerge/Anyka_ak3918_hacking_journey/raw/branch/main/
  SD_card_contents/anyka_hack/dropbear/dropbear_ecdsa_host_key
```

**So its private half is downloadable by anyone.** It was not established by noticing that two
cameras matched — that would only show they shared a key. It was established by *downloading
the key* and comparing.

> **Why this is worse than it sounds.** Host-key verification is the *one* thing SSH adds over
> telnet against someone already on the camera VLAN. Encryption without it just means you are
> encrypting to whoever answered. With a published key an impersonator verifies **correctly**,
> so the client shows no warning at all — the failure is completely silent, and it is silent
> in the direction that feels like success.

**Fix**: `tools/write-sd-card.sh` generates a fresh ECDSA key **per card**, on the workstation,
and asserts that what landed on the card is non-empty *and* is not that md5 — or it refuses to
ship the card. A `--no-ssh` card still gets the published key **deleted**.

`ssh-up.sh` re-checks the same md5 at boot and refuses to start rather than serve it, in case
one arrives from an old card or a restored backup.

> The repo's own `reference/sd-card-hack/anyka_hack/dropbear/` contains `dropbearmulti` but
> **no host key**, so nothing in this repository ever leaked it.

## It had never been started

**Measured**: `gergehack.sh` contains **no dropbear invocation of any kind**, and port 22 was
closed on both cameras. The binary and the key shipped on every card and sat inert. This is not
a feature that was switched off — it is the first time the daemon has run here.

## 🔑 ECDSA only, and it is not a preference

**Measured**: the daemon is **Dropbear v2016.74**. The public-key algorithms compiled into the
binary are:

```
ssh-dss   ssh-rsa   ecdsa-sha2-nistp256   ecdsa-sha2-nistp384   ecdsa-sha2-nistp521
```

**There is no `ssh-ed25519`.**

> ⚠️ `curve25519-sha256@libssh.org` **is** in the binary and is easy to misread as ed25519
> support. It is a **key exchange** method, not a key type. Different thing.

Confirmed on the device rather than from `strings`, **with a control** — both keys present in
`authorized_keys`, same server, same minute:

| key offered | result |
|---|---|
| ED25519 | `Permission denied (publickey)` |
| ECDSA-256 | logged in, `uid=0(root)`, ran a command |

The control is what makes this conclusive: it rules out "the key simply was not authorised",
which is the explanation an ed25519-only test would have left open.

**Inferred, not measured:** RSA is not a usable escape hatch either. Dropbear 2016.74 signs
`ssh-rsa` with SHA-1, and OpenSSH ≥ 8.8 disables `ssh-rsa` by default in *both*
`HostKeyAlgorithms` and `PubkeyAcceptedAlgorithms` — so an RSA key would need a client-side
`+ssh-rsa` opt-in on every machine, forever. This follows from documented OpenSSH defaults; it
was not tested here.

```bash
ssh-keygen -t ecdsa -b 256 -C anyka-cameras -f ~/.ssh/anyka_ecdsa
cp ~/.ssh/anyka_ecdsa.pub tools/authorized_keys.local     # gitignored
```

**An ed25519 key installs perfectly cleanly and then authenticates nobody**, which is why the
writer refuses a key file with no ECDSA key in it instead of warning about one.

## Where `authorized_keys` lives, and why it is not `~`

**Measured** on the camera:

```
/dev/root      on /            squashfs (ro)     <- root's home is "/", per /etc/passwd
/dev/mtdblock6 on /etc/jffs2   jffs2 rw    64 K total,   8 K free  (88% full)
/dev/mtdblock7 on /data        jffs2 rw   2.2 M total, ~492 K free
/dev/mmcblk0p1 on /mnt         vfat  rw          <- the card
```

`/root` does not exist and `$HOME` is `/`, which is read-only. Dropbear takes the home directory
from `getpwnam` and has **no option to relocate `authorized_keys`** (`-r` sets *host* keys; there
is no equivalent for authorized keys — the full option list was read).

Of the three writable places, only one is right:

| | why not |
|---|---|
| `/etc/jffs2` | 64 K at 88% full, **and** it is `mtd6` = slot `C` of the stock updater. A firmware update carrying `usr.jffs2` erases the whole partition. Wrong home for a credential |
| `/mnt` (the card) | lost on a card swap, and vfat cannot store the `0600` dropbear insists on |
| **`/data`** (`mtd7`) | survives card swaps **and** firmware updates. ✅ |

So root's home is repointed to `/data/root` by a **validated 140-byte rewrite** of
`/etc/jffs2/passwd` (5 lines; the staged file must keep its line count and a well-formed root
line or the change is refused, and the original is kept at `/data/passwd.orig`).

> **The flash-wear objection is already moot.** `Factory/config.sh` runs `passwd` on **every
> boot** to set the root password, which rewrites `/etc/jffs2/shadow` every boot. One
> conditional 140-byte write is not a new class of risk.

## Two directions of "who wins", on purpose

This is the part most likely to be "tidied" into consistency, so the reasoning is written down.

| | direction | why |
|---|---|---|
| **host key** | card → `/data` **only if absent** | A host key is an **identity**. If the card won, rewriting a card — the routine way every fix ships here — would change the camera's identity and throw a MITM warning at every client. Worse, the warning would become routine, which trains away the one reflex that makes verification worth having |
| **`authorized_keys`** | card → `/data`, **card wins** | This one is a **setting**. Rewriting the card is how a key is added or revoked, and a revocation the camera could ignore is worthless |

**Measured**: a *different* host key was written to a card and the camera rebooted — it kept
serving its originally adopted key and ignored the decoy. A camera adopts once and keeps it; a
fresh camera out of the bag adopts whatever its first card carried.

## 🔴 The boot hook must sit BEFORE `gergehack.sh`

**`gergehack.sh` never returns.** It ends in:

```sh
if [[ $run_ipc == 0 ]] && [[ $rootfs_modified == 0 ]]; then
  while [ 1 ]; do sleep 30; done
fi
```

and `Factory/config.sh` calls it **synchronously**. The backup every card is built from carries
`rootfs_modified=0`, so the loop fires on every card this project has ever written.

**Measured** on both cameras — this is the proof, not the reasoning:

```
431 root {config.sh}    /bin/sh /mnt/Factory/config.sh     <- still blocked
438 root {gergehack.sh} /bin/sh /etc/jffs2/gergehack.sh
795 root sleep 30                                          <- the loop, spinning
```

> **Anything appended to `Factory/config.sh` after that line is dead code.** The SSH hook is
> therefore **inserted before** it, using the same `awk` anchor the isp symlink repair uses, and
> the writer verifies the *placement* — not merely the presence — before calling it done.

This also means the boot-time IR-cut line and the first-boot identity naming, both of which are
appended after `gergehack.sh`, cannot run as placed. See
[the warning in `sd-card.md`](sd-card.md#what-gets-fixed) — that is an open thread, not a
settled one.

`rootfs_modified` is deliberately **not** flipped to `1` to make `gergehack.sh` return: it is a
claim about whether this camera's rootfs launches `anyka_ipc`, changing it alters vendor-app
behaviour, and editing `gergesettings.txt` triggers gergehack's own card→flash sync **and a
reboot**.

## What `ssh-up.sh` does, in order

1. Adopt the host key from the card **if `/data` has none** — tested with `-s` (non-empty), not
   `-f`, because a zero-byte key passes an existence test and would then be permanent.
2. **Refuse to start** if the key is the published one.
3. Refresh `authorized_keys` from the card if it differs; `0700` / `0600`.
4. **Refuse to start** if `authorized_keys` is missing or empty — a camera that accepts nobody
   is worse than one that never started.
5. Repoint root's home if it is not already `/data/root`.
6. `dropbear -s -r <key> -p 22`.
7. **Assert the effect**: something is actually listening on 22.

Deliberately **not** used: `-R` (would generate a key from the camera's ~180 bits of
`entropy_avail`), `-w` (root is the only account), `-b` (a banner is published to anyone who
connects).

### The telnet fallback, and the argument against it

If nothing is listening on 22, `ssh-up.sh` **restarts `telnetd`**.

- **for** — on a headless camera with no serial console, the alternative recovery is physically
  pulling the card. SSH-or-telnet, never neither. It fired correctly during development, when a
  corrupt host key killed dropbear.
- **against** — it is a downgrade path: someone who can break SSH gets telnet back. It needs
  local reach and a working root password to be worth anything.

Set `SSH_NO_TELNET_FALLBACK=1` in `gergesettings.txt` to fail closed instead.

## What this does *not* fix

- **Measured**: `Factory/config.sh` carries the root password **in plaintext on the card**, by
  design — it re-sets it on every boot. Key-only SSH takes that password off the **wire**; it
  stays on the **card**, readable by anyone who pulls it.
- **Measured**: the root hash is 13 characters with no `$` prefix — traditional **DES crypt**.
  **Inferred** from that format: only the **first 8 characters** of the password are
  significant, whatever length the vault generates, and a 12-bit salt makes it cheap to crack
  offline.
- **Inferred**: dropbear 2016.74 is ten years old and has a decade of unfixed CVEs. Not audited
  against this build. `tools/crosscompile/` is proven for this target, so building a current
  dropbear is feasible and would also bring ed25519 — filed, not done.

## Verifying it — by effect, never by config

This firmware returns success constantly, so check the behaviour:

```bash
ssh -i ~/.ssh/anyka_ecdsa root@<camera> 'id'          # expect uid=0(root)

# password auth MUST be refused:
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no root@<camera> true
#   -> Permission denied (publickey).

# the host key must NOT be the published one:
ssh-keyscan -t ecdsa <camera> 2>/dev/null | awk '{print $3}'
```

On the camera, `/tmp/ssh-up.log` records what happened at boot.

> ⚠️ **`PATH` over SSH is not the `PATH` you get over telnet.** Measured on a
> dropbear session:
>
> ```
> PATH=/usr/bin:/bin:/media/mmcblk0p2/data/usr/bin
> ```
>
> **No `/sbin`, no `/usr/sbin`** — so `reboot`, `netstat`, `ifconfig`, `insmod`
> and friends are *not found* unless you give the full path (`/sbin/reboot`).
> Telnet logins get a fuller `PATH`, so a command pasted from a telnet session
> can fail here for a reason that looks nothing like a `PATH` problem. Anything
> scripted against these cameras should use absolute paths.

## See also

- [`sd-card.md`](sd-card.md) — the writer, its flags, and the dead-hook warning
- [`stock-attack-surface.md`](stock-attack-surface.md) — telnet and the writable-root FTP
- [`web-ui.md`](web-ui.md) — port 80 and `ctl`
